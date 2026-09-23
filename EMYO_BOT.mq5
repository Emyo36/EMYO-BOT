//+------------------------------------------------------------------+
//|                     EMYO BOT SCALPING - BASE                    |
//+------------------------------------------------------------------+
#property copyright "EMYO"
#property version   "1.10"

#include <Trade\Trade.mqh>

//---------------------- PARAMÈTRES DU BOT --------------------------
input double Lots             = 0.01;
input double StopLossPips     = 10;
input double TakeProfitPips   = 30;
input double MaxSpreadPoints  = 60;    // Spread maximum autorisé (points)
input int    MaPeriod         = 50;    // Période de la moyenne mobile
input int    RsiPeriod        = 14;    // Période du RSI
input double RsiOversold      = 30;    // Seuil de survente
input double RsiOverbought    = 70;    // Seuil de surachat
input int    MaxTradesPerDay  = 10;    // 0 = illimité
input ulong  MagicNumber      = 360036;
input bool   AutoCloseOnStop  = true;  // Fermer les positions quand le bot est retiré

//---------------------- VARIABLES GLOBALES --------------------------
CTrade   trade;
int      maHandle   = INVALID_HANDLE;
int      rsiHandle  = INVALID_HANDLE;
int      tradesToday = 0;
int      currentDay  = -1;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   maHandle  = iMA(_Symbol, PERIOD_M1, MaPeriod, 0, MODE_SMA, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, PERIOD_M1, RsiPeriod, PRICE_CLOSE);

   if(maHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE)
   {
      Print("Erreur : impossible de créer les indicateurs");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   tradesToday = 0;
   Print("Bot lancé");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // On ne ferme pas les positions sur un simple changement de
   // timeframe, de paramètres ou une recompilation.
   if(AutoCloseOnStop &&
      reason != REASON_CHARTCHANGE &&
      reason != REASON_PARAMETERS  &&
      reason != REASON_RECOMPILE)
      CloseAllTrades();

   if(maHandle  != INVALID_HANDLE) IndicatorRelease(maHandle);
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);

   Print("Bot arrêté");
}

//+--------------------------FUNCTIONS-------------------------------+
// Taille d'un pip : 10 points sur les cotations à 3 ou 5 décimales
double PipSize()
{
   if(_Digits == 3 || _Digits == 5)
      return 10 * _Point;
   return _Point;
}

bool CheckSpread()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double spreadPoints = (ask - bid) / _Point;

   if(spreadPoints > MaxSpreadPoints)
   {
      Print("Spread trop élevé : ", spreadPoints, " points");
      return false;
   }

   return true;
}

// Vrai une seule fois par nouvelle bougie M1
bool IsNewBar()
{
   datetime barTime = iTime(_Symbol, PERIOD_M1, 0);
   if(barTime == lastBarTime)
      return false;

   lastBarTime = barTime;
   return true;
}

// Remet le compteur de trades à zéro à chaque nouveau jour
void UpdateDailyCounter()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   if(now.day_of_year != currentDay)
   {
      currentDay  = now.day_of_year;
      tradesToday = 0;
   }
}

// Vrai si le bot a déjà une position ouverte sur ce symbole
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void OpenBuy()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);   // on achète au Ask
   double sl    = NormalizeDouble(price - StopLossPips   * PipSize(), _Digits);
   double tp    = NormalizeDouble(price + TakeProfitPips * PipSize(), _Digits);

   if(trade.Buy(Lots, _Symbol, price, sl, tp))
   {
      tradesToday++;
      Print("BUY exécuté | SL=", sl, " TP=", tp);
   }
   else
      Print("BUY refusé : ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
void OpenSell()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);   // on vend au Bid
   double sl    = NormalizeDouble(price + StopLossPips   * PipSize(), _Digits);
   double tp    = NormalizeDouble(price - TakeProfitPips * PipSize(), _Digits);

   if(trade.Sell(Lots, _Symbol, price, sl, tp))
   {
      tradesToday++;
      Print("SELL exécuté | SL=", sl, " TP=", tp);
   }
   else
      Print("SELL refusé : ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
// Ferme uniquement les positions ouvertes par ce bot sur ce symbole
void CloseAllTrades()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber)
         trade.PositionClose(ticket);
   }

   Print("Toutes les positions du bot ont été fermées automatiquement.");
}

//+------------------------------------------------------------------+
void OnTick()
{
   // On travaille sur les bougies clôturées, une fois par bougie M1
   if(!IsNewBar())
      return;

   UpdateDailyCounter();

   if(MaxTradesPerDay > 0 && tradesToday >= MaxTradesPerDay)
      return;

   if(HasOpenPosition())
      return;

   // Index 1 = dernière bougie clôturée, index 2 = celle d'avant
   double ma[], rsi[], close[];
   ArraySetAsSeries(ma, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(close, true);

   if(CopyBuffer(maHandle,  0, 0, 3, ma)  < 3 ||
      CopyBuffer(rsiHandle, 0, 0, 3, rsi) < 3 ||
      CopyClose(_Symbol, PERIOD_M1, 0, 3, close) < 3)
      return;   // données pas encore prêtes

   // Retournement RSI : sortie de la zone de survente / surachat
   bool buySignal  = rsi[2] < RsiOversold   && rsi[1] >= RsiOversold;
   bool sellSignal = rsi[2] > RsiOverbought && rsi[1] <= RsiOverbought;

   // Filtre de tendance avec la moyenne mobile
   bool trendBuyAllowed  = close[1] > ma[1];
   bool trendSellAllowed = close[1] < ma[1];

   if(!(buySignal && trendBuyAllowed) && !(sellSignal && trendSellAllowed))
      return;

   if(!CheckSpread())
      return;

   if(buySignal && trendBuyAllowed)
      OpenBuy();
   else if(sellSignal && trendSellAllowed)
      OpenSell();
}
//+------------------------------------------------------------------+
