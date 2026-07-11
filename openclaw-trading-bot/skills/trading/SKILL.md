---
name: trading
description: Tools for automated forex and crypto trading (placeholder; not yet implemented).
---

# Trading skill

This skill will provide tools for automated trading on forex and crypto venues. **It is not yet implemented.**

When implemented, it will:

- Connect to configured exchanges (e.g. Binance, MT4/MT5, or other supported venues) via API.
- Place and cancel orders within skill-defined limits.
- Optionally manage risk (e.g. position size, stop-loss) according to configuration.

Trade execution is only via this skill and only when the user has installed and enabled it. The agent must not execute trades by any other means; see SOUL.md boundaries.

Implement the skill in this directory (tools, config schema, and credential usage per reference.md) when ready.
