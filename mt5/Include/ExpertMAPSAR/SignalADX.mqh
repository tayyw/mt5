//+------------------------------------------------------------------+
//| SignalADX.mqh — block entries when ADX is below min (no trend)   |
//+------------------------------------------------------------------+
#ifndef SIGNAL_ADX_MQH
#define SIGNAL_ADX_MQH

#include <Expert\ExpertSignal.mqh>

class CSignalADX : public CExpertSignal
  {
protected:
   CiADX             m_adx;
   int               m_period_adx;
   double            m_adx_min;

public:
                     CSignalADX(void) : m_period_adx(14), m_adx_min(25.0) {}
                    ~CSignalADX(void) {}

   void              PeriodADX(const int value)   { m_period_adx=value; }
   void              MinADX(const double value)   { m_adx_min=value;    }

   virtual bool      ValidationSettings(void)
     {
      if(!CExpertSignal::ValidationSettings())
         return(false);
      if(m_period_adx<=0)
        {
         printf(__FUNCTION__+": ADX period must be > 0");
         return(false);
        }
      if(m_adx_min<0.0)
        {
         printf(__FUNCTION__+": ADX min must be >= 0");
         return(false);
        }
      return(true);
     }

   virtual bool      InitIndicators(CIndicators *indicators)
     {
      if(indicators==NULL)
         return(false);
      if(!CExpertSignal::InitIndicators(indicators))
         return(false);
      if(!indicators.Add(GetPointer(m_adx)))
        {
         printf(__FUNCTION__+": error adding ADX");
         return(false);
        }
      if(!m_adx.Create(m_symbol.Name(),m_period,m_period_adx))
        {
         printf(__FUNCTION__+": error creating ADX");
         return(false);
        }
      return(true);
     }

   // Hard gate: EMPTY_VALUE prohibits open; 0.0 is neutral (no direction bias).
   virtual double    Direction(void)
     {
      const double adx=m_adx.Main(StartIndex());
      if(adx==EMPTY_VALUE || adx<m_adx_min)
         return(EMPTY_VALUE);
      return(0.0);
     }
  };

#endif
//+------------------------------------------------------------------+
