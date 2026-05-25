#pragma once

#include <drogon/HttpController.h>
#include "../MT5Client.h"

using namespace drogon;

class MT5Controller : public drogon::HttpController<MT5Controller>
{
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(MT5Controller::health,          "/health",                    Get);
    ADD_METHOD_TO(MT5Controller::accountInfo,     "/account",                   Get);
    ADD_METHOD_TO(MT5Controller::getPositions,    "/positions",                 Get);
    ADD_METHOD_TO(MT5Controller::closePosition,   "/positions/{ticket}/close",  Post);
    ADD_METHOD_TO(MT5Controller::getOrders,       "/orders",                    Get);
    ADD_METHOD_TO(MT5Controller::placeOrder,      "/orders",                    Post);
    ADD_METHOD_TO(MT5Controller::cancelOrder,     "/orders/{ticket}",           Delete);
    ADD_METHOD_TO(MT5Controller::orderHistory,    "/history/orders",            Get);
    ADD_METHOD_TO(MT5Controller::dealHistory,     "/history/deals",             Get);
    METHOD_LIST_END

    // GET /health
    void health(const HttpRequestPtr& req,
                std::function<void(const HttpResponsePtr&)>&& cb);

    // GET /account
    void accountInfo(const HttpRequestPtr& req,
                     std::function<void(const HttpResponsePtr&)>&& cb);

    // GET /positions
    void getPositions(const HttpRequestPtr& req,
                      std::function<void(const HttpResponsePtr&)>&& cb);

    // POST /positions/{ticket}/close
    void closePosition(const HttpRequestPtr& req,
                       std::function<void(const HttpResponsePtr&)>&& cb,
                       std::string ticket);

    // GET /orders
    void getOrders(const HttpRequestPtr& req,
                   std::function<void(const HttpResponsePtr&)>&& cb);

    // POST /orders  body: { symbol, type, volume, price, sl, tp, comment }
    void placeOrder(const HttpRequestPtr& req,
                    std::function<void(const HttpResponsePtr&)>&& cb);

    // DELETE /orders/{ticket}
    void cancelOrder(const HttpRequestPtr& req,
                     std::function<void(const HttpResponsePtr&)>&& cb,
                     std::string ticket);

    // GET /history/orders?from=<unix>&to=<unix>
    void orderHistory(const HttpRequestPtr& req,
                      std::function<void(const HttpResponsePtr&)>&& cb);

    // GET /history/deals?from=<unix>&to=<unix>
    void dealHistory(const HttpRequestPtr& req,
                     std::function<void(const HttpResponsePtr&)>&& cb);

private:
    static HttpResponsePtr reply(const Json::Value& v);
};

//+------------------------------------------------------------------+
//| Inline implementations (header-only controller)                  |
//+------------------------------------------------------------------+
inline HttpResponsePtr MT5Controller::reply(const Json::Value& v)
{
    auto resp = HttpResponse::newHttpJsonResponse(v);
    // Surface EA-level errors as HTTP 502
    if (v.isMember("status") && v["status"].asString() == "error")
        resp->setStatusCode(k502BadGateway);
    return resp;
}

inline void MT5Controller::health(const HttpRequestPtr&,
                                   std::function<void(const HttpResponsePtr&)>&& cb)
{
    auto& client = MT5Client::instance();
    Json::Value v;
    v["status"]    = client.isConnected() ? "ok" : "error";
    v["connected"] = client.isConnected();
    v["message"]   = client.isConnected() ? "EA connected" : "EA not connected";
    auto resp = HttpResponse::newHttpJsonResponse(v);
    if (!client.isConnected()) resp->setStatusCode(k503ServiceUnavailable);
    cb(resp);
}

inline void MT5Controller::accountInfo(const HttpRequestPtr&,
                                        std::function<void(const HttpResponsePtr&)>&& cb)
{
    cb(reply(MT5Client::instance().send("account_info")));
}

inline void MT5Controller::getPositions(const HttpRequestPtr&,
                                         std::function<void(const HttpResponsePtr&)>&& cb)
{
    cb(reply(MT5Client::instance().send("positions")));
}

inline void MT5Controller::closePosition(const HttpRequestPtr&,
                                          std::function<void(const HttpResponsePtr&)>&& cb,
                                          std::string ticket)
{
    Json::Value params;
    params["ticket"] = std::stoll(ticket);
    cb(reply(MT5Client::instance().send("close_position", params)));
}

inline void MT5Controller::getOrders(const HttpRequestPtr&,
                                      std::function<void(const HttpResponsePtr&)>&& cb)
{
    cb(reply(MT5Client::instance().send("orders")));
}

inline void MT5Controller::placeOrder(const HttpRequestPtr& req,
                                       std::function<void(const HttpResponsePtr&)>&& cb)
{
    auto body = req->getJsonObject();
    if (!body)
    {
        Json::Value err;
        err["status"]  = "error";
        err["message"] = "Request body must be JSON";
        auto resp = HttpResponse::newHttpJsonResponse(err);
        resp->setStatusCode(k400BadRequest);
        cb(resp);
        return;
    }

    // Validate required fields
    for (const auto& f : {"symbol", "type", "volume"})
    {
        if (!body->isMember(f))
        {
            Json::Value err;
            err["status"]  = "error";
            err["message"] = std::string("Missing required field: ") + f;
            auto resp = HttpResponse::newHttpJsonResponse(err);
            resp->setStatusCode(k400BadRequest);
            cb(resp);
            return;
        }
    }

    cb(reply(MT5Client::instance().send("place_order", *body)));
}

inline void MT5Controller::cancelOrder(const HttpRequestPtr&,
                                        std::function<void(const HttpResponsePtr&)>&& cb,
                                        std::string ticket)
{
    Json::Value params;
    params["ticket"] = std::stoll(ticket);
    cb(reply(MT5Client::instance().send("cancel_order", params)));
}

inline void MT5Controller::orderHistory(const HttpRequestPtr& req,
                                         std::function<void(const HttpResponsePtr&)>&& cb)
{
    Json::Value params;
    params["from"] = std::stoll(req->getParameter("from").empty() ? "0" : req->getParameter("from"));
    params["to"]   = std::stoll(req->getParameter("to").empty()   ? "0" : req->getParameter("to"));
    cb(reply(MT5Client::instance().send("order_history", params)));
}

inline void MT5Controller::dealHistory(const HttpRequestPtr& req,
                                        std::function<void(const HttpResponsePtr&)>&& cb)
{
    Json::Value params;
    params["from"] = std::stoll(req->getParameter("from").empty() ? "0" : req->getParameter("from"));
    params["to"]   = std::stoll(req->getParameter("to").empty()   ? "0" : req->getParameter("to"));
    cb(reply(MT5Client::instance().send("deal_history", params)));
}
