//+------------------------------------------------------------------+
//| SignalMABalanced.mqh — separate open threshold for shorts         |
//+------------------------------------------------------------------+
#ifndef SIGNAL_MA_BALANCED_MQH
#define SIGNAL_MA_BALANCED_MQH

#include <Expert\Signal\SignalMA.mqh>

class CSignalMABalanced : public CSignalMA
  {
private:
   int      m_threshold_open_short;

public:
                     CSignalMABalanced(void) : m_threshold_open_short(10) {}

   void              ThresholdOpenShort(const int value)
     {
      m_threshold_open_short=MathMax(0,MathMin(100,value));
     }

   virtual bool      CheckOpenShort(double &price,double &sl,double &tp,datetime &expiration)
     {
      // Use cached m_direction from SetDirection() (same as CheckOpenLong).
      if(m_direction==EMPTY_VALUE)
         return(false);

      if(-m_direction>=m_threshold_open_short)
        {
         m_base_price=0.0;
         return(OpenShortParams(price,sl,tp,expiration));
        }

      m_base_price=0.0;
      return(false);
     }
  };

#endif
