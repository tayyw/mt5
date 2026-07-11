//+------------------------------------------------------------------+
//|                                        CloseHedgeEAPositions.mq4 |
//| Close all positions opened by HedgeTradingEA (by magic number)   |
//+------------------------------------------------------------------+
#property copyright "OpenClaw"
#property strict

input int InpMagicNumber = 202502;  // Magic number (must match EA)
input int InpSlippage    = 30;     // Slippage (points)

//+------------------------------------------------------------------+
//| Script program start                                              |
//+------------------------------------------------------------------+
void OnStart()
{
   int closed = 0;
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if (OrderMagicNumber() != InpMagicNumber) continue;
      if (OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      double price = (OrderType() == OP_BUY) ? MarketInfo(OrderSymbol(), MODE_BID) : MarketInfo(OrderSymbol(), MODE_ASK);
      bool ok = OrderClose(OrderTicket(), OrderLots(), price, InpSlippage, clrNONE);
      if (ok) closed++; else Sleep(200);
      RefreshRates();
   }
   Alert("CloseHedgeEAPositions: closed ", closed, " order(s). Magic=", InpMagicNumber);
}

//+------------------------------------------------------------------+
