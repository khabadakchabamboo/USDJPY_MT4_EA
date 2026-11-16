//+------------------------------------------------------------------+
//|                                    MinimumShuffle_Config.mqh     |
//| Configuration, inputs, state keys, and persistence               |
//+------------------------------------------------------------------+
#ifndef MINIMUM_SHUFFLE_CONFIG_MQH
#define MINIMUM_SHUFFLE_CONFIG_MQH

input double TriggerJPY = 100.0;
input double TakeProfitJPY = 100.0;
input int MagicNumber = 9251100;

double referencePrice = 0.0;
int trackedTicket = 0;
double minimumLots = 0.0;
double contractSize = 0.0;
double tickSize = 0.0;
string stateKey;
string lockKey;
datetime nextTradeAttempt = 0;
datetime lastReportAt = 0;
string lastReport = "";

void Report(string message)
{
   datetime now = TimeLocal();
   if(message != lastReport || now - lastReportAt >= 30)
   {
      Print("MinimumShuffle: ", message);
      lastReport = message;
      lastReportAt = now;
   }
}

uint ServerHash()
{
   uint hash = 2166136261;
   string server = AccountServer();
   for(int i = 0; i < StringLen(server); i++)
      hash = (hash ^ (uint)StringGetCharacter(server, i)) * 16777619;
   return hash;
}

bool SaveState()
{
   ResetLastError();
   if(GlobalVariableSet(stateKey + ".ref", referencePrice) == 0)
   {
      Report("Cannot persist execution reference. Error " + IntegerToString(GetLastError()));
      return false;
   }
   if(GlobalVariableSet(stateKey + ".ticket", (double)trackedTicket) == 0)
   {
      Report("Cannot persist tracked ticket. Error " + IntegerToString(GetLastError()));
      return false;
   }
   GlobalVariablesFlush();
   return true;
}

bool LoadState()
{
   bool hasReference = GlobalVariableCheck(stateKey + ".ref");
   bool hasTicket = GlobalVariableCheck(stateKey + ".ticket");
   if(!hasReference && !hasTicket)
   {
      referencePrice = 0.0;
      trackedTicket = 0;
      return true;
   }
   if(!hasReference)
   {
      Report("Incomplete stored state: execution reference missing. Trading paused.");
      return false;
   }
   double storedReference;
   double storedTicket = 0.0;
   if(!GlobalVariableGet(stateKey + ".ref", storedReference) ||
      (hasTicket && !GlobalVariableGet(stateKey + ".ticket", storedTicket)))
   {
      Report("Cannot read stored state. Error " + IntegerToString(GetLastError()));
      return false;
   }
   if(!MathIsValidNumber(storedReference) || storedReference <= 0.0 ||
      !MathIsValidNumber(storedTicket) || storedTicket < 0.0 ||
      storedTicket > 2147483647.0 || storedTicket != MathFloor(storedTicket))
   {
      Report("Invalid stored state. Trading paused; inspect terminal global variables.");
      return false;
   }
   referencePrice = storedReference;
   trackedTicket = (int)storedTicket;
   return true;
}

bool ReadSpecification()
{
   minimumLots = MarketInfo(Symbol(), MODE_MINLOT);
   contractSize = MarketInfo(Symbol(), MODE_LOTSIZE);
   tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   double maximum = MarketInfo(Symbol(), MODE_MAXLOT);
   if(!MathIsValidNumber(minimumLots) || minimumLots <= 0.0 ||
      !MathIsValidNumber(contractSize) || contractSize <= 0.0 ||
      !MathIsValidNumber(tickSize) || tickSize <= 0.0 ||
      !MathIsValidNumber(step) || step <= 0.0 ||
      !MathIsValidNumber(maximum) || maximum < minimumLots)
   {
      Report("Broker symbol specification unavailable or invalid. Trading paused.");
      return false;
   }
   return true;
}

#endif
