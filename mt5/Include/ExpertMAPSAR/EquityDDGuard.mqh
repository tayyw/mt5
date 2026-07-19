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

   // Recover-close: after a soft-pause trip, flatten once RecoverPct of the
   // peak→trough loss has been clawed back (does not replace CloseAll).
   bool   m_recover_armed;
   double m_recover_peak;
   double m_recover_trough;

public:
                     CEquityDDGuard(void) : m_peak_equity(0.0),
                                            m_max_dd_pct(0.0),
                                            m_soft_paused(false),
                                            m_recover_armed(false),
                                            m_recover_peak(0.0),
                                            m_recover_trough(0.0) {}

   void              Init(const double maxDdPercent)
     {
      m_max_dd_pct  =MathMax(0.0,maxDdPercent);
      m_peak_equity =AccountInfoDouble(ACCOUNT_EQUITY);
      m_soft_paused =false;
      ClearRecover();
     }

   bool              Enabled(void) const { return(m_max_dd_pct>0.0); }
   bool              SoftPaused(void) const { return(m_soft_paused); }
   void              SoftPaused(const bool value) { m_soft_paused=value; }
   double            PeakEquity(void) const { return(m_peak_equity); }
   double            MaxDDPercent(void) const { return(m_max_dd_pct); }
   bool              RecoverArmed(void) const { return(m_recover_armed); }
   double            RecoverPeak(void) const { return(m_recover_peak); }
   double            RecoverTrough(void) const { return(m_recover_trough); }

   void              ClearRecover(void)
     {
      m_recover_armed  =false;
      m_recover_peak   =0.0;
      m_recover_trough =0.0;
     }

   void              ResetPeakToEquity(void)
     {
      m_peak_equity=AccountInfoDouble(ACCOUNT_EQUITY);
      m_soft_paused=false;
      ClearRecover();
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

   // Arm once at soft-pause trip. Freezes the peak used for recovery math.
   void              ArmRecover(void)
     {
      if(m_recover_armed)
         return;

      const double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      m_recover_peak  =(m_peak_equity>0.0 ? m_peak_equity : eq);
      m_recover_trough=eq;
      m_recover_armed =true;
     }

   void              UpdateRecoverTrough(void)
     {
      if(!m_recover_armed)
         return;

      const double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq<m_recover_trough)
         m_recover_trough=eq;
     }

   // True once equity has recovered recoverPct% of (peak - trough) from trough.
   // e.g. peak=10000, trough=8000, recoverPct=80 → target equity=9600.
   bool              Recovered(const double recoverPct) const
     {
      if(!m_recover_armed || m_recover_peak<=0.0)
         return(false);

      const double loss=m_recover_peak-m_recover_trough;
      if(loss<=0.0)
         return(true);

      const double pct=MathMax(0.0,MathMin(100.0,recoverPct));
      const double target=m_recover_trough+loss*(pct/100.0);
      return(AccountInfoDouble(ACCOUNT_EQUITY)>=target);
     }

   double            RecoverTarget(const double recoverPct) const
     {
      if(!m_recover_armed)
         return(0.0);

      const double loss=m_recover_peak-m_recover_trough;
      if(loss<=0.0)
         return(m_recover_peak);

      const double pct=MathMax(0.0,MathMin(100.0,recoverPct));
      return(m_recover_trough+loss*(pct/100.0));
     }
  };

#endif
