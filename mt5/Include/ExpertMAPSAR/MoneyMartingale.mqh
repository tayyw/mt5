//+------------------------------------------------------------------+
//| MoneyMartingale.mqh — SizeOptimized + optional loss-streak MG     |
//+------------------------------------------------------------------+
#ifndef MONEY_MARTINGALE_MQH
#define MONEY_MARTINGALE_MQH

#include <Expert\Money\MoneySizeOptimized.mqh>
#include <Trade\DealInfo.mqh>

class CMoneyMartingale : public CMoneySizeOptimized
  {
protected:
   bool     m_use_martingale;
   double   m_martingale_mult;
   int      m_martingale_max_steps;
   double   m_lot_scale;
   double   m_max_lot_cap;

   static bool DealClosesLongBasket(const CDealInfo &deal)
     {
      return(deal.Entry()==DEAL_ENTRY_OUT && deal.DealType()==DEAL_TYPE_SELL);
     }

   static bool DealClosesShortBasket(const CDealInfo &deal)
     {
      return(deal.Entry()==DEAL_ENTRY_OUT && deal.DealType()==DEAL_TYPE_BUY);
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

   int      CountConsecutiveLosses(const bool forLongBasket) const
     {
      if(m_symbol==NULL)
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

   double   BaseLotLong(const double price) const
     {
      if(m_symbol==NULL)
         return(0.0);

      if(price==0.0)
         return(m_account.MaxLotCheck(m_symbol.Name(),ORDER_TYPE_BUY,m_symbol.Ask(),m_percent));
      return(m_account.MaxLotCheck(m_symbol.Name(),ORDER_TYPE_BUY,price,m_percent));
     }

   double   BaseLotShort(const double price) const
     {
      if(m_symbol==NULL)
         return(0.0);

      if(price==0.0)
         return(m_account.MaxLotCheck(m_symbol.Name(),ORDER_TYPE_SELL,m_symbol.Bid(),m_percent));
      return(m_account.MaxLotCheck(m_symbol.Name(),ORDER_TYPE_SELL,price,m_percent));
     }

public:
                     CMoneyMartingale(void) : m_use_martingale(true),
                                              m_martingale_mult(2.0),
                                              m_martingale_max_steps(4),
                                              m_lot_scale(1.0),
                                              m_max_lot_cap(0.0) {}

   void              UseMartingale(const bool value)       { m_use_martingale=value; }
   void              MartingaleMult(const double value)    { m_martingale_mult=MathMax(1.0,value); }
   void              MartingaleMaxSteps(const int value)   { m_martingale_max_steps=MathMax(0,value); }
   void              LotScale(const double value)          { m_lot_scale=MathMax(0.01,value); }
   void              MaxLotCap(const double value)         { m_max_lot_cap=MathMax(0.0,value); }
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

   virtual double    CheckOpenLong(const double price,const double sl)
     {
      const double baseLot=BaseLotLong(price);
      if(baseLot<m_symbol.LotsMin())
         return(0.0);

      if(m_use_martingale)
        {
         const double lot=ApplyMartingale(baseLot,true);
         const int    steps=MathMin(CountConsecutiveLosses(true),m_martingale_max_steps);
         if(steps>0)
            Print("Martingale LONG streak=",steps," mult=",DoubleToString(MathPow(m_martingale_mult,steps),2),
                  " lot=",DoubleToString(lot,2));
         return(lot);
        }

      return(Optimize(baseLot));
     }

   virtual double    CheckOpenShort(const double price,const double sl)
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
