//+------------------------------------------------------------------+
//|                                    USDJPY_MinimumShuffle.mq4     |
//| Modularized version utilizing config and ticket-based history    |
//+------------------------------------------------------------------+
#property strict
#property version "1.05"
#include "..\JP225_MT4_EA\Common\ProfitProtector_MT4.mqh"
#include "..\JP225_MT4_EA\Common\GV_Lease.mqh"
#include "USDJPY_MinimumShuffle_Config.mqh"
#include "USDJPY_MinimumShuffle_History.mqh"

#property description "One minimum-size USDJPY position; last-fill movement signals."
#property description "JPY account only. No initial loss SL; common account-wide profit protection."

//+------------------------------------------------------------------+
bool AcquireLock(double &lease)
  {
   if(!GlobalVariableCheck(lockKey) && !GlobalVariableTemp(lockKey))
     {
      Report("Cannot create terminal trade lock. Error " + IntegerToString(GetLastError()));
      return false;
     }
   return GV_AcquireLease(lockKey, lease, 300.0);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool InspectOpenOrders(int &ownTicket)
  {
   ownTicket = 0;
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         Report("Cannot inspect open orders. Error " + IntegerToString(GetLastError()));
         return false;
        }
      if(OrderSymbol() != Symbol())
         continue;
      if(OrderMagicNumber() != MagicNumber ||
         (OrderType() != OP_BUY && OrderType() != OP_SELL))
        {
         Report("Other/pending order exists on this symbol. Trading paused; no order changed.");
         return false;
        }
      count++;
      ownTicket = OrderTicket();
      if(MathAbs(OrderLots() - minimumLots) > 0.00000001)
        {
         Report("Existing position is not broker-minimum size. Trading paused.");
         return false;
        }
     }
   if(count > 1)
     {
      Report("More than one strategy position exists. Trading paused; no order changed.");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double TargetPrice(int type, double entry)
  {
   double distance = TakeProfitJPY / (contractSize * minimumLots);
   double target;
   if(type == OP_BUY)
      target = MathCeil((entry + distance) / tickSize - 0.00000001) * tickSize;
   else
      target = MathFloor((entry - distance) / tickSize + 0.00000001) * tickSize;
   return NormalizeDouble(target, Digits);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool TargetAllowed(int type, double target, bool modification)
  {
   double level = MarketInfo(Symbol(), MODE_STOPLEVEL);
   if(modification)
      level = MathMax(level, MarketInfo(Symbol(), MODE_FREEZELEVEL));
   double minimumDistance = level * Point;
   double available = type == OP_BUY ? target - Bid : Ask - target;
   if(target <= 0.0 || available <= 0.0 ||
      available + Point * 0.000001 < minimumDistance ||
      (modification && level > 0.0 && available <= minimumDistance))
      return false;
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void TradeFailure(string operation)
  {
   int error = GetLastError();
   if(error == 128)
     {
      if(GlobalVariableSet(stateKey + ".halt", 1.0) == 0)
         Report("Cannot persist ambiguous-execution halt. Disable AutoTrading immediately.");
      GlobalVariablesFlush();
      Report("Trade timeout: execution outcome is uncertain. Disable AutoTrading, verify history, then clear " + stateKey + ".halt.");
      nextTradeAttempt = D'2099.12.31 23:59:59';
      return;
     }
   Report(operation + " failed. Error " + IntegerToString(error));
   nextTradeAttempt = TimeLocal() + 10;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool ClosePosition(int ticket)
  {
   if(!OrderSelect(ticket, SELECT_BY_TICKET) || OrderCloseTime() != 0)
      return false;
   int type = OrderType();
   double lots = OrderLots();
   RefreshRates();
   double price = type == OP_BUY ? Bid : Ask;
   ResetLastError();
   if(!OrderClose(ticket, lots, price, SlippagePoints, clrNONE))
     {
      TradeFailure("Market close");
      return false;
     }
   referencePrice = OrderClosePrice();
   trackedTicket = 0;
   return SaveState();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MaintainTarget(int ticket)
  {
   if(!OrderSelect(ticket, SELECT_BY_TICKET) || OrderCloseTime() != 0)
      return;
   int type = OrderType();
   double entry = OrderOpenPrice();
   double target = TargetPrice(type, entry);
   if(MathAbs(OrderTakeProfit() - target) < tickSize * 0.5)
      return;
   RefreshRates();
   double exitPrice = type == OP_BUY ? Bid : Ask;
   if((type == OP_BUY && exitPrice >= target) || (type == OP_SELL && exitPrice <= target))
     {
      ClosePosition(ticket);
      return;
     }
   if(!TargetAllowed(type, target, true))
      return;
   ResetLastError();
   if(!OrderModify(ticket, entry, OrderStopLoss(), target, 0, clrNONE))
      TradeFailure("Fill-based TP adjustment");
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OpenPosition(int type)
  {
   RefreshRates();
   double entry = type == OP_BUY ? Ask : Bid;
   double target = TargetPrice(type, entry);
   if(!TargetAllowed(type, target, false))
      return;
   ResetLastError();
   double remaining = AccountFreeMarginCheck(Symbol(), type, minimumLots);
   if(GetLastError() != 0 || remaining <= 0.0)
     {
      Report("Insufficient free margin.");
      nextTradeAttempt = TimeLocal() + 10;
      return;
     }
   ResetLastError();
   int ticket = OrderSend(Symbol(), type, minimumLots, entry, SlippagePoints, 0.0, target, "MinimumShuffle", MagicNumber, 0, clrNONE);
   if(ticket < 0)
     {
      TradeFailure("Opening order");
      return;
     }
   trackedTicket = ticket;
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
      return;
   referencePrice = OrderOpenPrice();
   if(!SaveState())
      return;
   MaintainTarget(ticket);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string GetOpenPositionInfo()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
        {
         int type = OrderType();
         if(type == OP_BUY || type == OP_SELL)
           {
            string typeStr = (type == OP_BUY) ? "BUY" : "SELL";
            double profit = OrderProfit() + OrderSwap() + OrderCommission();
            return("#" + IntegerToString(OrderTicket()) + " " + typeStr + " " + DoubleToString(OrderLots(), 2) + " @ " + DoubleToString(OrderOpenPrice(), Digits) + " PnL:¥" + DoubleToString(profit, 1));
           }
        }
     }
   return("None");
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ProcessTick()
  {
   if(!LoadState() || !ReadSpecification())
      return;
   if(GlobalVariableCheck(stateKey + ".halt"))
     {
      Report("Ambiguous-execution halt is active. Clear " + stateKey + ".halt in F3.");
      return;
     }
   RefreshRates();
   if(Bid <= 0.0 || Ask <= 0.0 || Ask < Bid)
      return;

   int ownTicket;
   if(!InspectOpenOrders(ownTicket))
      return;

   if(trackedTicket > 0)
     {
      if(!OrderSelect(trackedTicket, SELECT_BY_TICKET))
         return;
      if(OrderCloseTime() > 0)
        {
         referencePrice = OrderClosePrice();
         trackedTicket = 0;
         SaveState();
         return;
        }
      if(ownTicket != trackedTicket)
         return;
      if(MathAbs(referencePrice - OrderOpenPrice()) > tickSize * 0.5)
        {
         referencePrice = OrderOpenPrice();
         if(!SaveState())
            return;
        }
     }
   if(ownTicket > 0 && trackedTicket == 0)
     {
      if(!OrderSelect(ownTicket, SELECT_BY_TICKET))
         return;
      trackedTicket = ownTicket;
      referencePrice = OrderOpenPrice();
      SaveState();
      return;
     }
   if(referencePrice == 0.0)
     {
      RecoverHistory(MagicNumber, referencePrice);
      SaveState();
      return;
     }

   double midpoint = (Bid + Ask) / 2.0;
   double displacementJPY = (midpoint - referencePrice) * contractSize * minimumLots;
   double realizedPnL = GetRealizedProfit(MagicNumber, Symbol());

// Fixed string literals and proper escaping for Comment()
   Comment("--- MinimumShuffle [" + Symbol() + " / LIVE] ---",
           "\n[Account] Bal:¥" + DoubleToString(AccountBalance(), 0) + " | Eq:¥" + DoubleToString(AccountEquity(), 0),
           "\nUnrealized:¥" + DoubleToString(AccountProfit(), 1) + " | Realized:¥" + DoubleToString(realizedPnL, 1),
           "\n[Open Position] " + GetOpenPositionInfo(),
           "\nRef Price: " + DoubleToString(referencePrice, Digits) + " | Diff JPY: " + DoubleToString(displacementJPY, 2));

   if(!IsConnected() || !IsTradeAllowed() || MarketInfo(Symbol(), MODE_TRADEALLOWED) == 0 || TimeLocal() < nextTradeAttempt)
      return;

   int direction = -1;
   if(displacementJPY > TriggerJPY + 0.000001)
      direction = OP_BUY;
   else
      if(displacementJPY < -TriggerJPY - 0.000001)
         direction = OP_SELL;

   if(ownTicket > 0)
     {
      if(!OrderSelect(ownTicket, SELECT_BY_TICKET))
         return;
      if(direction >= 0 && direction != OrderType())
         ClosePosition(ownTicket);
      else
         MaintainTarget(ownTicket);
      return;
     }
   if(direction >= 0)
      OpenPosition(direction);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(AccountCurrency() != "JPY" || SymbolInfoString(Symbol(), SYMBOL_CURRENCY_BASE) != "USD" || SymbolInfoString(Symbol(), SYMBOL_CURRENCY_PROFIT) != "JPY")
      return INIT_FAILED;

   g_lastProcessedTicket = 0;
   g_accumulatedRealizedProfit = 0.0;

   string scope = IsTesting() ? "TEST" : "LIVE";
   stateKey = "MS." + IntegerToString(AccountNumber()) + "." + IntegerToString((int)ServerHash()) + "." + scope + "." + Symbol() + "." + IntegerToString(MagicNumber);
   lockKey = stateKey + ".lock";

   if(IsTesting())
     {
      referencePrice = 0.0;
      trackedTicket = 0;
      GlobalVariableDel(stateKey + ".ref");
      GlobalVariableDel(stateKey + ".ticket");
      GlobalVariableDel(lockKey);
      GlobalVariableDel(stateKey + ".halt");
     }
   if(!ReadSpecification())
      return INIT_FAILED;

   if(!EventSetTimer(1))
      return INIT_FAILED;
   PP_Announce("USDJPY MinimumShuffle 1.05");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(PP_Run())
      return;
   double lease;
   if(!AcquireLock(lease))
      return;
   ProcessTick();
   GV_ReleaseLease(lockKey, lease);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTimer() { PP_Run(); }
void OnDeinit(const int reason) { EventKillTimer(); Comment(""); }
//+------------------------------------------------------------------+
