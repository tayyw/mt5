//+------------------------------------------------------------------+
//| MoneyMartingale.mqh — SizeOptimized + optional loss-streak MG     |
//+------------------------------------------------------------------+
#ifndef MONEY_MARTINGALE_MQH
#define MONEY_MARTINGALE_MQH

#include <Expert\Money\MoneySizeOptimized.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\PositionInfo.mqh>

class CMoneyMartingale : public CMoneySizeOptimized
  {
protected:
   bool     m_use_martingale;
   double   m_martingale_mult;
   int      m_martingale_max_steps;
   double   m_lot_scale;
   double   m_max_lot_cap;
   double   m_sizing_base;   // 0=live free margin; >0=cap capital used for % sizing

   static bool DealClosesLongBasket(const CDealInfo &deal)
     {
      return(deal.Entry()==DEAL_ENTRY_OUT && deal.DealType()==DEAL_TYPE_SELL);
     }

   static bool DealClosesShortBasket(const CDealInfo &deal)
     {
      return(deal.Entry()==DEAL_ENTRY_OUT && deal.DealType()==DEAL_TYPE_BUY);
     }

   // Earliest open time on this side; 0 = flat (no active cycle → streak 0).
   datetime          ActiveCycleStart(const bool forLongBasket) const
     {
      if(m_symbol==NULL)
         return(0);

      CPositionInfo pos;
      datetime      earliest=0;

      for(int i=PositionsTotal()-1; i>=0; i--)
        {
         if(!pos.SelectByIndex(i))
            continue;
         if(pos.Symbol()!=m_symbol.Name())
            continue;
         if((ulong)pos.Magic()!=m_magic)
            continue;

         const bool isBuy=(pos.PositionType()==POSITION_TYPE_BUY);
         if(isBuy!=forLongBasket)
            continue;

         if(earliest==0 || pos.Time()<earliest)
            earliest=pos.Time();
        }

      return(earliest);
     }

   bool              DealInStreakWindow(const CDealInfo &deal,const datetime windowStart) const
     {
      if(windowStart<=0)
         return(false);
      return(deal.Time()>windowStart);
     }

   double   NormalizeLot(double lot) const
     {
      if(m_symbol==NULL)
         return(0.0);

      lot*=m_lot_scale;

      double stepvol=m_symbol.LotsStep();
      if(stepvol>0.0)
         lot=stepvol*NormalizeDouble(lot/stepvol,0);

      if(m_max_lot_cap>0.0)
         lot=MathMin(lot,m_max_lot_cap);

      if(lot<m_symbol.LotsMin())
         lot=m_symbol.LotsMin();
      if(lot>m_symbol.LotsMax())
         lot=m_symbol.LotsMax();

      return(lot);
     }

   // Consecutive losses only inside the current open cycle.
   // Flat book (no open positions) → always 0: next entry is a fresh base leg.
   int      CountConsecutiveLosses(const bool forLongBasket) const
     {
      if(m_symbol==NULL)
         return(0);

      const datetime windowStart=ActiveCycleStart(forLongBasket);
      if(windowStart<=0)
         return(0);

      HistorySelect(0,TimeCurrent());

      int       losses=0;
      CDealInfo deal;

      for(int i=HistoryDealsTotal()-1; i>=0; i--)
        {
         const ulong ticket=HistoryDealGetTicket(i);
         if(ticket==0)
            break;

         deal.Ticket(ticket);
         if(deal.Ticket()==0)
            continue;
         if(deal.Symbol()!=m_symbol.Name())
            continue;
         if((ulong)deal.Magic()!=m_magic)
            continue;
         if(deal.Entry()!=DEAL_ENTRY_OUT)
            continue;
         if(!DealInStreakWindow(deal,windowStart))
            break;

         if(forLongBasket && !DealClosesLongBasket(deal))
            continue;
         if(!forLongBasket && !DealClosesShortBasket(deal))
            continue;

         const double profit=deal.Profit()+deal.Commission()+deal.Swap();
         if(profit>0.0)
            break;
         if(profit<0.0)
            losses++;
        }

      return(losses);
     }

   double   ApplyMartingale(const double baseLot,const bool forLongBasket) const
     {
      if(baseLot<=0.0)
         return(0.0);

      int steps=CountConsecutiveLosses(forLongBasket);
      steps=MathMin(steps,m_martingale_max_steps);
      if(steps<=0)
         return(NormalizeLot(baseLot));

      const double lot=baseLot*MathPow(m_martingale_mult,steps);
      return(NormalizeLot(lot));
     }

   // Capital used for Percent sizing. Caps growth once free margin exceeds base.
   double   SizingCapital(void) const
     {
      const double free=m_account.FreeMargin();
      if(m_sizing_base<=0.0)
         return(free);
      return(MathMin(free,m_sizing_base));
     }

   // Same math as CAccountInfo::MaxLotCheck, but uses SizingCapital() instead of FreeMargin().
   double   LotFromPercent(const ENUM_ORDER_TYPE type,const double price) const
     {
      if(m_symbol==NULL || price<=0.0 || m_percent<1.0 || m_percent>100.0)
         return(0.0);

      // No base cap → keep stock MaxLotCheck path (identical live-margin behavior).
      if(m_sizing_base<=0.0)
         return(m_account.MaxLotCheck(m_symbol.Name(),type,price,m_percent));

      double margin=0.0;
      if(!OrderCalcMargin(type,m_symbol.Name(),1.0,price,margin) || margin<=0.0)
         return(0.0);

      double volume=NormalizeDouble(SizingCapital()*m_percent/100.0/margin,2);

      const double stepvol=m_symbol.LotsStep();
      if(stepvol>0.0)
         volume=stepvol*MathFloor(volume/stepvol);

      const double minvol=m_symbol.LotsMin();
      if(volume<minvol)
         return(0.0);

      const double maxvol=m_symbol.LotsMax();
      if(volume>maxvol)
         volume=maxvol;

      return(volume);
     }

   double   BaseLotLong(const double price) const
     {
      if(m_symbol==NULL)
         return(0.0);

      const double px=(price==0.0 ? m_symbol.Ask() : price);
      return(LotFromPercent(ORDER_TYPE_BUY,px));
     }

   double   BaseLotShort(const double price) const
     {
      if(m_symbol==NULL)
         return(0.0);

      const double px=(price==0.0 ? m_symbol.Bid() : price);
      return(LotFromPercent(ORDER_TYPE_SELL,px));
     }

public:
                     CMoneyMartingale(void) : m_use_martingale(true),
                                              m_martingale_mult(2.0),
                                              m_martingale_max_steps(4),
                                              m_lot_scale(1.0),
                                              m_max_lot_cap(0.0),
                                              m_sizing_base(0.0) {}

   void              UseMartingale(const bool value)       { m_use_martingale=value; }
   void              MartingaleMult(const double value)    { m_martingale_mult=MathMax(1.0,value); }
   void              MartingaleMaxSteps(const int value)   { m_martingale_max_steps=MathMax(0,value); }
   void              LotScale(const double value)          { m_lot_scale=MathMax(0.01,value); }
   void              MaxLotCap(const double value)         { m_max_lot_cap=MathMax(0.0,value); }
   void              SizingBase(const double value)        { m_sizing_base=MathMax(0.0,value); }
   bool              IsMartingaleEnabled(void) const       { return(m_use_martingale); }
   int               MaxSteps(void) const                  { return(m_martingale_max_steps); }

   int               LossStreak(const bool isBuy) const
     {
      return(CountConsecutiveLosses(isBuy));
     }

   double            StreakRealizedPnL(const bool isBuy) const
     {
      if(m_symbol==NULL)
         return(0.0);

      const datetime windowStart=ActiveCycleStart(isBuy);
      if(windowStart<=0)
         return(0.0);

      HistorySelect(0,TimeCurrent());

      double    sum=0.0;
      CDealInfo deal;

      for(int i=HistoryDealsTotal()-1; i>=0; i--)
        {
         const ulong ticket=HistoryDealGetTicket(i);
         if(ticket==0)
            break;

         deal.Ticket(ticket);
         if(deal.Ticket()==0)
            continue;
         if(deal.Symbol()!=m_symbol.Name())
            continue;
         if((ulong)deal.Magic()!=m_magic)
            continue;
         if(deal.Entry()!=DEAL_ENTRY_OUT)
            continue;
         if(!DealInStreakWindow(deal,windowStart))
            break;

         if(isBuy && !DealClosesLongBasket(deal))
            continue;
         if(!isBuy && !DealClosesShortBasket(deal))
            continue;

         const double profit=deal.Profit()+deal.Commission()+deal.Swap();
         if(profit>0.0)
            break;
         sum+=profit;
        }

      return(sum);
     }

   double            MartingaleLotForStep(const int stepIndex,const bool isBuy) const
     {
      const double baseLot=isBuy ? BaseLotLong(0.0) : BaseLotShort(0.0);
      if(baseLot<=0.0 || m_symbol==NULL)
         return(0.0);

      if(!m_use_martingale)
         return(NormalizeLot(baseLot));

      const int steps=MathMin(MathMax(0,stepIndex),m_martingale_max_steps);
      if(steps<=0)
         return(NormalizeLot(baseLot));

      return(NormalizeLot(baseLot*MathPow(m_martingale_mult,steps)));
     }

   virtual bool      ValidationSettings(void)
     {
      if(!CMoneySizeOptimized::ValidationSettings())
         return(false);
      if(m_martingale_mult<1.0)
        {
         printf(__FUNCTION__+": martingale multiplier must be >= 1");
         return(false);
        }
      return(true);
     }

   virtual double    CheckOpenLong(double price,double sl)
     {
      const double baseLot=BaseLotLong(price);
      if(baseLot<m_symbol.LotsMin())
         return(0.0);

      if(m_use_martingale)
        {
         // Flat → streak 0 → base lot. MG sizing only via stack while a cycle is open.
         const double lot=ApplyMartingale(baseLot,true);
         const int    steps=MathMin(CountConsecutiveLosses(true),m_martingale_max_steps);
         if(steps>0)
            Print("Martingale LONG streak=",steps," mult=",DoubleToString(MathPow(m_martingale_mult,steps),2),
                  " lot=",DoubleToString(lot,2));
         return(lot);
        }

      return(Optimize(baseLot));
     }

   virtual double    CheckOpenShort(double price,double sl)
     {
      const double baseLot=BaseLotShort(price);
      if(baseLot<m_symbol.LotsMin())
         return(0.0);

      if(m_use_martingale)
        {
         const double lot=ApplyMartingale(baseLot,false);
         const int    steps=MathMin(CountConsecutiveLosses(false),m_martingale_max_steps);
         if(steps>0)
            Print("Martingale SHORT streak=",steps," mult=",DoubleToString(MathPow(m_martingale_mult,steps),2),
                  " lot=",DoubleToString(lot,2));
         return(lot);
        }

      return(Optimize(baseLot));
     }
  };

#endif
