//+------------------------------------------------------------------+
//| ShockGuard.mqh — ATR/spread spike detection + entry cooldown      |
//+------------------------------------------------------------------+
#ifndef SHOCK_GUARD_MQH
#define SHOCK_GUARD_MQH

class CShockGuard
  {
private:
   bool               m_enabled;
   string             m_symbol;
   ENUM_TIMEFRAMES    m_period;
   int                m_atr_period;
   double             m_atr_spike_mult;
   double             m_spread_atr_mult;
   int                m_cooldown_bars;
   int                m_h_atr;
   bool               m_spike_active;
   int                m_cooldown_bars_left;
   datetime           m_last_bar_time;

   bool              RefreshSpikeState(void)
     {
      m_spike_active=false;

      if(!m_enabled || m_h_atr==INVALID_HANDLE)
         return(true);

      double atr[];
      ArraySetAsSeries(atr,true);

      const int need=MathMax(m_atr_period+1,22);
      if(CopyBuffer(m_h_atr,0,0,need,atr)<need)
         return(false);

      const double atrv=atr[1];
      if(atrv<=0.0)
         return(true);

      double atrSum=0.0;
      for(int i=1; i<=20; i++)
         atrSum+=atr[i];

      const double atrAvg=atrSum/20.0;
      if(atrAvg<=0.0)
         return(true);

      if(atrv>atrAvg*m_atr_spike_mult)
         m_spike_active=true;

      if(!m_spike_active && m_spread_atr_mult>0.0)
        {
         const double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
         const double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
         const double spread=ask-bid;
         if(spread>0.0 && spread>m_spread_atr_mult*atrv)
            m_spike_active=true;
        }

      return(true);
     }

   void              OnNewBar(void)
     {
      if(m_cooldown_bars_left>0)
         m_cooldown_bars_left--;
     }

public:
                     CShockGuard(void) : m_enabled(false),
                                         m_symbol(""),
                                         m_period(PERIOD_CURRENT),
                                         m_atr_period(14),
                                         m_atr_spike_mult(1.85),
                                         m_spread_atr_mult(0.15),
                                         m_cooldown_bars(60),
                                         m_h_atr(INVALID_HANDLE),
                                         m_spike_active(false),
                                         m_cooldown_bars_left(0),
                                         m_last_bar_time(0) {}

                    ~CShockGuard(void)
     {
      if(m_h_atr!=INVALID_HANDLE)
        {
         IndicatorRelease(m_h_atr);
         m_h_atr=INVALID_HANDLE;
        }
     }

   bool              Init(const string symbol,const ENUM_TIMEFRAMES period,
                          const bool enabled,const int atrPeriod,
                          const double atrSpikeMult,const double spreadAtrMult,
                          const int cooldownBars)
     {
      if(m_h_atr!=INVALID_HANDLE)
        {
         IndicatorRelease(m_h_atr);
         m_h_atr=INVALID_HANDLE;
        }

      m_symbol           =symbol;
      m_period           =period;
      m_enabled          =enabled;
      m_atr_period       =MathMax(2,atrPeriod);
      m_atr_spike_mult   =MathMax(1.0,atrSpikeMult);
      m_spread_atr_mult  =MathMax(0.0,spreadAtrMult);
      m_cooldown_bars    =MathMax(0,cooldownBars);
      m_spike_active     =false;
      m_cooldown_bars_left=0;
      m_last_bar_time    =0;

      if(!m_enabled)
         return(true);

      m_h_atr=iATR(m_symbol,m_period,m_atr_period);
      if(m_h_atr==INVALID_HANDLE)
        {
         Print("ShockGuard: iATR failed for ",m_symbol);
         return(false);
        }

      return(RefreshSpikeState());
     }

   bool              Update(void)
     {
      if(!m_enabled)
         return(true);

      const datetime barTime=iTime(m_symbol,m_period,0);
      if(barTime!=m_last_bar_time)
        {
         if(m_last_bar_time>0)
            OnNewBar();
         m_last_bar_time=barTime;
        }

      return(RefreshSpikeState());
     }

   bool              IsSpikeActive(void) const
     {
      return(m_enabled && m_spike_active);
     }

   bool              IsCooldownActive(void) const
     {
      return(m_enabled && m_cooldown_bars_left>0);
     }

   bool              IsTradingBlocked(void) const
     {
      return(IsSpikeActive() || IsCooldownActive());
     }

   void              ArmCooldown(void)
     {
      if(!m_enabled || m_cooldown_bars<=0)
         return;

      m_cooldown_bars_left=m_cooldown_bars;
      Print("ShockGuard: cooldown armed for ",m_cooldown_bars," bars");
     }

   int               CooldownBarsLeft(void) const { return(m_cooldown_bars_left); }
  };

#endif
