//+------------------------------------------------------------------+
//|                                                 insidebar_ea.mq5 |
//|                                  Copyright 2022, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2022, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include<Trade/Trade.mqh>

input double risk_percent = 1;
input ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT;
input ENUM_APPLIED_PRICE applied_price = PRICE_CLOSE;

input double entry_factor = 0.1;
input double tp_factor = 0.8;
input double sl_factor = 0.4;
input int order_expire_hour = 12;
input int candle_size = 5;
input int candle_body_percent = 60;

CTrade trade;

int magic_number = 124;
int handle_slow_ma;
int total_bars;

/*
   TODO:
      Spread check
      Margin check
      Market Close Period check -> Clear all pending order?
      Lot Size Correction -> Currency Conversion
      Equity sometime = 0 -> check connection?

   Added:
      Candle body ratio and size
      Check 2 previous high (unused)
*/

double priceToPips (double price1, double price2) {
   double price_dist = NormalizeDouble(MathAbs(price1 - price2), _Digits);

   //price_dist / pip_size
   double pips = NormalizeDouble(price_dist / (10 * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE)), 2);

   if (pips > 0) {
      return pips;
   } else {
      return -1;
   }
}

double findLotSize(double stopLossPips, double riskPercentage) {
   if (stopLossPips <= 0) {
      return -1;
   }

   double maxRiskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * riskPercentage / 100;

   double riskPerPip = maxRiskAmount / stopLossPips;

   double pipValue = 10 * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   Print("Pip Val.: ", pipValue);

   double lot = riskPerPip / pipValue;

   // _numberOfDecimal is based on the min_lot e.g. 2 if min lot is 0.01
   int lotdigits   = (int) - MathLog10(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP));
   return NormalizeDouble(lot, lotdigits);
}

bool signalInsideBar(ENUM_ORDER_TYPE order) {
   double open1  = iOpen(_Symbol, timeframe, 2);
   double close1 = iClose(_Symbol, timeframe, 2);

   double high1  = iHigh(_Symbol, timeframe, 2);
   double low1 = iLow(_Symbol, timeframe, 2);
   double high2  = iHigh(_Symbol, timeframe, 1);
   double low2 = iLow(_Symbol, timeframe, 1);

   if (MathAbs(open1 - close1)/MathAbs(high1 - low1) * 100 < candle_body_percent) {
      return false;
   }

   if (priceToPips(open1, close1) < candle_size) {
      return false;
   }

   if(order == ORDER_TYPE_BUY) {
      if (open1 >= close1) {
         return false;
      }

      if (high1 > high2 && low1 < low2) {
         return true;
      }

      return false;
   } else if(order == ORDER_TYPE_SELL) {
      if (open1 <= close1) {
         return false;
      }

      if (high1 > high2 && low1 < low2) {
         return true;
      }

      return false;
   }

   return false;
}

double calcEntryPrice(ENUM_ORDER_TYPE order, double high, double low) {
   double range = high - low;

   if(order == ORDER_TYPE_BUY) {
      return NormalizeDouble(high + entry_factor * range, _Digits);
   } else if(order == ORDER_TYPE_SELL) {
      return NormalizeDouble(low - entry_factor * range, _Digits);
   }

   return -1;
}

double calcTPPrice(ENUM_ORDER_TYPE order, double high, double low) {
   double range = high - low;

   if(order == ORDER_TYPE_BUY) {
      return NormalizeDouble(high + tp_factor * range, _Digits);
   } else if(order == ORDER_TYPE_SELL) {
      return NormalizeDouble(low - tp_factor * range, _Digits);
   }

   return -1;
}

double calcSLPrice(ENUM_ORDER_TYPE order, double high, double low) {
   double range = high - low;

   if(order == ORDER_TYPE_BUY) {
      return NormalizeDouble(high - sl_factor * range, _Digits);
   } else if(order == ORDER_TYPE_SELL) {
      return NormalizeDouble(low + sl_factor * range, _Digits);
   }

   return -1;
}

bool clearPositionAndOrder() {
   int orders = OrdersTotal();

   for(int i = orders - 1; i >= 0; i--) {
      ulong ticket = OrderGetTicket(i);

      if(ticket != 0) {
         long order_magic_number = OrderGetInteger(ORDER_MAGIC);

         if(order_magic_number == magic_number) {
            if (!trade.OrderDelete(ticket)) {
               Print("Error clearing orders");
               return false;
            }
         }
      }
   }

   int positions = PositionsTotal();

   for(int i = positions - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);

      if(ticket != 0) {
         long pos_magic_number = PositionGetInteger(POSITION_MAGIC);

         if(pos_magic_number == magic_number) {
            if (!trade.PositionClose(ticket)) {
               Print("Error clearing positions");
               return false;
            }
         }
      }
   }

   return true;
}

bool isPriceAboveMA () {
   double slowMAbuffer[];
   CopyBuffer(handle_slow_ma, 0, 1, 1, slowMAbuffer);

   double curr_price = SymbolInfoDouble(_Symbol, SYMBOL_LAST);

   if (curr_price > slowMAbuffer[0]) {
      return true;
   } else {
      return false;
   }
}

//unused
bool checkTwoPrevious(ENUM_ORDER_TYPE order) {
   if (order == ORDER_TYPE_BUY) {
      int first_index = iHighest(_Symbol, timeframe, MODE_HIGH, 40, 1);
      int second_index = iHighest(_Symbol, timeframe, MODE_HIGH, 20, 1);

      if (first_index == -1 || second_index == -1) {
         Print("Error: ", GetLastError());
         return false;
      }

      if (first_index != second_index) {
         return false;
      } else {
         return true;
      }
   } else if (order == ORDER_TYPE_SELL) {
      int first_index = iLowest(_Symbol, timeframe, MODE_LOW, 40, 1);
      int second_index = iLowest(_Symbol, timeframe, MODE_LOW, 20, 1);

      if (first_index == -1 || second_index == -1) {
         Print("Error: ", GetLastError());
         return false;
      }

      if (first_index != second_index) {
         return false;
      } else {
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(magic_number);
   trade.SetAsyncMode(true);

   total_bars = iBars(_Symbol, timeframe);

   handle_slow_ma = iMA(_Symbol, timeframe, 200, 0, MODE_SMMA, applied_price);

   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {

}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   int current_bars = iBars(_Symbol, timeframe);

   if(current_bars != total_bars) {
      total_bars = current_bars;

      Print("Buy Signal: ", signalInsideBar(ORDER_TYPE_BUY), ", Sell Signal: ", signalInsideBar(ORDER_TYPE_SELL));

      double high = iHigh(_Symbol, timeframe, 2);
      double low = iLow(_Symbol, timeframe, 2);

      if (signalInsideBar(ORDER_TYPE_BUY) && isPriceAboveMA()) {
         if (clearPositionAndOrder()) {
            double buy_stop_price = calcEntryPrice(ORDER_TYPE_BUY, high, low);
            double sl = calcSLPrice(ORDER_TYPE_BUY, high, low);
            double tp = calcTPPrice(ORDER_TYPE_BUY, high, low);
            double vol = findLotSize(priceToPips(sl, buy_stop_price), risk_percent);
            datetime expire_time = TimeCurrent() + order_expire_hour * PeriodSeconds(PERIOD_H1);

            Print("Vol: ", vol, "\nEntry: ", buy_stop_price, "\nStop loss: ", sl, "\nTake profit: ", tp);

            if (!trade.BuyStop(vol, buy_stop_price, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expire_time, "BUY STOP Babypips ISB")) {
               Print("Error ordering buy stop order");
            }
         }
      } else if (signalInsideBar(ORDER_TYPE_SELL) && !isPriceAboveMA()) {
         if (clearPositionAndOrder()) {
            double sell_stop_price = calcEntryPrice(ORDER_TYPE_SELL, high, low);
            double sl = calcSLPrice(ORDER_TYPE_SELL, high, low);
            double tp = calcTPPrice(ORDER_TYPE_SELL, high, low);
            double vol = findLotSize(priceToPips(sl, sell_stop_price), risk_percent);
            datetime expire_time = TimeCurrent() + order_expire_hour * PeriodSeconds(PERIOD_H1);

            Print("Vol: ", vol, "\nEntry: ", sell_stop_price, "\nStop loss: ", sl, "\nTake profit: ", tp);

            if (!trade.SellStop(vol, sell_stop_price, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expire_time, "SELL STOP Babypips ISB")) {
               Print("Error ordering sell stop order");
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
