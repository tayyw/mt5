#!/usr/bin/env bash
# Apply OpenClaw config for the trading bot.
# Replace YOUR_* placeholders before running. Do not commit real secrets.
set -e

OPENCLAW="${OPENCLAW:-openclaw}"

# --- Gateway ---
"$OPENCLAW" config set gateway.bind "127.0.0.1"
"$OPENCLAW" config set gateway.auth.password "YOUR_STRONG_PASSWORD_HERE"

# --- Telegram ---
"$OPENCLAW" config set channels.telegram.enabled true
"$OPENCLAW" config set channels.telegram.botToken "YOUR_TELEGRAM_BOT_TOKEN"
"$OPENCLAW" config set channels.telegram.dmPolicy "pairing"
"$OPENCLAW" config set channels.telegram.configWrites false
"$OPENCLAW" config set channels.telegram.groupPolicy "disabled"

# --- Models (aliases for /model in Telegram) ---
"$OPENCLAW" config set agents.defaults.models '{"moonshotai/kimi-k2.5": { "alias": "kimi" }, "anthropic/claude-sonnet-4-5": { "alias": "sonnet" }}'

# --- Sandbox ---
"$OPENCLAW" config set agents.defaults.sandbox.mode "all"
"$OPENCLAW" config set agents.defaults.sandbox.scope "session"
"$OPENCLAW" config set agents.defaults.sandbox.workspaceAccess "ro"
"$OPENCLAW" config set agents.defaults.sandbox.docker.network "none"
"$OPENCLAW" config set agents.defaults.sandbox.docker.memory "512m"
"$OPENCLAW" config set agents.defaults.sandbox.docker.cpus 1
"$OPENCLAW" config set agents.defaults.sandbox.docker.pidsLimit 100

# --- Tool policy ---
"$OPENCLAW" config set tools.deny '["browser", "exec", "process", "apply_patch", "write", "edit"]'
"$OPENCLAW" config set tools.allow '["read", "web_search", "web_fetch", "sessions_list", "sessions_history"]'
"$OPENCLAW" config set tools.elevated.enabled false

echo "Config applied. Restart gateway: $OPENCLAW gateway restart"
echo "Replace YOUR_STRONG_PASSWORD_HERE and YOUR_TELEGRAM_BOT_TOKEN before using in production."
