//+------------------------------------------------------------------+
//| ExpertMAPSAR.mqh — hedging, inverse, long/short allow flags       |
//+------------------------------------------------------------------+
#ifndef EXPERT_MAPSAR_MQH
#define EXPERT_MAPSAR_MQH

#include <Expert\Expert.mqh>
#include <Trade\PositionInfo.mqh>

class CExpertMAPSAR : public CExpert
  {
private:
   bool     m_allow_long;
   bool     m_allow_short;
   bool     m_allow_hedging;
   bool     m_inverse;
   bool     m_mg_group_exits;   // martingale basket owns exits (skip signal close)
   bool     m_no_new_entries;   // block signal entries; MG stack/exits still run
   ulong    m_magic_number;

   // Churn guard: after a trail/SL (or any) exit, block signal re-entry for N bars.
   // Stops the common MAPSAR loop: PSAR stops leg-1 on trend flip → MA still hot → reopen poorly.
   int      m_churn_cooldown_bars;
   bool     m_churn_same_dir_only;
   bool     m_churn_sl_exits_only;
   datetime m_churn_until_buy;
   datetime m_churn_until_sell;

   bool     HasSidePosition(const bool isBuy) const
     {
      CPositionInfo pos;
      for(int i=PositionsTotal()-1; i>=0; i--)
        {
         if(!pos.SelectByIndex(i))
            continue;
         if(pos.Symbol()!=m_symbol.Name())
            continue;
         if((ulong)pos.Magic()!=m_magic)
            continue;

         const bool legBuy=(pos.PositionType()==POSITION_TYPE_BUY);
         if(legBuy==isBuy)
            return(true);
        }
      return(false);
     }

   bool     HasAnyPosition(void) const
     {
      return(HasSidePosition(true) || HasSidePosition(false));
     }

   void     MirrorStopsForShort(const double signalPrice,const double signalSL,const double signalTP,
                                double &outSL,double &outTP) const
     {
      const double entry=m_symbol.Bid();
      outSL=0.0;
      outTP=0.0;
      if(signalSL>0.0 && signalPrice>0.0)
         outSL=entry+(signalPrice-signalSL);
      if(signalTP>0.0 && signalPrice>0.0)
         outTP=entry-(signalTP-signalPrice);
     }

   void     MirrorStopsForLong(const double signalPrice,const double signalSL,const double signalTP,
                               double &outSL,double &outTP) const
     {
      const double entry=m_symbol.Ask();
      outSL=0.0;
      outTP=0.0;
      if(signalSL>0.0 && signalPrice>0.0)
         outSL=entry-(signalSL-signalPrice);
      if(signalTP>0.0 && signalPrice>0.0)
         outTP=entry+(signalPrice-signalTP);
     }

   bool     OpenInvertedFromLongSignal(void)
     {
      double     price=EMPTY_VALUE;
      double     sl=0.0;
      double     tp=0.0;
      datetime   expiration=TimeCurrent();

      if(!m_signal.CheckOpenLong(price,sl,tp,expiration))
         return(false);

      if(!m_trade.SetOrderExpiration(expiration))
         m_expiration=expiration;

      if(price==EMPTY_VALUE)
         return(false);

      const double lot=LotOpenLong(price,sl);
      if(lot==0.0)
         return(false);

      double useSL=0.0;
      double useTP=0.0;
      MirrorStopsForShort(price,sl,tp,useSL,useTP);

      const bool ok=m_trade.Sell(lot,0.0,useSL,useTP,"INV");
      if(ok)
         Print("INVERSE: long signal → SELL lot=",DoubleToString(lot,2));
      else
         Print("INVERSE: long signal → SELL failed: ",m_trade.ResultRetcode()," ",
               m_trade.ResultRetcodeDescription());
      return(ok);
     }

   bool     OpenInvertedFromShortSignal(void)
     {
      double     price=EMPTY_VALUE;
      double     sl=0.0;
      double     tp=0.0;
      datetime   expiration=TimeCurrent();

      if(!m_signal.CheckOpenShort(price,sl,tp,expiration))
         return(false);

      if(!m_trade.SetOrderExpiration(expiration))
         m_expiration=expiration;

      if(price==EMPTY_VALUE)
         return(false);

      const double lot=LotOpenShort(price,sl);
      if(lot==0.0)
         return(false);

      double useSL=0.0;
      double useTP=0.0;
      MirrorStopsForLong(price,sl,tp,useSL,useTP);

      const bool ok=m_trade.Buy(lot,0.0,useSL,useTP,"INV");
      if(ok)
         Print("INVERSE: short signal → BUY lot=",DoubleToString(lot,2));
      else
         Print("INVERSE: short signal → BUY failed: ",m_trade.ResultRetcode()," ",
               m_trade.ResultRetcodeDescription());
      return(ok);
     }

public:
                     CExpertMAPSAR(void) : m_allow_long(true),
                                           m_allow_short(true),
                                           m_allow_hedging(false),
                                           m_inverse(false),
                                           m_mg_group_exits(false),
                                           m_no_new_entries(false),
                                           m_magic_number(0),
                                           m_churn_cooldown_bars(0),
                                           m_churn_same_dir_only(true),
                                           m_churn_sl_exits_only(true),
                                           m_churn_until_buy(0),
                                           m_churn_until_sell(0) {}

   void              Configure(const bool allowLong,const bool allowShort,const ulong magic)
     {
      m_allow_long=allowLong;
      m_allow_short=allowShort;
      m_magic_number=magic;
     }

   void              AllowLong(const bool value)     { m_allow_long=value; }
   void              AllowShort(const bool value)    { m_allow_short=value; }
   void              AllowHedging(const bool value)  { m_allow_hedging=value; }
   void              InverseSignals(const bool value){ m_inverse=value; }
   void              MartingaleGroupExits(const bool value){ m_mg_group_exits=value; }
   void              NoNewEntries(const bool value)  { m_no_new_entries=value; }
   void              ChurnCooldownBars(const int bars){ m_churn_cooldown_bars=MathMax(0,bars); }
   void              ChurnSameDirOnly(const bool value){ m_churn_same_dir_only=value; }
   void              ChurnSlExitsOnly(const bool value){ m_churn_sl_exits_only=value; }
   bool              AllowHedging(void) const        { return(m_allow_hedging); }
   bool              NoNewEntries(void) const        { return(m_no_new_entries); }
   int               ChurnCooldownBars(void) const   { return(m_churn_cooldown_bars); }

   // Call from OnTradeTransaction on DEAL_ENTRY_OUT for our magic.
   // exitedBuy = position that closed was a BUY; fromSL = DEAL_REASON_SL / SO.
   void              ArmChurnCooldown(const bool exitedBuy,const bool fromSL)
     {
      if(m_churn_cooldown_bars<=0)
         return;
      if(m_churn_sl_exits_only && !fromSL)
         return;

      const int periodSec=PeriodSeconds(m_period);
      if(periodSec<=0)
         return;

      const datetime until=TimeCurrent()+(datetime)(periodSec*m_churn_cooldown_bars);

      if(m_churn_same_dir_only)
        {
         if(exitedBuy)
            m_churn_until_buy=until;
         else
            m_churn_until_sell=until;
        }
      else
        {
         m_churn_until_buy=until;
         m_churn_until_sell=until;
        }

      Print("CHURN COOLDOWN: block ",
            (m_churn_same_dir_only ? (exitedBuy ? "BUY" : "SELL") : "BOTH"),
            " until ",TimeToString(until,TIME_DATE|TIME_SECONDS),
            " (",m_churn_cooldown_bars," bars",
            (fromSL ? ", SL/trail" : ", exit"),")");
     }

   bool              InChurnCooldown(const bool openingBuy) const
     {
      if(m_churn_cooldown_bars<=0)
         return(false);
      const datetime now=TimeCurrent();
      if(openingBuy)
         return(now<m_churn_until_buy);
      return(now<m_churn_until_sell);
     }

   // When MG group-close is on, skip signal exits so a side can stack to
   // StackMaxLegs and leave via basket recovery. Money emergency close still runs.
   virtual bool      CheckClose(void)
     {
      double lot=0.0;
      if((lot=m_money.CheckClose(GetPointer(m_position)))!=0.0)
         return(CloseAll(lot));

      if(m_mg_group_exits)
         return(false);

      if(m_position.PositionType()==POSITION_TYPE_BUY)
        {
         if(CheckCloseLong())
           {
            DeleteOrdersLong();
            return(true);
           }
        }
      else
        {
         if(CheckCloseShort())
           {
            DeleteOrdersShort();
            return(true);
           }
        }
      return(false);
     }

   // Guard the position side that will actually be opened.
   // Normal:  long signal → buy,  short signal → sell
   // Inverse: long signal → sell, short signal → buy
   // Without this, inverse+hedge floods buys: CheckOpenShort only blocked on
   // existing sells, then OpenInvertedFromShortSignal kept buying every tick.
   bool              CanOpenPositionSide(const bool openingBuy) const
     {
      if(InChurnCooldown(openingBuy))
         return(false);

      if(openingBuy)
        {
         if(!m_allow_long)
            return(false);
         if(HasSidePosition(true))
            return(false);
         if(!m_allow_hedging && HasSidePosition(false))
            return(false);
        }
      else
        {
         if(!m_allow_short)
            return(false);
         if(HasSidePosition(false))
            return(false);
         if(!m_allow_hedging && HasSidePosition(true))
            return(false);
        }
      return(true);
     }

   virtual bool      CheckOpenLong(void)
     {
      // Long signal path → buy normally, sell when inverse
      if(!CanOpenPositionSide(!m_inverse))
         return(false);

      if(!m_inverse)
         return(CExpert::CheckOpenLong());

      return(OpenInvertedFromLongSignal());
     }

   virtual bool      CheckOpenShort(void)
     {
      // Short signal path → sell normally, buy when inverse
      if(!CanOpenPositionSide(m_inverse))
         return(false);

      if(!m_inverse)
         return(CExpert::CheckOpenShort());

      return(OpenInvertedFromShortSignal());
     }

   virtual bool      CheckOpen(void)
     {
      // Signal / inverse first legs only — MartingaleBasket stacks still run in OnTick.
      if(m_no_new_entries)
         return(false);

      bool opened=false;

      if(CheckOpenLong())
         opened=true;
      if(CheckOpenShort())
         opened=true;

      return(opened);
     }

   virtual bool      CheckReverse(void)
     {
      if(m_no_new_entries || m_inverse || m_allow_hedging)
         return(false);
      if(m_allow_long && m_allow_short)
         return(CExpert::CheckReverse());
      return(false);
     }

   virtual bool      Processing(void)
     {
      if(!m_allow_hedging)
         return(CExpert::Processing());

      // Same as CExpert::Processing — without this, m_direction stays EMPTY_VALUE
      // and CheckOpenLong / CheckClose* never fire. CheckOpenShort still worked only
      // because SignalMABalanced recomputes Direction() itself (short bias).
      m_signal.SetDirection();

      bool result=false;

      CPositionInfo scan;
      ulong tickets[];
      int count=0;

      for(int i=0; i<PositionsTotal(); i++)
        {
         if(!scan.SelectByIndex(i))
            continue;
         if(scan.Symbol()!=m_symbol.Name())
            continue;
         if((ulong)scan.Magic()!=m_magic)
            continue;

         ArrayResize(tickets,count+1);
         tickets[count]=scan.Ticket();
         count++;
        }

      for(int j=0; j<count; j++)
        {
         if(!m_position.SelectByTicket(tickets[j]))
            continue;

         if(CheckClose())
           {
            result=true;
            continue;
           }

         if(CheckTrailingStop())
            result=true;
        }

      if(CheckOpen())
         result=true;

      return(result);
     }
  };

#endif
