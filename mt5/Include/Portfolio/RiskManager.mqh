//+------------------------------------------------------------------+
//| RiskManager.mqh  v3                                               |
//| Equity protection, heat, daily caps, lot sizing, martingale cap   |
//+------------------------------------------------------------------+
#property copyright "MT5 Portfolio EA"
#property strict

#ifndef RISK_MANAGER_MQH
#define RISK_MANAGER_MQH

class CRiskManager
{
private:
   double   m_peakEquity;
   double   m_maxDailyLossPct;
   double   m_maxDrawdownPct;
   double   m_maxRiskPerTradePct;
   double   m_maxPortfolioHeatPct;
   int      m_maxPositions;
   int      m_maxTradesPerDay;
   int      m_tradesToday;
   datetime m_dayStart;
   double   m_dayStartEquity;
   bool     m_tradingHalted;
   bool     m_hardHalt;
   string   m_haltReason;

public:
   CRiskManager()
   {
      m_peakEquity          = 0;
      m_maxDailyLossPct     = 2.0;
      m_maxDrawdownPct      = 10.0;
      m_maxRiskPerTradePct  = 0.5;
      m_maxPortfolioHeatPct = 4.0;
      m_maxPositions        = 4;
      m_maxTradesPerDay     = 3;
      m_tradesToday         = 0;
      m_dayStart            = 0;
      m_dayStartEquity      = 0;
      m_tradingHalted       = false;
      m_hardHalt            = false;
      m_haltReason          = "";
   }

   void Init(double maxDailyLossPct, double maxDrawdownPct,
             double maxRiskPerTradePct, double maxPortfolioHeatPct,
             int maxPositions, int maxTradesPerDay)
   {
      m_maxDailyLossPct     = maxDailyLossPct;
      m_maxDrawdownPct      = maxDrawdownPct;
      m_maxRiskPerTradePct  = maxRiskPerTradePct;
      m_maxPortfolioHeatPct = maxPortfolioHeatPct;
      m_maxPositions        = maxPositions;
      m_maxTradesPerDay     = MathMax(1, maxTradesPerDay);

      m_peakEquity     = AccountInfoDouble(ACCOUNT_EQUITY);
      m_dayStartEquity = m_peakEquity;
      m_dayStart       = DayKey();
      m_tradesToday    = 0;
      m_tradingHalted  = false;
      m_hardHalt       = false;
      m_haltReason     = "";
   }

   datetime DayKey() const
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      return StructToTime(dt);
   }

   void OnTickUpdate()
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity > m_peakEquity)
         m_peakEquity = equity;

      datetime today = DayKey();
      if(today != m_dayStart)
      {
         m_dayStart       = today;
         m_dayStartEquity = equity;
         m_tradesToday    = 0;
         if(m_tradingHalted && !m_hardHalt)
         {
            m_tradingHalted = false;
            m_haltReason    = "";
         }
      }

      if(CurrentDrawdownPct() >= m_maxDrawdownPct)
      {
         m_tradingHalted = true;
         m_hardHalt      = true;
         m_haltReason    = StringFormat("HARD max DD %.2f%%", CurrentDrawdownPct());
      }

      double dayLossPct = 0.0;
      if(m_dayStartEquity > 0 && equity < m_dayStartEquity)
         dayLossPct = (m_dayStartEquity - equity) / m_dayStartEquity * 100.0;

      if(!m_hardHalt && dayLossPct >= m_maxDailyLossPct)
      {
         m_tradingHalted = true;
         m_haltReason    = StringFormat("Daily loss %.2f%%", dayLossPct);
      }
   }

   void RegisterNewTrade()
   {
      m_tradesToday++;
   }

   bool CanOpenNewTrade(int openPositions, double currentHeatPct) const
   {
      if(m_hardHalt)
         return false;
      if(m_tradingHalted)
         return false;
      if(openPositions >= m_maxPositions)
         return false;
      if(currentHeatPct >= m_maxPortfolioHeatPct)
         return false;
      if(m_tradesToday >= m_maxTradesPerDay)
         return false;
      return true;
   }

   string EntryBlockReason(int openPositions, double currentHeatPct) const
   {
      if(m_hardHalt) return m_haltReason;
      if(m_tradingHalted) return m_haltReason;
      if(openPositions >= m_maxPositions)
         return StringFormat("Max positions %d", m_maxPositions);
      if(currentHeatPct >= m_maxPortfolioHeatPct)
         return StringFormat("Max heat %.1f%%", currentHeatPct);
      if(m_tradesToday >= m_maxTradesPerDay)
         return StringFormat("Max entries/day %d/%d", m_tradesToday, m_maxTradesPerDay);
      return "";
   }

   int MaxTradesPerDay() const { return m_maxTradesPerDay; }
   bool IsHardHalted() const { return m_hardHalt; }

   double MaxRiskPerTradePct() const { return m_maxRiskPerTradePct; }
   double MaxPortfolioHeatPct() const { return m_maxPortfolioHeatPct; }
   int    MaxPositions() const { return m_maxPositions; }
   int    TradesToday() const { return m_tradesToday; }
   bool   IsHalted() const { return m_tradingHalted || m_hardHalt; }
   string HaltReason() const { return m_haltReason; }

   double CurrentDrawdownPct() const
   {
      if(m_peakEquity <= 0)
         return 0;
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      return (m_peakEquity - eq) / m_peakEquity * 100.0;
   }

   double DailyPnLPct() const
   {
      if(m_dayStartEquity <= 0)
         return 0;
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      return (eq - m_dayStartEquity) / m_dayStartEquity * 100.0;
   }

   double CalculateLotSize(const string symbol, double stopDistancePrice,
                           double riskPctOverride = 0.0,
                           double volumeMultiplier = 1.0) const
   {
      if(stopDistancePrice <= 0)
         return 0;

      double riskPct = (riskPctOverride > 0 ? riskPctOverride : m_maxRiskPerTradePct);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskMoney = equity * riskPct / 100.0 * MathMax(1.0, volumeMultiplier);

      double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double lotStep   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double minLot    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      int    volDigits = 2;
      if(lotStep > 0)
      {
         volDigits = 0;
         double s = lotStep;
         while(volDigits < 8 && MathAbs(s - MathRound(s)) > 1e-8)
         {
            s *= 10.0;
            volDigits++;
         }
      }

      if(tickSize <= 0 || tickValue <= 0 || lotStep <= 0)
         return 0;

      double moneyPerLot = (stopDistancePrice / tickSize) * tickValue;
      if(moneyPerLot <= 0)
         return 0;

      double lots = riskMoney / moneyPerLot;
      lots = MathFloor(lots / lotStep) * lotStep;
      if(lots < minLot)
         return 0;
      lots = MathMin(maxLot, lots);

      double actualRisk = lots * moneyPerLot;
      if(actualRisk > riskMoney * 1.5)
      {
         lots = MathFloor((riskMoney / moneyPerLot) / lotStep) * lotStep;
         if(lots < minLot)
            return 0;
      }
      return NormalizeDouble(lots, volDigits);
   }
};

#endif
//+------------------------------------------------------------------+
