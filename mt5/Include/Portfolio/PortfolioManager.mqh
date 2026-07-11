//+------------------------------------------------------------------+
//| PortfolioManager.mqh  v5                                          |
//| Pyramiding, runner exits, hedging, martingale (single-symbol)     |
//+------------------------------------------------------------------+
#property copyright "MT5 Portfolio EA"
#property strict

#ifndef PORTFOLIO_MANAGER_MQH
#define PORTFOLIO_MANAGER_MQH

#include "RiskManager.mqh"
#include "Strategies.mqh"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

#define MAX_SYMBOLS 32
#define MAX_TRACK   64

struct SSymbolSlot
{
   string          symbol;
   CStrategyEngine engine;
   bool            ready;
   double          weight;
   int             magicOffset;
   string          group;
   datetime        cooldownUntil;
   int             lossStreak;
   double          lastPyramidPrice;
};

struct SPosTrack
{
   ulong  ticket;
   double riskDist;
   bool   partialDone;
   double openPrice;
   int    type;
   bool   isPyramid;
};

class CPortfolioManager
{
private:
   SSymbolSlot   m_slots[MAX_SYMBOLS];
   int           m_count;
   CRiskManager *m_risk;
   CTrade        m_trade;
   CPositionInfo m_pos;
   long          m_magicBase;
   int           m_slippage;
   double        m_minConfidence;
   bool          m_useFixedTP;
   bool          m_useTrailing;
   double        m_trailAtrMult;
   double        m_breakevenR;
   double        m_trailStartR;
   double        m_partialR;
   double        m_partialPct;
   double        m_progressiveLock;
   int           m_maxPerSymbol;
   bool          m_oneDirectionPerSymbol;
   bool          m_allowHedging;
   int           m_maxPerDirection;
   int           m_cooldownBars;
   int           m_sessionStartHour;
   int           m_sessionEndHour;
   bool          m_useSessionFilter;
   int           m_maxSameGroup;
   ENUM_TIMEFRAMES m_tf;

   bool          m_usePyramid;
   int           m_maxPyramidLegs;
   double        m_pyramidMinR;
   double        m_pyramidAddR;
   double        m_pyramidRiskPct;
   bool          m_pyramidNeedADX;
   double        m_pyramidADXMin;
   int           m_adxPeriod;

   bool          m_useMartingale;
   double        m_martingaleMult;
   int           m_martingaleMaxSteps;
   bool          m_flipOnSignal;

   SPosTrack     m_track[MAX_TRACK];
   int           m_trackCount;
   string        m_lastSkipReason;
   int           m_entriesOpened;

   bool InSession() const
   {
      if(!m_useSessionFilter) return true;
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int h = dt.hour;
      if(dt.day_of_week == 5 && h >= 18) return false;
      if(dt.day_of_week == 1 && h < 9) return false;
      if(m_sessionStartHour <= m_sessionEndHour)
         return (h >= m_sessionStartHour && h < m_sessionEndHour);
      return (h >= m_sessionStartHour || h < m_sessionEndHour);
   }

   ENUM_ORDER_TYPE_FILLING FillingFor(const string symbol) const
   {
      long fm = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
      if((fm & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
      if((fm & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
      return ORDER_FILLING_RETURN;
   }

   int FindTrack(const ulong ticket) const
   {
      for(int i = 0; i < m_trackCount; i++)
         if(m_track[i].ticket == ticket) return i;
      return -1;
   }

   void TrackAdd(const ulong ticket, const double riskDist, const double openPrice,
                 const int type, const bool isPyramid = false)
   {
      int idx = FindTrack(ticket);
      if(idx < 0)
      {
         if(m_trackCount >= MAX_TRACK)
         {
            for(int i = 1; i < m_trackCount; i++) m_track[i-1] = m_track[i];
            m_trackCount--;
         }
         idx = m_trackCount++;
      }
      m_track[idx].ticket = ticket;
      m_track[idx].riskDist = riskDist;
      m_track[idx].partialDone = false;
      m_track[idx].openPrice = openPrice;
      m_track[idx].type = type;
      m_track[idx].isPyramid = isPyramid;
   }

   void TrackCleanup()
   {
      for(int i = m_trackCount - 1; i >= 0; i--)
      {
         bool alive = false;
         for(int p = PositionsTotal() - 1; p >= 0; p--)
         {
            if(!m_pos.SelectByIndex(p)) continue;
            if(m_pos.Ticket() == m_track[i].ticket) { alive = true; break; }
         }
         if(!alive)
         {
            for(int j = i + 1; j < m_trackCount; j++) m_track[j-1] = m_track[j];
            m_trackCount--;
         }
      }
   }

   double GetAtr(const string sym) const
   {
      int hAtr = iATR(sym, m_tf, 14);
      if(hAtr == INVALID_HANDLE) return 0;
      double ab[];
      ArraySetAsSeries(ab, true);
      double v = 0;
      if(CopyBuffer(hAtr, 0, 0, 2, ab) >= 2) v = ab[1];
      IndicatorRelease(hAtr);
      return v;
   }

   bool AdxRising(const string sym, double &adxOut) const
   {
      adxOut = 0;
      int h = iADX(sym, m_tf, m_adxPeriod);
      if(h == INVALID_HANDLE) return false;
      double a[];
      ArraySetAsSeries(a, true);
      bool ok = (CopyBuffer(h, 0, 0, 4, a) >= 4);
      if(ok)
      {
         adxOut = a[1];
         ok = (a[1] >= a[2] && a[1] >= m_pyramidADXMin);
      }
      IndicatorRelease(h);
      return ok;
   }

   int CountSymbolPositions(const string symbol) const
   {
      int n = 0;
      CPositionInfo pos;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!pos.SelectByIndex(i)) continue;
         if(!IsOurMagic(pos.Magic())) continue;
         if(pos.Symbol() == symbol) n++;
      }
      return n;
   }

   int CountSymbolDir(const string symbol, const bool wantBuy) const
   {
      int n = 0;
      CPositionInfo pos;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!pos.SelectByIndex(i)) continue;
         if(!IsOurMagic(pos.Magic())) continue;
         if(pos.Symbol() != symbol) continue;
         bool isBuy = (pos.PositionType() == POSITION_TYPE_BUY);
         if(isBuy == wantBuy) n++;
      }
      return n;
   }

   int MaxLegsForDirection() const
   {
      if(m_usePyramid) return MathMax(1, m_maxPyramidLegs);
      return MathMax(1, m_maxPerDirection);
   }

   bool CanOpenDirection(const string sym, const ENUM_SIGNAL_DIR dir) const
   {
      bool wantBuy = (dir == SIGNAL_BUY);
      int dirCount = CountSymbolDir(sym, wantBuy);
      int maxLegs = MaxLegsForDirection();

      if(dirCount >= maxLegs)
         return false;

      if(m_allowHedging)
         return true;

      // No hedge: only one direction at a time; pyramids add via TryPyramid
      if(CountSymbolPositions(sym) > 0)
         return false;

      return true;
   }

   double MartingaleVolumeMult(const int slot) const
   {
      if(!m_useMartingale || slot < 0 || slot >= m_count)
         return 1.0;
      int steps = MathMin(m_slots[slot].lossStreak, m_martingaleMaxSteps);
      if(steps <= 0) return 1.0;
      return MathPow(m_martingaleMult, steps);
   }

   bool FindAnchorLeg(const string sym, const bool wantBuy,
                      ulong &ticketOut, double &riskOut, double &openOut, double &rOut)
   {
      ticketOut = 0;
      riskOut = openOut = rOut = 0;
      double bestR = -1e9;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!m_pos.SelectByIndex(i)) continue;
         if(!IsOurMagic(m_pos.Magic())) continue;
         if(m_pos.Symbol() != sym) continue;
         bool isBuy = (m_pos.PositionType() == POSITION_TYPE_BUY);
         if(isBuy != wantBuy) continue;

         ulong t = m_pos.Ticket();
         double open = m_pos.PriceOpen();
         double sl = m_pos.StopLoss();
         int ti = FindTrack(t);
         double risk = (ti >= 0 ? m_track[ti].riskDist : 0);
         if(risk <= 0 && sl > 0) risk = MathAbs(open - sl);
         if(risk <= 0) continue;

         double bid = SymbolInfoDouble(sym, SYMBOL_BID);
         double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
         double profit = isBuy ? (bid - open) : (open - ask);
         double rMult = profit / risk;
         if(rMult > bestR)
         {
            bestR = rMult;
            ticketOut = t;
            riskOut = risk;
            openOut = open;
            rOut = rMult;
         }
      }
      return (ticketOut > 0);
   }

   bool OpenPosition(const int slot, const string sym, const ENUM_SIGNAL_DIR dir,
                     const double lots, const double sl, const double tp,
                     const string comment, const double slDist, const bool isPyramid)
   {
      if(lots <= 0) return false;

      m_trade.SetExpertMagicNumber(MagicFor(slot));
      m_trade.SetDeviationInPoints(m_slippage);
      m_trade.SetTypeFilling(FillingFor(sym));

      bool ok = false;
      if(dir == SIGNAL_BUY)
         ok = m_trade.Buy(lots, sym, 0, sl, tp, comment);
      else
         ok = m_trade.Sell(lots, sym, 0, sl, tp, comment);

      if(!ok)
      {
         PrintFormat("FAIL %s %s %d %s", comment, sym,
                     m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
         return false;
      }

      m_risk.RegisterNewTrade();

      ulong newTicket = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!m_pos.SelectByIndex(i)) continue;
         if(m_pos.Symbol() != sym || m_pos.Magic() != MagicFor(slot)) continue;
         if(m_pos.Ticket() > newTicket)
            newTicket = m_pos.Ticket();
      }
      if(newTicket > 0 && m_pos.SelectByTicket(newTicket))
      {
         TrackAdd(newTicket, slDist, m_pos.PriceOpen(), (int)m_pos.PositionType(), isPyramid);
         if(isPyramid)
            m_slots[slot].lastPyramidPrice = m_pos.PriceOpen();
         PrintFormat("OPEN %s %s lots=%.2f SL=%.5f TP=%.5f",
                     comment, sym, lots, sl, tp);
      }
      return true;
   }

   void TryPyramid(const int slot)
   {
      if(!m_usePyramid || m_risk == NULL || m_risk.IsHalted()) return;
      if(!InSession()) return;

      string sym = m_slots[slot].symbol;
      int openAll = CountOurPositions();
      double heat = PortfolioHeatPct();
      if(!m_risk.CanOpenNewTrade(openAll, heat)) return;
      if(CountSymbolPositions(sym) >= m_maxPerSymbol) return;

      bool wantBuy = true;
      ulong anchorTicket;
      double anchorRisk, anchorOpen, anchorR;
      if(FindAnchorLeg(sym, true, anchorTicket, anchorRisk, anchorOpen, anchorR))
         wantBuy = true;
      else if(FindAnchorLeg(sym, false, anchorTicket, anchorRisk, anchorOpen, anchorR))
         wantBuy = false;
      else
         return;

      int dirLegs = CountSymbolDir(sym, wantBuy);
      if(dirLegs >= m_maxPyramidLegs || dirLegs < 1)
         return;
      if(anchorR < m_pyramidMinR)
         return;

      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      double curPrice = wantBuy ? ask : bid;
      double refPrice = (m_slots[slot].lastPyramidPrice > 0
                         ? m_slots[slot].lastPyramidPrice : anchorOpen);
      double advanceR = wantBuy
                        ? (curPrice - refPrice) / anchorRisk
                        : (refPrice - curPrice) / anchorRisk;
      if(advanceR < m_pyramidAddR)
         return;

      if(m_pyramidNeedADX)
      {
         double adx = 0;
         if(!AdxRising(sym, adx)) return;
      }

      if(!m_pos.SelectByTicket(anchorTicket)) return;
      double anchorSL = m_pos.StopLoss();
      double tp = m_useFixedTP ? m_pos.TakeProfit() : 0;

      double slDist = anchorRisk;
      double volMult = MartingaleVolumeMult(slot);
      double lots = m_risk.CalculateLotSize(sym, slDist, m_pyramidRiskPct, volMult);
      if(lots <= 0) return;

      string cmt = StringFormat("PYR_%s|leg%d", wantBuy ? "BUY" : "SELL", dirLegs + 1);
      ENUM_SIGNAL_DIR dir = wantBuy ? SIGNAL_BUY : SIGNAL_SELL;
      OpenPosition(slot, sym, dir, lots, anchorSL, tp, cmt, slDist, true);
   }

public:
   CPortfolioManager()
   {
      m_count = 0; m_risk = NULL; m_magicBase = 910500; m_slippage = 30;
      m_minConfidence = 0.58; m_useFixedTP = false; m_useTrailing = true;
      m_trailAtrMult = 1.5; m_breakevenR = 0.8; m_trailStartR = 1.5;
      m_partialR = 2.0; m_partialPct = 0.33; m_progressiveLock = 0.40;
      m_maxPerSymbol = 3; m_oneDirectionPerSymbol = true;
      m_allowHedging = false; m_maxPerDirection = 1;
      m_cooldownBars = 8; m_sessionStartHour = 7; m_sessionEndHour = 20;
      m_useSessionFilter = true; m_maxSameGroup = 1; m_tf = PERIOD_H1;
      m_usePyramid = true; m_maxPyramidLegs = 3;
      m_pyramidMinR = 1.0; m_pyramidAddR = 0.8; m_pyramidRiskPct = 0.30;
      m_pyramidNeedADX = true; m_pyramidADXMin = 22; m_adxPeriod = 14;
      m_useMartingale = false; m_martingaleMult = 2.0; m_martingaleMaxSteps = 4;
      m_flipOnSignal = true;
      m_trackCount = 0;
      m_lastSkipReason = "init";
      m_entriesOpened = 0;
   }

   void BindRisk(CRiskManager *risk) { m_risk = risk; }

   void Configure(long magicBase, int slippage, double minConfidence,
                  bool useFixedTP, bool useTrailing, double trailAtrMult,
                  double breakevenR, double trailStartR,
                  double partialR, double partialPct, double progressiveLock,
                  int maxPerSymbol, bool oneDirectionPerSymbol,
                  int cooldownBars, bool useSession,
                  int sessionStart, int sessionEnd, int maxSameGroup,
                  ENUM_TIMEFRAMES tf,
                  bool usePyramid, int maxPyramidLegs,
                  double pyramidMinR, double pyramidAddR, double pyramidRiskPct,
                  bool pyramidNeedADX, double pyramidADXMin, int adxPeriod,
                         bool allowHedging, int maxPerDirection,
                         bool useMartingale, double martingaleMult, int martingaleMaxSteps,
                         bool flipOnSignal)
   {
      m_magicBase = magicBase; m_slippage = slippage;
      m_minConfidence = minConfidence;
      m_useFixedTP = useFixedTP; m_useTrailing = useTrailing;
      m_trailAtrMult = trailAtrMult; m_breakevenR = breakevenR;
      m_trailStartR = trailStartR; m_partialR = partialR;
      m_partialPct = MathMax(0.0, MathMin(0.8, partialPct));
      m_progressiveLock = MathMax(0.0, MathMin(0.95, progressiveLock));
      m_maxPerSymbol = MathMax(1, maxPerSymbol);
      m_oneDirectionPerSymbol = oneDirectionPerSymbol;
      m_allowHedging = allowHedging;
      m_maxPerDirection = MathMax(1, maxPerDirection);
      m_cooldownBars = cooldownBars; m_useSessionFilter = useSession;
      m_sessionStartHour = sessionStart; m_sessionEndHour = sessionEnd;
      m_maxSameGroup = MathMax(1, maxSameGroup); m_tf = tf;
      m_usePyramid = usePyramid;
      m_maxPyramidLegs = MathMax(1, maxPyramidLegs);
      m_pyramidMinR = pyramidMinR; m_pyramidAddR = pyramidAddR;
      m_pyramidRiskPct = pyramidRiskPct;
      m_pyramidNeedADX = pyramidNeedADX; m_pyramidADXMin = pyramidADXMin;
      m_adxPeriod = adxPeriod;
      m_useMartingale = useMartingale;
      m_martingaleMult = MathMax(1.0, martingaleMult);
      m_martingaleMaxSteps = MathMax(0, martingaleMaxSteps);
      m_flipOnSignal = flipOnSignal;
      m_trade.SetExpertMagicNumber(magicBase);
      m_trade.SetDeviationInPoints(slippage);
   }

   bool AddSymbol(const string symbol, double weight, const string corrGroup,
                  int fastMA, int slowMA, int rsiPeriod,
                  double rsiPullLow, double rsiPullHigh,
                  int atrPeriod, double atrSlMin, double atrSlMax, double rewardR,
                  int donchian, int adxPeriod, double adxTrendMin, double adxBOMin,
                  ENUM_TIMEFRAMES tf, ENUM_TIMEFRAMES htf, bool useHtf,
                  bool allowBO, double maxSpreadAtr, double minBodyAtr,
                  bool allowLong, bool allowShort,
                  bool activeMode, bool slPullback, bool slMeanRev, bool slEmaCross,
                  bool slSessionBO, bool slInsideBar, bool slMomentum, bool slMAP,
                  int bbPeriod, double bbDev, double rsiOB, double rsiOS,
                  int sessionBOStart, int sessionBOEnd,
                  double emaCrossAdxMin, double meanRevAdxMax)
   {
      if(m_count >= MAX_SYMBOLS) return false;
      string sym = symbol;
      StringTrimLeft(sym); StringTrimRight(sym);
      if(StringLen(sym) == 0) return false;
      if(!SymbolSelect(sym, true))
      {
         Print("Portfolio: cannot select ", sym);
         return false;
      }

      int idx = m_count;
      m_slots[idx].symbol = sym;
      m_slots[idx].weight = MathMax(0.1, weight);
      m_slots[idx].magicOffset = m_count;
      m_slots[idx].group = corrGroup;
      m_slots[idx].cooldownUntil = 0;
      m_slots[idx].lossStreak = 0;
      m_slots[idx].lastPyramidPrice = 0;
      m_slots[idx].ready = false;

      m_slots[idx].engine.Configure(fastMA, slowMA, rsiPeriod,
                                    rsiPullLow, rsiPullHigh,
                                    atrPeriod, atrSlMin, atrSlMax, rewardR,
                                    donchian, adxPeriod, adxTrendMin, adxBOMin,
                                    tf, htf, useHtf, allowBO, maxSpreadAtr, minBodyAtr,
                                    allowLong, allowShort);
      m_slots[idx].engine.ConfigureSleeves(activeMode, slPullback, slMeanRev, slEmaCross,
                                           slSessionBO, slInsideBar, slMomentum, slMAP,
                                           bbPeriod, bbDev, rsiOB, rsiOS,
                                           sessionBOStart, sessionBOEnd,
                                           emaCrossAdxMin, meanRevAdxMax);
      m_slots[idx].ready = m_slots[idx].engine.InitHandles(sym);
      if(!m_slots[idx].ready)
      {
         Print("Portfolio: indicator init failed for ", sym);
         return false;
      }
      m_count++;
      return true;
   }

   int SymbolCount() const { return m_count; }
   long MagicFor(int slot) const { return m_magicBase + m_slots[slot].magicOffset; }

   bool IsOurMagic(const long mag) const
   {
      return (mag >= m_magicBase && mag < m_magicBase + MAX_SYMBOLS);
   }

   int CountOurPositions()
   {
      int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!m_pos.SelectByIndex(i)) continue;
         if(IsOurMagic(m_pos.Magic())) n++;
      }
      return n;
   }

   double PortfolioHeatPct()
   {
      if(m_risk == NULL) return 0;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0) return 0;
      double heatMoney = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!m_pos.SelectByIndex(i)) continue;
         if(!IsOurMagic(m_pos.Magic())) continue;
         string sym = m_pos.Symbol();
         double open = m_pos.PriceOpen();
         double sl = m_pos.StopLoss();
         double vol = m_pos.Volume();
         if(sl <= 0) { heatMoney += equity * 0.01; continue; }
         double dist = MathAbs(open - sl);
         double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
         double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
         if(tickSize <= 0 || tickValue <= 0) continue;
         heatMoney += (dist / tickSize) * tickValue * vol;
      }
      return heatMoney / equity * 100.0;
   }

   int CountGroupExposure(const string group, ENUM_SIGNAL_DIR dir)
   {
      if(group == "" || group == "NONE") return 0;
      int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!m_pos.SelectByIndex(i)) continue;
         if(!IsOurMagic(m_pos.Magic())) continue;
         int slot = (int)(m_pos.Magic() - m_magicBase);
         if(slot < 0 || slot >= m_count) continue;
         if(m_slots[slot].group != group) continue;
         if(dir == SIGNAL_BUY && m_pos.PositionType() == POSITION_TYPE_BUY) n++;
         if(dir == SIGNAL_SELL && m_pos.PositionType() == POSITION_TYPE_SELL) n++;
      }
      return n;
   }

   void SetCooldown(int slot)
   {
      if(slot < 0 || slot >= m_count) return;
      int sec = PeriodSeconds(m_tf) * MathMax(1, m_cooldownBars);
      m_slots[slot].cooldownUntil = TimeCurrent() + sec;
   }

   void SetCooldownBySymbol(const string symbol)
   {
      for(int i = 0; i < m_count; i++)
         if(m_slots[i].symbol == symbol) { SetCooldown(i); return; }
   }

   void RegisterLossBySymbol(const string symbol)
   {
      for(int i = 0; i < m_count; i++)
      {
         if(m_slots[i].symbol != symbol) continue;
         if(m_useMartingale)
         {
            m_slots[i].lossStreak = MathMin(m_slots[i].lossStreak + 1, m_martingaleMaxSteps + 2);
            PrintFormat("Martingale %s streak=%d mult=%.2f",
                        symbol, m_slots[i].lossStreak, MartingaleVolumeMult(i));
         }
         SetCooldown(i);
         return;
      }
   }

   void RegisterWinBySymbol(const string symbol)
   {
      for(int i = 0; i < m_count; i++)
      {
         if(m_slots[i].symbol != symbol) continue;
         if(m_useMartingale && m_slots[i].lossStreak > 0)
         {
            PrintFormat("Martingale %s reset (was streak=%d)", symbol, m_slots[i].lossStreak);
            m_slots[i].lossStreak = 0;
         }
         return;
      }
   }

   int LossStreakForSymbol(const string symbol) const
   {
      for(int i = 0; i < m_count; i++)
         if(m_slots[i].symbol == symbol) return m_slots[i].lossStreak;
      return 0;
   }

   void ManageOpenPositions()
   {
      TrackCleanup();

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!m_pos.SelectByIndex(i)) continue;
         if(!IsOurMagic(m_pos.Magic())) continue;

         string sym = m_pos.Symbol();
         ulong ticket = m_pos.Ticket();
         double open = m_pos.PriceOpen();
         double sl = m_pos.StopLoss();
         double tp = m_pos.TakeProfit();
         double vol = m_pos.Volume();
         int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         double bid = SymbolInfoDouble(sym, SYMBOL_BID);
         double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
         double point = SymbolInfoDouble(sym, SYMBOL_POINT);

         int ti = FindTrack(ticket);
         double riskDist = 0;
         if(ti >= 0) riskDist = m_track[ti].riskDist;
         if(riskDist <= 0 && sl > 0) riskDist = MathAbs(open - sl);
         if(riskDist <= 0) continue;

         double atrv = GetAtr(sym);
         bool isBuy = (m_pos.PositionType() == POSITION_TYPE_BUY);
         double profit = isBuy ? (bid - open) : (open - ask);
         double rMult = profit / riskDist;

         if(!m_useFixedTP && tp > 0)
            m_trade.PositionModify(ticket, sl, 0);

         if(m_partialPct > 0 && m_partialR > 0 && rMult >= m_partialR)
         {
            bool done = (ti >= 0 && m_track[ti].partialDone);
            if(!done)
            {
               double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
               double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
               double closeVol = MathFloor((vol * m_partialPct) / step) * step;
               if(closeVol >= minLot && (vol - closeVol) >= minLot - 1e-8)
               {
                  if(m_trade.PositionClosePartial(ticket, closeVol))
                  {
                     if(ti >= 0) m_track[ti].partialDone = true;
                     PrintFormat("PARTIAL %.2f lots @ %.2fR %s", closeVol, rMult, sym);
                     if(!m_pos.SelectByTicket(ticket)) continue;
                     sl = m_pos.StopLoss();
                     tp = m_pos.TakeProfit();
                     vol = m_pos.Volume();
                  }
               }
               else if(ti >= 0)
                  m_track[ti].partialDone = true;
            }
         }

         if(!m_useTrailing) continue;

         if(rMult >= m_breakevenR)
         {
            if(isBuy)
            {
               double be = NormalizeDouble(open + 15 * point, digits);
               if(sl < be && be < bid)
                  m_trade.PositionModify(ticket, be, m_useFixedTP ? tp : 0);
            }
            else
            {
               double be = NormalizeDouble(open - 15 * point, digits);
               if((sl == 0 || sl > be) && be > ask)
                  m_trade.PositionModify(ticket, be, m_useFixedTP ? tp : 0);
            }
            if(!m_pos.SelectByTicket(ticket)) continue;
            sl = m_pos.StopLoss();
         }

         if(rMult >= m_trailStartR && atrv > 0)
         {
            double lockR = m_progressiveLock * rMult;
            if(isBuy)
            {
               double newSL = NormalizeDouble(bid - m_trailAtrMult * atrv, digits);
               double lock = NormalizeDouble(open + lockR * riskDist, digits);
               if(newSL < lock) newSL = lock;
               if(newSL > sl && newSL < bid)
                  m_trade.PositionModify(ticket, newSL, m_useFixedTP ? tp : 0);
            }
            else
            {
               double newSL = NormalizeDouble(ask + m_trailAtrMult * atrv, digits);
               double lock = NormalizeDouble(open - lockR * riskDist, digits);
               if(newSL > lock) newSL = lock;
               if((sl == 0 || newSL < sl) && newSL > ask)
                  m_trade.PositionModify(ticket, newSL, m_useFixedTP ? tp : 0);
            }
         }
      }
   }

   double ScaledRiskPct(int slot, double confidence)
   {
      if(m_risk == NULL) return 0;
      double base = m_risk.MaxRiskPerTradePct();
      double wSum = 0;
      for(int i = 0; i < m_count; i++) wSum += m_slots[i].weight;
      double wNorm = (wSum > 0 ? m_slots[slot].weight / wSum : 1.0 / MathMax(1, m_count));
      double confScale = 0.80 + MathMax(0.0, confidence - 0.6) * 0.7;
      double risk = base * (0.6 + 0.8 * wNorm) * confScale;

      double heat = PortfolioHeatPct();
      double remaining = m_risk.MaxPortfolioHeatPct() - heat;
      if(remaining < risk) risk = MathMax(0.0, remaining * 0.75);

      double dd = m_risk.CurrentDrawdownPct();
      if(dd > 2.0) risk *= MathMax(0.35, 1.0 - (dd - 2.0) / 12.0);
      if(m_risk.DailyPnLPct() < -0.4) risk *= 0.55;
      return risk;
   }

   bool HasOppositePosition(const string sym, const ENUM_SIGNAL_DIR dir) const
   {
      bool wantBuy = (dir == SIGNAL_BUY);
      CPositionInfo pos;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!pos.SelectByIndex(i)) continue;
         if(!IsOurMagic(pos.Magic())) continue;
         if(pos.Symbol() != sym) continue;
         bool isBuy = (pos.PositionType() == POSITION_TYPE_BUY);
         if(isBuy != wantBuy) return true;
      }
      return false;
   }

   void CloseAllOurOnSymbol(const string sym)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!m_pos.SelectByIndex(i)) continue;
         if(!IsOurMagic(m_pos.Magic())) continue;
         if(m_pos.Symbol() != sym) continue;
         m_trade.PositionClose(m_pos.Ticket());
      }
   }

   bool PrepareForEntry(const int slot, const string sym, const ENUM_SIGNAL_DIR dir,
                        string &failReason)
   {
      failReason = "";
      if(CanOpenDirection(sym, dir))
         return true;

      if(m_flipOnSignal && HasOppositePosition(sym, dir))
      {
         CloseAllOurOnSymbol(sym);
         if(CanOpenDirection(sym, dir))
            return true;
      }

      if(CountSymbolPositions(sym) > 0)
         failReason = "position open (enable FlipOnSignal)";
      else
         failReason = "direction blocked";
      return false;
   }

   bool TryExecuteSignal(const int slot, const string sym, const STradeSignal &sig,
                         string &failReason)
   {
      failReason = "";
      if(sig.direction == SIGNAL_NONE) { failReason = "empty signal"; return false; }
      if(sig.confidence < m_minConfidence)
      {
         failReason = StringFormat("conf %.2f<%.2f", sig.confidence, m_minConfidence);
         return false;
      }

      if(m_slots[slot].group != "" && m_slots[slot].group != "NONE")
      {
         if(CountGroupExposure(m_slots[slot].group, sig.direction) >= m_maxSameGroup)
         { failReason = "group cap"; return false; }
      }

      if(!PrepareForEntry(slot, sym, sig.direction, failReason))
         return false;

      int openAll = CountOurPositions();
      double heat = PortfolioHeatPct();
      if(m_risk != NULL)
      {
         string block = m_risk.EntryBlockReason(openAll, heat);
         if(block != "") { failReason = block; return false; }
      }
      if(CountSymbolPositions(sym) >= m_maxPerSymbol)
      { failReason = "max symbol pos"; return false; }

      double riskPct = ScaledRiskPct(slot, sig.confidence);
      if(riskPct < 0.05) { failReason = "risk scaled to 0"; return false; }

      double slDist = MathAbs(sig.entryPrice - sig.stopLoss);
      double volMult = MartingaleVolumeMult(slot);
      double lots = m_risk.CalculateLotSize(sym, slDist, riskPct, volMult);
      if(lots <= 0) { failReason = "lots=0 (balance/sl)"; return false; }

      double tp = m_useFixedTP ? sig.takeProfit : 0;

      m_trade.SetExpertMagicNumber(MagicFor(slot));
      m_trade.SetDeviationInPoints(m_slippage);
      m_trade.SetTypeFilling(FillingFor(sym));

      string cmt = StringFormat("%s|c%.2f|MGx%.1f", sig.comment, sig.confidence, volMult);
      if(m_useMartingale && volMult > 1.0)
         cmt = StringFormat("%s|streak%d", cmt, m_slots[slot].lossStreak);

      bool ok = false;
      if(sig.direction == SIGNAL_BUY)
         ok = m_trade.Buy(lots, sym, 0, sig.stopLoss, tp, cmt);
      else
         ok = m_trade.Sell(lots, sym, 0, sig.stopLoss, tp, cmt);

      if(ok)
      {
         m_entriesOpened++;
         m_slots[slot].lastPyramidPrice = 0;
         ulong newTicket = 0;
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            if(!m_pos.SelectByIndex(i)) continue;
            if(m_pos.Symbol() == sym && m_pos.Magic() == MagicFor(slot))
            {
               if(m_pos.Ticket() > newTicket)
                  newTicket = m_pos.Ticket();
            }
         }
         if(newTicket > 0 && m_pos.SelectByTicket(newTicket))
            TrackAdd(newTicket, slDist, m_pos.PriceOpen(),
                     (int)m_pos.PositionType(), false);
         PrintFormat("OPEN %s %s lots=%.2f risk%%=%.2f MG=%.2fx conf=%.2f SL=%.5f TP=%.5f",
                     sig.comment, sym, lots, riskPct, volMult, sig.confidence,
                     sig.stopLoss, tp);
         return true;
      }

      failReason = StringFormat("broker %d", m_trade.ResultRetcode());
      PrintFormat("FAIL %s %s %d %s", sig.comment, sym,
                  m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
      return false;
   }

   void ProcessSlot(int slot, datetime &lastBarTime[])
   {
      if(slot < 0 || slot >= m_count || !m_slots[slot].ready) return;

      string sym = m_slots[slot].symbol;
      datetime barTime = iTime(sym, m_tf, 0);
      if(barTime == 0) return;
      bool newBar = (lastBarTime[slot] != barTime);
      if(newBar) lastBarTime[slot] = barTime;

      if(m_usePyramid && newBar && m_risk != NULL && !m_risk.IsHardHalted())
         TryPyramid(slot);

      if(!newBar) return;

      if(m_risk != NULL && m_risk.IsHardHalted())
      {
         m_lastSkipReason = m_risk.HaltReason();
         return;
      }
      if(!InSession())
      {
         m_lastSkipReason = "session OUT";
         return;
      }
      if(TimeCurrent() < m_slots[slot].cooldownUntil)
      {
         m_lastSkipReason = "cooldown";
         return;
      }

      STradeSignal primary, secondary;
      bool hasSecondary = false;
      if(!m_slots[slot].engine.GenerateSignals(sym, primary, secondary, hasSecondary))
      {
         m_lastSkipReason = m_slots[slot].engine.LastRejectReason();
         return;
      }

      string failReason = "";
      bool opened = false;
      if(TryExecuteSignal(slot, sym, primary, failReason))
         opened = true;
      else if(failReason != "")
         m_lastSkipReason = StringFormat("exec: %s", failReason);

      if(m_allowHedging && hasSecondary)
      {
         string fail2 = "";
         if(TryExecuteSignal(slot, sym, secondary, fail2))
            opened = true;
         else if(!opened && fail2 != "")
            m_lastSkipReason = StringFormat("exec2: %s", fail2);
      }

      if(opened && m_risk != NULL)
      {
         m_risk.RegisterNewTrade();
         m_lastSkipReason = StringFormat("opened %s", primary.comment);
      }
      else if(!opened && m_lastSkipReason == "")
         m_lastSkipReason = "signal ok, exec failed";
   }

   void OnTick(datetime &lastBarTime[])
   {
      if(m_risk != NULL) m_risk.OnTickUpdate();
      ManageOpenPositions();
      if(m_risk != NULL && m_risk.IsHardHalted()) return;
      for(int s = 0; s < m_count; s++)
         ProcessSlot(s, lastBarTime);
   }

   void Deinit()
   {
      for(int i = 0; i < m_count; i++) m_slots[i].engine.Release();
      m_count = 0;
      m_trackCount = 0;
   }

   string StatusLine()
   {
      string halt = "OK";
      if(m_risk != NULL)
      {
         if(m_risk.IsHardHalted()) halt = m_risk.HaltReason();
         else if(m_risk.IsHalted()) halt = "SOFT: " + m_risk.HaltReason();
      }
      double dd = (m_risk != NULL) ? m_risk.CurrentDrawdownPct() : 0;
      double day = (m_risk != NULL) ? m_risk.DailyPnLPct() : 0;
      int td = (m_risk != NULL) ? m_risk.TradesToday() : 0;
      int maxTd = (m_risk != NULL) ? m_risk.MaxTradesPerDay() : 0;
      int buys = 0, sells = 0;
      int barsEv = 0, setups = 0;
      string sigHint = "";
      if(m_count > 0)
      {
         string sym = m_slots[0].symbol;
         buys = CountSymbolDir(sym, true);
         sells = CountSymbolDir(sym, false);
         barsEv = m_slots[0].engine.BarsEvaluated();
         setups = m_slots[0].engine.SetupsFound();
         sigHint = m_slots[0].engine.LastRejectReason();
      }
      int mg = (m_count > 0 ? m_slots[0].lossStreak : 0);
      string hedge = m_allowHedging ? StringFormat(" B%d/S%d", buys, sells) : "";
      string mgStr = m_useMartingale ? StringFormat(" MG=%d", mg) : "";
      return StringFormat("Pos=%d Heat=%.1f%% DD=%.1f%% Day=%.1f%% Ent=%d/%d%s%s\nSig bars=%d setups=%d | Last: %s\nSkip: %s | %s",
                          CountOurPositions(), PortfolioHeatPct(), dd, day, td, maxTd,
                          hedge, mgStr, barsEv, setups, sigHint, m_lastSkipReason, halt);
   }

   string DiagnosticLine() const { return m_lastSkipReason; }
   int TotalEntriesOpened() const { return m_entriesOpened; }
};

#endif
//+------------------------------------------------------------------+
