#include "MT5Client.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>

#include <chrono>
#include <drogon/drogon.h>
#include <json/json.h>
#include <random>
#include <sstream>

MT5Client& MT5Client::instance()
{
    static MT5Client inst;
    return inst;
}

bool MT5Client::start(int port)
{
    serverFd_ = ::socket(AF_INET, SOCK_STREAM, 0);
    if (serverFd_ < 0) return false;

    int opt = 1;
    ::setsockopt(serverFd_, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    sockaddr_in addr{};
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port        = htons(static_cast<uint16_t>(port));

    if (::bind(serverFd_, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) return false;
    if (::listen(serverFd_, 1) < 0) return false;

    running_ = true;
    acceptThread_ = std::thread(&MT5Client::acceptLoop, this);
    LOG_INFO << "MT5Client: TCP server listening on port " << port;
    return true;
}

void MT5Client::stop()
{
    running_ = false;
    if (serverFd_ >= 0) { ::close(serverFd_); serverFd_ = -1; }

    int fd = clientFd_.exchange(-1);
    if (fd >= 0) ::close(fd);

    if (acceptThread_.joinable()) acceptThread_.join();
}

void MT5Client::acceptLoop()
{
    while (running_)
    {
        sockaddr_in peer{};
        socklen_t   len = sizeof(peer);
        int fd = ::accept(serverFd_, reinterpret_cast<sockaddr*>(&peer), &len);
        if (fd < 0)
        {
            if (running_) LOG_WARN << "MT5Client: accept() failed";
            continue;
        }

        // Enable TCP keep-alive so stale connections are detected
        int ka = 1;
        ::setsockopt(fd, SOL_SOCKET,  SO_KEEPALIVE, &ka, sizeof(ka));
        int idle = 10, intvl = 5, cnt = 3;
        ::setsockopt(fd, IPPROTO_TCP, TCP_KEEPIDLE,  &idle,  sizeof(idle));
        ::setsockopt(fd, IPPROTO_TCP, TCP_KEEPINTVL, &intvl, sizeof(intvl));
        ::setsockopt(fd, IPPROTO_TCP, TCP_KEEPCNT,   &cnt,   sizeof(cnt));

        // Reduce latency
        int nd = 1;
        ::setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &nd, sizeof(nd));

        LOG_INFO << "MT5Client: EA connected from " << inet_ntoa(peer.sin_addr);

        // Replace any existing connection (EA reconnected)
        {
            std::lock_guard<std::mutex> lk(cmdMutex_);
            int old = clientFd_.exchange(fd);
            if (old >= 0) ::close(old);
            readBuf_.clear();
        }
    }
}

//+------------------------------------------------------------------+

Json::Value MT5Client::send(const std::string& action,
                             const Json::Value& params,
                             int                timeoutMs)
{
    std::lock_guard<std::mutex> lk(cmdMutex_);

    int fd = clientFd_.load();
    if (fd < 0) return errJson("EA not connected");

    // Build request
    std::string id = makeId();
    Json::Value cmd;
    cmd["id"]     = id;
    cmd["action"] = action;
    if (!params.isNull())
    {
        for (const auto& k : params.getMemberNames())
            cmd[k] = params[k];
    }

    Json::StreamWriterBuilder wb;
    wb["indentation"] = "";
    std::string line = Json::writeString(wb, cmd) + "\n";

    if (!sendRaw(fd, line))
    {
        int old = clientFd_.exchange(-1);
        if (old >= 0) ::close(old);
        readBuf_.clear();
        return errJson("Send failed — EA disconnected");
    }

    std::string resp = recvLine(fd, timeoutMs);
    if (resp.empty())
    {
        int old = clientFd_.exchange(-1);
        if (old >= 0) ::close(old);
        readBuf_.clear();
        return errJson("Timeout waiting for EA response");
    }

    Json::Value result;
    Json::CharReaderBuilder rb;
    std::string errs;
    std::istringstream ss(resp);
    if (!Json::parseFromStream(rb, ss, &result, &errs))
        return errJson("Invalid JSON from EA: " + errs);

    return result;
}

bool MT5Client::sendRaw(int fd, const std::string& msg)
{
    const char* ptr = msg.data();
    size_t      rem = msg.size();
    while (rem > 0)
    {
        ssize_t n = ::send(fd, ptr, rem, MSG_NOSIGNAL);
        if (n <= 0) return false;
        ptr += n;
        rem -= static_cast<size_t>(n);
    }
    return true;
}

std::string MT5Client::recvLine(int fd, int timeoutMs)
{
    using clock = std::chrono::steady_clock;
    auto deadline = clock::now() + std::chrono::milliseconds(timeoutMs);

    while (true)
    {
        auto pos = readBuf_.find('\n');
        if (pos != std::string::npos)
        {
            std::string line = readBuf_.substr(0, pos);
            readBuf_         = readBuf_.substr(pos + 1);
            return line;
        }

        auto now  = clock::now();
        if (now >= deadline) return "";

        long ms = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - now).count();
        timeval tv{ms / 1000, static_cast<suseconds_t>((ms % 1000) * 1000)};
        ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

        char buf[4096];
        ssize_t n = ::recv(fd, buf, sizeof(buf), 0);
        if (n <= 0) return "";
        readBuf_.append(buf, static_cast<size_t>(n));
    }
}

std::string MT5Client::makeId()
{
    static std::mt19937_64 rng{std::random_device{}()};
    std::ostringstream oss;
    oss << std::hex << rng();
    return oss.str();
}

Json::Value MT5Client::errJson(const std::string& msg)
{
    Json::Value v;
    v["status"]  = "error";
    v["message"] = msg;
    return v;
}
