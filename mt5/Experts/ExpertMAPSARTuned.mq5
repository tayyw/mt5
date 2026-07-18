//+------------------------------------------------------------------+
//| ExpertMAPSARTuned.mq5                                            |
//| Tuned from ExpertMAPSARSizeOptimized for EURUSD M1               |
//+------------------------------------------------------------------+
#property copyright "MT5 MAPSAR Tuned"
#property link      "https://www.mql5.com"
#property version   "1.24"
#property description "MA+PSAR tuned + martingale stack, group exit, hedging baskets, basket aborts"

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
input bool               Inp_NoNewEntries           =false; // Block new signal entries; MG stack/exit only

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

input group "=== Martingale aborts ==="
input double             Inp_MG_MaxBasketLossPct       =2.0;  // Close side if floating loss >= % equity (0=off)
input double             Inp_MG_AbortATRMult           =3.0;  // Close if adverse from 1st leg >= mult*ATR (0=off)
input int                Inp_MG_AbortATRPeriod         =14;
input int                Inp_MG_AbortMaxBars           =48;   // Close if age>=bars and never touched BE (0=off)

input group "=== Tester withdrawals ==="
input bool               Inp_SimulateWithdrawals       =false; // Tester only: pull profit milestones
input double             Inp_WithdrawEvery             =1000.0; // Withdraw this amount each time balance is +step above baseline

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
int                 Expert_MagicNumber =27894;
CExpertMAPSAR       ExtExpert;
CMartingaleBasket   g_mgBasket;
CMoneyMartingale   *g_money           =NULL;
double              g_withdraw_baseline=0.0;
double              g_withdrawn_total  =0.0;

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
   ExtExpert.NoNewEntries(Inp_NoNewEntries);

   g_withdraw_baseline=AccountInfoDouble(ACCOUNT_BALANCE);
   g_withdrawn_total=0.0;
   if(Inp_SimulateWithdrawals)
     {
      if(!MQLInfoInteger(MQL_TESTER))
         Print("WARN: SimulateWithdrawals only works in Strategy Tester (TesterWithdrawal).");
      if(Inp_WithdrawEvery<=0.0)
        {
         Print("ERROR: Inp_WithdrawEvery must be > 0");
         return(INIT_FAILED);
        }
     }

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
                   Inp_MG_GroupMinProfit,Inp_MG_StackMaxLegs,Inp_MG_StackStepPoints,
                   Inp_MG_MaxBasketLossPct,Inp_MG_AbortATRMult,
                   Inp_MG_AbortATRPeriod,Inp_MG_AbortMaxBars);

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
         (Inp_NoNewEntries ? " | NO NEW ENTRIES (MG manage only)" : ""),
         " | thresh L=",Inp_ThresholdOpen," S=",Inp_ThresholdOpenShort,
         " | money ",Inp_Money_Percent,"% scale=",Inp_LotScale,
         (Inp_UseMartingale ? StringFormat(" | MG %.1fx",Inp_MartingaleMult) : ""),
         (Inp_UseMartingale ? StringFormat(" | abort loss=%.1f%% atr=%.1fx bars=%d",
                                           Inp_MG_MaxBasketLossPct,Inp_MG_AbortATRMult,Inp_MG_AbortMaxBars) : ""),
         (Inp_SimulateWithdrawals ? StringFormat(" | WD every %.0f (base=%.2f)",Inp_WithdrawEvery,g_withdraw_baseline) : ""));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
bool HasOurPosition(void)
  {
   CPositionInfo pos;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(!pos.SelectByIndex(i))
         continue;
      if(pos.Symbol()!=_Symbol)
         continue;
      if((ulong)pos.Magic()!= (ulong)Expert_MagicNumber)
         continue;
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| When balance is +WithdrawEvery above baseline, pull that amount. |
//| Only flat (no EA positions) so floating DD can't block margin.   |
//+------------------------------------------------------------------+
void TrySimulateWithdrawals(void)
  {
   if(!Inp_SimulateWithdrawals)
      return;
   if(!MQLInfoInteger(MQL_TESTER))
      return;
   if(Inp_WithdrawEvery<=0.0)
      return;
   if(HasOurPosition())
      return;

   // e.g. base 10k → at 11k withdraw 1k (balance≈10k); at 11k again withdraw again.
   while(AccountInfoDouble(ACCOUNT_BALANCE) - g_withdraw_baseline >= Inp_WithdrawEvery)
     {
      const double bal=AccountInfoDouble(ACCOUNT_BALANCE);
      const double free=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(free < Inp_WithdrawEvery)
        {
         Print("WD skip: free margin ",DoubleToString(free,2),
               " < ",DoubleToString(Inp_WithdrawEvery,2));
         break;
        }
      if(!TesterWithdrawal(Inp_WithdrawEvery))
        {
         Print("WD failed: ",GetLastError()," bal=",DoubleToString(bal,2));
         break;
        }
      g_withdrawn_total+=Inp_WithdrawEvery;
      Print("WD ",DoubleToString(Inp_WithdrawEvery,2),
            " | bal ",DoubleToString(bal,2)," → ",DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2),
            " | total WD=",DoubleToString(g_withdrawn_total,2));
     }
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(Inp_SimulateWithdrawals && MQLInfoInteger(MQL_TESTER))
      Print("WD summary: withdrawn=",DoubleToString(g_withdrawn_total,2),
            " | tester STAT_WITHDRAWAL=",DoubleToString(TesterStatistics(STAT_WITHDRAWAL),2));
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

   TrySimulateWithdrawals();
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
