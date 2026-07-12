//+------------------------------------------------------------------+
//| ATRSpikeGuard.mqh — block entries/stack when ATR spikes         |
//+------------------------------------------------------------------+
#ifndef ATR_SPIKE_GUARD_MQH
#define ATR_SPIKE_GUARD_MQH

class CATRSpikeGuard
  {
private:
   bool               m_enabled;
   string             m_symbol;
   ENUM_TIMEFRAMES    m_period;
   int                m_atr_period;
   double             m_spike_mult;
   int                m_h_atr;
   bool               m_spike_active;

   bool              Refresh(void)
     {
      m_spike_active=false;

      if(!m_enabled || m_h_atr==INVALID_HANDLE)
         return(true);

      double atr[];
      ArraySetAsSeries(atr,true);

      const int need=MathMax(m_atr_period+1,22);
      if(CopyBuffer(m_h_atr,0,0,need,atr)<need)
        {
         // Not enough history yet (common at tester start) — allow trading until warmed up
         m_spike_active=false;
         return(true);
        }

      const double atrv=atr[1];
      if(atrv<=0.0)
         return(true);

      double atrSum=0.0;
      for(int i=1; i<=20; i++)
         atrSum+=atr[i];

      const double atrAvg=atrSum/20.0;
      if(atrAvg<=0.0)
         return(true);

      if(atrv>atrAvg*m_spike_mult)
         m_spike_active=true;

      return(true);
     }

public:
                     CATRSpikeGuard(void) : m_enabled(false),
                                            m_symbol(""),
                                            m_period(PERIOD_CURRENT),
                                            m_atr_period(14),
                                            m_spike_mult(1.85),
                                            m_h_atr(INVALID_HANDLE),
                                            m_spike_active(false) {}

                    ~CATRSpikeGuard(void)
     {
      if(m_h_atr!=INVALID_HANDLE)
        {
         IndicatorRelease(m_h_atr);
         m_h_atr=INVALID_HANDLE;
        }
     }

   bool              Init(const string symbol,const ENUM_TIMEFRAMES period,
                          const bool enabled,const int atrPeriod,const double spikeMult)
     {
      if(m_h_atr!=INVALID_HANDLE)
        {
         IndicatorRelease(m_h_atr);
         m_h_atr=INVALID_HANDLE;
        }

      m_symbol      =symbol;
      m_period      =period;
      m_enabled     =enabled;
      m_atr_period  =MathMax(2,atrPeriod);
      m_spike_mult  =MathMax(1.0,spikeMult);
      m_spike_active=false;

      if(!m_enabled)
         return(true);

      m_h_atr=iATR(m_symbol,m_period,m_atr_period);
      if(m_h_atr==INVALID_HANDLE)
        {
         Print("ATRSpikeGuard: iATR failed for ",m_symbol);
         return(false);
        }

      Refresh();
      return(true);
     }

   bool              Update(void)
     {
      if(!m_enabled)
         return(true);
      return(Refresh());
     }

   bool              IsSpikeActive(void) const
     {
      return(m_enabled && m_spike_active);
     }
  };

#endif
