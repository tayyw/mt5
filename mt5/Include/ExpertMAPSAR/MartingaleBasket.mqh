//+------------------------------------------------------------------+
//| MartingaleBasket.mqh — per-side baskets (long / short) + stack    |
//+------------------------------------------------------------------+
#ifndef MARTINGALE_BASKET_MQH
#define MARTINGALE_BASKET_MQH

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <ExpertMAPSAR\MoneyMartingale.mqh>

// Default stack spread cap in *symbol points* (SYMBOL_POINT units).
// Same integer works across denominations: EURUSD 5-digit, USDJPY 3-digit, XAU, etc.
#define MG_STACK_SPREAD_CAP_DEFAULT 18

class CMartingaleBasket
  {
private:
   bool               m_use_group_close;
   bool               m_allow_stack;
   double             m_min_group_profit;
   int                m_stack_max_legs;
   int                m_stack_step_points;
   int                m_max_spread_points; // always >= 1 after Init (never off)
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

   // Symbol point size for any denomination (FX 3/5-digit, metals, CFDs).
   double            SymbolPointSize(void) const
     {
      double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      if(point>0.0)
         return(point);
      point=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
      return(point);
     }

   // Spread in this symbol's points: max(live ask-bid, broker SYMBOL_SPREAD).
   double            SpreadPointsNow(const double bid,const double ask,const double point) const
     {
      if(point<=0.0 || ask<=bid)
         return(DBL_MAX);
      const double live=(ask-bid)/point;
      const double broker=(double)SymbolInfoInteger(m_symbol,SYMBOL_SPREAD);
      return(MathMax(live,broker));
     }

   // Price distance → integer symbol points (avoids float noise across digits).
   int               DistancePoints(const double priceMove,const double point) const
     {
      if(point<=0.0)
         return(0);
      return((int)MathFloor(priceMove/point+1e-8));
     }

   // Shared LONG+SHORT gate: refuse stack adds on wide / chaotic spreads.
   bool              SpreadAllowsStack(const double spreadPts,int &capOut) const
     {
      capOut=m_max_spread_points;
      if(capOut<=0)
         capOut=MG_STACK_SPREAD_CAP_DEFAULT;
      if(spreadPts>capOut)
         return(false);
      // Absolute: spread alone must never equal a full step.
      if(spreadPts>=m_stack_step_points)
         return(false);
      return(true);
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

      const double point=SymbolPointSize();
      if(point<=0.0 || m_stack_step_points<=0)
         return;

      const double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      const double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
      if(ask<=bid || !MathIsValidNumber(bid) || !MathIsValidNumber(ask))
         return;

      const double spreadPts=SpreadPointsNow(bid,ask,point);
      int spreadCap=0;
      if(!SpreadAllowsStack(spreadPts,spreadCap))
        {
         Print("Martingale STACK skip ",m_symbol," ",(isBuy?"LONG":"SHORT"),
               ": spread ",DoubleToString(spreadPts,1),
               "pts > cap ",spreadCap,
               " (step=",m_stack_step_points," symbol-pts)");
         return;
        }

      // Adverse vs fill price — same rule both sides, any symbol:
      // LONG adds at Ask → measure Ask vs last open; SHORT adds at Bid → measure Bid.
      // Never use the opposite quote (that counted spread spikes as price travel).
      const double markPrice=isBuy ? ask : bid;
      const double adverseMove=isBuy ? (lastOpenPrice-markPrice) : (markPrice-lastOpenPrice);
      const int    adversePts=DistancePoints(adverseMove,point);

      if(adversePts<m_stack_step_points)
         return;

      // Step from open legs only (flat entries are always base lot; no history streak).
      const int stepIndex=posCount;
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

         Print("Martingale STACK ",m_symbol," ",tag," leg=",posCount+1," step=",stepIndex,
               " lot=",DoubleToString(lot,2),
               " adverse=",adversePts,"pts");
        }
      else
         Print("Martingale STACK ",m_symbol," ",tag," failed: ",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
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
                                               m_max_spread_points(MG_STACK_SPREAD_CAP_DEFAULT),
                                               m_period(PERIOD_CURRENT),
                                               m_symbol(""),
                                               m_magic(0),
                                               m_last_stack_bar_buy(0),
                                               m_last_stack_bar_sell(0),
                                               m_money(NULL) {}

   void              Init(const string symbol,const ulong magic,const ENUM_TIMEFRAMES period,
                          CMoneyMartingale *money,const bool useGroupClose,const bool allowStack,
                          const double minGroupProfit,const int stackMaxLegs,
                          const int stackStepPoints,
                          const int maxSpreadPoints=MG_STACK_SPREAD_CAP_DEFAULT)
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
      // Always-on: 0/negative → default. Stack guard cannot be disabled.
      m_max_spread_points=(maxSpreadPoints>0 ? maxSpreadPoints : MG_STACK_SPREAD_CAP_DEFAULT);
      m_last_stack_bar_buy=0;
      m_last_stack_bar_sell=0;

      // StackMaxLegs=0/1 → posCount>=max blocks every add (only the first leg can exist).
      if(m_allow_stack && m_stack_max_legs<2)
         Print("WARN: MG StackMaxLegs=",stackMaxLegs,
               " (effective ",m_stack_max_legs,
               ") — need >= 2 to add stack legs. Stacking is disabled.");

      if(m_allow_stack)
        {
         const double point=SymbolPointSize();
         const int    digits=(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
         Print("MG stack spread guard ON (LONG+SHORT) ",m_symbol,
               " digits=",digits,
               " point=",DoubleToString(point,MathMax(digits,1)),
               " | cap=",m_max_spread_points," symbol-pts",
               " step=",m_stack_step_points," symbol-pts",
               " — blocked when spread>cap or spread>=step; adverse=fill-side only");
        }
     }

   void              AllowStack(const bool value) { m_allow_stack=value; }
   bool              AllowStack(void) const       { return(m_allow_stack); }

   bool              CloseAllPositions(void)
     {
      const bool buyOk=CloseSideBasket(true);
      const bool sellOk=CloseSideBasket(false);
      return(buyOk && sellOk);
     }

   void              Update(void)
     {
      // Same spread + fill-side guards run for both baskets.
      UpdateSide(true);   // LONG
      UpdateSide(false);  // SHORT
     }
  };

#endif
