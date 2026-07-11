---
name: oanda
description: Use the OANDA v20 REST API for forex market data, account info, and trading (pricing, candles, orders, trades, positions, transactions).
---

# OANDA v20 API skill

Use this skill when the user asks for OANDA forex data or account/trading operations: real-time or historical prices, candlesticks, account summary, open positions, trades, orders, or transaction history.

## When to use

- User asks for OANDA account balance, summary, NAV, margin, or P&L.
- User asks for forex pair prices (e.g. EUR_USD, USD_CAD), candles, or market data.
- User asks for open positions, open trades, or order book / pending orders.
- User asks for transaction history or trade history for an OANDA account.
- User requests to place, modify, or cancel an order or close a trade (only if SOUL.md and tool policy allow execution; otherwise provide instructions or read-only data only).

## Authentication and base URLs

- **Credentials:** OANDA personal access token and (for account-scoped calls) account ID. Obtain the token from the [Account Management Portal (AMP)](https://www.oanda.com/) → Manage API Access. Never embed the token in SOUL.md or skill files; read from `~/.openclaw/credentials/` or environment variables (e.g. `OANDA_TOKEN`, `OANDA_ACCOUNT_ID`).
- **Header:** `Authorization: Bearer <TOKEN>`, `Content-Type: application/json`. Optional: `Accept-Datetime-Format: RFC3339` or `UNIX`.
- **REST base URL:**
  - Practice: `https://api-fxpractice.oanda.com`
  - Live: `https://api-fxtrade.oanda.com`
- **Streaming base URL** (for price/transaction streams):
  - Practice: `https://stream-fxpractice.oanda.com`
  - Live: `https://stream-fxtrade.oanda.com`

Use the base URL that matches the user's account (practice vs live). All paths below are relative to that base (e.g. `GET {base}/v3/accounts`).

## Stream vs REST — when to use which

- **Use REST** for the OpenClaw agent (Telegram chat, one-off queries): "What's EUR_USD?", "Show my positions", "Place this order". Agent tools are request/response; a single GET or POST per question is the right fit. Use the **REST** base URL and the non-stream endpoints (e.g. `GET /v3/accounts/{accountID}/pricing`, `GET .../positions`).
- **Use the stream API** for a **separate 24/7 process** (e.g. a small service or script that runs alongside OpenClaw): subscribe to the price stream and/or transaction stream for low-latency updates (e.g. up to 4 prices/sec per instrument), react to price levels or new fills without polling. The agent cannot hold a long-lived stream connection; that belongs in a dedicated process. When you implement the trading skill, that process can use the stream; the agent continues to use REST for ad-hoc queries and overrides.

## API areas (all relevant v20 endpoints)

1. **Account** — List accounts, account details, account summary.
2. **Instrument** — List tradeable instruments for an account; candlestick data for an instrument.
3. **Pricing** — Current prices for instruments; latest candles; price stream (streaming).
4. **Order** — Create orders (market, limit, stop, take profit, stop loss, trailing stop); list/cancel orders.
5. **Trade** — List open/closed trades; close or modify trades.
6. **Position** — List all positions; position for a single instrument.
7. **Transaction** — List transactions (time range, type filter, pagination).

See **reference.md** in this skill for full endpoint paths, methods, and parameters. Official docs: [OANDA v20 Introduction](https://developer.oanda.com/rest-live-v20/introduction/), [Pricing](https://developer.oanda.com/rest-live-v20/pricing-ep/), [Account](https://developer.oanda.com/rest-live-v20/account-ep/), [Order](https://developer.oanda.com/rest-live-v20/order-ep/), [Trade](https://developer.oanda.com/rest-live-v20/trade-ep/), [Position](https://developer.oanda.com/rest-live-v20/position-ep/), [Transaction](https://developer.oanda.com/rest-live-v20/transaction-ep/), [Instrument](https://developer.oanda.com/rest-live-v20/instrument-ep/).

## How to call the API

- Use the available HTTP tool (e.g. `web_fetch` or the tool that allows sending GET/POST/PATCH/PUT with headers) to call the endpoints in reference.md.
- Replace `{accountID}` with the user's OANDA account ID and `{instrument}` with the instrument name (e.g. `EUR_USD`).
- For streaming endpoints, use the streaming base URL and handle chunked/streaming response per OANDA docs.
- Respect rate limits (e.g. 5/sec for list accounts, 30/sec for account details, 120/sec for orders/trades/positions/transactions/pricing/candles).

## Boundaries

- Do not execute orders, close trades, or modify positions unless the user has explicitly requested it and SOUL.md / tool policy permit execution.
- Never log or echo the Bearer token or account ID in conversation; use credentials only for outbound API calls.
