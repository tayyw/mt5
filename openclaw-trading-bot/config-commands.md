# OpenClaw config commands (trading bot)

Run these on the OpenClaw host. Replace placeholders (`YOUR_*`) with real values; do not commit secrets.

For 24/7 automation (periodic checks, stream watcher), see [24-7-automation.md](24-7-automation.md). Those use external triggers and do not require extra OpenClaw config.

## Gateway

- **Bind to localhost only** (never expose to the internet):
  ```bash
  openclaw config set gateway.bind "127.0.0.1"
  ```
- **Auth password** (use a strong password, 20+ chars; store in a password manager):
  ```bash
  openclaw config set gateway.auth.password "YOUR_STRONG_PASSWORD_HERE"
  ```

## Telegram

- **Enable Telegram** and set bot token (from [@BotFather](https://t.me/BotFather)):
  ```bash
  openclaw config set channels.telegram.enabled true
  openclaw config set channels.telegram.botToken "YOUR_TELEGRAM_BOT_TOKEN"
  openclaw config set channels.telegram.dmPolicy "pairing"
  openclaw config set channels.telegram.configWrites false
  openclaw config set channels.telegram.groupPolicy "disabled"
  ```
  - `dmPolicy "pairing"`: strangers cannot message the bot until you approve a pairing code.
  - `configWrites false`: prevents changing config via Telegram.
  - `groupPolicy "disabled"`: bot is not used in groups.

## Models (optional)

If you use Kimi + Claude fallback and want aliases for `/model` in Telegram:

```bash
openclaw config set agents.defaults.models '{
  "moonshotai/kimi-k2.5": { "alias": "kimi" },
  "anthropic/claude-sonnet-4-5": { "alias": "sonnet" }
}'
```

Add fallback after onboarding: `openclaw models auth add` (choose Anthropic), then `openclaw models fallbacks add anthropic/claude-sonnet-4-5`.

## Sandbox (Docker)

- **Enable sandbox** (all sessions in Docker):
  ```bash
  openclaw config set agents.defaults.sandbox.mode "all"
  openclaw config set agents.defaults.sandbox.scope "session"
  openclaw config set agents.defaults.sandbox.workspaceAccess "ro"
  ```
- **Network isolation** (no outbound from sandbox; built-in web tools run on gateway):
  ```bash
  openclaw config set agents.defaults.sandbox.docker.network "none"
  ```
  **Note:** Built-in web tools (e.g. `web_fetch`) run on the gateway, so the OANDA skill can call OANDA’s API without sandbox network access. When you add the Trading skill or any skill that calls exchange APIs from inside the sandbox, you may need to relax this (e.g. allow outbound only to exchange API hosts). Document and test any change.
- **Resource limits**:
  ```bash
  openclaw config set agents.defaults.sandbox.docker.memory "512m"
  openclaw config set agents.defaults.sandbox.docker.cpus 1
  openclaw config set agents.defaults.sandbox.docker.pidsLimit 100
  ```

## Tool policy

- **Deny list** (blocks dangerous tools):
  ```bash
  openclaw config set tools.deny '["browser", "exec", "process", "apply_patch", "write", "edit"]'
  ```
- **Allow list** (what the agent can use now):
  ```bash
  openclaw config set tools.allow '["read", "web_search", "web_fetch", "sessions_list", "sessions_history"]'
  ```
  The OANDA skill uses the built-in `web_fetch`; no extra tool is needed. When the Trading skill is implemented and registers a tool, add that tool name (e.g. `trading`) to this list.
- **Disable elevated mode** (no escaping the sandbox):
  ```bash
  openclaw config set tools.elevated.enabled false
  ```

## After changing config

```bash
openclaw gateway restart
```

Verify: `openclaw sandbox explain`, `openclaw models status`, `openclaw security audit`.

## Credentials (OANDA, exchanges)

Store OANDA token, account ID, and any exchange API keys in the OpenClaw credentials store or in environment variables—not in `openclaw config`. Do not commit them. The OANDA skill reads credentials from `~/.openclaw/credentials/` or env (e.g. `OANDA_TOKEN`, `OANDA_ACCOUNT_ID`).

## API spending

- **Moonshot:** Prepaid credits at [platform.moonshot.ai](https://platform.moonshot.ai); load a small amount (e.g. $5–10), do not auto-reload.
- **Anthropic:** Set daily and monthly limits in [console.anthropic.com](https://console.anthropic.com) → Settings → Plans & Billing → Spending Limits; set email alerts at 50% and 80%.
- **Monitor usage:**
  ```bash
  openclaw status --usage
  ```
