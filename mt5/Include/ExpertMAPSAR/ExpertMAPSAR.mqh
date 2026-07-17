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
   ulong    m_magic_number;

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

      return(m_trade.Sell(lot,0.0,useSL,useTP,"INV"));
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

      return(m_trade.Buy(lot,0.0,useSL,useTP,"INV"));
     }

public:
                     CExpertMAPSAR(void) : m_allow_long(true),
                                           m_allow_short(true),
                                           m_allow_hedging(false),
                                           m_inverse(false),
                                           m_magic_number(0) {}

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
   bool              AllowHedging(void) const        { return(m_allow_hedging); }

   // Guard the position side that will actually be opened.
   // Normal:  long signal → buy,  short signal → sell
   // Inverse: long signal → sell, short signal → buy
   bool     CanOpenPositionSide(const bool openingBuy) const
     {
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
      bool opened=false;

      if(CheckOpenLong())
         opened=true;
      if(CheckOpenShort())
         opened=true;

      return(opened);
     }

   virtual bool      CheckReverse(void)
     {
      if(m_inverse || m_allow_hedging)
         return(false);
      if(m_allow_long && m_allow_short)
         return(CExpert::CheckReverse());
      return(false);
     }

   virtual bool      Processing(void)
     {
      if(!m_allow_hedging)
         return(CExpert::Processing());

      // Same as CExpert::Processing — CheckOpenLong uses cached m_direction.
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
