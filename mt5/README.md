# PortfolioMaxProfit v6 — Multi-Sleeve Active EA

Single-symbol EA with **7 parallel strategy sleeves** (common patterns from commercial/profitable MT5 EAs). v5 was slow because only strict HTF pullback + Donchian fired rarely.

> **Disclaimer:** More trades ≠ more profit. Backtest each symbol/spread. Research sources: mean-reversion scalpers, session breakouts, EMA cross systems, momentum burst / SMC-style engines.

## v6 sleeves (toggle in **Active Sleeves**)

| Code | Strategy | When it fires |
|------|----------|----------------|
| `PB_*` | HTF pullback | Strong trend + measured retrace (v5 strict) |
| `BO_*` | Donchian breakout | ADX rising + range break |
| `MR_*` | **Mean reversion** | BB touch + RSI extreme, ADX low (range) |
| `XUP_*` / `XDN_*` | **EMA cross** | 21/55 cross + ADX ≥ 16 |
| `SES_*` | **Session breakout** | Asian range break 07–11 server |
| `IB_*` | **Inside bar** | Mother bar compression break |
| `MOM_*` | **Momentum burst** | Body > 1.15× ATR + trend |

Best confidence wins per bar; hedging can open **both** long and short if both qualify.

## Active defaults (more trades)

```
InpTF              = M15
InpUseHTF          = false
InpActiveMode      = true
InpMinConfidence   = 0.50
InpMaxTradesPerDay = 24
InpCooldownBars    = 2
All sleeves        = ON
```

## Strict / slow preset (like v5)

```
InpTF = H1, InpUseHTF = true
InpActiveMode = false
Disable: MeanRev, EmaCross, SessionBO, InsideBar, Momentum
Keep: SleevePullback + Breakout only
InpMinConfidence = 0.58
InpMaxTradesPerDay = 6
```

## Install

```bash
./sync_to_mt5.sh
```

Compile **F7**, Strategy Tester → Inputs → enable/disable sleeves per symbol.

## Files

| Path | Role |
|------|------|
| `Experts/PortfolioMaxProfit.mq5` | v6 inputs |
| `Include/Portfolio/Strategies.mqh` | Multi-sleeve engine |
| `Include/Portfolio/PortfolioManager.mqh` | Execution, hedge, MG |
