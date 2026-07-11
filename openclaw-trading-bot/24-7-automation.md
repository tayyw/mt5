# 24/7 automatic trading with OpenClaw

Your goal makes sense: the bot should run automatically 24/7 — either **checking periodically** (e.g. every 5 minutes) or **reacting when price hits a level** (hooks). OpenClaw can participate in that, but it does not do the scheduling or streaming by itself.

## What OpenClaw does natively

- The **gateway** runs 24/7 (e.g. via LaunchAgent on the Mac Mini): it’s always on and ready.
- The **agent** is **reactive**: it acts when it receives a message (Telegram, etc.). It does not have a built-in cron, timer, or price-stream subscriber. So out of the box it does **not** “wake up every 5 minutes” or “run when price hits X” on its own.

So: **yes, the idea makes sense; OpenClaw alone cannot run the schedule or the price hooks.** You add that with a small amount of glue.

## How to get 24/7 automatic behavior

Two patterns that work well:

### 1. Trigger the agent on a schedule or on price level

Keep the **agent as the brain**: it runs the OANDA/trading skill when it’s **triggered** by something external.

- **Periodic checks (e.g. every 5 minutes)**  
  - A **scheduler** (e.g. cron, launchd, or a small script with a loop + sleep) runs every 5 minutes and **sends a message to the bot** (e.g. via Telegram or any channel OpenClaw supports).  
  - Example: cron runs a script that uses the Telegram Bot API to send a message to your bot: “Run trading check: evaluate market and trade per my strategy.”  
  - The agent receives the message, runs the OANDA skill (prices, positions, risk), and can place/cancel orders per SOUL and tool policy. So the **trading logic** lives in the agent/skills; the **schedule** is external.

- **Price-level hooks (“when price at X, do Y”)**  
  - A **small companion process** subscribes to OANDA’s **price stream** (or polls the REST API frequently). When price crosses your level, it either:  
    - **A)** Sends a message to the bot (e.g. “EUR_USD bid crossed 1.0500, execute the buy plan”), and the agent runs the trading skill and places the order; or  
    - **B)** Calls the OANDA REST API directly to place the order (the companion is a thin “trigger” that only fires at your level).  
  - So the “hook” is implemented by the stream watcher; the “do something” can be either the agent (A) or direct API (B).

In both cases, OpenClaw **can** do the trading (with the right skills and config); what it **cannot** do by itself is “every 5 min” or “when price hits X” — that’s the job of cron + optional stream watcher.

### 2. Companion trader (optional alternative)

A **separate daemon** does all timing and execution: it runs every 5 min and/or subscribes to the OANDA stream, and it calls the OANDA API directly to place/cancel orders. OpenClaw is then used only for ad-hoc questions (“What are my positions?”, “Change my daily limit”) and strategy updates. The 24/7 loop does not go through the agent.

Use this if you prefer to keep the “auto” logic in code (e.g. Python/Node) and use OpenClaw only as an assistant.

## Recommended for you

Given you want the **bot** to trade 24/7:

1. **Periodic (e.g. 5 min):** Add a **cron job** (or launchd on macOS) that every 5 minutes sends a single message to your OpenClaw bot (e.g. via Telegram). The message tells the agent to run the trading check (e.g. “Run trading check”). The agent uses the OANDA skill (and trading skill when built) to fetch prices/positions and place orders as allowed. No change to OpenClaw’s design — you only add an external trigger.
2. **Price-level hooks:** Add a **stream watcher** (small script or service) that subscribes to OANDA’s price stream, detects when price crosses your levels, and either (A) sends a message to the bot (“Price hit X, execute Y”) so the agent does the trade, or (B) places the order itself via OANDA API. The OANDA skill’s “Stream vs REST” note applies: the stream is for this watcher; the agent keeps using REST for ad-hoc and for any logic you want it to run when triggered by the watcher.

So: **yes, OpenClaw can be the bot that trades 24/7** — as long as “every 5 minutes” and “when price at level” are implemented by a **scheduler** and an optional **price-stream watcher** that **trigger** the agent (or, if you prefer, a companion that executes and the agent only assists).

## Summary

| You want | OpenClaw alone? | Practical approach |
|----------|------------------|---------------------|
| Bot trades 24/7 | No (reactive only) | Cron (or timer) sends “run trading check” to the bot every 5 min; agent runs OANDA/trading skill. |
| When price at X, do Y | No (no stream/hooks) | Companion subscribes to OANDA price stream; when level hit, it messages the bot or places order via API. |
| Agent does the trading logic | Yes | Keep using skills + SOUL; triggers (cron + stream watcher) only tell the agent *when* to run. |

Next steps: implement the cron (or launchd) trigger and, if you want price hooks, a small OANDA price-stream watcher that messages your bot or calls the API at your levels.

---

## Stream watcher (price-level hooks)

The stream watcher is a small, long-running process that subscribes to OANDA’s price stream, compares incoming prices to your configured levels, and triggers an action when a level is crossed (e.g. send a message to the OpenClaw bot or place an order via the OANDA API).

### Role

- **Input:** OANDA streaming prices (and optional heartbeats).
- **Config:** Which instruments to watch, price levels (e.g. EUR_USD bid ≥ 1.0500 or ≤ 1.0300), and what to do when a level is hit.
- **Output:** Either (A) send a message to your Telegram bot so the **agent** runs the trading skill and places the order, or (B) call the OANDA REST API directly to place the order.

Run the watcher on the same host as OpenClaw (e.g. Mac Mini) or any machine with network access to OANDA and, for (A), to the Telegram Bot API.

### OANDA price stream

- **URL (GET, long-lived):**  
  `https://stream-fxpractice.oanda.com/v3/accounts/{accountID}/pricing/stream?instruments=EUR_USD,USD_CAD`  
  (Live: `https://stream-fxtrade.oanda.com/...`.)
- **Headers:** `Authorization: Bearer <OANDA_TOKEN>`, `Content-Type: application/json`. Optional: `Accept-Datetime-Format: RFC3339`.
- **Query params:**  
  - `instruments` (required): comma-separated list, e.g. `EUR_USD`, `USD_CAD`.  
  - `snapshot` (optional, default true): send a snapshot of current prices when the connection opens.  
  - `includeHomeConversions` (optional): include home conversion factors.
- **Response:** Chunked transfer encoding. Each chunk contains one or more JSON objects, one per line (newline-delimited JSON). Each line is either:
  - **ClientPrice:** `instrument`, `time`, `bids`, `asks`, `closeoutBid`, `closeoutAsk`, `status` (e.g. `"tradeable"`). Use `closeoutBid` / `closeoutAsk` for a single executable price per side.
  - **PricingHeartbeat:** `"type": "HEARTBEAT"`, `time` — sent about every 5 seconds; use to detect a live connection.
- **Rate:** Up to 4 price updates per second per instrument. Reconnect with backoff on disconnect or HTTP error.

See [OANDA Pricing stream](https://developer.oanda.com/rest-live-v20/pricing-ep/) (stream endpoint and response schema).

### Level logic

- **Config per instrument:** e.g. `EUR_USD`: trigger when `closeoutBid >= 1.0500` (buy level) or `closeoutAsk <= 1.0300` (sell level). Store the last direction crossed to avoid re-triggering on every tick (e.g. only trigger when crossing from below to above, or above to below).
- **Cooldown (optional):** After triggering, ignore the same level for N minutes or until price moves away and crosses again, to avoid duplicate orders or messages.

### Triggering the OpenClaw bot (option A)

To have the **agent** execute the trade when a level is hit:

1. **Telegram:** Your OpenClaw bot is paired with your Telegram user. Use the **Telegram Bot API** to send a message *as if you had typed it*: have the watcher call `sendMessage` to the **chat id** of your conversation with the bot (the same chat where you talk to the bot).
   - **Endpoint:** `POST https://api.telegram.org/bot<BOT_TOKEN>/sendMessage`
   - **Body:** `{"chat_id": "<YOUR_CHAT_ID>", "text": "EUR_USD bid crossed 1.0500. Execute the buy plan per my strategy."}`
   - **Getting chat_id:** Send a message to your bot, then call `GET https://api.telegram.org/bot<BOT_TOKEN>/getUpdates` and read `message.chat.id` from the update.
2. The agent receives the message like any user message, runs the OANDA/trading skill, and can place the order per SOUL and tool policy. Keep the message clear and specific (instrument, level, and intent) so the agent knows what to do.

Store `BOT_TOKEN` and `YOUR_CHAT_ID` in env or a config file the watcher reads; do not commit them.

### Placing the order directly (option B)

If the watcher should place the order itself (no agent in the loop):

- When a level is crossed, the watcher calls the OANDA REST API: `POST https://api-fxtrade.oanda.com/v3/accounts/{accountID}/orders` (or practice URL) with the same Bearer token and a JSON body for the order (e.g. market order with instrument, units). See the OANDA skill’s **reference.md** (Order section) and [Order endpoint](https://developer.oanda.com/rest-live-v20/order-ep/).
- Enforce risk limits (max size, daily loss) in the watcher or via a shared config the agent can also read.

### Deployment

- **Process:** Run the watcher as a long-lived process (e.g. Python or Node script in a loop: connect to stream → read lines → parse JSON → check levels → trigger action; reconnect on disconnect).
- **Credentials:** Read OANDA token and account ID from env (e.g. `OANDA_TOKEN`, `OANDA_ACCOUNT_ID`) or from `~/.openclaw/credentials/` if the watcher runs on the same host and you keep a single source of truth. For option A, add Telegram `BOT_TOKEN` and `CHAT_ID`.
- **Service:** Run under launchd (macOS) or systemd (Linux) so it starts on boot and restarts on failure. Redirect logs to a file or logging service for debugging.
- **Config file (optional):** Store instruments, levels, and action (message_bot vs place_order) in a small JSON or YAML file so you can change levels without editing code.

### Summary

| Piece | Responsibility |
|-------|-----------------|
| Stream watcher | Subscribe to OANDA price stream; detect level cross; send Telegram message (A) or call OANDA order API (B). |
| OpenClaw agent | (A only) Receive message; run OANDA/trading skill; place/cancel orders per SOUL. |
| Cron / launchd | (Separate) Every 5 min, send “Run trading check” to the bot for periodic checks. |

With the stream watcher in place, “when price is at a certain level then do something” is complete: the watcher handles the “when,” and either the agent (A) or the watcher (B) handles the “do something.”
