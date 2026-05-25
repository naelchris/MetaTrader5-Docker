#include <drogon/drogon.h>
#include "MT5Client.h"
#include "controllers/MT5Controller.h"

int main()
{
    int tcpPort  = 9000;
    int httpPort = 8080;

    const char* envTcp  = std::getenv("MT5_TCP_PORT");
    const char* envHttp = std::getenv("HTTP_PORT");
    if (envTcp)  tcpPort  = std::stoi(envTcp);
    if (envHttp) httpPort = std::stoi(envHttp);

    // Start TCP server waiting for the MQL5 EA connection
    if (!MT5Client::instance().start(tcpPort))
    {
        LOG_ERROR << "Failed to start MT5 TCP server on port " << tcpPort;
        return 1;
    }

    drogon::app()
        .setLogLevel(trantor::Logger::kInfo)
        .addListener("0.0.0.0", httpPort)
        .setThreadNum(4)
        .registerController(std::make_shared<MT5Controller>())
        .run();

    MT5Client::instance().stop();
    return 0;
}
