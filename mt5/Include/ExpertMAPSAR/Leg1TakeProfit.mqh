//+------------------------------------------------------------------+
//| Leg1TakeProfit.mqh — floor + ratchet TP for signal entries only |
//+------------------------------------------------------------------+
#ifndef LEG1_TAKE_PROFIT_MQH
#define LEG1_TAKE_PROFIT_MQH

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

class CLeg1TakeProfit
  {
private:
   bool              m_enabled;
   string            m_symbol;
   ulong             m_magic;
   ENUM_TIMEFRAMES   m_period;
   int               m_atr_period;
   double            m_min_atr_mult;
   double            m_trail_atr_mult;
   int               m_min_points;
   int               m_atr_handle;
   datetime          m_last_bar;
   CTrade            m_trade;

   bool              IsStackLeg(const string comment) const
     {
      return(StringFind(comment,"MG|")>=0);
     }

   int               Digits(void) const
     {
      return((int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS));
     }

   double            Point(void) const
     {
      return(SymbolInfoDouble(m_symbol,SYMBOL_POINT));
     }

   double            StopsDistance(void) const
     {
      const long stops=SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL);
      const double point=Point();
      if(point<=0.0)
         return(0.0);
      return(stops*point);
     }

   bool              ReadAtr(const int shift,double &atr) const
     {
      atr=0.0;
      if(m_atr_handle==INVALID_HANDLE)
         return(false);

      double buf[];
      ArraySetAsSeries(buf,true);
      if(CopyBuffer(m_atr_handle,0,shift,1,buf)!=1)
         return(false);

      atr=buf[0];
      return(atr>0.0);
     }

   double            TargetDistance(const double atr) const
     {
      const double point=Point();
      if(point<=0.0 || atr<=0.0)
         return(0.0);

      const double dist_pts=m_min_points*point;
      const double dist_min=m_min_atr_mult*atr;
      const double dist_trail=m_trail_atr_mult*atr;
      return(MathMax(dist_pts,MathMax(dist_min,dist_trail)));
     }

   bool              CalcTpPrice(const bool isBuy,const double entry,const double atr,double &tp) const
     {
      const double dist=TargetDistance(atr);
      if(dist<=0.0)
         return(false);

      const double min_gap=StopsDistance();
      if(isBuy)
         tp=NormalizeDouble(entry+MathMax(dist,min_gap),Digits());
      else
         tp=NormalizeDouble(entry-MathMax(dist,min_gap),Digits());

      return(tp>0.0);
     }

   bool              TpValidForModify(const bool isBuy,const double tp) const
     {
      const double min_gap=StopsDistance();
      if(isBuy)
        {
         const double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
         return(tp>ask+min_gap);
        }

      const double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      return(tp<bid-min_gap);
     }

   bool              RatchetTp(const ulong ticket,const bool isBuy,const double entry,
                               const double currentTp,const double atr)
     {
      double newTp=0.0;
      if(!CalcTpPrice(isBuy,entry,atr,newTp))
         return(false);

      if(isBuy)
        {
         if(currentTp>0.0 && newTp<=currentTp)
            return(false);
        }
      else
        {
         if(currentTp>0.0 && newTp>=currentTp)
            return(false);
        }

      if(!TpValidForModify(isBuy,newTp))
         return(false);

      CPositionInfo pos;
      if(!pos.SelectByTicket(ticket))
         return(false);

      const double sl=pos.StopLoss();
      if(!m_trade.PositionModify(ticket,sl,newTp))
        {
         Print("Leg1TP ratchet failed #",ticket," err=",GetLastError());
         return(false);
        }

      return(true);
     }

   bool              EnsureInitialTp(CPositionInfo &pos)
     {
      if(pos.TakeProfit()>0.0)
         return(false);

      double atr=0.0;
      if(!ReadAtr(1,atr))
         return(false);

      const bool isBuy=(pos.PositionType()==POSITION_TYPE_BUY);
      double tp=0.0;
      if(!CalcTpPrice(isBuy,pos.PriceOpen(),atr,tp))
         return(false);

      const double sl=pos.StopLoss();
      if(!m_trade.PositionModify(pos.Ticket(),sl,tp))
        {
         Print("Leg1TP initial set failed #",pos.Ticket()," err=",GetLastError());
         return(false);
        }

      Print("Leg1TP set #",pos.Ticket()," tp=",DoubleToString(tp,Digits()),
            " dist=",DoubleToString(TargetDistance(atr)/Point(),1),"pts");
      return(true);
     }

   void              ManagePosition(CPositionInfo &pos,const bool onNewBar)
     {
      if(pos.Symbol()!=m_symbol)
         return;
      if((ulong)pos.Magic()!=m_magic)
         return;
      if(IsStackLeg(pos.Comment()))
         return;

      if(pos.TakeProfit()<=0.0)
        {
         EnsureInitialTp(pos);
         return;
        }

      if(!onNewBar)
         return;

      double atr=0.0;
      if(!ReadAtr(1,atr))
         return;

      const bool isBuy=(pos.PositionType()==POSITION_TYPE_BUY);
      RatchetTp(pos.Ticket(),isBuy,pos.PriceOpen(),pos.TakeProfit(),atr);
     }

public:
                     CLeg1TakeProfit(void) : m_enabled(false),
                                             m_magic(0),
                                             m_period(PERIOD_CURRENT),
                                             m_atr_period(14),
                                             m_min_atr_mult(0.8),
                                             m_trail_atr_mult(1.5),
                                             m_min_points(0),
                                             m_atr_handle(INVALID_HANDLE),
                                             m_last_bar(0) {}

                    ~CLeg1TakeProfit(void)
     {
      Deinit();
     }

   bool              Init(const string symbol,const ulong magic,const ENUM_TIMEFRAMES period,
                          const bool enabled,const int atrPeriod,
                          const double minAtrMult,const double trailAtrMult,
                          const int minPoints)
     {
      m_symbol         =symbol;
      m_magic          =magic;
      m_period         =period;
      m_enabled        =enabled;
      m_atr_period     =MathMax(2,atrPeriod);
      m_min_atr_mult   =MathMax(0.1,minAtrMult);
      m_trail_atr_mult =MathMax(m_min_atr_mult,trailAtrMult);
      m_min_points     =MathMax(0,minPoints);
      m_last_bar       =0;

      if(!m_enabled)
         return(true);

      m_atr_handle=iATR(m_symbol,m_period,m_atr_period);
      if(m_atr_handle==INVALID_HANDLE)
        {
         Print("Leg1TP: iATR create failed err=",GetLastError());
         return(false);
        }

      m_trade.SetExpertMagicNumber(m_magic);
      return(true);
     }

   void              Deinit(void)
     {
      if(m_atr_handle!=INVALID_HANDLE)
        {
         IndicatorRelease(m_atr_handle);
         m_atr_handle=INVALID_HANDLE;
        }
     }

   void              OnTick(void)
     {
      if(!m_enabled)
         return;

      const datetime barTime=iTime(m_symbol,m_period,0);
      const bool onNewBar=(barTime!=0 && barTime!=m_last_bar);
      if(onNewBar)
         m_last_bar=barTime;

      CPositionInfo pos;
      for(int i=PositionsTotal()-1; i>=0; i--)
        {
         if(!pos.SelectByIndex(i))
            continue;
         ManagePosition(pos,onNewBar);
        }
     }
  };

#endif
