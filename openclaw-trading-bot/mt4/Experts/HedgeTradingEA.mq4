//+------------------------------------------------------------------+
//|                                              HedgeTradingEA.mq4  |
//| Battle-hardened EA for hedging accounts — forex pairs            |
//| Risk limits, margin checks, retries, hedging-aware position mgmt |
//+------------------------------------------------------------------+
#property copyright "OpenClaw"
#property link      ""
#property version   "1.00"
#property strict

//--- Inputs: Risk & limits
input string   InpAllowedSymbols    = "*";           // Allowed symbols (comma list or * for chart symbol only)
input int      InpMagicNumber       = 202502;        // Magic number (identify EA orders)
input double   InpRiskPercent       = 1.0;           // Risk per trade (% of balance, 0 = use fixed lot)
input double   InpFixedLots         = 0.01;          // Fixed lot size (used if Risk% = 0)
input double   InpMaxDailyLossPercent = 5.0;         // Max daily loss % — halt new trades if exceeded
input int      InpMaxOpenOrdersTotal = 20;           // Max open orders (all symbols)
input int      InpMaxOpenOrdersPerSymbol = 5;        // Max open orders per symbol (hedging: buy+sell)
input int      InpMaxSpreadPoints   = 50;            // Max spread (points) — no open if exceeded
input int      InpSlippage          = 30;            // Slippage (points)
input int      InpMaxRetries        = 5;             // OrderSend retries on requote

//--- Inputs: Stops
input bool     InpUseSL             = true;          // Use stop loss
input bool     InpUseTP             = true;          // Use take profit
input int      InpSLPoints          = 300;           // Stop loss (points)
input int      InpTPPoints          = 600;           // Take profit (points)

//--- Strategy selector
enum ENUM_STRATEGY
{
   STRAT_MA_CROSS = 0,       // MA crossover
   STRAT_RSI_REVERSAL = 1,   // RSI oversold/overbought
   STRAT_BREAKOUT = 2,       // N-bar high/low breakout
   STRAT_BOLLINGER = 3,      // Bollinger mean reversion
   STRAT_TREND_MA = 4,       // Trend: price vs single MA
   STRAT_RSI_DIVERGENCE = 5  // RSI divergence (overbought+bearish=sell, oversold+bullish=buy)
};

//--- Combination: Single = one strategy; Confluence = primary AND filter agree; Any = primary OR filter
enum ENUM_COMBINE
{
   COMBINE_SINGLE = 0,       // Single strategy only
   COMBINE_CONFLUENCE = 1,   // Confluence (both must agree)
   COMBINE_ANY = 2           // Any (primary or filter can trigger)
};

input ENUM_STRATEGY InpStrategy    = STRAT_MA_CROSS;   // Primary strategy
input ENUM_COMBINE  InpCombineMode = COMBINE_SINGLE;   // Combine mode
input ENUM_STRATEGY InpFilterStrategy = STRAT_TREND_MA; // Filter strategy (when Confluence/Any)

//--- Inputs: MA Cross (Strategy 0)
input int      InpFastMA            = 10;            // [MA] Fast MA period
input int      InpSlowMA            = 30;            // [MA] Slow MA period
input ENUM_MA_METHOD InpMAMethod    = MODE_EMA;      // [MA] MA method
input ENUM_APPLIED_PRICE InpMAPrice = PRICE_CLOSE;   // [MA] MA applied price

//--- Inputs: RSI Reversal (Strategy 1)
input int      InpRSIPeriod         = 14;            // [RSI] Period
input int      InpRSIOverbought     = 70;            // [RSI] Overbought level
input int      InpRSIOversold       = 30;            // [RSI] Oversold level
input ENUM_APPLIED_PRICE InpRSIPrice = PRICE_CLOSE; // [RSI] Applied price

//--- Inputs: Breakout (Strategy 2)
input int      InpBreakoutBars      = 20;            // [Breakout] Lookback bars (high/low)
input int      InpBreakoutConfirm   = 1;             // [Breakout] Close must be beyond level (1=yes)

//--- Inputs: Bollinger (Strategy 3)
input int      InpBBPeriod          = 20;            // [BB] Period
input double   InpBBDeviation       = 2.0;           // [BB] Deviation
input ENUM_APPLIED_PRICE InpBBPrice = PRICE_CLOSE;   // [BB] Applied price

//--- Inputs: Trend MA (Strategy 4)
input int      InpTrendMAPeriod     = 50;            // [Trend] MA period
input ENUM_MA_METHOD InpTrendMAMethod = MODE_EMA;    // [Trend] MA method
input ENUM_APPLIED_PRICE InpTrendMAPrice = PRICE_CLOSE; // [Trend] Applied price

//--- Inputs: RSI Divergence (Strategy 5) — overbought+bearish div = sell only; oversold+bullish = buy only
input int      InpDivLookback       = 24;            // [Div] Lookback bars for swing high/low
input ENUM_APPLIED_PRICE InpDivPrice = PRICE_CLOSE;   // [Div] Price for RSI (close typical)

//--- State
datetime g_lastBarTime = 0;
double   g_dailyStartBalance = 0;
datetime g_lastDayChecked = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_lastBarTime = 0;
   g_dailyStartBalance = AccountBalance();
   g_lastDayChecked = TimeCurrent();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Optional: log final stats
}

//+------------------------------------------------------------------+
//| Check if symbol is allowed                                         |
//+------------------------------------------------------------------+
bool IsSymbolAllowed(const string symbol)
{
   if (InpAllowedSymbols == "" || InpAllowedSymbols == "*")
      return (symbol == Symbol());
   string list[];
   int n = StringSplit(InpAllowedSymbols, ',', list);
   for (int i = 0; i < n; i++)
      if (StringTrimLeft(StringTrimRight(list[i])) == symbol)
         return true;
   return false;
}

//+------------------------------------------------------------------+
//| Count open orders for symbol by type (hedging-aware)              |
//+------------------------------------------------------------------+
int CountOrdersForSymbol(const string symbol, const int type)
{
   int count = 0;
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if (OrderSymbol() != symbol || OrderMagicNumber() != InpMagicNumber) continue;
      if (OrderType() == OP_BUY || OrderType() == OP_SELL)
      {
         if (type == -1 || (int)OrderType() == type)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Total open orders for symbol (buy + sell)                         |
//+------------------------------------------------------------------+
int TotalOrdersForSymbol(const string symbol)
{
   return CountOrdersForSymbol(symbol, OP_BUY) + CountOrdersForSymbol(symbol, OP_SELL);
}

//+------------------------------------------------------------------+
//| Total open orders with our magic                                   |
//+------------------------------------------------------------------+
int TotalOrdersWithMagic()
{
   int count = 0;
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if (OrderMagicNumber() != InpMagicNumber) continue;
      if (OrderType() == OP_BUY || OrderType() == OP_SELL) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Update daily start balance at day change                           |
//+------------------------------------------------------------------+
void UpdateDailyStartBalance()
{
   if (g_lastDayChecked == 0 || TimeCurrent() - g_lastDayChecked >= 86400)
   {
      g_dailyStartBalance = AccountBalance();
      g_lastDayChecked = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Daily P&L in account currency (approx: balance - daily start)      |
//+------------------------------------------------------------------+
double GetDailyPL()
{
   UpdateDailyStartBalance();
   return AccountBalance() - g_dailyStartBalance;
}

//+------------------------------------------------------------------+
//| Check if daily loss limit exceeded                                 |
//+------------------------------------------------------------------+
bool IsDailyLossLimitHit()
{
   if (InpMaxDailyLossPercent <= 0) return false;
   double pl = GetDailyPL();
   double limit = g_dailyStartBalance * (InpMaxDailyLossPercent / 100.0);
   return (pl <= -MathAbs(limit));
}

//+------------------------------------------------------------------+
//| Get current spread in points                                       |
//+------------------------------------------------------------------+
int GetSpreadPoints(const string symbol)
{
   double point = MarketInfo(symbol, MODE_POINT);
   if (point <= 0) return 99999;
   int digits = (int)MarketInfo(symbol, MODE_DIGITS);
   double spread = MarketInfo(symbol, MODE_SPREAD);
   if (digits == 3 || digits == 5) spread *= 10;
   return (int)spread;
}

//+------------------------------------------------------------------+
//| Normalize lot size to broker rules                                 |
//+------------------------------------------------------------------+
double NormalizeLots(const string symbol, double lots)
{
   double minLot = MarketInfo(symbol, MODE_MINLOT);
   double maxLot = MarketInfo(symbol, MODE_MAXLOT);
   double step  = MarketInfo(symbol, MODE_LOTSTEP);
   if (step <= 0) step = 0.01;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   lots = MathFloor(lots / step) * step;
   if (lots < minLot) lots = minLot;
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Calculate lot size (risk % or fixed)                               |
//+------------------------------------------------------------------+
double CalcLots(const string symbol, const int orderType, const int slPoints)
{
   double lots = InpFixedLots;
   if (InpRiskPercent > 0 && slPoints > 0)
   {
      double riskMoney = AccountBalance() * (InpRiskPercent / 100.0);
      double tickValue = MarketInfo(symbol, MODE_TICKVALUE);
      double point     = MarketInfo(symbol, MODE_POINT);
      int digits       = (int)MarketInfo(symbol, MODE_DIGITS);
      if (digits == 3 || digits == 5) tickValue *= 10;
      if (point > 0 && tickValue > 0)
      {
         double riskLots = riskMoney / (slPoints * point * tickValue / point);
         lots = NormalizeLots(symbol, riskLots);
      }
   }
   return NormalizeLots(symbol, lots);
}

//+------------------------------------------------------------------+
//| Open order with retries and margin check                           |
//+------------------------------------------------------------------+
int OpenOrder(const string symbol, const int cmd, double lots,
              double price, double sl, double tp, const string comment)
{
   if (!IsSymbolAllowed(symbol)) return -1;
   if (IsDailyLossLimitHit()) return -1;
   if (TotalOrdersWithMagic() >= InpMaxOpenOrdersTotal) return -1;
   if (TotalOrdersForSymbol(symbol) >= InpMaxOpenOrdersPerSymbol) return -1;
   if (GetSpreadPoints(symbol) > InpMaxSpreadPoints) return -1;

   lots = NormalizeLots(symbol, lots);
   if (lots < MarketInfo(symbol, MODE_MINLOT)) return -1;

   double marginRequired = 0;
   if (cmd == OP_BUY)
      marginRequired = MarketInfo(symbol, MODE_MARGINREQUIRED);
   else
      marginRequired = MarketInfo(symbol, MODE_MARGINREQUIRED);
   if (AccountFreeMargin() < marginRequired * lots * 1.1) return -1; // 10% buffer

   color arrowColor = (cmd == OP_BUY) ? clrGreen : clrRed;
   int ticket = -1;
   for (int attempt = 0; attempt < InpMaxRetries; attempt++)
   {
      if (cmd == OP_BUY)
         price = MarketInfo(symbol, MODE_ASK);
      else
         price = MarketInfo(symbol, MODE_BID);

      ticket = OrderSend(symbol, cmd, lots, price, InpSlippage, sl, tp,
                        comment, InpMagicNumber, 0, arrowColor);
      if (ticket >= 0) return ticket;
      int err = GetLastError();
      if (err == 134) break; // Not enough money
      if (err == 131) break; // Invalid trade parameters
      if (err == 148) { Sleep(500); RefreshRates(); continue; } // Requote
      if (err == 136) { Sleep(500); RefreshRates(); continue; } // Off quotes
      Sleep(200 * (attempt + 1));
      RefreshRates();
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Build SL/TP prices (0 = disabled)                                  |
//+------------------------------------------------------------------+
void BuildSLTP(const string symbol, const int cmd, double price,
               double &outSL, double &outTP)
{
   outSL = 0; outTP = 0;
   double point = MarketInfo(symbol, MODE_POINT);
   int digits   = (int)MarketInfo(symbol, MODE_DIGITS);
   if (digits == 3 || digits == 5) point *= 10;

   if (InpUseSL && InpSLPoints > 0)
   {
      if (cmd == OP_BUY) outSL = NormalizeDouble(price - InpSLPoints * point, digits);
      else               outSL = NormalizeDouble(price + InpSLPoints * point, digits);
   }
   if (InpUseTP && InpTPPoints > 0)
   {
      if (cmd == OP_BUY) outTP = NormalizeDouble(price + InpTPPoints * point, digits);
      else               outTP = NormalizeDouble(price - InpTPPoints * point, digits);
   }
}

//+------------------------------------------------------------------+
//| Strategy 0: MA crossover — 1 = buy, -1 = sell, 0 = none            |
//+------------------------------------------------------------------+
int SignalMACross(const string symbol)
{
   double fast   = iMA(symbol, 0, InpFastMA, 0, InpMAMethod, InpMAPrice, 1);
   double slow   = iMA(symbol, 0, InpSlowMA, 0, InpMAMethod, InpMAPrice, 1);
   double fastP  = iMA(symbol, 0, InpFastMA, 0, InpMAMethod, InpMAPrice, 2);
   double slowP  = iMA(symbol, 0, InpSlowMA, 0, InpMAMethod, InpMAPrice, 2);
   if (fastP <= slowP && fast > slow) return 1;
   if (fastP >= slowP && fast < slow) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Strategy 1: RSI reversal — oversold = buy, overbought = sell      |
//+------------------------------------------------------------------+
int SignalRSIReversal(const string symbol)
{
   double rsi1 = iRSI(symbol, 0, InpRSIPeriod, InpRSIPrice, 1);
   double rsi2 = iRSI(symbol, 0, InpRSIPeriod, InpRSIPrice, 2);
   if (rsi2 <= InpRSIOversold && rsi1 > InpRSIOversold) return 1;   // cross up from oversold
   if (rsi2 >= InpRSIOverbought && rsi1 < InpRSIOverbought) return -1; // cross down from overbought
   return 0;
}

//+------------------------------------------------------------------+
//| Strategy 2: Breakout — close above N-bar high = buy, below low = sell |
//+------------------------------------------------------------------+
int SignalBreakout(const string symbol)
{
   double highN = iHigh(symbol, 0, 1);
   double lowN  = iLow(symbol, 0, 1);
   for (int i = 2; i <= InpBreakoutBars; i++)
   {
      if (iHigh(symbol, 0, i) > highN) highN = iHigh(symbol, 0, i);
      if (iLow(symbol, 0, i) < lowN)  lowN  = iLow(symbol, 0, i);
   }
   double close1 = iClose(symbol, 0, 1);
   double close2 = iClose(symbol, 0, 2);
   if (InpBreakoutConfirm != 0)
   {
      if (close2 <= highN && close1 > highN) return 1;
      if (close2 >= lowN && close1 < lowN)  return -1;
   }
   else
   {
      if (close1 > highN) return 1;
      if (close1 < lowN)  return -1;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Strategy 3: Bollinger mean reversion — touch lower band = buy, upper = sell |
//+------------------------------------------------------------------+
int SignalBollinger(const string symbol)
{
   double upper1 = iBands(symbol, 0, InpBBPeriod, InpBBDeviation, 0, InpBBPrice, MODE_UPPER, 1);
   double lower1 = iBands(symbol, 0, InpBBPeriod, InpBBDeviation, 0, InpBBPrice, MODE_LOWER, 1);
   double upper2 = iBands(symbol, 0, InpBBPeriod, InpBBDeviation, 0, InpBBPrice, MODE_UPPER, 2);
   double lower2 = iBands(symbol, 0, InpBBPeriod, InpBBDeviation, 0, InpBBPrice, MODE_LOWER, 2);
   double close1 = iClose(symbol, 0, 1);
   double close2 = iClose(symbol, 0, 2);
   if (close2 <= lower2 && close1 > lower1) return 1;   // bounce off lower band
   if (close2 >= upper2 && close1 < upper1) return -1;  // rejection from upper band
   return 0;
}

//+------------------------------------------------------------------+
//| Strategy 4: Trend MA — price above MA = buy only, below = sell only |
//+------------------------------------------------------------------+
int SignalTrendMA(const string symbol)
{
   double ma1 = iMA(symbol, 0, InpTrendMAPeriod, 0, InpTrendMAMethod, InpTrendMAPrice, 1);
   double ma2 = iMA(symbol, 0, InpTrendMAPeriod, 0, InpTrendMAMethod, InpTrendMAPrice, 2);
   double close1 = iClose(symbol, 0, 1);
   double close2 = iClose(symbol, 0, 2);
   if (close2 <= ma2 && close1 > ma1) return 1;   // cross above MA
   if (close2 >= ma2 && close1 < ma1) return -1;  // cross below MA
   return 0;
}

//+------------------------------------------------------------------+
//| Strategy 5: RSI divergence — overbought + bearish div = sell only; |
//|             oversold + bullish div = buy only                      |
//+------------------------------------------------------------------+
int SignalRSIDivergence(const string symbol)
{
   if (InpDivLookback < 5) return 0;
   int lookback = MathMin(InpDivLookback, 100);

   // Bearish: two price highs, recent > previous; two RSI values, recent < previous; recent RSI in overbought
   int recentHighBar = 1;
   double highMax = iHigh(symbol, 0, 1);
   for (int i = 2; i <= lookback; i++)
   {
      double h = iHigh(symbol, 0, i);
      if (h > highMax) { highMax = h; recentHighBar = i; }
   }
   int prevHighBar = recentHighBar + 1;
   if (prevHighBar > lookback) return 0;
   double prevHighMax = iHigh(symbol, 0, prevHighBar);
   for (int i = prevHighBar + 1; i <= lookback; i++)
   {
      double h = iHigh(symbol, 0, i);
      if (h > prevHighMax) { prevHighMax = h; prevHighBar = i; }
   }
   double rsiRecent = iRSI(symbol, 0, InpRSIPeriod, InpDivPrice, recentHighBar);
   double rsiPrev   = iRSI(symbol, 0, InpRSIPeriod, InpDivPrice, prevHighBar);
   if (highMax > prevHighMax && rsiRecent < rsiPrev && rsiRecent >= InpRSIOverbought)
      return -1;   // bearish divergence in overbought → sell only

   // Bullish: two price lows, recent < previous; two RSI values, recent > previous; recent RSI in oversold
   int recentLowBar = 1;
   double lowMin = iLow(symbol, 0, 1);
   for (int i = 2; i <= lookback; i++)
   {
      double l = iLow(symbol, 0, i);
      if (l < lowMin) { lowMin = l; recentLowBar = i; }
   }
   int prevLowBar = recentLowBar + 1;
   if (prevLowBar > lookback) return 0;
   double prevLowMin = iLow(symbol, 0, prevLowBar);
   for (int i = prevLowBar + 1; i <= lookback; i++)
   {
      double l = iLow(symbol, 0, i);
      if (l < prevLowMin) { prevLowMin = l; prevLowBar = i; }
   }
   rsiRecent = iRSI(symbol, 0, InpRSIPeriod, InpDivPrice, recentLowBar);
   rsiPrev   = iRSI(symbol, 0, InpRSIPeriod, InpDivPrice, prevLowBar);
   if (lowMin < prevLowMin && rsiRecent > rsiPrev && rsiRecent <= InpRSIOversold)
      return 1;   // bullish divergence in oversold → buy only

   return 0;
}

//+------------------------------------------------------------------+
//| Get raw signal from one strategy (1 = buy, -1 = sell, 0 = none)   |
//+------------------------------------------------------------------+
int GetSignalFromStrategy(const ENUM_STRATEGY strat, const string symbol)
{
   switch (strat)
   {
      case STRAT_MA_CROSS:       return SignalMACross(symbol);
      case STRAT_RSI_REVERSAL:   return SignalRSIReversal(symbol);
      case STRAT_BREAKOUT:       return SignalBreakout(symbol);
      case STRAT_BOLLINGER:      return SignalBollinger(symbol);
      case STRAT_TREND_MA:       return SignalTrendMA(symbol);
      case STRAT_RSI_DIVERGENCE: return SignalRSIDivergence(symbol);
      default:                   return SignalMACross(symbol);
   }
}

//+------------------------------------------------------------------+
//| Combined signal: Single / Confluence (AND) / Any (OR)             |
//+------------------------------------------------------------------+
int GetSignal(const string symbol)
{
   int primary = GetSignalFromStrategy(InpStrategy, symbol);
   if (InpCombineMode == COMBINE_SINGLE)
      return primary;

   int filterSig = GetSignalFromStrategy(InpFilterStrategy, symbol);
   if (InpCombineMode == COMBINE_CONFLUENCE)
   {
      if (primary != 0 && filterSig == primary) return primary;
      return 0;
   }
   if (InpCombineMode == COMBINE_ANY)
   {
      if (primary != 0) return primary;
      return filterSig;
   }
   return primary;
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   string symbol = Symbol();
   if (!IsSymbolAllowed(symbol)) return;

   if (IsDailyLossLimitHit()) return;
   if (TotalOrdersWithMagic() >= InpMaxOpenOrdersTotal) return;
   if (TotalOrdersForSymbol(symbol) >= InpMaxOpenOrdersPerSymbol) return;
   if (GetSpreadPoints(symbol) > InpMaxSpreadPoints) return;

   // New bar only (optional: remove for every-tick entry)
   datetime barTime = iTime(symbol, 0, 0);
   if (barTime == g_lastBarTime) return;
   g_lastBarTime = barTime;

   int sig = GetSignal(symbol);
   if (sig == 0) return;

   int cmd = (sig > 0) ? OP_BUY : OP_SELL;
   double price = (cmd == OP_BUY) ? MarketInfo(symbol, MODE_ASK) : MarketInfo(symbol, MODE_BID);
   double sl, tp;
   BuildSLTP(symbol, cmd, price, sl, tp);

   double lots = CalcLots(symbol, cmd, InpSLPoints > 0 ? InpSLPoints : 100);
   string comment = "HedgeEA_" + IntegerToString(InpMagicNumber);

   int ticket = OpenOrder(symbol, cmd, lots, price, sl, tp, comment);
   if (ticket >= 0)
      Print("HedgeEA: opened ", (cmd == OP_BUY ? "BUY" : "SELL"), " ", symbol, " ticket=", ticket, " lots=", lots);
   else if (GetLastError() != 0)
      Print("HedgeEA: OrderSend failed ", symbol, " err=", GetLastError());
}

//+------------------------------------------------------------------+
