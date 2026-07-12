#!/usr/bin/env bash
# Run MT5 Strategy Tester headless via terminal64.exe /config:...
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
WINEPREFIX="${WINEPREFIX:-$HOME/Library/Application Support/net.metaquotes.wine.metatrader5}"
MT5="${MT5_HOME:-$WINEPREFIX/drive_c/Program Files/MetaTrader 5}"
WINE="${WINE:-/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine}"
WINESERVER="${WINESERVER:-/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wineserver}"

FROM_DATE="${1:-2024.10.01}"
TO_DATE="${2:-2024.11.30}"
DEPOSIT="${3:-10000}"
REPORT_NAME="${4:-cli_${FROM_DATE}_${TO_DATE}}"

INI_NAME="backtest_cli.ini"
INI_HOST="$MT5/$INI_NAME"
REPORT_HTM="$MT5/${REPORT_NAME}.htm"

if [[ ! -x "$WINE" ]]; then
  echo "ERROR: wine not found at $WINE"
  exit 1
fi

if pgrep -f "terminal64.exe" >/dev/null 2>&1 || pgrep -f "MetaTrader 5.app" >/dev/null 2>&1; then
  echo "WARN: MT5 appears to be running — close it first for reliable CLI backtests."
fi

cat > "$INI_HOST" <<EOF
[Common]
Login=6619964
Server=OANDA_SG-Demo-1

[Tester]
Expert=Experts\\Advisors\\ExpertMAPSARTuned.ex5
Symbol=EURUSD
Period=1
Optimization=0
Model=1
FromDate=${FROM_DATE}
ToDate=${TO_DATE}
ForwardMode=0
Deposit=${DEPOSIT}
Currency=USD
Leverage=50
ExecutionMode=0
Report=${REPORT_NAME}
ReplaceReport=1
ShutdownTerminal=1
Visual=0
EOF

echo "Branch: $(git -C "$ROOT/.." branch --show-current 2>/dev/null || echo unknown)"
echo "Config: $INI_HOST"
echo "Report: $REPORT_HTM"
echo "Range:  $FROM_DATE -> $TO_DATE  deposit=$DEPOSIT"
echo ""

export WINEPREFIX
export WINEDEBUG=-all

# Ensure wine server is up
if [[ -x "$WINESERVER" ]]; then
  "$WINESERVER" -p >/dev/null 2>&1 || true
fi

echo "Compiling EA..."
"$WINE" "$MT5/metaeditor64.exe" \
  /compile:"C:\\Program Files\\MetaTrader 5\\MQL5\\Experts\\ExpertMAPSARTuned.mq5" \
  /log 2>/dev/null || true

echo "Starting tester (may take several minutes for M1)..."
START_TS=$(date +%s)
"$WINE" "$MT5/terminal64.exe" /portable "/config:C:\\Program Files\\MetaTrader 5\\${INI_NAME}"
END_TS=$(date +%s)
echo "Terminal exited after $((END_TS - START_TS))s"

echo ""
FOUND=""
for candidate in \
  "$REPORT_HTM" \
  "$MT5/MQL5/Files/${REPORT_NAME}.htm" \
  "$MT5/MQL5/Files/reports/${REPORT_NAME}.htm"; do
  if [[ -f "$candidate" ]]; then
    FOUND="$candidate"
    break
  fi
done

if [[ -n "$FOUND" ]]; then
  echo "Report written: $FOUND"
  rg -i "Total net profit|Profit factor|Total trades|Bars in test|Initial deposit" "$FOUND" 2>/dev/null | head -15 || true
else
  echo "Report not found."
  echo "Recent tester log tail:"
  LOG=$(ls -t "$MT5/Tester/logs/"*.log 2>/dev/null | head -1)
  if [[ -n "$LOG" ]]; then
    rg "testing of|tester stopped|finished|error|OnInit|Total net" "$LOG" 2>/dev/null | tail -20 || tail -20 "$LOG"
  fi
fi
