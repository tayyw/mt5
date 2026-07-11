//+------------------------------------------------------------------+
//| Strategies.mqh  v6                                                |
//| Multi-sleeve: strict trend + mean-rev, EMA cross, session BO,    |
//| inside bar, momentum burst (research-backed active EAs)           |
//+------------------------------------------------------------------+
#property copyright "MT5 Portfolio EA"
#property strict

#ifndef STRATEGIES_MQH
#define STRATEGIES_MQH

enum ENUM_SIGNAL_DIR
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
};

enum ENUM_STRATEGY_ID
{
   STRAT_TREND      = 1,
   STRAT_BREAKOUT   = 2,
   STRAT_MEAN_REV   = 3,
   STRAT_EMA_CROSS  = 4,
   STRAT_SESSION_BO = 5,
   STRAT_INSIDE_BAR = 6,
   STRAT_MOMENTUM   = 7,
   STRAT_MA_MAP     = 8
};

struct STradeSignal
{
   ENUM_SIGNAL_DIR  direction;
   ENUM_STRATEGY_ID strategy;
   double           confidence;
   double           entryPrice;
   double           stopLoss;
   double           takeProfit;
   double           atr;
   double           riskPoints;
   string           comment;
};

class CStrategyEngine
{
private:
   int              m_fastMA;
   int              m_slowMA;
   int              m_rsiPeriod;
   double           m_rsiPullLow;
   double           m_rsiPullHigh;
   int              m_atrPeriod;
   double           m_atrSlMin;
   double           m_atrSlMax;
   double           m_rewardR;
   int              m_donchianPeriod;
   int              m_adxPeriod;
   double           m_adxTrendMin;
   double           m_adxBreakoutMin;
   ENUM_TIMEFRAMES  m_tf;
   ENUM_TIMEFRAMES  m_htf;
   bool             m_useHtf;
   bool             m_allowBreakout;
   double           m_maxSpreadAtr;
   double           m_minBodyAtr;
   bool             m_allowLong;
   bool             m_allowShort;

   bool             m_activeMode;
   bool             m_sleevePullback;
   bool             m_sleeveMeanRev;
   bool             m_sleeveEmaCross;
   bool             m_sleeveSessionBO;
   bool             m_sleeveInsideBar;
   bool             m_sleeveMomentum;
   bool             m_sleeveMAP;
   int              m_bbPeriod;
   double           m_bbDev;
   double           m_rsiOB;
   double           m_rsiOS;
   int              m_sessionBOStart;
   int              m_sessionBOEnd;
   double           m_emaCrossAdxMin;
   double           m_meanRevAdxMax;

   int h_fast, h_slow, h_rsi, h_atr, h_adx, h_htf_ma, h_htf_atr, h_bb;
   string           m_lastReject;
   int              m_barsEvaluated;
   int              m_setupsFound;

   bool FailReject(const string reason)
   {
      m_lastReject = reason;
      return false;
   }

   bool CopyOK(const int h, const int buf, const int n, double &a[])
   {
      ArraySetAsSeries(a, true);
      return (h != INVALID_HANDLE && CopyBuffer(h, buf, 0, n, a) >= n);
   }

   void ConsiderBest(STradeSignal &sideBest, const STradeSignal &cand)
   {
      if(cand.direction == SIGNAL_NONE) return;
      if(sideBest.direction == SIGNAL_NONE || cand.confidence > sideBest.confidence)
         sideBest = cand;
   }

   void SetSLBand(const string symbol, const ENUM_SIGNAL_DIR dir, const double entry,
                  const double atrv, STradeSignal &s)
   {
      if(dir == SIGNAL_BUY)
      {
         s.stopLoss = entry - m_atrSlMin * atrv;
         if(entry - s.stopLoss > m_atrSlMax * atrv)
            s.stopLoss = entry - m_atrSlMax * atrv;
         if(entry - s.stopLoss < m_atrSlMin * atrv * 0.85)
            s.stopLoss = entry - m_atrSlMin * atrv * 0.85;
      }
      else
      {
         s.stopLoss = entry + m_atrSlMin * atrv;
         if(s.stopLoss - entry > m_atrSlMax * atrv)
            s.stopLoss = entry + m_atrSlMax * atrv;
         if(s.stopLoss - entry < m_atrSlMin * atrv * 0.85)
            s.stopLoss = entry + m_atrSlMin * atrv * 0.85;
      }
   }

public:
   CStrategyEngine()
   {
      h_fast = h_slow = h_rsi = h_atr = h_adx = h_htf_ma = h_htf_atr = h_bb = INVALID_HANDLE;
      m_allowLong = m_allowShort = true;
      m_activeMode = true;
      m_sleevePullback = m_sleeveMeanRev = m_sleeveEmaCross = true;
      m_sleeveSessionBO = m_sleeveInsideBar = m_sleeveMomentum = true;
      m_sleeveMAP = true;
      m_bbPeriod = 20; m_bbDev = 2.0;
      m_rsiOB = 68; m_rsiOS = 32;
      m_sessionBOStart = 7; m_sessionBOEnd = 10;
      m_emaCrossAdxMin = 16; m_meanRevAdxMax = 28;
      m_lastReject = "init";
      m_barsEvaluated = 0;
      m_setupsFound = 0;
   }

   ~CStrategyEngine() { Release(); }

   void Configure(int fastMA, int slowMA, int rsiPeriod,
                  double rsiPullLow, double rsiPullHigh,
                  int atrPeriod, double atrSlMin, double atrSlMax, double rewardR,
                  int donchian, int adxPeriod, double adxTrendMin, double adxBOMin,
                  ENUM_TIMEFRAMES tf, ENUM_TIMEFRAMES htf, bool useHtf,
                  bool allowBreakout, double maxSpreadAtr, double minBodyAtr,
                  bool allowLong = true, bool allowShort = true)
   {
      m_fastMA = fastMA; m_slowMA = slowMA; m_rsiPeriod = rsiPeriod;
      m_rsiPullLow = rsiPullLow; m_rsiPullHigh = rsiPullHigh;
      m_atrPeriod = atrPeriod;
      m_atrSlMin = atrSlMin; m_atrSlMax = atrSlMax; m_rewardR = rewardR;
      m_donchianPeriod = donchian; m_adxPeriod = adxPeriod;
      m_adxTrendMin = adxTrendMin; m_adxBreakoutMin = adxBOMin;
      m_tf = tf; m_htf = htf; m_useHtf = useHtf;
      m_allowBreakout = allowBreakout;
      m_maxSpreadAtr = maxSpreadAtr;
      m_minBodyAtr = minBodyAtr;
      m_allowLong = allowLong;
      m_allowShort = allowShort;
   }

   void ConfigureSleeves(bool activeMode, bool sleevePullback, bool sleeveMeanRev,
                         bool sleeveEmaCross, bool sleeveSessionBO, bool sleeveInsideBar,
                         bool sleeveMomentum, bool sleeveMAP,
                         int bbPeriod, double bbDev,
                         double rsiOB, double rsiOS, int sessionBOStart, int sessionBOEnd,
                         double emaCrossAdxMin, double meanRevAdxMax)
   {
      m_activeMode = activeMode;
      m_sleevePullback = sleevePullback;
      m_sleeveMeanRev = sleeveMeanRev;
      m_sleeveEmaCross = sleeveEmaCross;
      m_sleeveSessionBO = sleeveSessionBO;
      m_sleeveInsideBar = sleeveInsideBar;
      m_sleeveMomentum = sleeveMomentum;
      m_sleeveMAP = sleeveMAP;
      m_bbPeriod = MathMax(10, bbPeriod);
      m_bbDev = MathMax(1.2, bbDev);
      m_rsiOB = rsiOB; m_rsiOS = rsiOS;
      m_sessionBOStart = sessionBOStart;
      m_sessionBOEnd = sessionBOEnd;
      m_emaCrossAdxMin = emaCrossAdxMin;
      m_meanRevAdxMax = meanRevAdxMax;
   }

   ENUM_TIMEFRAMES SignalTF() const { return m_tf; }
   string LastRejectReason() const { return m_lastReject; }
   int    BarsEvaluated() const { return m_barsEvaluated; }
   int    SetupsFound() const { return m_setupsFound; }

   bool InitHandles(const string symbol)
   {
      Release();
      h_fast = iMA(symbol, m_tf, m_fastMA, 0, MODE_EMA, PRICE_CLOSE);
      h_slow = iMA(symbol, m_tf, m_slowMA, 0, MODE_EMA, PRICE_CLOSE);
      h_rsi  = iRSI(symbol, m_tf, m_rsiPeriod, PRICE_CLOSE);
      h_atr  = iATR(symbol, m_tf, m_atrPeriod);
      h_adx  = iADX(symbol, m_tf, m_adxPeriod);
      if(m_sleeveMeanRev)
         h_bb = iBands(symbol, m_tf, m_bbPeriod, 0, m_bbDev, PRICE_CLOSE);
      if(m_useHtf)
      {
         h_htf_ma  = iMA(symbol, m_htf, 100, 0, MODE_EMA, PRICE_CLOSE);
         h_htf_atr = iATR(symbol, m_htf, m_atrPeriod);
      }
      if(h_fast == INVALID_HANDLE || h_slow == INVALID_HANDLE ||
         h_rsi == INVALID_HANDLE || h_atr == INVALID_HANDLE || h_adx == INVALID_HANDLE)
         return false;
      if(m_sleeveMeanRev && h_bb == INVALID_HANDLE) return false;
      if(m_useHtf && (h_htf_ma == INVALID_HANDLE || h_htf_atr == INVALID_HANDLE))
         return false;
      return true;
   }

   void Release()
   {
      if(h_fast != INVALID_HANDLE)    { IndicatorRelease(h_fast); h_fast = INVALID_HANDLE; }
      if(h_slow != INVALID_HANDLE)    { IndicatorRelease(h_slow); h_slow = INVALID_HANDLE; }
      if(h_rsi != INVALID_HANDLE)     { IndicatorRelease(h_rsi); h_rsi = INVALID_HANDLE; }
      if(h_atr != INVALID_HANDLE)     { IndicatorRelease(h_atr); h_atr = INVALID_HANDLE; }
      if(h_adx != INVALID_HANDLE)     { IndicatorRelease(h_adx); h_adx = INVALID_HANDLE; }
      if(h_bb != INVALID_HANDLE)      { IndicatorRelease(h_bb); h_bb = INVALID_HANDLE; }
      if(h_htf_ma != INVALID_HANDLE)  { IndicatorRelease(h_htf_ma); h_htf_ma = INVALID_HANDLE; }
      if(h_htf_atr != INVALID_HANDLE) { IndicatorRelease(h_htf_atr); h_htf_atr = INVALID_HANDLE; }
   }

   static void NormalizeStops(const string symbol, ENUM_SIGNAL_DIR dir,
                              double entry, double &sl, double &tp)
   {
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      long stops = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double minDist = MathMax((double)stops * point, 10.0 * point);
      double floor = entry * 0.00025;
      if(minDist < floor) minDist = floor;

      if(dir == SIGNAL_BUY)
      {
         if((entry - sl) < minDist) sl = entry - minDist;
         if((tp - entry) < minDist) tp = entry + minDist;
      }
      else
      {
         if((sl - entry) < minDist) sl = entry + minDist;
         if((entry - tp) < minDist) tp = entry - minDist;
      }
      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);
   }

   int HtfBias(const string symbol)
   {
      if(!m_useHtf) return 0;
      double ma[], atr[], closes[];
      if(!CopyOK(h_htf_ma, 0, 3, ma)) return 0;
      if(!CopyOK(h_htf_atr, 0, 3, atr)) return 0;
      ArraySetAsSeries(closes, true);
      if(CopyClose(symbol, m_htf, 0, 3, closes) < 3) return 0;
      double sep = atr[1] * (m_activeMode ? 0.15 : 0.25);
      if(closes[1] > ma[1] + sep && closes[1] > closes[2]) return 1;
      if(closes[1] < ma[1] - sep && closes[1] < closes[2]) return -1;
      return 0;
   }

   bool FinalizeSignal(const string symbol, STradeSignal &s, const bool relaxMinPoints = false)
   {
      if(s.direction == SIGNAL_NONE) return false;

      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      NormalizeStops(symbol, s.direction, s.entryPrice, s.stopLoss, s.takeProfit);
      s.riskPoints = MathAbs(s.entryPrice - s.stopLoss);
      if(s.riskPoints <= 0) return false;

      if(s.direction == SIGNAL_BUY)
         s.takeProfit = NormalizeDouble(s.entryPrice + m_rewardR * s.riskPoints, digits);
      else
         s.takeProfit = NormalizeDouble(s.entryPrice - m_rewardR * s.riskPoints, digits);

      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double minPts = relaxMinPoints ? 8.0 : 12.0;
      if(s.riskPoints < minPts * point) return false;

      double reward = MathAbs(s.takeProfit - s.entryPrice);
      double minRR = m_activeMode ? m_rewardR * 0.75 : m_rewardR * 0.9;
      if(reward / s.riskPoints < minRR) return false;

      s.entryPrice = NormalizeDouble(s.entryPrice, digits);
      return true;
   }

   bool FinalizeSignalLight(const string symbol, STradeSignal &s)
   {
      if(s.direction == SIGNAL_NONE) return false;
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      NormalizeStops(symbol, s.direction, s.entryPrice, s.stopLoss, s.takeProfit);
      s.riskPoints = MathAbs(s.entryPrice - s.stopLoss);
      if(s.riskPoints <= 0) return false;
      if(s.direction == SIGNAL_BUY)
         s.takeProfit = NormalizeDouble(s.entryPrice + m_rewardR * s.riskPoints, digits);
      else
         s.takeProfit = NormalizeDouble(s.entryPrice - m_rewardR * s.riskPoints, digits);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(s.riskPoints < 5.0 * point) return false;
      s.entryPrice = NormalizeDouble(s.entryPrice, digits);
      return true;
   }

   void PickBest(const STradeSignal &a, const STradeSignal &b, STradeSignal &best)
   {
      if(a.direction == SIGNAL_NONE && b.direction == SIGNAL_NONE)
      { best.direction = SIGNAL_NONE; return; }
      if(a.direction == SIGNAL_NONE) { best = b; return; }
      if(b.direction == SIGNAL_NONE) { best = a; return; }
      best = (a.confidence >= b.confidence ? a : b);
   }

   bool GenerateSignal(const string symbol, STradeSignal &out)
   {
      STradeSignal secondary;
      bool hasSecondary = false;
      return GenerateSignals(symbol, out, secondary, hasSecondary);
   }

   bool GenerateSignals(const string symbol, STradeSignal &primary,
                        STradeSignal &secondary, bool &hasSecondary)
   {
      primary.direction = SIGNAL_NONE;
      secondary.direction = SIGNAL_NONE;
      hasSecondary = false;

      double fast[], slow[], rsi[], atr[], adx[], pdi[], mdi[];
      if(!CopyOK(h_fast, 0, 8, fast)) return false;
      if(!CopyOK(h_slow, 0, 8, slow)) return false;
      if(!CopyOK(h_rsi, 0, 8, rsi)) return false;
      if(!CopyOK(h_atr, 0, 30, atr)) return false;
      if(!CopyOK(h_adx, 0, 6, adx)) return false;
      if(!CopyOK(h_adx, 1, 6, pdi)) return false;
      if(!CopyOK(h_adx, 2, 6, mdi)) return false;

      double atrv = atr[1];
      if(atrv <= 0) return false;

      double atrSum = 0;
      for(int i = 1; i <= 20; i++) atrSum += atr[i];
      double atrAvg = atrSum / 20.0;
      if(atrAvg <= 0) return false;
      double spikeMult = m_activeMode ? 3.0 : 1.85;
      double deadMult  = m_activeMode ? 0.0 : 0.45;
      if(atrv > atrAvg * spikeMult) return FailReject("ATR spike");
      if(deadMult > 0 && atrv < atrAvg * deadMult) return FailReject("ATR dead");

      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double spread = ask - bid;
      if(spread < 0) return FailReject("bad quote");
      if(spread > 0 && spread > m_maxSpreadAtr * atrv)
         return FailReject(StringFormat("spread %.5f>%.5f", spread, m_maxSpreadAtr * atrv));

      m_barsEvaluated++;

      int need = MathMax(m_donchianPeriod + 6, 30);
      double h[], l[], c[], o[];
      ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
      ArraySetAsSeries(c, true); ArraySetAsSeries(o, true);
      if(CopyHigh(symbol, m_tf, 0, need, h) < need) return false;
      if(CopyLow(symbol, m_tf, 0, need, l) < need) return false;
      if(CopyClose(symbol, m_tf, 0, 10, c) < 10) return false;
      if(CopyOpen(symbol, m_tf, 0, 10, o) < 10) return false;

      int htf = HtfBias(symbol);
      bool htfLongOK  = (!m_useHtf || htf > 0);
      bool htfShortOK = (!m_useHtf || htf < 0);
      bool strictHtfBlock = (m_useHtf && htf == 0 && !m_activeMode);

      bool adxStrict = (adx[1] >= m_adxTrendMin && adx[1] >= adx[3]);
      bool bullStruct = (fast[1] > slow[1] && slow[1] > slow[4] && c[1] > slow[1]);
      bool bearStruct = (fast[1] < slow[1] && slow[1] < slow[4] && c[1] < slow[1]);
      double mom = c[1] - c[5];

      double swingLow = l[1], swingHigh = h[1];
      for(int i = 2; i <= 5; i++)
      {
         if(l[i] < swingLow) swingLow = l[i];
         if(h[i] > swingHigh) swingHigh = h[i];
      }

      double body = MathAbs(c[1] - o[1]);
      double range = h[1] - l[1];
      if(range <= 0) return false;
      double bodyMin = m_activeMode ? m_minBodyAtr * 0.65 : m_minBodyAtr;
      bool bullCandle = (c[1] > o[1] && body >= bodyMin * atrv && body / range >= 0.40);
      bool bearCandle = (c[1] < o[1] && body >= bodyMin * atrv && body / range >= 0.40);

      double dHigh = h[2], dLow = l[2];
      for(int i = 3; i <= m_donchianPeriod + 1; i++)
      {
         if(h[i] > dHigh) dHigh = h[i];
         if(l[i] < dLow) dLow = l[i];
      }

      STradeSignal longSig, shortSig;
      longSig.direction = SIGNAL_NONE;
      shortSig.direction = SIGNAL_NONE;
      longSig.atr = atrv;
      shortSig.atr = atrv;
      const bool relax = m_activeMode;

      // --- Sleeve 1: Strict pullback (slow, high quality) ---
      if(m_sleevePullback && !strictHtfBlock && adxStrict)
      {
         bool touchedL = (l[1] <= fast[1] + 0.25 * atrv) || (l[2] <= fast[2] + 0.30 * atrv);
         double localHigh = MathMax(h[2], MathMax(h[3], h[4]));
         double retraceL = localHigh - l[1];
         bool longSetup = m_allowLong && htfLongOK && bullStruct && touchedL &&
                          (swingLow > slow[1] - 0.15 * atrv) &&
                          (retraceL >= 0.35 * atrv && retraceL <= 1.8 * atrv) &&
                          (pdi[1] > mdi[1]) && (mom > 0) &&
                          (rsi[1] >= m_rsiPullLow && rsi[1] <= 58.0) &&
                          bullCandle && (c[1] > fast[1]) && (c[1] > c[2]);
         if(longSetup)
         {
            STradeSignal s;
            s.direction = SIGNAL_BUY;
            s.strategy = STRAT_TREND;
            s.entryPrice = ask;
            s.atr = atrv;
            double rawSL = swingLow - 0.10 * atrv;
            s.stopLoss = MathMax(ask - m_atrSlMax * atrv, MathMin(rawSL, ask - m_atrSlMin * atrv));
            double risk = ask - s.stopLoss;
            s.takeProfit = ask + m_rewardR * risk;
            s.riskPoints = risk;
            s.confidence = 0.62 + MathMin(0.12, (adx[1] - m_adxTrendMin) / 60.0);
            s.comment = "PB_BUY";
            STradeSignal fin = s;
            if(FinalizeSignal(symbol, fin)) ConsiderBest(longSig, fin);
         }

         bool touchedS = (h[1] >= fast[1] - 0.25 * atrv) || (h[2] >= fast[2] - 0.30 * atrv);
         double localLow = MathMin(l[2], MathMin(l[3], l[4]));
         double retraceS = h[1] - localLow;
         bool shortSetup = m_allowShort && htfShortOK && bearStruct && touchedS &&
                           (swingHigh < slow[1] + 0.15 * atrv) &&
                           (retraceS >= 0.35 * atrv && retraceS <= 1.8 * atrv) &&
                           (mdi[1] > pdi[1]) && (mom < 0) &&
                           (rsi[1] <= m_rsiPullHigh && rsi[1] >= 42.0) &&
                           bearCandle && (c[1] < fast[1]) && (c[1] < c[2]);
         if(shortSetup)
         {
            STradeSignal s;
            s.direction = SIGNAL_SELL;
            s.strategy = STRAT_TREND;
            s.entryPrice = bid;
            s.atr = atrv;
            double rawSL = swingHigh + 0.10 * atrv;
            s.stopLoss = MathMin(bid + m_atrSlMax * atrv, MathMax(rawSL, bid + m_atrSlMin * atrv));
            double risk = s.stopLoss - bid;
            s.takeProfit = bid - m_rewardR * risk;
            s.riskPoints = risk;
            s.confidence = 0.62 + MathMin(0.12, (adx[1] - m_adxTrendMin) / 60.0);
            s.comment = "PB_SELL";
            STradeSignal fin = s;
            if(FinalizeSignal(symbol, fin)) ConsiderBest(shortSig, fin);
         }
      }

      // --- Sleeve 2: Donchian breakout ---
      if(m_allowBreakout && !strictHtfBlock)
      {
         bool rising = (adx[1] > adx[2] && adx[1] >= m_adxBreakoutMin);
         if(m_allowLong && htfLongOK && rising && c[1] > dHigh && bullCandle &&
            pdi[1] > mdi[1] && (c[1] - dHigh) <= 0.6 * atrv && (c[1] > fast[1]))
         {
            STradeSignal s;
            s.direction = SIGNAL_BUY;
            s.strategy = STRAT_BREAKOUT;
            s.entryPrice = ask;
            s.atr = atrv;
            s.stopLoss = MathMin(dHigh - 0.15 * atrv, ask - m_atrSlMin * atrv);
            SetSLBand(symbol, SIGNAL_BUY, ask, atrv, s);
            double risk = ask - s.stopLoss;
            s.takeProfit = ask + m_rewardR * risk;
            s.riskPoints = risk;
            s.confidence = 0.58 + MathMin(0.10, adx[1] / 100.0);
            s.comment = "BO_BUY";
            STradeSignal fin = s;
            if(FinalizeSignal(symbol, fin, relax)) ConsiderBest(longSig, fin);
         }
         if(m_allowShort && htfShortOK && rising && c[1] < dLow && bearCandle &&
            mdi[1] > pdi[1] && (dLow - c[1]) <= 0.6 * atrv && (c[1] < fast[1]))
         {
            STradeSignal s;
            s.direction = SIGNAL_SELL;
            s.strategy = STRAT_BREAKOUT;
            s.entryPrice = bid;
            s.atr = atrv;
            s.stopLoss = MathMax(dLow + 0.15 * atrv, bid + m_atrSlMin * atrv);
            SetSLBand(symbol, SIGNAL_SELL, bid, atrv, s);
            double risk = s.stopLoss - bid;
            s.takeProfit = bid - m_rewardR * risk;
            s.riskPoints = risk;
            s.confidence = 0.58 + MathMin(0.10, adx[1] / 100.0);
            s.comment = "BO_SELL";
            STradeSignal fin = s;
            if(FinalizeSignal(symbol, fin, relax)) ConsiderBest(shortSig, fin);
         }
      }

      // --- Sleeve 3: Mean reversion (BB + RSI) — ranging markets ---
      if(m_sleeveMeanRev && adx[1] <= m_meanRevAdxMax)
      {
         double bbU[], bbM[], bbL[];
         if(CopyOK(h_bb, 0, 3, bbM) && CopyOK(h_bb, 1, 3, bbU) && CopyOK(h_bb, 2, 3, bbL))
         {
            if(m_allowLong && c[1] <= bbL[1] + 0.05 * atrv && rsi[1] <= m_rsiOS &&
               c[1] > o[1] && c[1] > c[2])
            {
               STradeSignal s;
               s.direction = SIGNAL_BUY;
               s.strategy = STRAT_MEAN_REV;
               s.entryPrice = ask;
               s.atr = atrv;
               s.stopLoss = MathMin(l[1], bbL[1]) - 0.15 * atrv;
               SetSLBand(symbol, SIGNAL_BUY, ask, atrv, s);
               double risk = ask - s.stopLoss;
               s.takeProfit = ask + m_rewardR * risk;
               s.riskPoints = risk;
               s.confidence = 0.54 + MathMin(0.08, (m_meanRevAdxMax - adx[1]) / 40.0);
               s.comment = "MR_BUY";
               STradeSignal fin = s;
               if(FinalizeSignal(symbol, fin, true)) ConsiderBest(longSig, fin);
            }
            if(m_allowShort && c[1] >= bbU[1] - 0.05 * atrv && rsi[1] >= m_rsiOB &&
               c[1] < o[1] && c[1] < c[2])
            {
               STradeSignal s;
               s.direction = SIGNAL_SELL;
               s.strategy = STRAT_MEAN_REV;
               s.entryPrice = bid;
               s.atr = atrv;
               s.stopLoss = MathMax(h[1], bbU[1]) + 0.15 * atrv;
               SetSLBand(symbol, SIGNAL_SELL, bid, atrv, s);
               double risk = s.stopLoss - bid;
               s.takeProfit = bid - m_rewardR * risk;
               s.riskPoints = risk;
               s.confidence = 0.54 + MathMin(0.08, (m_meanRevAdxMax - adx[1]) / 40.0);
               s.comment = "MR_SELL";
               STradeSignal fin = s;
               if(FinalizeSignal(symbol, fin, true)) ConsiderBest(shortSig, fin);
            }
         }
      }

      // --- Sleeve 4: EMA crossover ---
      if(m_sleeveEmaCross && adx[1] >= m_emaCrossAdxMin)
      {
         bool crossUp = (fast[1] > slow[1] && fast[2] <= slow[2]);
         bool crossDn = (fast[1] < slow[1] && fast[2] >= slow[2]);
         if(m_allowLong && crossUp && c[1] > slow[1] && bullCandle &&
            (!m_useHtf || htfLongOK || m_activeMode))
         {
            STradeSignal s;
            s.direction = SIGNAL_BUY;
            s.strategy = STRAT_EMA_CROSS;
            s.entryPrice = ask;
            s.atr = atrv;
            s.stopLoss = MathMin(swingLow, slow[1]) - 0.12 * atrv;
            SetSLBand(symbol, SIGNAL_BUY, ask, atrv, s);
            double risk = ask - s.stopLoss;
            s.takeProfit = ask + m_rewardR * risk;
            s.riskPoints = risk;
            s.confidence = 0.53 + MathMin(0.10, (adx[1] - m_emaCrossAdxMin) / 50.0);
            s.comment = "XUP_BUY";
            STradeSignal fin = s;
            if(FinalizeSignal(symbol, fin, true)) ConsiderBest(longSig, fin);
         }
         if(m_allowShort && crossDn && c[1] < slow[1] && bearCandle &&
            (!m_useHtf || htfShortOK || m_activeMode))
         {
            STradeSignal s;
            s.direction = SIGNAL_SELL;
            s.strategy = STRAT_EMA_CROSS;
            s.entryPrice = bid;
            s.atr = atrv;
            s.stopLoss = MathMax(swingHigh, slow[1]) + 0.12 * atrv;
            SetSLBand(symbol, SIGNAL_SELL, bid, atrv, s);
            double risk = s.stopLoss - bid;
            s.takeProfit = bid - m_rewardR * risk;
            s.riskPoints = risk;
            s.confidence = 0.53 + MathMin(0.10, (adx[1] - m_emaCrossAdxMin) / 50.0);
            s.comment = "XDN_SELL";
            STradeSignal fin = s;
            if(FinalizeSignal(symbol, fin, true)) ConsiderBest(shortSig, fin);
         }
      }

      // --- Sleeve 5: Session range breakout (Asian range → London) ---
      if(m_sleeveSessionBO)
      {
         MqlDateTime barDt;
         TimeToStruct(iTime(symbol, m_tf, 1), barDt);
         bool inWindow = (barDt.hour >= m_sessionBOStart && barDt.hour < m_sessionBOEnd);

         if(inWindow)
         {
            double rangeHigh = 0, rangeLow = 1e100;
            int bars = MathMin(need - 1, 48);
            for(int i = 2; i <= bars; i++)
            {
               datetime bt = iTime(symbol, m_tf, i);
               MqlDateTime dt;
               TimeToStruct(bt, dt);
               if(dt.hour >= 0 && dt.hour < m_sessionBOStart)
               {
                  if(h[i] > rangeHigh) rangeHigh = h[i];
                  if(l[i] < rangeLow) rangeLow = l[i];
               }
            }
            if(rangeHigh > rangeLow && (rangeHigh - rangeLow) >= 0.25 * atrv)
            {
               if(m_allowLong && c[1] > rangeHigh && bullCandle && c[1] > fast[1])
               {
                  STradeSignal s;
                  s.direction = SIGNAL_BUY;
                  s.strategy = STRAT_SESSION_BO;
                  s.entryPrice = ask;
                  s.atr = atrv;
                  s.stopLoss = rangeHigh - 0.20 * atrv;
                  SetSLBand(symbol, SIGNAL_BUY, ask, atrv, s);
                  double risk = ask - s.stopLoss;
                  s.takeProfit = ask + m_rewardR * risk;
                  s.riskPoints = risk;
                  s.confidence = 0.55;
                  s.comment = "SES_BUY";
                  STradeSignal fin = s;
                  if(FinalizeSignal(symbol, fin, true)) ConsiderBest(longSig, fin);
               }
               if(m_allowShort && c[1] < rangeLow && bearCandle && c[1] < fast[1])
               {
                  STradeSignal s;
                  s.direction = SIGNAL_SELL;
                  s.strategy = STRAT_SESSION_BO;
                  s.entryPrice = bid;
                  s.atr = atrv;
                  s.stopLoss = rangeLow + 0.20 * atrv;
                  SetSLBand(symbol, SIGNAL_SELL, bid, atrv, s);
                  double risk = s.stopLoss - bid;
                  s.takeProfit = bid - m_rewardR * risk;
                  s.riskPoints = risk;
                  s.confidence = 0.55;
                  s.comment = "SES_SELL";
                  STradeSignal fin = s;
                  if(FinalizeSignal(symbol, fin, true)) ConsiderBest(shortSig, fin);
               }
            }
         }
      }

      // --- Sleeve 6: Inside bar breakout ---
      if(m_sleeveInsideBar && need >= 5)
      {
         bool inside = (h[2] < h[3] && l[2] > l[3]);
         if(inside)
         {
            if(m_allowLong && c[1] > h[2] && c[1] > o[1] && fast[1] >= slow[1])
            {
               STradeSignal s;
               s.direction = SIGNAL_BUY;
               s.strategy = STRAT_INSIDE_BAR;
               s.entryPrice = ask;
               s.atr = atrv;
               s.stopLoss = l[2] - 0.10 * atrv;
               SetSLBand(symbol, SIGNAL_BUY, ask, atrv, s);
               double risk = ask - s.stopLoss;
               s.takeProfit = ask + m_rewardR * risk;
               s.riskPoints = risk;
               s.confidence = 0.52;
               s.comment = "IB_BUY";
               STradeSignal fin = s;
               if(FinalizeSignal(symbol, fin, true)) ConsiderBest(longSig, fin);
            }
            if(m_allowShort && c[1] < l[2] && c[1] < o[1] && fast[1] <= slow[1])
            {
               STradeSignal s;
               s.direction = SIGNAL_SELL;
               s.strategy = STRAT_INSIDE_BAR;
               s.entryPrice = bid;
               s.atr = atrv;
               s.stopLoss = h[2] + 0.10 * atrv;
               SetSLBand(symbol, SIGNAL_SELL, bid, atrv, s);
               double risk = s.stopLoss - bid;
               s.takeProfit = bid - m_rewardR * risk;
               s.riskPoints = risk;
               s.confidence = 0.52;
               s.comment = "IB_SELL";
               STradeSignal fin = s;
               if(FinalizeSignal(symbol, fin, true)) ConsiderBest(shortSig, fin);
            }
         }
      }

      // --- Sleeve 7: Momentum burst ---
      if(m_sleeveMomentum && body >= 1.15 * atrv)
      {
         if(m_allowLong && bullCandle && c[1] > h[2] && fast[1] > slow[1] &&
            pdi[1] > mdi[1] && (!m_useHtf || htfLongOK || m_activeMode))
         {
            STradeSignal s;
            s.direction = SIGNAL_BUY;
            s.strategy = STRAT_MOMENTUM;
            s.entryPrice = ask;
            s.atr = atrv;
            s.stopLoss = l[1] - 0.12 * atrv;
            SetSLBand(symbol, SIGNAL_BUY, ask, atrv, s);
            double risk = ask - s.stopLoss;
            s.takeProfit = ask + m_rewardR * risk;
            s.riskPoints = risk;
            s.confidence = 0.54 + MathMin(0.08, body / atrv / 3.0);
            s.comment = "MOM_BUY";
            STradeSignal fin = s;
            if(FinalizeSignal(symbol, fin, true)) ConsiderBest(longSig, fin);
         }
         if(m_allowShort && bearCandle && c[1] < l[2] && fast[1] < slow[1] &&
            mdi[1] > pdi[1] && (!m_useHtf || htfShortOK || m_activeMode))
         {
            STradeSignal s;
            s.direction = SIGNAL_SELL;
            s.strategy = STRAT_MOMENTUM;
            s.entryPrice = bid;
            s.atr = atrv;
            s.stopLoss = h[1] + 0.12 * atrv;
            SetSLBand(symbol, SIGNAL_SELL, bid, atrv, s);
            double risk = s.stopLoss - bid;
            s.takeProfit = bid - m_rewardR * risk;
            s.riskPoints = risk;
            s.confidence = 0.54 + MathMin(0.08, body / atrv / 3.0);
            s.comment = "MOM_SELL";
            STradeSignal fin = s;
            if(FinalizeSignal(symbol, fin, true)) ConsiderBest(shortSig, fin);
         }
      }

      // --- Sleeve 8: MA trend / cross (MAPSAR-like — high frequency) ---
      if(m_sleeveMAP)
      {
         bool maCrossUp = (fast[1] > slow[1] && fast[2] <= slow[2]);
         bool maCrossDn = (fast[1] < slow[1] && fast[2] >= slow[2]);
         bool pxCrossUp = (c[1] > fast[1] && c[2] <= fast[2] && fast[1] > slow[1]);
         bool pxCrossDn = (c[1] < fast[1] && c[2] >= fast[2] && fast[1] < slow[1]);

         if(m_allowLong && (maCrossUp || pxCrossUp) && rsi[1] > 40 && rsi[1] < 75)
         {
            STradeSignal s;
            s.direction = SIGNAL_BUY;
            s.strategy = STRAT_MA_MAP;
            s.entryPrice = ask;
            s.atr = atrv;
            s.stopLoss = ask - m_atrSlMin * atrv;
            double risk = ask - s.stopLoss;
            s.takeProfit = ask + m_rewardR * risk;
            s.riskPoints = risk;
            s.confidence = 0.50 + (maCrossUp ? 0.04 : 0.0);
            s.comment = maCrossUp ? "MAP_XUP" : "MAP_PXUP";
            STradeSignal fin = s;
            if(FinalizeSignalLight(symbol, fin)) ConsiderBest(longSig, fin);
         }
         if(m_allowShort && (maCrossDn || pxCrossDn) && rsi[1] < 60 && rsi[1] > 25)
         {
            STradeSignal s;
            s.direction = SIGNAL_SELL;
            s.strategy = STRAT_MA_MAP;
            s.entryPrice = bid;
            s.atr = atrv;
            s.stopLoss = bid + m_atrSlMin * atrv;
            double risk = s.stopLoss - bid;
            s.takeProfit = bid - m_rewardR * risk;
            s.riskPoints = risk;
            s.confidence = 0.50 + (maCrossDn ? 0.04 : 0.0);
            s.comment = maCrossDn ? "MAP_XDN" : "MAP_PXDN";
            STradeSignal fin = s;
            if(FinalizeSignalLight(symbol, fin)) ConsiderBest(shortSig, fin);
         }
      }

      PickBest(longSig, shortSig, primary);
      if(primary.direction == SIGNAL_NONE)
      {
         m_lastReject = "no setup matched";
         return false;
      }

      m_setupsFound++;
      m_lastReject = StringFormat("OK %s c=%.2f", primary.comment, primary.confidence);

      if(longSig.direction != SIGNAL_NONE && shortSig.direction != SIGNAL_NONE &&
         longSig.direction != shortSig.direction)
      {
         secondary = (primary.direction == SIGNAL_BUY ? shortSig : longSig);
         hasSecondary = true;
      }

      return true;
   }
};

#endif
//+------------------------------------------------------------------+
