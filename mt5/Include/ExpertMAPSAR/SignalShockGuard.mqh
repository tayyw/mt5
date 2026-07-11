//+------------------------------------------------------------------+
//| SignalShockGuard.mqh — block entries during spike / cooldown      |
//+------------------------------------------------------------------+
#ifndef SIGNAL_SHOCK_GUARD_MQH
#define SIGNAL_SHOCK_GUARD_MQH

#include <Expert\ExpertSignal.mqh>
#include <ExpertMAPSAR\ShockGuard.mqh>

class CSignalShockGuard : public CExpertSignal
  {
private:
   CShockGuard      *m_guard;

public:
                     CSignalShockGuard(void) : m_guard(NULL) {}
                    ~CSignalShockGuard(void) {}

   void              SetGuard(CShockGuard *guard) { m_guard=guard; }

   virtual double    Direction(void)
     {
      if(m_guard!=NULL && m_guard.IsTradingBlocked())
         return(EMPTY_VALUE);
      return(0.0);
     }
  };

#endif
