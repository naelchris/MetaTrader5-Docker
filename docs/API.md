# MT5 Bridge API

A C++ (Drogon) REST API that bridges MetaTrader 5 to external systems via a MQL5 Expert Advisor TCP connection.

---

## Architecture

```
                            host
                       127.0.0.1:18080
External Client ─────────────┐
                             │  HTTP
                             ▼
              ┌──────────────────────────────┐
              │  mt5_bridge  (172.28.0.10)   │
              │  C++ Drogon REST API :8080   │
              │  + TCP listener :9000        │
              └──────────────▲───────────────┘
                             │  TCP (Docker network mt5_net)
                             │  EA dials out to 172.28.0.10:9000
              ┌──────────────┴───────────────┐
              │  mt5          (172.28.0.20)  │
              │  MetaTrader 5 in Wine        │
              │  MQL5 EA: MT5Bridge.mq5      │
              └──────────────────────────────┘
```

The EA connects **out** to the bridge — no inbound port is needed on the MT5 container. Both containers sit on the static `mt5_net` network (`172.28.0.0/24`) so the bridge IP is stable across restarts and can be added to MT5's WebRequest allowlist.

---

## Base URL

```
http://localhost:18080
```

The bridge container exposes port `8080` internally; `docker-compose.yaml` publishes it on the host as `127.0.0.1:18080`.

---

## Response envelope

All responses share the same envelope.

**Success**
```json
{
  "status": "ok",
  "data": { ... }
}
```

**Error** — HTTP 502 for EA-level errors, 400 for bad requests, 503 when EA is disconnected
```json
{
  "status": "error",
  "message": "human-readable reason"
}
```

---

## Endpoints

### Health

#### `GET /health`

Returns whether the MQL5 EA is currently connected.

**Response 200 — connected**
```json
{
  "status": "ok",
  "connected": true,
  "message": "EA connected"
}
```

**Response 503 — EA not connected**
```json
{
  "status": "error",
  "connected": false,
  "message": "EA not connected"
}
```

---

### Account

#### `GET /account`

Returns account balance, equity, margin, and trading status.

**Response**
```json
{
  "status": "ok",
  "data": {
    "login": 12345678,
    "name": "John Doe",
    "server": "BrokerName-Demo",
    "currency": "USD",
    "balance": 10000.00,
    "equity": 10245.50,
    "margin": 200.00,
    "free_margin": 10045.50,
    "profit": 245.50,
    "leverage": 100,
    "trade_allowed": true
  }
}
```

---

### Positions

#### `GET /positions`

Returns all currently open positions.

**Response**
```json
{
  "status": "ok",
  "data": [
    {
      "ticket": 123456789,
      "symbol": "EURUSD",
      "type": 0,
      "volume": 0.10,
      "open_price": 1.08450,
      "current_price": 1.08620,
      "sl": 1.08000,
      "tp": 1.09000,
      "profit": 17.00,
      "swap": -0.50,
      "comment": "api trade",
      "time": 1716800000
    }
  ]
}
```

**Position `type` values**

| Value | Meaning |
|-------|---------|
| `0` | Buy |
| `1` | Sell |

---

#### `POST /positions/{ticket}/close`

Closes an open position at market price.

**Path parameter**

| Name | Type | Description |
|------|------|-------------|
| `ticket` | integer | Position ticket number |

**Example**
```
POST /positions/123456789/close
```

**Response**
```json
{
  "status": "ok",
  "data": {
    "ticket": 123456790,
    "deal": 987654321,
    "retcode": 10009,
    "comment": "Request executed"
  }
}
```

---

### Orders

#### `GET /orders`

Returns all pending (unfilled) orders.

**Response**
```json
{
  "status": "ok",
  "data": [
    {
      "ticket": 111222333,
      "symbol": "GBPUSD",
      "type": 2,
      "volume": 0.05,
      "price": 1.26500,
      "sl": 1.26000,
      "tp": 1.27500,
      "comment": "limit entry",
      "time_setup": 1716800000
    }
  ]
}
```

**Order `type` values**

| Value | Meaning |
|-------|---------|
| `0` | Buy Market |
| `1` | Sell Market |
| `2` | Buy Limit |
| `3` | Sell Limit |
| `4` | Buy Stop |
| `5` | Sell Stop |

---

#### `POST /orders`

Places a new market or pending order.

**Request body**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `symbol` | string | Yes | Instrument name e.g. `"EURUSD"` |
| `type` | integer | Yes | Order type (see table above) |
| `volume` | float | Yes | Lot size |
| `price` | float | No | Limit/stop price. For market orders use `0` or omit |
| `sl` | float | No | Stop loss price. `0` = none |
| `tp` | float | No | Take profit price. `0` = none |
| `comment` | string | No | Order comment (max 31 chars) |

**Market buy example**
```json
{
  "symbol": "EURUSD",
  "type": 0,
  "volume": 0.10,
  "sl": 1.08000,
  "tp": 1.09500,
  "comment": "api buy"
}
```

**Limit sell example**
```json
{
  "symbol": "GBPUSD",
  "type": 3,
  "volume": 0.05,
  "price": 1.27000,
  "sl": 1.27500,
  "tp": 1.25500,
  "comment": "limit sell"
}
```

**Response**
```json
{
  "status": "ok",
  "data": {
    "ticket": 123456791,
    "deal": 987654322,
    "retcode": 10009,
    "comment": "Request executed",
    "price": 1.08620,
    "volume": 0.10
  }
}
```

**Common `retcode` values**

| Code | Meaning |
|------|---------|
| `10009` | Request executed successfully |
| `10016` | Invalid stops (bad SL/TP) |
| `10018` | Market closed |
| `10019` | Insufficient funds |
| `10006` | Request rejected |

---

#### `DELETE /orders/{ticket}`

Cancels a pending order.

**Path parameter**

| Name | Type | Description |
|------|------|-------------|
| `ticket` | integer | Order ticket number |

**Example**
```
DELETE /orders/111222333
```

**Response**
```json
{
  "status": "ok",
  "data": {
    "retcode": 10009,
    "comment": "Request executed"
  }
}
```

---

### History

#### `GET /history/orders?from={unix}&to={unix}`

Returns historical (filled or cancelled) orders within a time range.

**Query parameters**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `from` | integer | `0` | Start Unix timestamp |
| `to` | integer | now | End Unix timestamp |

**Example**
```
GET /history/orders?from=1716700000&to=1716800000
```

**Response**
```json
{
  "status": "ok",
  "data": [
    {
      "ticket": 111000111,
      "symbol": "EURUSD",
      "type": 0,
      "volume": 0.10,
      "price": 1.08450,
      "state": 2,
      "time_setup": 1716700100,
      "time_done": 1716700101
    }
  ]
}
```

**Order `state` values**

| Value | Meaning |
|-------|---------|
| `1` | Placed |
| `2` | Filled |
| `3` | Cancelled |
| `4` | Partial |
| `5` | Rejected |

---

#### `GET /history/deals?from={unix}&to={unix}`

Returns historical deals (executions) within a time range.

**Query parameters** — same as `/history/orders`

**Response**
```json
{
  "status": "ok",
  "data": [
    {
      "ticket": 987000001,
      "symbol": "EURUSD",
      "type": 0,
      "entry": 0,
      "volume": 0.10,
      "price": 1.08450,
      "profit": 0.00,
      "commission": -0.70,
      "swap": 0.00,
      "time": 1716700101
    }
  ]
}
```

**Deal `entry` values**

| Value | Meaning |
|-------|---------|
| `0` | Entry in (position opened) |
| `1` | Entry out (position closed) |
| `2` | Reverse |

---

## Error examples

**EA not connected**
```json
HTTP 502
{
  "status": "error",
  "message": "EA not connected"
}
```

**Missing required field**
```json
HTTP 400
{
  "status": "error",
  "message": "Missing required field: symbol"
}
```

**Position not found**
```json
HTTP 502
{
  "status": "error",
  "message": "Position not found: 123456789"
}
```

---

## Running & Deployment

### Prerequisites

- Docker ≥ 24
- Docker Compose ≥ 2

---

### 1. Configure environment

```bash
cp .env.example .env
```

Edit `.env`:
```env
UID=1000
GID=1000
CUSTOM_USER=your_username
PASSWORD=your_secure_password
```

---

### 2. Start MT5 + bridge

```bash
docker compose up -d
```

The first run downloads and installs MetaTrader 5 inside Wine, which takes **5–10 minutes**. Subsequent starts are fast.

Watch logs:
```bash
docker compose logs -f
```

---

### 3. Allow the bridge URL inside MT5 *(one-time, required)*

MT5 blocks `SocketConnect()` to any address that is not in the **Allow WebRequest for listed URL** allowlist (since build 1881). Without this step the EA loads but the connection silently fails.

1. Open MT5 in your browser at `http://localhost:3000`
2. **Tools → Options → Expert Advisors**
3. Tick ☑ **Allow WebRequest for listed URL**
4. Click **Add** and enter exactly: `http://172.28.0.10:9000`
5. Click **OK**

The bridge container is pinned to `172.28.0.10` in `docker-compose.yaml`, so this URL is stable across restarts.

---

### 4. Install and configure the EA

1. In the MT5 terminal go to **File → Open Data Folder → MQL5 → Experts → MT5Bridge**
   - The `MT5Bridge.mq5` file is already mounted there via the volume
2. In MetaEditor, open `MT5Bridge.mq5` and press **F7** to compile
3. Back in the MT5 terminal, open any chart (e.g. EURUSD, M1)
4. Drag **MT5Bridge** from the Navigator panel onto the chart
5. In the EA settings dialog leave defaults (or override):
   - `BridgeHost` = `172.28.0.10` *(matches the static IP in docker-compose.yaml)*
   - `BridgePort` = `9000`
   - `TimerIntervalMs` = `50`
6. Enable **Allow DLL imports** and **Allow live trading**, then click OK
7. The EA journal tab should show: `MT5Bridge: connected to 172.28.0.10:9000`

---

### 5. Verify

```bash
curl http://localhost:18080/health
```

Expected:
```json
{"connected":true,"message":"EA connected","status":"ok"}
```

---

### 6. Quick smoke test

```bash
# Account info
curl http://localhost:18080/account

# Open positions
curl http://localhost:18080/positions

# Place a market buy (demo account only — real money is real)
curl -X POST http://localhost:18080/orders \
  -H "Content-Type: application/json" \
  -d '{"symbol":"EURUSD","type":0,"volume":0.01,"sl":0,"tp":0,"comment":"test"}'
```

---

### Rebuilding the bridge after code changes

```bash
docker compose up -d --build bridge
```

The MT5 container does not need to restart; the EA will reconnect automatically within ~2 seconds.

---

### Stopping everything

```bash
docker compose down
```

To also remove the MT5 installation (Wine prefix):
```bash
docker compose down -v
```

---

### Port reference

| Container port | Host binding | Purpose |
|----------------|--------------|---------|
| `3000` | `127.0.0.1:3000` | MT5 VNC web UI |
| `8001` | `127.0.0.1:8001` | mt5linux rpyc (internal, legacy) |
| `8080` | `127.0.0.1:18080` | Bridge REST API |
| `9000` | none — Docker network only | EA → bridge TCP connection |

### Network reference

The `mt5_net` Docker network uses subnet `172.28.0.0/24` with static IPs:

| Container | Static IP |
|-----------|-----------|
| `mt5_bridge` | `172.28.0.10` |
| `mt5` | `172.28.0.20` |

---

### Troubleshooting

| Symptom | Fix |
|---------|-----|
| `/health` returns `"EA not connected"` but EA is attached and no error in journal | The bridge URL is not in the **Allow WebRequest for listed URL** list. `SocketConnect()` fails silently when blocked. Add `http://172.28.0.10:9000` in **Tools → Options → Expert Advisors**. |
| EA journal shows connection refused | Bridge container may not be running — `docker compose ps bridge` |
| EA journal shows `connected to <hostname>` then immediately disconnects | Bridge accepted the TCP connection but the URL is missing from MT5's allowlist — same fix as above |
| Bridge container has a different IP than `172.28.0.10` | The `mt5_net` network already existed with a different subnet. Run `docker compose down && docker network rm mt5_net && docker compose up -d`. |
| `retcode 10018` on place order | Market is closed (weekend / holiday) |
| `retcode 10016` on place order | SL/TP are too close to current price — check broker's minimum stop level |
| Build fails in Docker | Ensure Docker has at least 2 GB RAM available for the Drogon compile |
