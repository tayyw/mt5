# Trading skill — planned scope (reference)

## Venues

- **Crypto:** e.g. Binance, other CEXes (TBD when implementing).
- **Forex:** e.g. MetaTrader 4/5 or broker APIs (TBD when implementing).

## Credentials

- Exchange/broker API keys with **read** and **trade** permissions as required.
- Keys must be stored in `~/.openclaw/credentials/` or via environment variables only. Never embed keys in SOUL.md, skill files, or logs.

## Risk limits (to be enforced by the skill)

- Max position size per symbol and per account.
- Daily loss limit; halt trading when reached.
- Optional: max open orders, allowed symbols only.

## Sandbox and tool policy

- When the skill is implemented, add its tool name to the OpenClaw allow list in config.
- If the skill needs to call exchange APIs from the host or from a sandboxed context, adjust sandbox network policy as needed (e.g. allow outbound only to exchange API hosts); document any change.
