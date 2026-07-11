# MT4 Battle-Hardened Hedging EA

MetaTrader 4 Expert Advisor and scripts for forex pairs on **hedging-enabled** accounts. Designed for strict risk control, requote handling, and correct handling of multiple buy/sell positions per symbol.

## Requirements

- MetaTrader 4 with **hedging** account type (not netting).
- Broker that allows multiple positions per symbol (buy and sell simultaneously).

## Installation

1. Copy `Experts/HedgeTradingEA.mq4` into your MT4 `MQL4/Experts/` folder.
2. Copy `Scripts/CloseHedgeEAPositions.mq4` into `MQL4/Scripts/` (optional).
3. In MT4: **File → Open Data Folder** to find the correct paths.
4. Compile in MetaEditor (F7). Fix any broker-specific warnings (e.g. deprecated symbols).
5. Attach the EA to a chart (e.g. EURUSD M15). Enable **AutoTrading**.

## EA Inputs

| Input | Description | Suggested |
|-------|-------------|-----------|
| **Allowed symbols** | Comma list (e.g. `EURUSD,GBPUSD`) or `*` for chart symbol only | `*` |
| **Magic number** | Unique ID for this EA’s orders | `202502` |
| **Risk %** | Risk per trade as % of balance; 0 = use fixed lot | `1.0` or `0` |
| **Fixed lots** | Used when Risk % = 0 | `0.01` |
| **Max daily loss %** | Halt new trades when daily loss reaches this % of start-of-day balance | `5.0` |
| **Max open orders total** | Cap across all symbols | `20` |
| **Max open orders per symbol** | Cap per symbol (buy + sell) | `5` |
| **Max spread (points)** | No new trade if spread &gt; this | `50` |
| **Slippage (points)** | OrderSend slippage | `30` |
| **Max retries** | Requote/retry count for OrderSend | `5` |
| **Use SL / Use TP** | Apply stop loss and take profit | On |
| **SL/TP (points)** | Distance in points | e.g. 300 / 600 |
| **Strategy** | Primary strategy (see below) | MA Cross |
| **Combine mode** | Single / Confluence (AND) / Any (OR) | Single |
| **Filter strategy** | Second strategy for Confluence or Any | Trend MA |
| **Fast MA / Slow MA** | MA Cross: periods | 10 / 30 |
| **RSI period / levels** | RSI strategies: period, overbought, oversold | 14, 70, 30 |
| **Breakout bars** | Breakout: lookback bars for high/low | 20 |
| **BB period / deviation** | Bollinger: period, deviation | 20, 2.0 |
| **Trend MA period** | Trend MA: period | 50 |
| **Div lookback** | RSI Divergence: bars for swing high/low | 24 |

## Strategies

Choose a **primary strategy** (and optionally a **filter strategy** when combining):

| Strategy | Idea | Best suited to |
|----------|------|----------------|
| **MA Cross** | Fast MA crosses above slow MA → buy; below → sell. | Trend starts on higher timeframes (e.g. H1). |
| **RSI Reversal** | RSI leaves oversold (e.g. &lt; 30) → buy; leaves overbought (e.g. &gt; 70) → sell. | Ranging markets, mean reversion. |
| **Breakout** | Price closes above last N-bar high → buy; below last N-bar low → sell. | Breakouts from consolidation (e.g. 20-bar). |
| **Bollinger** | Price bounces off lower band → buy; rejects from upper band → sell. | Ranges, mean reversion. |
| **Trend MA** | Price crosses above MA → buy; below MA → sell. | Single-MA trend filter. |
| **RSI Divergence** | **Directional only:** overbought + bearish divergence (price higher high, RSI lower high) → **sell only**; oversold + bullish divergence (price lower low, RSI higher low) → **buy only**. | Topping/bottoming momentum; fewer but higher-conviction signals. |

All strategies trigger **on a new bar** (one signal per bar) to avoid repainting. Tune SL/TP and risk to match the strategy (e.g. wider for breakout, tighter for RSI).

## Combining strategies (confluence / any)

Many professional EAs use **confluence** (several conditions must agree) to cut false signals:

- **Single** — Only the primary strategy is used (default).
- **Confluence (AND)** — A trade is taken only when **both** primary and filter strategy give the **same** direction (both buy or both sell). If either says 0 or they disagree, no trade. Example: MA Cross says buy, Trend MA says buy → buy; MA Cross says buy, Trend MA says sell → no trade.
- **Any (OR)** — If the primary strategy gives a signal, that is used; otherwise the filter strategy’s signal is used. Use to add a second chance to enter (e.g. primary = RSI Divergence, filter = Breakout).

This follows common practice: multiple indicators with AND/OR combination, trend filters (e.g. MA) to confirm entries, and optional “any” mode for diversification.

## Hedging behaviour

- The EA counts **buy** and **sell** positions **separately** per symbol.
- It respects **Max open orders per symbol** as the total of buys + sells for that symbol.
- All orders use the same **magic number** so they can be identified and closed by the script.

## Risk safeguards

- **Daily loss limit**: At the start of each day (server time) the EA stores the account balance. If current balance drops by more than **Max daily loss %**, it stops opening new trades until the next day.
- **Margin**: Before opening, it checks `AccountFreeMargin()` with a 10% buffer.
- **Spread**: No new trade if current spread &gt; **Max spread (points)**.
- **Lots**: Normalized to broker `MODE_MINLOT`, `MODE_MAXLOT`, `MODE_LOTSTEP`. Optional risk-based lot from **Risk %** and SL distance.

## Custom strategy

To add your own logic: implement a new function that returns 1 (buy), -1 (sell), or 0 (none), add an option to `ENUM_STRATEGY`, and call it from `GetSignalFromStrategy()`. The combined signal (Single/Confluence/Any) and the existing risk and order-execution code stay as is.

## Script: close all EA positions

`CloseHedgeEAPositions.mq4` closes every position with the given magic number. Set **Magic number** to match the EA, then run the script from the Navigator (drag onto any chart). Useful for shutting down the strategy or testing.

## Files

- `Experts/HedgeTradingEA.mq4` — main Expert Advisor
- `Scripts/CloseHedgeEAPositions.mq4` — close all positions by magic

## Disclaimer

This is trading software. Use on demo first. You are responsible for your own risk and broker compliance. The authors are not liable for any financial loss.
