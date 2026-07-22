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
      // SYMBOL_SPREAD is already in this symbol's points (works for JPY/XAU/5-digit FX).
      // Also check live ask-bid so rollover spikes are caught even if SYMBOL_SPREAD lags.
      const string sym=m_symbol.Name();
      double point=SymbolInfoDouble(sym,SYMBOL_POINT);
      if(point<=0.0)
         point=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
      if(point<=0.0)
         return(EMPTY_VALUE);

      const double bid=SymbolInfoDouble(sym,SYMBOL_BID);
      const double ask=SymbolInfoDouble(sym,SYMBOL_ASK);
      double live=0.0;
      if(ask>bid)
         live=(ask-bid)/point;

      const double broker=(double)SymbolInfoInteger(sym,SYMBOL_SPREAD);
      const double spread=MathMax(live,broker);
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
