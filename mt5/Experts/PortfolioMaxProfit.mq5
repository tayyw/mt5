//+------------------------------------------------------------------+
//| PortfolioMaxProfit.mq5  v6                                        |
//| Multi-sleeve active trader: 7 strategies, long+short, hedge, MG   |
//| Run one instance per chart/symbol.                                |
//+------------------------------------------------------------------+
#property copyright "MT5 Portfolio EA"
#property link      ""
#property version   "6.02"
#property strict
#property description "v6 Multi-sleeve: MR, EMA cross, session BO, inside bar, momentum"

#include <Portfolio/RiskManager.mqh>
#include <Portfolio/PortfolioManager.mqh>

enum ENUM_INP_SIGNAL_TF
{
   INP_TF_M1  = PERIOD_M1,     // M1 — 1 minute
   INP_TF_M5  = PERIOD_M5,     // M5 — 5 minutes
   INP_TF_M15 = PERIOD_M15,    // M15 — 15 minutes
   INP_TF_M30 = PERIOD_M30,    // M30 — 30 minutes
   INP_TF_H1  = PERIOD_H1,     // H1 — 1 hour
   INP_TF_H4  = PERIOD_H4,     // H4 — 4 hours
   INP_TF_D1  = PERIOD_D1,     // D1 — daily
   INP_TF_W1  = PERIOD_W1      // W1 — weekly
};

enum ENUM_INP_HTF_TF
{
   INP_HTF_M15 = PERIOD_M15,   // M15 — 15 minutes
   INP_HTF_M30 = PERIOD_M30,   // M30 — 30 minutes
   INP_HTF_H1  = PERIOD_H1,    // H1 — 1 hour
   INP_HTF_H4  = PERIOD_H4,    // H4 — 4 hours
   INP_HTF_D1  = PERIOD_D1,    // D1 — daily
   INP_HTF_W1  = PERIOD_W1     // W1 — weekly
};

//--- Timeframes
input group "=== Timeframes ==="
input ENUM_INP_SIGNAL_TF InpTF  = INP_TF_M5;    // M5 ≈ MAPSAR frequency
input ENUM_INP_HTF_TF    InpHTF = INP_HTF_H1;
input bool   InpUseHTF            = false;      // Off = active sleeves fire more

//--- Strategy (strict sleeve filters)
input group "=== Strategy (strict) ==="
input int    InpFastMA            = 21;
input int    InpSlowMA            = 55;
input int    InpRSIPeriod         = 14;
input double InpRSIPullLow        = 38;
input double InpRSIPullHigh       = 62;
input int    InpATRPeriod         = 14;
input double InpATR_SL_Min        = 1.0;
input double InpATR_SL_Max        = 1.8;
input double InpRewardR           = 3.0;
input int    InpDonchian          = 20;
input int    InpADXPeriod         = 14;
input double InpADXTrendMin       = 20;
input double InpADXBreakoutMin    = 22;
input double InpMinConfidence     = 0.48;
input bool   InpAllowBreakout     = true;
input bool   InpAllowLong         = true;
input bool   InpAllowShort        = true;
input double InpMaxSpreadATR      = 0.15;
input double InpMinBodyATR        = 0.12;

//--- Active multi-sleeve (research: MR, session BO, EMA cross, momentum)
input group "=== Active Sleeves ==="
input bool   InpActiveMode        = true;       // Relax filters, more trades
input bool   InpSleevePullback    = true;       // Strict HTF pullback (slow)
input bool   InpSleeveMeanRev     = true;       // BB + RSI mean reversion
input bool   InpSleeveEmaCross    = true;       // EMA 21/55 crossover
input bool   InpSleeveSessionBO   = true;       // Asian range → London BO
input bool   InpSleeveInsideBar   = true;       // Inside bar breakout
input bool   InpSleeveMomentum    = true;       // Large body momentum burst
input bool   InpSleeveMAP         = true;       // MA cross MAPSAR-like (high freq)
input int    InpBBPeriod          = 20;
input double InpBBDev             = 2.0;
input double InpRSI_OB            = 68;
input double InpRSI_OS            = 32;
input int    InpSessionBOStart    = 7;         // Server hour: range break window
input int    InpSessionBOEnd      = 11;
input double InpEmaCrossAdxMin    = 16;
input double InpMeanRevAdxMax     = 28;

//--- Session
input group "=== Session ==="
input bool   InpUseSession        = false;     // Off for backtest (like MAPSAR)
input int    InpSessionStartHour  = 6;
input int    InpSessionEndHour    = 22;

//--- Risk
input group "=== Risk ==="
input double InpRiskPerTradePct   = 0.45;
input double InpMaxHeatPct        = 4.0;
input double InpMaxDailyLossPct   = 3.0;
input double InpMaxDrawdownPct    = 18.0;
input int    InpMaxPositions      = 1;          // One at a time (flip on signal)
input int    InpMaxTradesPerDay   = 999;        // No artificial daily stop
input bool   InpOneDirPerSymbol   = true;
input int    InpCooldownBars      = 0;

//--- Hedging
input group "=== Hedging ==="
input bool   InpAllowHedging      = false;      // Hedge blocks new entries
input int    InpMaxPerDirection   = 1;

//--- Flip (MAPSAR-style: close & reverse)
input group "=== Flip / MAP style ==="
input bool   InpFlipOnSignal      = true;       // Close opposite, then enter

//--- Martingale
input group "=== Martingale ==="
input bool   InpUseMartingale     = false;
input double InpMartingaleMult    = 2.0;
input int    InpMartingaleMaxSteps = 4;

//--- Pyramiding
input group "=== Pyramiding ==="
input bool   InpUsePyramid        = false;
input int    InpMaxPyramidLegs    = 3;
input double InpPyramidMinR       = 1.0;
input double InpPyramidAddR       = 0.8;
input double InpPyramidRiskPct    = 0.25;
input bool   InpPyramidNeedADX    = true;
input double InpPyramidADXMin     = 18;

//--- Trade management
input group "=== Trade Management ==="
input bool   InpUseFixedTP        = false;
input bool   InpUseTrailing       = true;
input double InpTrailATR          = 1.4;
input double InpBreakevenR        = 0.7;
input double InpTrailStartR       = 1.2;
input double InpPartialR          = 1.5;
input double InpPartialPct        = 0.33;
input double InpProgressiveLock   = 0.35;
input int    InpSlippagePoints    = 30;
input long   InpMagic             = 910500;

//--- Runtime
input group "=== Runtime ==="
input bool   InpShowPanel         = true;
input int    InpPanelSeconds      = 2;

CRiskManager      g_risk;
CPortfolioManager g_portfolio;
datetime          g_lastBar[1];
datetime          g_lastPanel = 0;
string            g_symbol = "";

ENUM_TIMEFRAMES SignalTF() { return (ENUM_TIMEFRAMES)InpTF; }
ENUM_TIMEFRAMES HtfTF()     { return (ENUM_TIMEFRAMES)InpHTF; }

string TfShortName(const ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      default:         return IntegerToString((int)tf);
   }
}

int OnInit()
{
   g_symbol = _Symbol;
   ENUM_TIMEFRAMES tf  = SignalTF();
   ENUM_TIMEFRAMES htf = HtfTF();

   if(InpUseHTF && (int)htf <= (int)tf)
      PrintFormat("WARN: HTF (%s) should be higher than signal TF (%s)",
                  TfShortName(htf), TfShortName(tf));

   if(!InpAllowLong && !InpAllowShort)
   {
      Print("ERROR: Both InpAllowLong and InpAllowShort are false.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(!InpSleevePullback && !InpSleeveMeanRev && !InpSleeveEmaCross &&
      !InpSleeveSessionBO && !InpSleeveInsideBar && !InpSleeveMomentum &&
      !InpSleeveMAP && !InpAllowBreakout)
   {
      Print("ERROR: No strategy sleeve enabled.");
      return INIT_PARAMETERS_INCORRECT;
   }

   long tradeMode = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_MODE);
   if(InpAllowShort && tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
      PrintFormat("WARN: %s is close-only — shorts may fail.", g_symbol);

   g_risk.Init(InpMaxDailyLossPct, InpMaxDrawdownPct,
               InpRiskPerTradePct, InpMaxHeatPct,
               InpMaxPositions, InpMaxTradesPerDay);

   g_portfolio.BindRisk(GetPointer(g_risk));
   g_portfolio.Configure(InpMagic, InpSlippagePoints, InpMinConfidence,
                         InpUseFixedTP, InpUseTrailing, InpTrailATR,
                         InpBreakevenR, InpTrailStartR,
                         InpPartialR, InpPartialPct, InpProgressiveLock,
                         InpMaxPositions, InpOneDirPerSymbol,
                         InpCooldownBars, InpUseSession,
                         InpSessionStartHour, InpSessionEndHour,
                         1, tf,
                         InpUsePyramid, InpMaxPyramidLegs,
                         InpPyramidMinR, InpPyramidAddR, InpPyramidRiskPct,
                         InpPyramidNeedADX, InpPyramidADXMin, InpADXPeriod,
                         InpAllowHedging, InpMaxPerDirection,
                         InpUseMartingale, InpMartingaleMult, InpMartingaleMaxSteps,
                         InpFlipOnSignal);

   ArrayInitialize(g_lastBar, 0);

   bool ok = g_portfolio.AddSymbol(
      g_symbol, 1.0, "NONE",
      InpFastMA, InpSlowMA, InpRSIPeriod,
      InpRSIPullLow, InpRSIPullHigh,
      InpATRPeriod, InpATR_SL_Min, InpATR_SL_Max, InpRewardR,
      InpDonchian, InpADXPeriod, InpADXTrendMin, InpADXBreakoutMin,
      tf, htf, InpUseHTF,
      InpAllowBreakout, InpMaxSpreadATR, InpMinBodyATR,
      InpAllowLong, InpAllowShort,
      InpActiveMode, InpSleevePullback, InpSleeveMeanRev, InpSleeveEmaCross,
      InpSleeveSessionBO, InpSleeveInsideBar, InpSleeveMomentum, InpSleeveMAP,
      InpBBPeriod, InpBBDev, InpRSI_OB, InpRSI_OS,
      InpSessionBOStart, InpSessionBOEnd,
      InpEmaCrossAdxMin, InpMeanRevAdxMax);

   if(!ok)
   {
      PrintFormat("Failed to initialize symbol: %s", g_symbol);
      return INIT_FAILED;
   }

   PrintFormat("PortfolioMaxProfit v6.02: %s TF=%s | MAP=%s flip=%s sess=%s",
               g_symbol, TfShortName(tf),
               InpSleeveMAP ? "ON" : "OFF",
               InpFlipOnSignal ? "ON" : "OFF",
               InpUseSession ? "filter" : "24h");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   g_portfolio.Deinit();
   Comment("");
}

void OnTick()
{
   g_portfolio.OnTick(g_lastBar);
   if(InpShowPanel)
   {
      datetime now = TimeCurrent();
      if(now - g_lastPanel >= InpPanelSeconds)
      {
         g_lastPanel = now;
         Comment(StringFormat("PortfolioMaxProfit v6.02 | %s\n", g_symbol) +
                 g_portfolio.StatusLine() +
                 StringFormat("\nEq: %.2f Bal: %.2f",
                              AccountInfoDouble(ACCOUNT_EQUITY),
                              AccountInfoDouble(ACCOUNT_BALANCE)));
      }
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   long dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(dealMagic != InpMagic)
      return;

   long dealEntry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_OUT_BY)
      return;

   string dealSym = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   double dealProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                       + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                       + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   if(dealProfit < 0)
      g_portfolio.RegisterLossBySymbol(dealSym);
   else if(dealProfit > 0)
      g_portfolio.RegisterWinBySymbol(dealSym);
}
//+------------------------------------------------------------------+
