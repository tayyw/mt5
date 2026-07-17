//+------------------------------------------------------------------+
//| ExpertMAPSARTuned.mq5                                            |
//| Tuned from ExpertMAPSARSizeOptimized for EURUSD M1               |
//+------------------------------------------------------------------+
#property copyright "MT5 MAPSAR Tuned"
#property link      "https://www.mql5.com"
#property version   "1.21"
#property description "MA+PSAR tuned + martingale stack, group exit, hedging baskets"

#include <Expert\Signal\SignalITF.mqh>
#include <Expert\Signal\SignalRSI.mqh>
#include <Expert\Trailing\TrailingParabolicSAR.mqh>
#include <ExpertMAPSAR\ExpertMAPSAR.mqh>
#include <ExpertMAPSAR\SignalMABalanced.mqh>
#include <ExpertMAPSAR\MoneyMartingale.mqh>
#include <ExpertMAPSAR\MartingaleBasket.mqh>
#include <ExpertMAPSAR\SignalSpread.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Expert ==="
input string             Inp_Expert_Title           ="ExpertMAPSARTuned";
input bool               Inp_EveryTick              =true;
input int                Inp_ThresholdOpen           =14;
input int                Inp_ThresholdOpenShort      =10;
input int                Inp_ThresholdClose          =88;

input group "=== Direction & hedging ==="
input bool               Inp_AllowLong              =true;
input bool               Inp_AllowShort             =true;
input bool               Inp_AllowHedging           =false;
input bool               Inp_InverseSignals         =false;

input group "=== Signal MA (M1 entry) ==="
input int                Inp_Signal_MA_Period        =10;
input int                Inp_Signal_MA_Shift         =3;
input ENUM_MA_METHOD     Inp_Signal_MA_Method        =MODE_EMA;
input ENUM_APPLIED_PRICE Inp_Signal_MA_Applied       =PRICE_CLOSE;
input int                Inp_Pattern_Cross           =90;
input int                Inp_Pattern_Pierce          =75;
input int                Inp_Pattern_Position        =25;

input group "=== HTF trend filter (M15) ==="
input bool               Inp_UseHTFFilter            =true;
input ENUM_TIMEFRAMES    Inp_HTF_Period              =PERIOD_M15;
input int                Inp_HTF_MA_Period           =50;
input double             Inp_HTF_Filter_Weight       =0.30;

input group "=== Session & spread ==="
input bool               Inp_UseSessionFilter        =true;
input int                Inp_SessionStartHour        =7;
input int                Inp_SessionEndHour            =20;
input bool               Inp_UseSpreadFilter         =true;
input int                Inp_MaxSpreadPoints         =18;

input group "=== RSI momentum filter ==="
input bool               Inp_UseRSIFilter            =true;
input int                Inp_RSI_Period                =14;
input double             Inp_RSI_Filter_Weight       =0.25;

input group "=== Trailing PSAR ==="
input double             Inp_Trailing_ParabolicSAR_Step    =0.014;
input double             Inp_Trailing_ParabolicSAR_Maximum =0.18;

input group "=== Money ==="
input double             Inp_Money_DecreaseFactor      =2.5;
input double             Inp_Money_Percent             =4.0;
input double             Inp_LotScale                  =1.0;
input double             Inp_MaxLotCap                 =0.0;

input group "=== Martingale ==="
input bool               Inp_UseMartingale             =true;
input double             Inp_MartingaleMult            =1.5;
input int                Inp_MartingaleMaxSteps        =3;
input bool               Inp_MG_GroupClose             =true;
input double             Inp_MG_GroupMinProfit         =0.0;
input bool               Inp_MG_AllowStack             =true;
input int                Inp_MG_StackMaxLegs           =4;
input int                Inp_MG_StackStepPoints        =120;

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
int                 Expert_MagicNumber =27894;
CExpertMAPSAR       ExtExpert;
CMartingaleBasket   g_mgBasket;
CMoneyMartingale   *g_money           =NULL;

//+------------------------------------------------------------------+
int OnInit(void)
  {
   if(!Inp_AllowLong && !Inp_AllowShort)
     {
      Print("ERROR: Both Inp_AllowLong and Inp_AllowShort are false.");
      return(INIT_FAILED);
     }

   ExtExpert.Configure(Inp_AllowLong,Inp_AllowShort,Expert_MagicNumber);
   ExtExpert.InverseSignals(Inp_InverseSignals);
   ExtExpert.AllowHedging(Inp_AllowHedging);
   ExtExpert.MartingaleGroupExits(Inp_UseMartingale && Inp_MG_GroupClose);

   if(!ExtExpert.Init(Symbol(),Period(),Inp_EveryTick,Expert_MagicNumber))
     {
      printf(__FUNCTION__+": error initializing expert");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

   CSignalMABalanced *signal=new CSignalMABalanced;
   if(signal==NULL)
     {
      printf(__FUNCTION__+": error creating signal");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

   if(!ExtExpert.InitSignal(signal))
     {
      printf(__FUNCTION__+": error initializing signal");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

   signal.ThresholdOpen(Inp_ThresholdOpen);
   signal.ThresholdOpenShort(Inp_ThresholdOpenShort);
   signal.ThresholdClose(Inp_ThresholdClose);

   signal.PeriodMA(Inp_Signal_MA_Period);
   signal.Shift(Inp_Signal_MA_Shift);
   signal.Method(Inp_Signal_MA_Method);
   signal.Applied(Inp_Signal_MA_Applied);
   signal.Pattern_0(Inp_Pattern_Position);
   signal.Pattern_1(10);
   signal.Pattern_2(Inp_Pattern_Cross);
   signal.Pattern_3(Inp_Pattern_Pierce);

   if(!signal.ValidationSettings())
     {
      printf(__FUNCTION__+": error signal parameters");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

   if(Inp_UseHTFFilter)
     {
      CSignalMA *htf=new CSignalMA;
      if(htf==NULL)
        {
         printf(__FUNCTION__+": error creating HTF filter");
         ExtExpert.Deinit();
         return(INIT_FAILED);
        }
      signal.AddFilter(htf);
      htf.Period(Inp_HTF_Period);
      htf.PeriodMA(Inp_HTF_MA_Period);
      htf.Shift(0);
      htf.Method(MODE_EMA);
      htf.Applied(PRICE_CLOSE);
      htf.Weight(Inp_HTF_Filter_Weight);
      if(!htf.ValidationSettings())
        {
         printf(__FUNCTION__+": error HTF filter parameters");
         ExtExpert.Deinit();
         return(INIT_FAILED);
        }
     }

   if(Inp_UseSessionFilter)
     {
      CSignalITF *itf=new CSignalITF;
      if(itf==NULL)
        {
         printf(__FUNCTION__+": error creating session filter");
         ExtExpert.Deinit();
         return(INIT_FAILED);
        }
      signal.AddFilter(itf);
      itf.GoodHourOfDay(-1);
      itf.BadHoursOfDay(BuildBadHoursMask(Inp_SessionStartHour,Inp_SessionEndHour));
      itf.GoodDayOfWeek(-1);
      itf.BadDaysOfWeek(0);
      itf.Weight(1.0);
     }

   if(Inp_UseSpreadFilter)
     {
      CSignalSpread *spread=new CSignalSpread;
      if(spread==NULL)
        {
         printf(__FUNCTION__+": error creating spread filter");
         ExtExpert.Deinit();
         return(INIT_FAILED);
        }
      signal.AddFilter(spread);
      spread.MaxSpreadPoints(Inp_MaxSpreadPoints);
      spread.Weight(1.0);
     }

   if(Inp_UseRSIFilter)
     {
      CSignalRSI *rsi=new CSignalRSI;
      if(rsi==NULL)
        {
         printf(__FUNCTION__+": error creating RSI filter");
         ExtExpert.Deinit();
         return(INIT_FAILED);
        }
      signal.AddFilter(rsi);
      rsi.PeriodRSI(Inp_RSI_Period);
      rsi.Applied(PRICE_CLOSE);
      rsi.Weight(Inp_RSI_Filter_Weight);
      if(!rsi.ValidationSettings())
        {
         printf(__FUNCTION__+": error RSI filter parameters");
         ExtExpert.Deinit();
         return(INIT_FAILED);
        }
     }

   CTrailingPSAR *trailing=new CTrailingPSAR;
   if(trailing==NULL)
     {
      printf(__FUNCTION__+": error creating trailing");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

   if(!ExtExpert.InitTrailing(trailing))
     {
      printf(__FUNCTION__+": error initializing trailing");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

   trailing.Step(Inp_Trailing_ParabolicSAR_Step);
   trailing.Maximum(Inp_Trailing_ParabolicSAR_Maximum);

   if(!trailing.ValidationSettings())
     {
      printf(__FUNCTION__+": error trailing parameters");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

   g_money=new CMoneyMartingale;
   if(g_money==NULL)
     {
      printf(__FUNCTION__+": error creating money");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

   if(!ExtExpert.InitMoney(g_money))
     {
      printf(__FUNCTION__+": error initializing money");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

   g_money.DecreaseFactor(Inp_Money_DecreaseFactor);
   g_money.Percent(Inp_Money_Percent);
   g_money.LotScale(Inp_LotScale);
   g_money.MaxLotCap(Inp_MaxLotCap);
   g_money.UseMartingale(Inp_UseMartingale);
   g_money.MartingaleMult(Inp_MartingaleMult);
   g_money.MartingaleMaxSteps(Inp_MartingaleMaxSteps);

   g_mgBasket.Init(Symbol(),Expert_MagicNumber,Period(),g_money,
                   Inp_UseMartingale && Inp_MG_GroupClose,
                   Inp_UseMartingale && Inp_MG_AllowStack,
                   Inp_MG_GroupMinProfit,Inp_MG_StackMaxLegs,Inp_MG_StackStepPoints);

   if(!g_money.ValidationSettings())
     {
      printf(__FUNCTION__+": error money parameters");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

   if(!ExtExpert.InitIndicators())
     {
      printf(__FUNCTION__+": error initializing indicators");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

   const long tradeMode=SymbolInfoInteger(Symbol(),SYMBOL_TRADE_MODE);
   if(Inp_AllowShort && tradeMode==SYMBOL_TRADE_MODE_LONGONLY)
      Print("WARN: Symbol is LONGONLY — shorts will fail.");
   if(Inp_AllowLong && tradeMode==SYMBOL_TRADE_MODE_SHORTONLY)
      Print("WARN: Symbol is SHORTONLY — longs will fail.");
   if(Inp_AllowHedging)
     {
      const long marginMode=AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(marginMode!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
         Print("WARN: Inp_AllowHedging needs a hedging account (retail hedging).");
     }

   Print(Inp_Expert_Title," init OK | ",Symbol()," ",EnumToString(Period()),
         " | L=",Inp_AllowLong," S=",Inp_AllowShort,
         " | hedge=",Inp_AllowHedging,
         (Inp_InverseSignals ? " | INVERSE ON (long sig→SELL, short sig→BUY)" : ""),
         " | thresh L=",Inp_ThresholdOpen," S=",Inp_ThresholdOpenShort,
         " | money ",Inp_Money_Percent,"% scale=",Inp_LotScale,
         (Inp_UseMartingale ? StringFormat(" | MG %.1fx",Inp_MartingaleMult) : ""));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ExtExpert.Deinit();
  }

//+------------------------------------------------------------------+
void OnTick(void)
  {
   if(Inp_UseMartingale)
      g_mgBasket.Update();

   ExtExpert.OnTick();

   if(Inp_UseMartingale)
      g_mgBasket.Update();
  }

//+------------------------------------------------------------------+
void OnTrade(void)
  {
   ExtExpert.OnTrade();
  }

//+------------------------------------------------------------------+
void OnTimer(void)
  {
   ExtExpert.OnTimer();
  }
//+------------------------------------------------------------------+
