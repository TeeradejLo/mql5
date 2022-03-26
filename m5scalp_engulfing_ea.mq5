//+------------------------------------------------------------------+
//|                                         m5scalp_engulfing_ea.mq5 |
//|                                  Copyright 2022, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2022, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

input int tppips = 20; //Take Profit (in pips)
input int slpips = 10; //Stop Loss (in pips)

int MagicNumber = 123;

int handlerFastMA = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_SMMA, PRICE_CLOSE);
int handlerMidMA = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_SMMA, PRICE_CLOSE);
int handlerSlowMA = iMA(_Symbol, PERIOD_CURRENT, 200, 0, MODE_SMMA, PRICE_CLOSE);

CTrade trade;

double FindLotSize(int stopLossPips, double riskPercentage) {
   // e.g. £10 = £1000 * 1%
   double maxRiskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * riskPercentage / 100;

   // e.g. 20 pence = £10 / 50
   double riskPerPip = maxRiskAmount / stopLossPips;

   double pipValue = 10 * SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double lot = riskPerPip / pipValue;

   // _numberOfDecimal is based on the min_lot e.g. 2 if min lot is 0.01
   int lotdigits   = (int) - MathLog10(SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP));
   return NormalizeDouble(lot, lotdigits);
}

double takeProfitPrice (int pips, double currPrice, ENUM_ORDER_TYPE order) {

   if (order == ORDER_TYPE_BUY) {
      return currPrice + pips * 10 * SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   }

   if (order == ORDER_TYPE_SELL) {
      return currPrice - pips * 10 * SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   }

   return 0;
}

double stopLossPrice (int pips, double currPrice, ENUM_ORDER_TYPE order) {

   if (order == ORDER_TYPE_BUY) {
      return currPrice - pips * 10 * SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   }

   if (order == ORDER_TYPE_SELL) {
      return currPrice + pips * 10 * SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   }

   return 0;
}

void ApplyTrailingSL() {
    double buysl = stopLossPrice(slpips, SymbolInfoDouble(_Symbol, SYMBOL_ASK), ORDER_TYPE_BUY);
    double sellsl = stopLossPrice(slpips, SymbolInfoDouble(_Symbol, SYMBOL_BID), ORDER_TYPE_SELL);

    int count = PositionsTotal();
    for (int i = count-1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);

      if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
         if (buysl > PositionGetDouble(POSITION_PRICE_OPEN) && buysl > PositionGetDouble(POSITION_SL)) {
            trade.PositionModify(ticket, buysl, PositionGetDouble(POSITION_TP));
         }
         continue;
      }
      if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
         if (sellsl < PositionGetDouble(POSITION_PRICE_OPEN) && sellsl < PositionGetDouble(POSITION_SL)) {
            trade.PositionModify(ticket, sellsl, PositionGetDouble(POSITION_TP));
         }
      }
    }
}

bool isbullengulfing() {
   double open1  = iOpen(Symbol(),Period(), 2);
   double close1 = iClose(NULL,PERIOD_CURRENT, 2);
   double open2  = iOpen(Symbol(),Period(), 1);
   double close2 = iClose(NULL,PERIOD_CURRENT, 1);

   if (open1 > close1) {
      if (close2 > open1) {
         return true;
      } else {
         return false;
      }
   }

   return false;
}

bool isbearengulfing() {
   double open1  = iOpen(Symbol(),Period(), 2);
   double close1 = iClose(NULL,PERIOD_CURRENT, 2);
   double open2  = iOpen(Symbol(),Period(), 1);
   double close2 = iClose(NULL,PERIOD_CURRENT, 1);

   if (open1 < close1) {
      if (close2 < open1) {
         return true;
      } else {
         return false;
      }
   }

   return false;
}

bool isbulltrend() {
   double fastMAbuffer[];
   CopyBuffer(handlerFastMA, 0, 1, 20, fastMAbuffer);
   ArraySetAsSeries(fastMAbuffer, true);

   double midMAbuffer[];
   CopyBuffer(handlerMidMA, 0, 1, 20, midMAbuffer);
   ArraySetAsSeries(midMAbuffer, true);

   double slowMAbuffer[];
   CopyBuffer(handlerSlowMA, 0, 1, 20, slowMAbuffer);
   ArraySetAsSeries(slowMAbuffer, true);

   for (int i = 0; i < 20; i++) {
      if (fastMAbuffer[i] > midMAbuffer[i] && midMAbuffer[i] > slowMAbuffer[i]) {
         continue;
      }
      return false;
   }
   return true;
}

bool isbeartrend() {
   double fastMAbuffer[];
   CopyBuffer(handlerFastMA, 0, 1, 20, fastMAbuffer);
   ArraySetAsSeries(fastMAbuffer, true);

   double midMAbuffer[];
   CopyBuffer(handlerMidMA, 0, 1, 20, midMAbuffer);
   ArraySetAsSeries(midMAbuffer, true);

   double slowMAbuffer[];
   CopyBuffer(handlerSlowMA, 0, 1, 20, slowMAbuffer);
   ArraySetAsSeries(slowMAbuffer, true);

   for (int i = 0; i < 20; i++) {
      if (fastMAbuffer[i] < midMAbuffer[i] && midMAbuffer[i] < slowMAbuffer[i]) {
         continue;
      }
      return false;
   }
   return true;
}

bool isMAsteep() {
   double fastMAbuffer[];
   CopyBuffer(handlerFastMA, 0, 1, 5, fastMAbuffer);
   ArraySetAsSeries(fastMAbuffer, true);

   if (MathAbs((fastMAbuffer[4] - fastMAbuffer[0])) > 30 * SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE)) {
      return true;
   }
   return false;
}

bool rsiAbove50() {
   int handlerRSI = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
   double rsibuffer[];
   CopyBuffer(handlerRSI, 0, 1, 1, rsibuffer);
   ArraySetAsSeries(rsibuffer, true);

   if (rsibuffer[0] > 50) {
      return true;
   } else {
      return false;
   }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetAsyncMode(true);

   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{


}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime timestamp = 0;
   datetime curr_time = iTime(_Symbol, PERIOD_CURRENT, 0);

   if (timestamp != curr_time) {
      timestamp = curr_time;

      if (PositionsTotal() < 1) {
         if (isbulltrend()) {
            if (isbullengulfing() && rsiAbove50() && isMAsteep()) {
               double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               double sl = stopLossPrice(slpips, ask, ORDER_TYPE_BUY);
               double tp = takeProfitPrice(tppips, ask, ORDER_TYPE_BUY);
               trade.Buy(FindLotSize(slpips, 1), _Symbol, ask, sl, tp, "BUY");
            }
         }
         if (isbeartrend()) {
            if (isbearengulfing() && !rsiAbove50() && isMAsteep()) {
               double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               double sl = stopLossPrice(slpips, bid, ORDER_TYPE_SELL);
               double tp = takeProfitPrice(tppips, bid, ORDER_TYPE_SELL);
               trade.Sell(FindLotSize(slpips, 1), _Symbol, bid, sl, tp, "SELL");
            }
         }
       }
   }
}
//+------------------------------------------------------------------+
