//+------------------------------------------------------------------+
//| SignalMABalanced.mqh — short open threshold + no-chase filter    |
//+------------------------------------------------------------------+
#ifndef SIGNAL_MA_BALANCED_MQH
#define SIGNAL_MA_BALANCED_MQH

#include <Expert\Signal\SignalMA.mqh>

class CSignalMABalanced : public CSignalMA
  {
private:
   int               m_threshold_open_short;
   bool              m_no_chase;
   int               m_no_chase_atr_period;
   double            m_no_chase_atr_mult;
   CiATR             m_atr;

   bool              TooExtendedForLong(void)
     {
      if(!m_no_chase || m_symbol==NULL)
         return(false);

      const int idx=StartIndex();
      const double ma=MA(idx);
      const double atr=m_atr.Main(1);
      if(ma<=0.0 || atr<=0.0)
         return(false);

      // Long chase: Ask already stretched too far above MA
      return(m_symbol.Ask()>ma+m_no_chase_atr_mult*atr);
     }

   bool              TooExtendedForShort(void)
     {
      if(!m_no_chase || m_symbol==NULL)
         return(false);

      const int idx=StartIndex();
      const double ma=MA(idx);
      const double atr=m_atr.Main(1);
      if(ma<=0.0 || atr<=0.0)
         return(false);

      // Short chase: Bid already stretched too far below MA
      return(m_symbol.Bid()<ma-m_no_chase_atr_mult*atr);
     }

public:
                     CSignalMABalanced(void) : m_threshold_open_short(10),
                                               m_no_chase(true),
                                               m_no_chase_atr_period(14),
                                               m_no_chase_atr_mult(1.0) {}

   void              ThresholdOpenShort(const int value)
     {
      m_threshold_open_short=MathMax(0,MathMin(100,value));
     }

   void              NoChase(const bool value)            { m_no_chase=value; }
   void              NoChaseATRPeriod(const int period)  { m_no_chase_atr_period=MathMax(1,period); }
   void              NoChaseATRMult(const double mult)   { m_no_chase_atr_mult=MathMax(0.0,mult); }

   virtual bool      ValidationSettings(void)
     {
      if(!CSignalMA::ValidationSettings())
         return(false);
      if(m_no_chase && m_no_chase_atr_period<=0)
        {
         printf(__FUNCTION__+": no-chase ATR period must be > 0");
         return(false);
        }
      return(true);
     }

   virtual bool      InitIndicators(CIndicators *indicators)
     {
      if(!CSignalMA::InitIndicators(indicators))
         return(false);

      if(!m_no_chase)
         return(true);

      if(!indicators.Add(GetPointer(m_atr)))
        {
         printf(__FUNCTION__+": error adding ATR");
         return(false);
        }
      if(!m_atr.Create(m_symbol.Name(),m_period,m_no_chase_atr_period))
        {
         printf(__FUNCTION__+": error creating ATR");
         return(false);
        }
      m_atr.BufferResize(MathMax(3,m_no_chase_atr_period+2));
      return(true);
     }

   virtual bool      CheckOpenLong(double &price,double &sl,double &tp,datetime &expiration)
     {
      if(m_direction==EMPTY_VALUE)
         return(false);

      if(m_direction<m_threshold_open)
        {
         m_base_price=0.0;
         return(false);
        }

      if(TooExtendedForLong())
        {
         m_base_price=0.0;
         return(false);
        }

      m_base_price=0.0;
      return(OpenLongParams(price,sl,tp,expiration));
     }

   virtual bool      CheckOpenShort(double &price,double &sl,double &tp,datetime &expiration)
     {
      // Use cached m_direction from SetDirection() (same as CheckOpenLong).
      if(m_direction==EMPTY_VALUE)
         return(false);

      if(-m_direction<m_threshold_open_short)
        {
         m_base_price=0.0;
         return(false);
        }

      if(TooExtendedForShort())
        {
         m_base_price=0.0;
         return(false);
        }

      m_base_price=0.0;
      return(OpenShortParams(price,sl,tp,expiration));
     }
  };

#endif
//+------------------------------------------------------------------+
