//+------------------------------------------------------------------+
//| EquityDDGuard.mqh — peak-equity drawdown circuit breaker          |
//+------------------------------------------------------------------+
#ifndef EQUITY_DD_GUARD_MQH
#define EQUITY_DD_GUARD_MQH

class CEquityDDGuard
  {
private:
   double m_peak_equity;
   double m_max_dd_pct;     // 0 = disabled
   bool   m_soft_paused;    // used when CloseAll=false (pause until DD recovers)

public:
                     CEquityDDGuard(void) : m_peak_equity(0.0),
                                            m_max_dd_pct(0.0),
                                            m_soft_paused(false) {}

   void              Init(const double maxDdPercent)
     {
      m_max_dd_pct  =MathMax(0.0,maxDdPercent);
      m_peak_equity =AccountInfoDouble(ACCOUNT_EQUITY);
      m_soft_paused =false;
     }

   bool              Enabled(void) const { return(m_max_dd_pct>0.0); }
   bool              SoftPaused(void) const { return(m_soft_paused); }
   void              SoftPaused(const bool value) { m_soft_paused=value; }
   double            PeakEquity(void) const { return(m_peak_equity); }
   double            MaxDDPercent(void) const { return(m_max_dd_pct); }

   void              ResetPeakToEquity(void)
     {
      m_peak_equity=AccountInfoDouble(ACCOUNT_EQUITY);
      m_soft_paused=false;
     }

   double            CurrentDDPercent(void) const
     {
      if(m_peak_equity<=0.0)
         return(0.0);
      const double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq>=m_peak_equity)
         return(0.0);
      return((m_peak_equity-eq)/m_peak_equity*100.0);
     }

   // Updates peak. Returns true while equity DD from peak is at/above the limit.
   bool              Breached(void)
     {
      if(!Enabled())
         return(false);

      const double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq>m_peak_equity)
         m_peak_equity=eq;

      return(CurrentDDPercent()>=m_max_dd_pct);
     }
  };

#endif
