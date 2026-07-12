//+------------------------------------------------------------------+
//| SignalATRSpike.mqh — block entries during ATR spike              |
//+------------------------------------------------------------------+
#ifndef SIGNAL_ATR_SPIKE_MQH
#define SIGNAL_ATR_SPIKE_MQH

#include <Expert\ExpertSignal.mqh>
#include <ExpertMAPSAR\ATRSpikeGuard.mqh>

class CSignalATRSpike : public CExpertSignal
  {
private:
   CATRSpikeGuard   *m_guard;

public:
                     CSignalATRSpike(void) : m_guard(NULL) {}
                    ~CSignalATRSpike(void) {}

   void              SetGuard(CATRSpikeGuard *guard) { m_guard=guard; }

   virtual double    Direction(void)
     {
      if(m_guard!=NULL && m_guard.IsSpikeActive())
         return(EMPTY_VALUE);
      return(0.0);
     }
  };

#endif
