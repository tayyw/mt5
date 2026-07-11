# OANDA v20 REST API — endpoint reference

All paths are relative to the chosen base URL (`https://api-fxpractice.oanda.com` or `https://api-fxtrade.oanda.com`). Streaming paths use `https://stream-fxpractice.oanda.com` or `https://stream-fxtrade.oanda.com`. Every request needs `Authorization: Bearer <TOKEN>` and `Content-Type: application/json`.

---

## Account

| Method | Path | Description | Rate limit |
|--------|------|-------------|------------|
| GET | `/v3/accounts` | List all accounts for the token | 5/sec |
| GET | `/v3/accounts/{accountID}` | Full account details (orders, trades, positions) | 30/sec |
| GET | `/v3/accounts/{accountID}/summary` | Account summary (NAV, margin, balance, P&L, counts) | 30/sec |
| GET | `/v3/accounts/{accountID}/instruments` | Tradeable instruments for the account. Optional query: `instruments=EUR_USD,USD_CAD` | 120/sec |

Docs: [Account endpoints](https://developer.oanda.com/rest-live-v20/account-ep/)

---

## Instrument & candlestick data

| Method | Path | Description | Key query params |
|--------|------|-------------|------------------|
| GET | `/v3/accounts/{accountID}/instruments/{instrument}/candles` | Candlestick data for an instrument | `granularity` (S5, S15, M1, M4, H1, D, W, M), `from`, `to`, `count` (max 5000), `price` (M/B/A), `smooth`, `dailyAlignment`, `alignmentTimezone`, `weeklyAlignment` |
| GET | `/v3/accounts/{accountID}/candles/latest` | Latest / most recently completed candles | `candleSpecifications` (csv), `units`, `smooth`, `dailyAlignment`, `alignmentTimezone`, `weeklyAlignment` |

Docs: [Pricing (candles)](https://developer.oanda.com/rest-live-v20/pricing-ep/), [Instrument](https://developer.oanda.com/rest-live-v20/instrument-ep/)

---

## Pricing

| Method | Path | Description | Key query params |
|--------|------|-------------|------------------|
| GET | `/v3/accounts/{accountID}/pricing` | Current pricing for instruments | `instruments` (csv, e.g. EUR_USD,USD_CAD), `since`, `includeUnitsAvailable`, `includeHomeConversions` |
| GET | `/v3/accounts/{accountID}/pricing/stream` | **Streaming** prices (use **stream** base URL) | `instruments` (csv), `snapshot`, `includeHomeConversions` |

Docs: [Pricing endpoints](https://developer.oanda.com/rest-live-v20/pricing-ep/)

---

## Order

| Method | Path | Description | Rate limit |
|--------|------|-------------|------------|
| POST | `/v3/accounts/{accountID}/orders` | Create order (market, limit, stop, take profit, stop loss, trailing stop, etc.) | 120/sec |
| GET | `/v3/accounts/{accountID}/orders` | List orders (optional: `ids`, `state`, `instrument`, `count`, `beforeID`) | 120/sec |
| GET | `/v3/accounts/{accountID}/orders/{orderSpecifier}` | Single order | 120/sec |
| PUT | `/v3/accounts/{accountID}/orders/{orderSpecifier}/cancel` | Cancel order | 120/sec |
| PATCH | `/v3/accounts/{accountID}/orders/{orderSpecifier}` | Modify order (e.g. price, distance) | 120/sec |

Order types include Market, Limit, Stop, MarketIfTouched, TakeProfit, StopLoss, TrailingStopLoss; durations include FOK, IOC, GTC, GTD, DAY.  
Docs: [Order endpoints](https://developer.oanda.com/rest-live-v20/order-ep/)

---

## Trade

| Method | Path | Description | Key query params |
|--------|------|-------------|------------------|
| GET | `/v3/accounts/{accountID}/trades` | List trades | `ids`, `state` (OPEN, CLOSED, etc.), `instrument`, `count` (default 50, max 500), `beforeID` |
| GET | `/v3/accounts/{accountID}/trades/{tradeSpecifier}` | Single trade | — |
| PATCH | `/v3/accounts/{accountID}/trades/{tradeSpecifier}` | Modify trade (e.g. take profit, stop loss) | Body: takeProfit, stopLoss, trailingStopLoss |
| PUT | `/v3/accounts/{accountID}/trades/{tradeSpecifier}/close` | Close trade (full or partial) | Body: units, longClose, shortClose |
| PUT | `/v3/accounts/{accountID}/trades/{tradeSpecifier}/orders` | Create dependent order (TP/SL) for trade | — |

Docs: [Trade endpoints](https://developer.oanda.com/rest-live-v20/trade-ep/)

---

## Position

| Method | Path | Description | Rate limit |
|--------|------|-------------|------------|
| GET | `/v3/accounts/{accountID}/positions` | List all positions | 120/sec |
| GET | `/v3/accounts/{accountID}/positions/{instrument}` | Position for one instrument | 120/sec |
| PUT | `/v3/accounts/{accountID}/positions/{instrument}/close` | Close position (full or partial) | 120/sec |

Docs: [Position endpoints](https://developer.oanda.com/rest-live-v20/position-ep/)

---

## Transaction

| Method | Path | Description | Key query params |
|--------|------|-------------|------------------|
| GET | `/v3/accounts/{accountID}/transactions` | List transactions (time-based) | `from`, `to`, `pageSize` (max 1000), `type` (comma-separated). Max range 365 days. |
| GET | `/v3/accounts/{accountID}/transactions/{transactionID}` | Single transaction | — |
| GET | `/v3/accounts/{accountID}/transactions/idrange` | Transactions in ID range | `from`, `to` |
| GET | `/v3/accounts/{accountID}/transactions/sinceid` | Transactions since ID | `id` |
| GET | `/v3/accounts/{accountID}/transactions/stream` | **Streaming** transactions (use **stream** base URL) | `from` |

Docs: [Transaction endpoints](https://developer.oanda.com/rest-live-v20/transaction-ep/)

---

## Quick reference

- **Base URLs:** Practice `api-fxpractice.oanda.com`, Live `api-fxtrade.oanda.com`; streaming: `stream-fxpractice.oanda.com` / `stream-fxtrade.oanda.com`.
- **Auth:** Personal access token from AMP; Bearer in `Authorization` header.
- **Introduction:** [OANDA v20 Introduction](https://developer.oanda.com/rest-live-v20/introduction/).
