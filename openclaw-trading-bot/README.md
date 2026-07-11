# OpenClaw trading bot foundation

Foundational files for an OpenClaw-based automated trading bot (forex, crypto): SOUL.md, config, and a placeholder trading skill. The trading skill itself is not yet implemented.

## Deploy to your OpenClaw host

1. **SOUL.md**  
   Copy to the OpenClaw workspace:
   ```bash
   mkdir -p ~/.openclaw/workspace
   cp SOUL.md ~/.openclaw/workspace/SOUL.md
   ```

2. **Config**  
   Either run the commands in [config-commands.md](config-commands.md) by hand, or edit [apply-config.sh](apply-config.sh) to replace `YOUR_STRONG_PASSWORD_HERE` and `YOUR_TELEGRAM_BOT_TOKEN`, then run:
   ```bash
   chmod +x apply-config.sh
   ./apply-config.sh
   openclaw gateway restart
   ```

3. **Skills**  
   Copy the skill directories into OpenClaw’s skills location (see OpenClaw docs for the path, e.g. under `~/.openclaw/` or your project workspace):
   ```bash
   cp -r skills/trading /path/to/openclaw/skills/
   cp -r skills/oanda /path/to/openclaw/skills/
   ```
   - **oanda** — OANDA v20 REST API (pricing, candles, account, orders, trades, positions, transactions). Requires OANDA token and account ID in credentials or env.
   - **trading** — Placeholder for the future trading skill; add its tool to the config allow list when implemented and adjust sandbox/network if needed.

## Secrets

Do not commit real secrets. Use placeholders in `apply-config.sh` and store API keys, bot tokens, and exchange credentials in the OpenClaw credentials store or environment variables.
