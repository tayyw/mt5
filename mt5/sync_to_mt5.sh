#!/usr/bin/env bash
# Sync this repo's EA + includes into the local Wine MT5 tree.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
MT5="${MT5_HOME:-$HOME/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5}"

if [[ ! -d "$MT5/MQL5" ]]; then
  echo "MT5 MQL5 folder not found: $MT5/MQL5"
  echo "Set MT5_HOME to your MetaTrader 5 install root."
  exit 1
fi

mkdir -p "$MT5/MQL5/Include/Portfolio"
mkdir -p "$MT5/MQL5/Include/ExpertMAPSAR"
mkdir -p "$MT5/MQL5/Experts"
mkdir -p "$MT5/MQL5/Experts/Advisors"

cp -f "$ROOT/Include/Portfolio/"*.mqh "$MT5/MQL5/Include/Portfolio/"
cp -f "$ROOT/Include/ExpertMAPSAR/"*.mqh "$MT5/MQL5/Include/ExpertMAPSAR/"
cp -f "$ROOT/Experts/PortfolioMaxProfit.mq5" "$MT5/MQL5/Experts/"
cp -f "$ROOT/Experts/PortfolioMaxProfit.mq5" "$MT5/MQL5/Experts/Advisors/"
cp -f "$ROOT/Experts/ExpertMAPSARTuned.mq5" "$MT5/MQL5/Experts/"
cp -f "$ROOT/Experts/ExpertMAPSARTuned.mq5" "$MT5/MQL5/Experts/Advisors/"

echo "Synced to:"
echo "  $MT5/MQL5/Experts/PortfolioMaxProfit.mq5"
echo "  $MT5/MQL5/Experts/ExpertMAPSARTuned.mq5"
echo "  $MT5/MQL5/Include/Portfolio/*.mqh"
echo "  $MT5/MQL5/Include/ExpertMAPSAR/*.mqh"
echo "Recompile in MetaEditor (F7)."
