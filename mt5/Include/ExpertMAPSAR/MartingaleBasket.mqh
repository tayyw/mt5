//+------------------------------------------------------------------+
//| MartingaleBasket.mqh — per-side baskets (long / short) + stack    |
//+------------------------------------------------------------------+
#ifndef MARTINGALE_BASKET_MQH
#define MARTINGALE_BASKET_MQH

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <ExpertMAPSAR\MoneyMartingale.mqh>

class CMartingaleBasket
  {
private:
   bool               m_use_group_close;
   bool               m_allow_stack;
   double             m_min_group_profit;
   int                m_stack_max_legs;
   int                m_stack_step_points;
   ENUM_TIMEFRAMES    m_period;
   string             m_symbol;
   ulong              m_magic;
   datetime           m_last_stack_bar_buy;
   datetime           m_last_stack_bar_sell;
   CMoneyMartingale  *m_money;

   ENUM_ORDER_TYPE_FILLING FillingMode(void) const
     {
      const long mode=SymbolInfoInteger(m_symbol,SYMBOL_FILLING_MODE);
      if((mode & SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
         return(ORDER_FILLING_FOK);
      if((mode & SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
         return(ORDER_FILLING_IOC);
      return(ORDER_FILLING_RETURN);
     }

   int               SidePositionCount(const bool isBuy) const
     {
      CPositionInfo pos;
      int count=0;

      for(int i=PositionsTotal()-1; i>=0; i--)
        {
         if(!pos.SelectByIndex(i))
            continue;
         if(pos.Symbol()!=m_symbol)
            continue;
         if((ulong)pos.Magic()!=m_magic)
            continue;

         const bool legBuy=(pos.PositionType()==POSITION_TYPE_BUY);
         if(legBuy==isBuy)
            count++;
        }

      return(count);
     }

   double            SideFloatingPnL(const bool isBuy) const
     {
      CPositionInfo pos;
      double pnl=0.0;

      for(int i=PositionsTotal()-1; i>=0; i--)
        {
         if(!pos.SelectByIndex(i))
            continue;
         if(pos.Symbol()!=m_symbol)
            continue;
         if((ulong)pos.Magic()!=m_magic)
            continue;

         const bool legBuy=(pos.PositionType()==POSITION_TYPE_BUY);
         if(legBuy!=isBuy)
            continue;

         pnl+=pos.Profit()+pos.Swap()+pos.Commission();
        }

      return(pnl);
     }

   double            SideCycleNetPnL(const bool isBuy) const
     {
      if(m_money==NULL)
         return(SideFloatingPnL(isBuy));
      return(m_money.StreakRealizedPnL(isBuy)+SideFloatingPnL(isBuy));
     }

   bool              SideInMartingaleGroup(const bool isBuy) const
     {
      if(m_money!=NULL && m_money.LossStreak(isBuy)>0)
         return(true);
      return(SidePositionCount(isBuy)>1);
     }

   bool              GetLatestLeg(const bool isBuy,datetime &openTime,double &openPrice) const
     {
      CPositionInfo pos;
      openTime=0;
      openPrice=0.0;

      for(int i=PositionsTotal()-1; i>=0; i--)
        {
         if(!pos.SelectByIndex(i))
            continue;
         if(pos.Symbol()!=m_symbol)
            continue;
         if((ulong)pos.Magic()!=m_magic)
            continue;

         const bool legBuy=(pos.PositionType()==POSITION_TYPE_BUY);
         if(legBuy!=isBuy)
            continue;

         if(pos.Time()>=openTime)
           {
            openTime=pos.Time();
            openPrice=pos.PriceOpen();
           }
        }

      return(openTime>0);
     }

   bool              CloseSideBasket(const bool isBuy)
     {
      CTrade        trade;
      CPositionInfo pos;
      trade.SetExpertMagicNumber(m_magic);
      bool ok=true;

      for(int i=PositionsTotal()-1; i>=0; i--)
        {
         if(!pos.SelectByIndex(i))
            continue;
         if(pos.Symbol()!=m_symbol)
            continue;
         if((ulong)pos.Magic()!=m_magic)
            continue;

         const bool legBuy=(pos.PositionType()==POSITION_TYPE_BUY);
         if(legBuy!=isBuy)
            continue;

         if(!trade.PositionClose(pos.Ticket()))
            ok=false;
        }

      if(isBuy)
         m_last_stack_bar_buy=0;
      else
         m_last_stack_bar_sell=0;

      return(ok);
     }

   void              TryStackAddSide(const bool isBuy)
     {
      if(!m_allow_stack || m_money==NULL || !m_money.IsMartingaleEnabled())
         return;

      const int posCount=SidePositionCount(isBuy);
      if(posCount<=0 || posCount>=m_stack_max_legs)
         return;

      if(SideCycleNetPnL(isBuy)>=m_min_group_profit)
         return;

      datetime lastOpenTime=0;
      double   lastOpenPrice=0.0;
      if(!GetLatestLeg(isBuy,lastOpenTime,lastOpenPrice))
         return;

      const datetime barTime=iTime(m_symbol,m_period,0);
      if(isBuy)
        {
         if(barTime==m_last_stack_bar_buy)
            return;
        }
      else
        {
         if(barTime==m_last_stack_bar_sell)
            return;
        }

      const double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      if(point<=0.0 || m_stack_step_points<=0)
         return;

      const double stepDist=m_stack_step_points*point;
      const double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      const double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
      const double refPrice=isBuy ? bid : ask;
      const double adverseMove=isBuy ? (lastOpenPrice-refPrice) : (refPrice-lastOpenPrice);

      if(adverseMove<stepDist)
         return;

      const int stepIndex=m_money.LossStreak(isBuy)+posCount;
      const double lot=m_money.MartingaleLotForStep(stepIndex,isBuy);
      if(lot<=0.0)
         return;

      CTrade trade;
      trade.SetExpertMagicNumber(m_magic);
      trade.SetTypeFilling(FillingMode());

      const string tag=isBuy ? "B" : "S";
      const string comment=StringFormat("MG|%s|leg=%d",tag,posCount+1);
      const bool ok=isBuy ? trade.Buy(lot,m_symbol,0,0,0,comment)
                          : trade.Sell(lot,m_symbol,0,0,0,comment);

      if(ok)
        {
         if(isBuy)
            m_last_stack_bar_buy=barTime;
         else
            m_last_stack_bar_sell=barTime;

         Print("Martingale STACK ",tag," leg=",posCount+1," step=",stepIndex,
               " lot=",DoubleToString(lot,2),
               " adverse=",DoubleToString(adverseMove/point,1),"pts");
        }
      else
         Print("Martingale STACK ",tag," failed: ",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
     }

   void              UpdateSide(const bool isBuy)
     {
      const int posCount=SidePositionCount(isBuy);
      if(posCount<=0)
         return;

      if(m_use_group_close && SideInMartingaleGroup(isBuy))
        {
         const double cycleNet=SideCycleNetPnL(isBuy);
         if(cycleNet>=m_min_group_profit)
           {
            Print("Martingale GROUP CLOSE ",(isBuy?"LONG":"SHORT"),
                  " legs=",posCount,
                  " floating=",DoubleToString(SideFloatingPnL(isBuy),2),
                  " streakRealized=",DoubleToString(m_money!=NULL ? m_money.StreakRealizedPnL(isBuy) : 0.0,2),
                  " cycleNet=",DoubleToString(cycleNet,2));
            CloseSideBasket(isBuy);
            return;
           }
        }

      TryStackAddSide(isBuy);
     }

public:
                     CMartingaleBasket(void) : m_use_group_close(true),
                                               m_allow_stack(true),
                                               m_min_group_profit(0.0),
                                               m_stack_max_legs(4),
                                               m_stack_step_points(120),
                                               m_period(PERIOD_CURRENT),
                                               m_symbol(""),
                                               m_magic(0),
                                               m_last_stack_bar_buy(0),
                                               m_last_stack_bar_sell(0),
                                               m_money(NULL) {}

   void              Init(const string symbol,const ulong magic,const ENUM_TIMEFRAMES period,
                          CMoneyMartingale *money,const bool useGroupClose,const bool allowStack,
                          const double minGroupProfit,const int stackMaxLegs,
                          const int stackStepPoints)
     {
      m_symbol           =symbol;
      m_magic            =magic;
      m_period           =period;
      m_money            =money;
      m_use_group_close  =useGroupClose;
      m_allow_stack      =allowStack;
      m_min_group_profit =minGroupProfit;
      m_stack_max_legs   =MathMax(1,stackMaxLegs);
      m_stack_step_points=MathMax(1,stackStepPoints);
      m_last_stack_bar_buy=0;
      m_last_stack_bar_sell=0;

      // StackMaxLegs=0/1 → posCount>=max blocks every add (only the first leg can exist).
      if(m_allow_stack && m_stack_max_legs<2)
         Print("WARN: MG StackMaxLegs=",stackMaxLegs,
               " (effective ",m_stack_max_legs,
               ") — need >= 2 to add stack legs. Stacking is disabled.");
     }

   void              Update(void)
     {
      UpdateSide(true);
      UpdateSide(false);
     }
  };

#endif
