//+------------------------------------------------------------------+
//| SignalSpread.mqh — block entries when spread is too wide         |
//+------------------------------------------------------------------+
#include <Expert\ExpertSignal.mqh>

class CSignalSpread : public CExpertSignal
  {
protected:
   int m_max_spread_points;

public:
                     CSignalSpread(void) : m_max_spread_points(20) {}
                    ~CSignalSpread(void) {}

   void              MaxSpreadPoints(int value) { m_max_spread_points=value; }

   virtual double    Direction(void)
     {
      long spread=SymbolInfoInteger(m_symbol.Name(),SYMBOL_SPREAD);
      if(spread>m_max_spread_points)
         return(EMPTY_VALUE);
      return(0.0);
     }
  };

//+------------------------------------------------------------------+
//| Build BadHoursOfDay bitmask: disable hours outside [start,end]   |
//+------------------------------------------------------------------+
int BuildBadHoursMask(const int session_start,const int session_end)
  {
   int mask=0;
   for(int h=0; h<24; h++)
     {
      if(h<session_start || h>session_end)
         mask|=(1<<h);
     }
   return(mask);
  }

//+------------------------------------------------------------------+
