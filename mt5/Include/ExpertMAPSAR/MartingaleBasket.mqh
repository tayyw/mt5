//+------------------------------------------------------------------+
//| MartingaleBasket.mqh — per-side baskets (long / short) + stack    |
//| Soft aborts: MaxBasketLoss%, ATR regime, time/MFE                 |
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
   double             m_max_basket_loss_pct; // 0 = off; close when floating <= -pct% equity
   double             m_abort_atr_mult;     // 0 = off; close when adverse from oldest >= mult*ATR
   int                m_abort_atr_period;
   int                m_abort_max_bars;     // 0 = off; close if age>=bars and never touched BE
   ENUM_TIMEFRAMES    m_period;
   string             m_symbol;
   ulong              m_magic;
   datetime           m_last_stack_bar_buy;
   datetime           m_last_stack_bar_sell;
   double             m_best_floating_buy;  // MFE tracker (reset when side flat)
   double             m_best_floating_sell;
   int                m_atr_handle;
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

   bool              GetOldestLeg(const bool isBuy,datetime &openTime,double &openPrice) const
     {
      CPositionInfo pos;
      openTime=0;
      openPrice=0.0;
      bool found=false;

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

         if(!found || pos.Time()<openTime)
           {
            openTime=pos.Time();
            openPrice=pos.PriceOpen();
            found=true;
           }
        }

      return(found);
     }

   double            CurrentATR(void) const
     {
      if(m_atr_handle==INVALID_HANDLE)
         return(0.0);

      double buf[];
      ArraySetAsSeries(buf,true);
      if(CopyBuffer(m_atr_handle,0,0,1,buf)<=0)
         return(0.0);
      return(buf[0]);
     }

   int               BarsSince(const datetime openTime) const
     {
      if(openTime<=0)
         return(0);

      const int shift=iBarShift(m_symbol,m_period,openTime,true);
      if(shift<0)
         return(0);
      return(shift);
     }

   void              ResetSideMFE(const bool isBuy)
     {
      if(isBuy)
         m_best_floating_buy=-DBL_MAX;
      else
         m_best_floating_sell=-DBL_MAX;
     }

   void              TrackSideMFE(const bool isBuy,const double floating)
     {
      if(isBuy)
        {
         if(m_best_floating_buy<=-DBL_MAX/2.0 || floating>m_best_floating_buy)
            m_best_floating_buy=floating;
        }
      else
        {
         if(m_best_floating_sell<=-DBL_MAX/2.0 || floating>m_best_floating_sell)
            m_best_floating_sell=floating;
        }
     }

   double            BestFloating(const bool isBuy) const
     {
      return(isBuy ? m_best_floating_buy : m_best_floating_sell);
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

      ResetSideMFE(isBuy);
      return(ok);
     }

   bool              TryAbortSide(const bool isBuy)
     {
      const int posCount=SidePositionCount(isBuy);
      if(posCount<=0)
        {
         ResetSideMFE(isBuy);
         return(false);
        }

      const double floating=SideFloatingPnL(isBuy);
      TrackSideMFE(isBuy,floating);

      const string side=isBuy ? "LONG" : "SHORT";

      // 1) Max basket loss % of equity (floating)
      if(m_max_basket_loss_pct>0.0)
        {
         const double equity=AccountInfoDouble(ACCOUNT_EQUITY);
         if(equity>0.0)
           {
            const double limit=-equity*m_max_basket_loss_pct/100.0;
            if(floating<=limit)
              {
               Print("Martingale ABORT LOSS% ",side,
                     " legs=",posCount,
                     " floating=",DoubleToString(floating,2),
                     " limit=",DoubleToString(limit,2),
                     " (",DoubleToString(m_max_basket_loss_pct,2),"% equity)");
               CloseSideBasket(isBuy);
               return(true);
              }
           }
        }

      datetime oldestTime=0;
      double   oldestPrice=0.0;
      if(!GetOldestLeg(isBuy,oldestTime,oldestPrice))
         return(false);

      // 2) Regime: adverse move from first leg >= AbortATRMult * ATR
      if(m_abort_atr_mult>0.0)
        {
         const double atr=CurrentATR();
         if(atr>0.0)
           {
            const double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
            const double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
            const double refPrice=isBuy ? bid : ask;
            const double adverse=isBuy ? (oldestPrice-refPrice) : (refPrice-oldestPrice);
            const double threshold=m_abort_atr_mult*atr;

            if(adverse>=threshold)
              {
               const int dig=(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
               Print("Martingale ABORT ATR ",side,
                     " legs=",posCount,
                     " adverse=",DoubleToString(adverse,dig),
                     " >= ",DoubleToString(m_abort_atr_mult,2),"*ATR=",
                     DoubleToString(threshold,dig),
                     " floating=",DoubleToString(floating,2));
               CloseSideBasket(isBuy);
               return(true);
              }
           }
        }

      // 3) Time + no MFE to breakeven: age >= MaxBars and best floating never >= 0
      if(m_abort_max_bars>0)
        {
         const int ageBars=BarsSince(oldestTime);
         const double best=BestFloating(isBuy);
         const bool neverBreakeven=(best<-1.0e-8 || best<=-DBL_MAX/2.0);

         if(ageBars>=m_abort_max_bars && neverBreakeven &&
            SideCycleNetPnL(isBuy)<m_min_group_profit)
           {
            Print("Martingale ABORT TIME ",side,
                  " legs=",posCount,
                  " ageBars=",ageBars,"/",m_abort_max_bars,
                  " bestFloat=",DoubleToString(best<=-DBL_MAX/2.0 ? floating : best,2),
                  " cycleNet=",DoubleToString(SideCycleNetPnL(isBuy),2));
            CloseSideBasket(isBuy);
            return(true);
           }
        }

      return(false);
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
        {
         ResetSideMFE(isBuy);
         return;
        }

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

      if(TryAbortSide(isBuy))
         return;

      TryStackAddSide(isBuy);
     }

public:
                     CMartingaleBasket(void) : m_use_group_close(true),
                                               m_allow_stack(true),
                                               m_min_group_profit(0.0),
                                               m_stack_max_legs(4),
                                               m_stack_step_points(120),
                                               m_max_basket_loss_pct(0.0),
                                               m_abort_atr_mult(0.0),
                                               m_abort_atr_period(14),
                                               m_abort_max_bars(0),
                                               m_period(PERIOD_CURRENT),
                                               m_symbol(""),
                                               m_magic(0),
                                               m_last_stack_bar_buy(0),
                                               m_last_stack_bar_sell(0),
                                               m_best_floating_buy(-DBL_MAX),
                                               m_best_floating_sell(-DBL_MAX),
                                               m_atr_handle(INVALID_HANDLE),
                                               m_money(NULL) {}

                    ~CMartingaleBasket(void)
     {
      if(m_atr_handle!=INVALID_HANDLE)
        {
         IndicatorRelease(m_atr_handle);
         m_atr_handle=INVALID_HANDLE;
        }
     }

   void              Init(const string symbol,const ulong magic,const ENUM_TIMEFRAMES period,
                          CMoneyMartingale *money,const bool useGroupClose,const bool allowStack,
                          const double minGroupProfit,const int stackMaxLegs,
                          const int stackStepPoints,
                          const double maxBasketLossPct=0.0,
                          const double abortAtrMult=0.0,
                          const int abortAtrPeriod=14,
                          const int abortMaxBars=0)
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
      m_max_basket_loss_pct=MathMax(0.0,maxBasketLossPct);
      m_abort_atr_mult   =MathMax(0.0,abortAtrMult);
      m_abort_atr_period =MathMax(1,abortAtrPeriod);
      m_abort_max_bars   =MathMax(0,abortMaxBars);
      m_last_stack_bar_buy=0;
      m_last_stack_bar_sell=0;
      ResetSideMFE(true);
      ResetSideMFE(false);

      if(m_atr_handle!=INVALID_HANDLE)
        {
         IndicatorRelease(m_atr_handle);
         m_atr_handle=INVALID_HANDLE;
        }

      if(m_abort_atr_mult>0.0)
        {
         m_atr_handle=iATR(m_symbol,m_period,m_abort_atr_period);
         if(m_atr_handle==INVALID_HANDLE)
            Print("WARN: MG ATR handle failed err=",GetLastError(),
                  " — ATR abort disabled until re-init.");
        }

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
