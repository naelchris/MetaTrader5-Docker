//+------------------------------------------------------------------+
//|                                                    MT5Bridge.mq5 |
//|  TCP client EA — connects to the C++ Drogon bridge server        |
//|  and handles JSON commands for account, positions, orders, trade  |
//+------------------------------------------------------------------+
#property copyright "MT5 Bridge"
#property version   "1.00"
#property strict

input string BridgeHost     = "bridge"; // Bridge server hostname (Docker service name)
input int    BridgePort     = 9000;     // Bridge server TCP port
input int    TimerIntervalMs = 50;      // Polling interval (ms)

int    gSocket    = INVALID_HANDLE;
bool   gConnected = false;
string gReadBuf   = "";

//+------------------------------------------------------------------+
int OnInit()
{
    EventSetMillisecondTimer(TimerIntervalMs);
    TryConnect();
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    EventKillTimer();
    if (gSocket != INVALID_HANDLE)
    {
        SocketClose(gSocket);
        gSocket = INVALID_HANDLE;
    }
}

void OnTick() {}

void OnTimer()
{
    if (!gConnected || gSocket == INVALID_HANDLE || !SocketIsConnected(gSocket))
    {
        gConnected = false;
        TryConnect();
        return;
    }
    ProcessIncoming();
}

//+------------------------------------------------------------------+
void TryConnect()
{
    if (gSocket != INVALID_HANDLE)
    {
        SocketClose(gSocket);
        gSocket = INVALID_HANDLE;
    }
    gSocket = SocketCreate();
    if (gSocket == INVALID_HANDLE) return;

    if (!SocketConnect(gSocket, BridgeHost, (uint)BridgePort, 2000))
    {
        SocketClose(gSocket);
        gSocket = INVALID_HANDLE;
        return;
    }
    gConnected = true;
    gReadBuf   = "";
    Print("MT5Bridge: connected to ", BridgeHost, ":", BridgePort);
}

void ProcessIncoming()
{
    uint avail = SocketIsReadable(gSocket);
    if (avail == 0) return;

    uchar buf[];
    ArrayResize(buf, avail);
    int n = SocketRead(gSocket, buf, avail, 0);
    if (n <= 0) { gConnected = false; return; }

    gReadBuf += CharArrayToString(buf, 0, n, CP_UTF8);

    int pos;
    while ((pos = StringFind(gReadBuf, "\n")) >= 0)
    {
        string line = StringSubstr(gReadBuf, 0, pos);
        gReadBuf    = StringSubstr(gReadBuf, pos + 1);
        StringTrimLeft(line);
        StringTrimRight(line);
        if (StringLen(line) == 0) continue;

        string resp = Dispatch(line) + "\n";
        uchar out[];
        int len = StringToCharArray(resp, out, 0, StringLen(resp), CP_UTF8) - 1;
        if (len > 0) SocketSend(gSocket, out, len);
    }
}

//+------------------------------------------------------------------+
//| Command dispatcher                                                |
//+------------------------------------------------------------------+
string Dispatch(const string &json)
{
    string id     = JStr(json, "id");
    string action = JStr(json, "action");
    string status = "ok";
    string errMsg = "";
    string data   = "null";

    if      (action == "ping")           data = "\"pong\"";
    else if (action == "account_info")   data = AccountInfo();
    else if (action == "positions")      data = Positions();
    else if (action == "orders")         data = Orders();
    else if (action == "place_order")  { data = PlaceOrder(json, errMsg);    if (errMsg != "") status = "error"; }
    else if (action == "close_position"){ data = ClosePosition(json, errMsg);if (errMsg != "") status = "error"; }
    else if (action == "cancel_order") { data = CancelOrder(json, errMsg);   if (errMsg != "") status = "error"; }
    else if (action == "order_history")  data = OrderHistory(json);
    else if (action == "deal_history")   data = DealHistory(json);
    else { status = "error"; errMsg = "unknown action: " + action; }

    string out = "{\"id\":\"" + id + "\",\"status\":\"" + status + "\"";
    if (status == "ok")
        out += ",\"data\":" + data;
    else
        out += ",\"message\":\"" + EscJson(errMsg) + "\"";
    return out + "}";
}

//+------------------------------------------------------------------+
//| Account info                                                      |
//+------------------------------------------------------------------+
string AccountInfo()
{
    string s = "{";
    s += "\"login\":"         + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))          + ",";
    s += "\"name\":\""        + EscJson(AccountInfoString(ACCOUNT_NAME))                   + "\",";
    s += "\"server\":\""      + EscJson(AccountInfoString(ACCOUNT_SERVER))                 + "\",";
    s += "\"currency\":\""    + EscJson(AccountInfoString(ACCOUNT_CURRENCY))               + "\",";
    s += "\"balance\":"       + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2)      + ",";
    s += "\"equity\":"        + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2)       + ",";
    s += "\"margin\":"        + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN), 2)       + ",";
    s += "\"free_margin\":"   + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2)  + ",";
    s += "\"profit\":"        + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2)       + ",";
    s += "\"leverage\":"      + IntegerToString(AccountInfoInteger(ACCOUNT_LEVERAGE))      + ",";
    s += "\"trade_allowed\":" + (AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ? "true" : "false");
    return s + "}";
}

//+------------------------------------------------------------------+
//| Open positions                                                    |
//+------------------------------------------------------------------+
string Positions()
{
    int total = PositionsTotal();
    string s = "[";
    for (int i = 0; i < total; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket == 0) continue;
        if (i > 0) s += ",";
        s += PositionJson(ticket);
    }
    return s + "]";
}

string PositionJson(ulong ticket)
{
    string s = "{";
    s += "\"ticket\":"         + IntegerToString(ticket)                                          + ",";
    s += "\"symbol\":\""       + EscJson(PositionGetString(POSITION_SYMBOL))                     + "\",";
    s += "\"type\":"           + IntegerToString(PositionGetInteger(POSITION_TYPE))               + ",";
    s += "\"volume\":"         + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2)            + ",";
    s += "\"open_price\":"     + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), 5)        + ",";
    s += "\"current_price\":"  + DoubleToString(PositionGetDouble(POSITION_PRICE_CURRENT), 5)    + ",";
    s += "\"sl\":"             + DoubleToString(PositionGetDouble(POSITION_SL), 5)                + ",";
    s += "\"tp\":"             + DoubleToString(PositionGetDouble(POSITION_TP), 5)                + ",";
    s += "\"profit\":"         + DoubleToString(PositionGetDouble(POSITION_PROFIT), 2)            + ",";
    s += "\"swap\":"           + DoubleToString(PositionGetDouble(POSITION_SWAP), 2)              + ",";
    s += "\"comment\":\""      + EscJson(PositionGetString(POSITION_COMMENT))                    + "\",";
    s += "\"time\":"           + IntegerToString(PositionGetInteger(POSITION_TIME));
    return s + "}";
}

//+------------------------------------------------------------------+
//| Pending orders                                                    |
//+------------------------------------------------------------------+
string Orders()
{
    int total = OrdersTotal();
    string s = "[";
    for (int i = 0; i < total; i++)
    {
        ulong ticket = OrderGetTicket(i);
        if (ticket == 0) continue;
        if (i > 0) s += ",";
        s += OrderJson(ticket);
    }
    return s + "]";
}

string OrderJson(ulong ticket)
{
    string s = "{";
    s += "\"ticket\":"      + IntegerToString(ticket)                                          + ",";
    s += "\"symbol\":\""   + EscJson(OrderGetString(ORDER_SYMBOL))                           + "\",";
    s += "\"type\":"        + IntegerToString(OrderGetInteger(ORDER_TYPE))                    + ",";
    s += "\"volume\":"      + DoubleToString(OrderGetDouble(ORDER_VOLUME_INITIAL), 2)         + ",";
    s += "\"price\":"       + DoubleToString(OrderGetDouble(ORDER_PRICE_OPEN), 5)             + ",";
    s += "\"sl\":"          + DoubleToString(OrderGetDouble(ORDER_SL), 5)                    + ",";
    s += "\"tp\":"          + DoubleToString(OrderGetDouble(ORDER_TP), 5)                    + ",";
    s += "\"comment\":\""  + EscJson(OrderGetString(ORDER_COMMENT))                         + "\",";
    s += "\"time_setup\":"  + IntegerToString(OrderGetInteger(ORDER_TIME_SETUP));
    return s + "}";
}

//+------------------------------------------------------------------+
//| Place order                                                       |
//+------------------------------------------------------------------+
string PlaceOrder(const string &json, string &errMsg)
{
    string symbol  = JStr(json, "symbol");
    int    type    = (int)JInt(json, "type");
    double volume  = JDbl(json, "volume");
    double price   = JDbl(json, "price");
    double sl      = JDbl(json, "sl");
    double tp      = JDbl(json, "tp");
    string comment = JStr(json, "comment");

    MqlTradeRequest req = {};
    MqlTradeResult  res = {};

    req.action       = TRADE_ACTION_DEAL;
    req.symbol       = symbol;
    req.volume       = volume;
    req.type         = (ENUM_ORDER_TYPE)type;
    req.price        = price;
    req.sl           = sl;
    req.tp           = tp;
    req.comment      = comment;
    req.type_filling = ORDER_FILLING_IOC;
    req.deviation    = 10;

    if (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT ||
        type == ORDER_TYPE_BUY_STOP  || type == ORDER_TYPE_SELL_STOP)
        req.action = TRADE_ACTION_PENDING;

    if (!OrderSend(req, res))
    {
        errMsg = "OrderSend failed code=" + IntegerToString(GetLastError()) + " " + res.comment;
        return "null";
    }

    string s = "{";
    s += "\"ticket\":"   + IntegerToString(res.order)   + ",";
    s += "\"deal\":"     + IntegerToString(res.deal)    + ",";
    s += "\"retcode\":"  + IntegerToString(res.retcode) + ",";
    s += "\"comment\":\"" + EscJson(res.comment)        + "\",";
    s += "\"price\":"    + DoubleToString(res.price, 5) + ",";
    s += "\"volume\":"   + DoubleToString(res.volume, 2);
    return s + "}";
}

//+------------------------------------------------------------------+
//| Close position                                                    |
//+------------------------------------------------------------------+
string ClosePosition(const string &json, string &errMsg)
{
    ulong ticket = (ulong)JInt(json, "ticket");

    if (!PositionSelectByTicket(ticket))
    {
        errMsg = "Position not found: " + IntegerToString(ticket);
        return "null";
    }

    string symbol  = PositionGetString(POSITION_SYMBOL);
    double volume  = PositionGetDouble(POSITION_VOLUME);
    int    posType = (int)PositionGetInteger(POSITION_TYPE);

    MqlTradeRequest req = {};
    MqlTradeResult  res = {};

    req.action       = TRADE_ACTION_DEAL;
    req.position     = ticket;
    req.symbol       = symbol;
    req.volume       = volume;
    req.type         = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    req.price        = (posType == POSITION_TYPE_BUY)
                           ? SymbolInfoDouble(symbol, SYMBOL_BID)
                           : SymbolInfoDouble(symbol, SYMBOL_ASK);
    req.deviation    = 10;
    req.type_filling = ORDER_FILLING_IOC;

    if (!OrderSend(req, res))
    {
        errMsg = "Close failed code=" + IntegerToString(GetLastError()) + " " + res.comment;
        return "null";
    }

    string s = "{";
    s += "\"ticket\":"   + IntegerToString(res.order)   + ",";
    s += "\"deal\":"     + IntegerToString(res.deal)    + ",";
    s += "\"retcode\":"  + IntegerToString(res.retcode) + ",";
    s += "\"comment\":\"" + EscJson(res.comment)        + "\"";
    return s + "}";
}

//+------------------------------------------------------------------+
//| Cancel pending order                                              |
//+------------------------------------------------------------------+
string CancelOrder(const string &json, string &errMsg)
{
    ulong ticket = (ulong)JInt(json, "ticket");

    MqlTradeRequest req = {};
    MqlTradeResult  res = {};
    req.action = TRADE_ACTION_REMOVE;
    req.order  = ticket;

    if (!OrderSend(req, res))
    {
        errMsg = "Cancel failed code=" + IntegerToString(GetLastError()) + " " + res.comment;
        return "null";
    }

    string s = "{";
    s += "\"retcode\":"  + IntegerToString(res.retcode) + ",";
    s += "\"comment\":\"" + EscJson(res.comment)        + "\"";
    return s + "}";
}

//+------------------------------------------------------------------+
//| Order history                                                     |
//+------------------------------------------------------------------+
string OrderHistory(const string &json)
{
    datetime from = (datetime)JInt(json, "from");
    datetime to   = (datetime)JInt(json, "to");
    if (to == 0) to = TimeCurrent();

    HistorySelect(from, to);
    int total = HistoryOrdersTotal();
    string s = "[";
    for (int i = 0; i < total; i++)
    {
        ulong ticket = HistoryOrderGetTicket(i);
        if (ticket == 0) continue;
        if (i > 0) s += ",";
        string o = "{";
        o += "\"ticket\":"     + IntegerToString(ticket)                                               + ",";
        o += "\"symbol\":\""   + EscJson(HistoryOrderGetString(ticket, ORDER_SYMBOL))                 + "\",";
        o += "\"type\":"       + IntegerToString(HistoryOrderGetInteger(ticket, ORDER_TYPE))           + ",";
        o += "\"volume\":"     + DoubleToString(HistoryOrderGetDouble(ticket, ORDER_VOLUME_INITIAL), 2)+ ",";
        o += "\"price\":"      + DoubleToString(HistoryOrderGetDouble(ticket, ORDER_PRICE_OPEN), 5)   + ",";
        o += "\"state\":"      + IntegerToString(HistoryOrderGetInteger(ticket, ORDER_STATE))          + ",";
        o += "\"time_setup\":" + IntegerToString(HistoryOrderGetInteger(ticket, ORDER_TIME_SETUP))    + ",";
        o += "\"time_done\":"  + IntegerToString(HistoryOrderGetInteger(ticket, ORDER_TIME_DONE));
        s += o + "}";
    }
    return s + "]";
}

//+------------------------------------------------------------------+
//| Deal history                                                      |
//+------------------------------------------------------------------+
string DealHistory(const string &json)
{
    datetime from = (datetime)JInt(json, "from");
    datetime to   = (datetime)JInt(json, "to");
    if (to == 0) to = TimeCurrent();

    HistorySelect(from, to);
    int total = HistoryDealsTotal();
    string s = "[";
    for (int i = 0; i < total; i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if (ticket == 0) continue;
        if (i > 0) s += ",";
        string d = "{";
        d += "\"ticket\":"      + IntegerToString(ticket)                                              + ",";
        d += "\"symbol\":\""   + EscJson(HistoryDealGetString(ticket, DEAL_SYMBOL))                  + "\",";
        d += "\"type\":"        + IntegerToString(HistoryDealGetInteger(ticket, DEAL_TYPE))            + ",";
        d += "\"entry\":"       + IntegerToString(HistoryDealGetInteger(ticket, DEAL_ENTRY))           + ",";
        d += "\"volume\":"      + DoubleToString(HistoryDealGetDouble(ticket, DEAL_VOLUME), 2)         + ",";
        d += "\"price\":"       + DoubleToString(HistoryDealGetDouble(ticket, DEAL_PRICE), 5)          + ",";
        d += "\"profit\":"      + DoubleToString(HistoryDealGetDouble(ticket, DEAL_PROFIT), 2)         + ",";
        d += "\"commission\":"  + DoubleToString(HistoryDealGetDouble(ticket, DEAL_COMMISSION), 2)    + ",";
        d += "\"swap\":"        + DoubleToString(HistoryDealGetDouble(ticket, DEAL_SWAP), 2)           + ",";
        d += "\"time\":"        + IntegerToString(HistoryDealGetInteger(ticket, DEAL_TIME));
        s += d + "}";
    }
    return s + "]";
}

//+------------------------------------------------------------------+
//| Minimal JSON helpers                                              |
//+------------------------------------------------------------------+
string JStr(const string &json, const string &key)
{
    string search = "\"" + key + "\":\"";
    int start = StringFind(json, search);
    if (start < 0) return "";
    start += StringLen(search);
    int end = StringFind(json, "\"", start);
    if (end < 0) return "";
    return StringSubstr(json, start, end - start);
}

long JInt(const string &json, const string &key)
{
    string search = "\"" + key + "\":";
    int start = StringFind(json, search);
    if (start < 0) return 0;
    start += StringLen(search);
    while (start < StringLen(json) && StringGetCharacter(json, start) == ' ') start++;
    string num = "";
    for (int i = start; i < StringLen(json); i++)
    {
        ushort c = StringGetCharacter(json, i);
        if (c >= '0' && c <= '9') num += ShortToString(c);
        else if (c == '-' && StringLen(num) == 0) num += ShortToString(c);
        else break;
    }
    return StringToInteger(num);
}

double JDbl(const string &json, const string &key)
{
    string search = "\"" + key + "\":";
    int start = StringFind(json, search);
    if (start < 0) return 0.0;
    start += StringLen(search);
    while (start < StringLen(json) && StringGetCharacter(json, start) == ' ') start++;
    string num = "";
    for (int i = start; i < StringLen(json); i++)
    {
        ushort c = StringGetCharacter(json, i);
        if ((c >= '0' && c <= '9') || c == '.' || (c == '-' && StringLen(num) == 0))
            num += ShortToString(c);
        else break;
    }
    return StringToDouble(num);
}

string EscJson(const string &s)
{
    string out = s;
    StringReplace(out, "\\", "\\\\");
    StringReplace(out, "\"", "\\\"");
    StringReplace(out, "\n", "\\n");
    StringReplace(out, "\r", "\\r");
    return out;
}
