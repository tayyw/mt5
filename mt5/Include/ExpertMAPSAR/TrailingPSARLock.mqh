//+------------------------------------------------------------------+
//| TrailingPSARLock.mqh — PSAR trail + swing/ATR profit lock        |
//| Picks the tighter of PSAR and recent-swing lock so fast runs     |
//| bank more while PSAR still handles trend-flip exits.             |
//+------------------------------------------------------------------+
#ifndef TRAILING_PSAR_LOCK_MQH
#define TRAILING_PSAR_LOCK_MQH

#include <Expert\ExpertTrailing.mqh>

class CTrailingPSARLock : public CExpertTrailing
  {
protected:
   CiSAR             m_sar;
   CiATR             m_atr;

   double            m_step;
   double            m_maximum;

   bool              m_lock_enable;
   int               m_swing_bars;
   int               m_atr_period;
   double            m_atr_mult;      // cushion beyond swing extreme
   double            m_lock_start_atr; // arm lock once floating profit >= this * ATR

   bool              ConsiderLong(const double cand,const double base,const double level,
                                  double &best) const
     {
      if(cand==EMPTY_VALUE || cand<=0.0)
         return(false);
      const double v=NormalizeDouble(cand,m_symbol.Digits());
      if(v>base && v<level)
        {
         if(best==EMPTY_VALUE || v>best)
            best=v;
         return(true);
        }
      return(false);
     }

   bool              ConsiderShort(const double cand,const double base,const double level,
                                   double &best) const
     {
      if(cand==EMPTY_VALUE || cand<=0.0)
         return(false);
      const double v=NormalizeDouble(cand,m_symbol.Digits());
      if(v<base && v>level)
        {
         if(best==EMPTY_VALUE || v<best)
            best=v;
         return(true);
        }
      return(false);
     }

   double            SwingLockLong(void) const
     {
      if(!m_lock_enable || m_high==NULL || m_low==NULL)
         return(EMPTY_VALUE);

      const double atr=m_atr.Main(1);
      if(atr<=0.0)
         return(EMPTY_VALUE);

      int idx=0;
      const double swing=m_low.MinValue(1,m_swing_bars,idx);
      if(swing==EMPTY_VALUE || swing<=0.0)
         return(EMPTY_VALUE);

      return(NormalizeDouble(swing-m_atr_mult*atr,m_symbol.Digits()));
     }

   double            SwingLockShort(void) const
     {
      if(!m_lock_enable || m_high==NULL || m_low==NULL)
         return(EMPTY_VALUE);

      const double atr=m_atr.Main(1);
      if(atr<=0.0)
         return(EMPTY_VALUE);

      int idx=0;
      const double swing=m_high.MaxValue(1,m_swing_bars,idx);
      if(swing==EMPTY_VALUE || swing<=0.0)
         return(EMPTY_VALUE);

      const double spread=m_symbol.Spread()*m_symbol.Point();
      return(NormalizeDouble(swing+m_atr_mult*atr+spread,m_symbol.Digits()));
     }

   bool              LockArmedLong(const CPositionInfo *position) const
     {
      if(!m_lock_enable)
         return(false);
      const double atr=m_atr.Main(1);
      if(atr<=0.0)
         return(false);
      const double profit=m_symbol.Bid()-position.PriceOpen();
      return(profit>=m_lock_start_atr*atr);
     }

   bool              LockArmedShort(const CPositionInfo *position) const
     {
      if(!m_lock_enable)
         return(false);
      const double atr=m_atr.Main(1);
      if(atr<=0.0)
         return(false);
      const double profit=position.PriceOpen()-m_symbol.Ask();
      return(profit>=m_lock_start_atr*atr);
     }

public:
                     CTrailingPSARLock(void);
                    ~CTrailingPSARLock(void);

   void              Step(const double step)             { m_step=step; }
   void              Maximum(const double maximum)       { m_maximum=maximum; }
   void              LockEnable(const bool value)        { m_lock_enable=value; }
   void              SwingBars(const int bars)           { m_swing_bars=MathMax(1,bars); }
   void              ATRPeriod(const int period)         { m_atr_period=MathMax(1,period); }
   void              ATRMult(const double mult)          { m_atr_mult=MathMax(0.0,mult); }
   void              LockStartATR(const double mult)     { m_lock_start_atr=MathMax(0.0,mult); }

   virtual bool      ValidationSettings(void);
   virtual bool      InitIndicators(CIndicators *indicators);
   virtual bool      CheckTrailingStopLong(CPositionInfo *position,double &sl,double &tp);
   virtual bool      CheckTrailingStopShort(CPositionInfo *position,double &sl,double &tp);
  };

//+------------------------------------------------------------------+
void CTrailingPSARLock::CTrailingPSARLock(void) : m_step(0.02),
                                                  m_maximum(0.2),
                                                  m_lock_enable(true),
                                                  m_swing_bars(3),
                                                  m_atr_period(14),
                                                  m_atr_mult(0.35),
                                                  m_lock_start_atr(0.8)
  {
   m_used_series=USE_SERIES_HIGH+USE_SERIES_LOW;
  }

//+------------------------------------------------------------------+
void CTrailingPSARLock::~CTrailingPSARLock(void)
  {
  }

//+------------------------------------------------------------------+
bool CTrailingPSARLock::ValidationSettings(void)
  {
   if(!CExpertTrailing::ValidationSettings())
      return(false);
   if(m_step<=0.0 || m_maximum<=0.0)
     {
      printf(__FUNCTION__+": PSAR step/maximum must be > 0");
      return(false);
     }
   if(m_lock_enable && m_swing_bars<1)
     {
      printf(__FUNCTION__+": swing bars must be >= 1");
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
bool CTrailingPSARLock::InitIndicators(CIndicators *indicators)
  {
   if(indicators==NULL)
      return(false);

   if(!indicators.Add(GetPointer(m_sar)))
     {
      printf(__FUNCTION__+": error adding SAR");
      return(false);
     }
   if(!m_sar.Create(m_symbol.Name(),m_period,m_step,m_maximum))
     {
      printf(__FUNCTION__+": error creating SAR");
      return(false);
     }
   m_sar.BufferResize(MathMax(3,m_swing_bars+2));

   if(m_lock_enable)
     {
      if(!indicators.Add(GetPointer(m_atr)))
        {
         printf(__FUNCTION__+": error adding ATR");
         return(false);
        }
      if(!m_atr.Create(m_symbol.Name(),m_period,m_atr_period))
        {
         printf(__FUNCTION__+": error creating ATR");
         return(false);
        }
      m_atr.BufferResize(MathMax(3,m_swing_bars+2));
     }

   return(true);
  }

//+------------------------------------------------------------------+
bool CTrailingPSARLock::CheckTrailingStopLong(CPositionInfo *position,double &sl,double &tp)
  {
   if(position==NULL)
      return(false);

   const double level=NormalizeDouble(m_symbol.Bid()-m_symbol.StopsLevel()*m_symbol.Point(),
                                      m_symbol.Digits());
   const double pos_sl=position.StopLoss();
   const double base=(pos_sl==0.0) ? position.PriceOpen() : pos_sl;

   sl=EMPTY_VALUE;
   tp=EMPTY_VALUE;

   double best=EMPTY_VALUE;
   ConsiderLong(m_sar.Main(1),base,level,best);

   if(LockArmedLong(position))
      ConsiderLong(SwingLockLong(),base,level,best);

   if(best!=EMPTY_VALUE)
      sl=best;

   return(sl!=EMPTY_VALUE);
  }

//+------------------------------------------------------------------+
bool CTrailingPSARLock::CheckTrailingStopShort(CPositionInfo *position,double &sl,double &tp)
  {
   if(position==NULL)
      return(false);

   const double level=NormalizeDouble(m_symbol.Ask()+m_symbol.StopsLevel()*m_symbol.Point(),
                                      m_symbol.Digits());
   const double pos_sl=position.StopLoss();
   const double base=(pos_sl==0.0) ? position.PriceOpen() : pos_sl;
   const double spread=m_symbol.Spread()*m_symbol.Point();

   sl=EMPTY_VALUE;
   tp=EMPTY_VALUE;

   double best=EMPTY_VALUE;
   ConsiderShort(m_sar.Main(1)+spread,base,level,best);

   if(LockArmedShort(position))
      ConsiderShort(SwingLockShort(),base,level,best);

   if(best!=EMPTY_VALUE)
      sl=best;

   return(sl!=EMPTY_VALUE);
  }

#endif
//+------------------------------------------------------------------+
