# Integration Guide

How to stand up the MT5 ↔ bridge stack from scratch and call the REST API from your own application.

This guide is focused on the *integration path* — what to install, what to click, what to call, and the one MT5 gotcha that traps everyone. For the full endpoint reference see [API.md](./API.md).

---

## 1. How the pieces fit together

```
                            host
                       127.0.0.1:18080
Your app  ───────────────────┐
                             │  HTTP  (REST)
                             ▼
              ┌──────────────────────────────┐
              │  mt5_bridge  172.28.0.10     │
              │  Drogon REST API   :8080     │
              │  TCP listener      :9000     │
              └──────────────▲───────────────┘
                             │  TCP — EA dials OUT
                             │  to 172.28.0.10:9000
              ┌──────────────┴───────────────┐
              │  mt5          172.28.0.20    │
              │  MetaTrader 5 in Wine        │
              │  MQL5 EA: MT5Bridge.mq5      │
              └──────────────────────────────┘
```

Key facts:

- **Two containers, one Docker network (`mt5_net`, subnet `172.28.0.0/24`).** Both IPs are pinned in `docker-compose.yaml` so they survive restarts.
- **The EA is the TCP client**, not the server. It dials out to the bridge every 50 ms via `OnTimer()` until connected. No inbound port is opened on the MT5 container.
- **Your app never talks to MT5 directly.** It talks to the bridge over HTTP on `127.0.0.1:18080`. The bridge translates HTTP requests into newline-delimited JSON commands and forwards them to the EA over the TCP socket.

---

## 2. Prerequisites

- Docker ≥ 24 and Docker Compose ≥ 2
- A free MT5 demo account (any broker) — credentials are entered inside MT5 itself, not in `.env`
- ~5 GB free disk for the MT5 image + Wine install on first run
- Linux/macOS host (`linux/amd64`). On Apple Silicon, Docker emulates amd64 automatically; expect slower first boot.

---

## 3. First-time setup

### 3.1 Configure environment

```bash
cp .env.example .env
```

Edit `.env`:

```env
UID=1000
GID=1000
CUSTOM_USER=admin
PASSWORD=change-me
```

`CUSTOM_USER` / `PASSWORD` are the credentials for the MT5 web UI (KasmVNC), **not** your broker login.

### 3.2 Start the stack

```bash
docker compose up -d
```

First boot downloads + installs MT5 inside Wine — **5–10 minutes**. Watch:

```bash
docker compose logs -f mt5
```

When you see the MT5 splash, move on.

### 3.3 Allow the bridge URL inside MT5 *(this is the gotcha)*

Since MT5 build 1881, **`SocketConnect()` checks the same allowlist as `WebRequest()`**. If the target host is not listed, the call fails *silently* — no journal entry, no error, the EA just sits there trying forever. Fix:

1. Open MT5 in your browser: `http://localhost:3000` (login with `CUSTOM_USER` / `PASSWORD`)
2. **Tools → Options → Expert Advisors**
3. Tick ☑ **Allow WebRequest for listed URL**
4. Click **Add**, paste exactly: `http://172.28.0.10:9000`
5. **OK**

You only have to do this once per MT5 profile.

### 3.4 Log in to your broker

Inside MT5: **File → Login to Trade Account** and enter your demo credentials. Wait until the bottom-right shows a live connection (kbps numbers ticking).

### 3.5 Compile and attach the EA

1. **File → Open Data Folder → MQL5 → Experts → MT5Bridge** — the source file `MT5Bridge.mq5` is already there (bind-mounted from `./Metatrader/experts/`)
2. Right-click `MT5Bridge.mq5` → **Compile** (or open it in MetaEditor and press **F7**). You should get `0 errors, 0 warnings`.
3. Back in the MT5 terminal, open any chart (e.g. **EURUSD M1**)
4. From the **Navigator → Expert Advisors** panel, drag **MT5Bridge** onto the chart
5. In the dialog:
   - **Common** tab: tick ☑ *Allow Algo Trading*, ☑ *Allow DLL imports*
   - **Inputs** tab: defaults are correct (`BridgeHost = 172.28.0.10`, `BridgePort = 9000`)
   - Click **OK**
6. Also make sure the global **Algo Trading** toolbar button is green
7. The chart should show a smiley face (☺) in the top-right corner

### 3.6 Verify

```bash
curl http://localhost:18080/health
```

Expected:

```json
{"connected":true,"message":"EA connected","status":"ok"}
```

If you see `connected:false`, jump to [Troubleshooting](#7-troubleshooting).

---

## 4. Calling the API from your application

The bridge speaks plain HTTP + JSON on `127.0.0.1:18080`. No auth, no headers required. Bind it to `0.0.0.0` in `docker-compose.yaml` only if you understand the risk — this gives anyone on the network the ability to place trades.

### Python

```python
import requests

BASE = "http://127.0.0.1:18080"

def account():
    return requests.get(f"{BASE}/account").json()["data"]

def positions():
    return requests.get(f"{BASE}/positions").json()["data"]

def buy(symbol: str, volume: float, sl: float = 0, tp: float = 0):
    body = {"symbol": symbol, "type": 0, "volume": volume,
            "sl": sl, "tp": tp, "comment": "api"}
    return requests.post(f"{BASE}/orders", json=body).json()

print(account())
print(buy("EURUSD", 0.01))
```

### Node.js

```js
const BASE = "http://127.0.0.1:18080";

const account = () =>
  fetch(`${BASE}/account`).then(r => r.json()).then(j => j.data);

const buy = (symbol, volume, sl = 0, tp = 0) =>
  fetch(`${BASE}/orders`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ symbol, type: 0, volume, sl, tp, comment: "api" }),
  }).then(r => r.json());

console.log(await account());
console.log(await buy("EURUSD", 0.01));
```

### Health-check pattern

Before placing any trade, gate on `/health`:

```python
def ready() -> bool:
    try:
        r = requests.get(f"{BASE}/health", timeout=2)
        return r.status_code == 200 and r.json().get("connected") is True
    except requests.RequestException:
        return False
```

The bridge returns HTTP **503** when the EA is not connected, so a status-only check works too.

See [API.md](./API.md) for the full endpoint list, request/response shapes, order-type codes, and retcode meanings.

---

## 5. Day-2 operations

### Restart only the bridge after a code change

```bash
docker compose up -d --build bridge
```

MT5 keeps running. The EA auto-reconnects within ~50 ms.

### Restart only MT5

```bash
docker compose restart mt5
```

Your installed EA, charts, and login are persisted in the `./config/` bind mount.

### Update the EA source

Edit `Metatrader/experts/MT5Bridge.mq5` on the host — the change appears instantly inside MT5 (bind mount). Recompile in MetaEditor (F7); the EA on the chart auto-reloads.

### Stop everything

```bash
docker compose down          # keeps MT5 install
docker compose down -v       # also wipes the Wine prefix
```

### Inspect the network

```bash
docker network inspect mt5_net
```

Both containers should show their pinned IPs.

---

## 6. Production hardening checklist

This project is intentionally minimal. Before exposing it beyond `localhost`:

- [ ] **Add authentication.** The bridge has no auth. Put it behind a reverse proxy with a token or mTLS.
- [ ] **Bind to a non-routable interface only.** The compose file already binds to `127.0.0.1`; leave it that way unless you understand the risk.
- [ ] **Restrict outbound MT5 internet access** to your broker's IP range only.
- [ ] **Use a demo account first.** Then a real account with a *small* balance. The API will happily lose all of it.
- [ ] **Validate input on your side.** The bridge passes `volume`, `sl`, `tp`, etc. straight through to `OrderSend()`. A typo in lot size is a real trade.
- [ ] **Log every order.** The MT5 Journal tab is the source of truth, but it does not persist across reinstalls. Mirror calls in your own system.
- [ ] **Watch for `retcode != 10009`** in every order response — many failures (insufficient funds, invalid stops, market closed) come back with HTTP 200 but a non-success retcode.

---

## 7. Troubleshooting

### `/health` says `connected: false`, EA Journal is silent

99% of the time: MT5's WebRequest allowlist is missing `http://172.28.0.10:9000`. See [3.3](#33-allow-the-bridge-url-inside-mt5-this-is-the-gotcha). `SocketConnect()` fails silently when blocked.

### EA Journal shows `connection refused`

The bridge container is not running:

```bash
docker compose ps bridge
docker compose logs bridge
```

### Bridge container has a different IP than 172.28.0.10

Usually because the `mt5_net` network was created *before* you added the static subnet config. Recreate it:

```bash
docker compose down
docker network rm mt5_net
docker compose up -d
```

Then verify:

```bash
docker inspect mt5_bridge \
  --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
# → 172.28.0.10
```

### The 172.28.0.0/24 subnet clashes with another network

Pick a different /24 in `docker-compose.yaml` (e.g. `172.29.0.0/24`), update the EA's `BridgeHost` input default in `Metatrader/experts/MT5Bridge.mq5`, and update the MT5 WebRequest allowlist entry. All three must match.

### Order returns HTTP 200 but `retcode` is not 10009

The trade was rejected by MT5/broker. Common codes:

| Code | Meaning |
|------|---------|
| `10016` | Invalid SL/TP (too close to price) |
| `10018` | Market closed (weekend, holiday, outside session) |
| `10019` | Insufficient funds |
| `10006` | Request rejected (often: trading disabled on the account) |

Full table in [API.md](./API.md#common-retcode-values).

### Trade does not happen at all (no retcode)

Check that the **Algo Trading** button in the MT5 toolbar is green, the chart has the smiley face, and the account has *Trade allowed* (`GET /account` → `trade_allowed: true`).

### EA disappears from the chart after MT5 restart

By default MT5 does not save EA state per chart on close. Re-attach the EA, then save the chart as a template (right-click → **Template → Save Template**) and set it as the default.

---

## 8. File map

| Path | What it is |
|------|------------|
| `docker-compose.yaml` | Two-container stack + pinned static IPs |
| `src/` | C++ Drogon bridge source (`MT5Client.{h,cpp}`, `controllers/`, `main.cpp`) |
| `src/Dockerfile` | Bridge container image |
| `Metatrader/experts/MT5Bridge.mq5` | The EA — runs inside MT5, talks TCP to the bridge |
| `Metatrader/start.sh` | MT5 boot script (mounted into the MT5 container) |
| `config/` | MT5 Wine prefix (auto-created, gitignored) |
| `docs/API.md` | Full REST endpoint reference |
| `docs/INTEGRATION.md` | This file |
