#pragma once

#include <json/json.h>
#include <atomic>
#include <mutex>
#include <string>
#include <thread>

// Singleton TCP server that waits for the MQL5 EA to connect.
// Serializes commands one-at-a-time (MT5/MQL5 is single-threaded).
class MT5Client
{
public:
    static MT5Client& instance();

    bool start(int port = 9000);
    void stop();

    // Blocking call: sends action + params to EA, waits up to timeoutMs for response.
    Json::Value send(const std::string& action,
                     const Json::Value& params  = Json::Value::null,
                     int                timeoutMs = 5000);

    bool isConnected() const { return clientFd_.load() >= 0; }

private:
    MT5Client()  = default;
    ~MT5Client() { stop(); }

    MT5Client(const MT5Client&)            = delete;
    MT5Client& operator=(const MT5Client&) = delete;

    void acceptLoop();

    static std::string makeId();
    static Json::Value errJson(const std::string& msg);

    bool        sendRaw(int fd, const std::string& msg);
    std::string recvLine(int fd, int timeoutMs);

    int serverFd_ = -1;
    std::atomic<int> clientFd_{-1};

    std::mutex  cmdMutex_;   // serializes send() calls
    std::string readBuf_;    // line buffer, only touched under cmdMutex_

    std::thread         acceptThread_;
    std::atomic<bool>   running_{false};
};
