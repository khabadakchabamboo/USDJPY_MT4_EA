//+------------------------------------------------------------------+
//|                                   MinimumShuffle_History.mqh     |
//| Robust composite high-water mark realized profit tracking        |
//+------------------------------------------------------------------+
#ifndef MINIMUM_SHUFFLE_HISTORY_MQH
#define MINIMUM_SHUFFLE_HISTORY_MQH

datetime g_lastProcessedCloseTime = 0;
ulong    g_lastProcessedTicket    = 0;
double   g_accumulatedRealizedProfit = 0.0;

double GetRealizedProfit(int magicNumber, string targetSymbol)
{
   int historyTotal = OrdersHistoryTotal();
   string sym = (targetSymbol == "") ? Symbol() : targetSymbol;
   
   for(int i = 0; i < historyTotal; i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
         
      datetime closeTime = (datetime)OrderCloseTime();
      ulong    ticket    = (ulong)OrderTicket();
      
      // Skip anything older than or equal to our composite high-water mark
      if(closeTime < g_lastProcessedCloseTime)
         continue;
      if(closeTime == g_lastProcessedCloseTime && ticket <= g_lastProcessedTicket)
         continue;
         
      // Filter by symbol and magic number
      if(OrderSymbol() == sym && OrderMagicNumber() == magicNumber)
      {
         int hType = OrderType();
         if(hType == OP_BUY || hType == OP_SELL)
         {
            g_accumulatedRealizedProfit += OrderProfit() + OrderSwap() + OrderCommission();
         }
      }
      
      // Advance composite high-water mark (chronological time first, ticket as tie-breaker)
      if(closeTime > g_lastProcessedCloseTime)
      {
         g_lastProcessedCloseTime = closeTime;
         g_lastProcessedTicket    = ticket;
      }
      else if(closeTime == g_lastProcessedCloseTime && ticket > g_lastProcessedTicket)
      {
         g_lastProcessedTicket = ticket;
      }
   }
   
   return g_accumulatedRealizedProfit;
}

bool RecoverHistory(int magicNumber, double &outReferencePrice)
{
   datetime latestClose = 0;
   int latestTicket = 0;
   double latestPrice = 0.0;
   
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
      {
         Print("MinimumShuffle: Cannot inspect account history. Error ", GetLastError());
         return false;
      }
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != magicNumber ||
         (OrderType() != OP_BUY && OrderType() != OP_SELL) || OrderCloseTime() <= 0)
         continue;
         
      datetime closeTime = (datetime)OrderCloseTime();
      int ticket = OrderTicket();
      
      if(closeTime > latestClose || (closeTime == latestClose && ticket > latestTicket))
      {
         latestClose = closeTime;
         latestTicket = ticket;
         latestPrice = OrderClosePrice();
      }
   }
   
   if(latestClose > 0)
   {
      outReferencePrice = latestPrice;
      Print("MinimumShuffle: recovered last strategy close ", latestTicket,
            " at ", DoubleToString(outReferencePrice, Digits));
   }
   else
   {
      outReferencePrice = (Bid + Ask) / 2.0;
      Print("MinimumShuffle: no strategy execution history; seeding midpoint ",
            DoubleToString(outReferencePrice, Digits), ". No initial trade.");
   }
   return true;
}

#endif