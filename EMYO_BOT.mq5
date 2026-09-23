//+------------------------------------------------------------------+
//|                     EMYO BOT SCALPING - BASE                    |
//+------------------------------------------------------------------+
#property copyright "EMYO"
#property version   "1.20"

#include <Trade\Trade.mqh>

//---------------------- PARAMÈTRES DU BOT --------------------------
input group "Taille des positions"
input double Lots               = 0.01;  // Lot fixe (si RiskPercent = 0)
input double RiskPercent        = 0;     // % du solde risqué par trade (0 = lot fixe)

input group "Sorties"
input double StopLossPips       = 10;
input double TakeProfitPips     = 30;
input double BreakEvenPips      = 8;     // Gain qui déclenche le break-even (0 = off)
input double BreakEvenLockPips  = 1;     // Pips sécurisés au break-even
input double TrailingStopPips   = 0;     // Distance du trailing stop (0 = off)
input double TrailingStepPips   = 1;     // Déplacement minimum du trailing

input group "Signaux"
input int    MaPeriod           = 50;    // Période de la moyenne mobile
input int    RsiPeriod          = 14;    // Période du RSI
input double RsiOversold        = 30;    // Seuil de survente
input double RsiOverbought      = 70;    // Seuil de surachat

input group "Filtres"
input double MaxSpreadPoints    = 60;    // Spread maximum autorisé (points)
input int    MaxSlippagePoints  = 10;    // Glissement maximum accepté (points)
input int    StartHour          = 0;     // Heure serveur de début (StartHour = EndHour : 24h/24)
input int    EndHour            = 0;     // Heure serveur de fin (exclue)

input group "Sécurité"
input int    MaxTradesPerDay    = 10;    // 0 = illimité
input double MaxDailyLossPercent = 3;    // Arrêt du jour après cette perte en % (0 = off)
input ulong  MagicNumber        = 360036;
input bool   AutoCloseOnStop    = true;  // Fermer les positions quand le bot est retiré

//---------------------- VARIABLES GLOBALES --------------------------
CTrade   trade;
int      maHandle    = INVALID_HANDLE;
int      rsiHandle   = INVALID_HANDLE;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if(StopLossPips <= 0 || TakeProfitPips <= 0 || MaPeriod <= 0 || RsiPeriod <= 0 ||
      RsiOversold >= RsiOverbought || StartHour < 0 || StartHour > 23 ||
      EndHour < 0 || EndHour > 23 || Lots <= 0 || RiskPercent < 0)
   {
      Print("Erreur : paramètres invalides");
      return(INIT_PARAMETERS_INCORRECT);
   }

   maHandle  = iMA(_Symbol, PERIOD_M1, MaPeriod, 0, MODE_SMA, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, PERIOD_M1, RsiPeriod, PRICE_CLOSE);

   if(maHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE)
   {
      Print("Erreur : impossible de créer les indicateurs");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

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

// Distance minimale imposée par le courtier entre le prix et le SL/TP
double MinStopDistance()
{
   return SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
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

// Vrai si l'heure serveur est dans la plage de trading
bool IsTradingHour()
{
   if(StartHour == EndHour)
      return true;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   if(StartHour < EndHour)
      return now.hour >= StartHour && now.hour < EndHour;

   // Plage qui passe minuit, ex. 22h -> 6h
   return now.hour >= StartHour || now.hour < EndHour;
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

// Lit l'historique du jour : nombre de trades ouverts et résultat net.
// Basé sur l'historique du compte, donc juste même après un redémarrage.
void GetTodayStats(int &tradesToday, double &profitToday)
{
   tradesToday = 0;
   profitToday = 0;

   datetime now      = TimeCurrent();
   datetime dayStart = now - (now % 86400);

   if(!HistorySelect(dayStart, now))
      return;

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;

      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol ||
         HistoryDealGetInteger(deal, DEAL_MAGIC) != (long)MagicNumber)
         continue;

      if(HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
         tradesToday++;

      profitToday += HistoryDealGetDouble(deal, DEAL_PROFIT)
                   + HistoryDealGetDouble(deal, DEAL_SWAP)
                   + HistoryDealGetDouble(deal, DEAL_COMMISSION);
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

// Lot fixe, ou lot calculé pour ne risquer que RiskPercent du solde
double CalculateLots()
{
   double lots = Lots;

   if(RiskPercent > 0)
   {
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue <= 0 || tickSize <= 0)
         return 0;

      double riskMoney  = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
      double lossPerLot = StopLossPips * PipSize() / tickSize * tickValue;
      lots = riskMoney / lossPerLot;
   }

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(lotStep <= 0)
      return 0;

   lots = MathFloor(lots / lotStep + 1e-9) * lotStep;
   int lotDigits = (int)MathMax(0, MathCeil(-MathLog10(lotStep)));

   if(lots < minLot)
   {
      Print("Lot calculé trop petit (", lots, "), minimum du courtier : ", minLot);
      return 0;
   }

   return NormalizeDouble(MathMin(lots, maxLot), lotDigits);
}

// Vrai si les distances SL/TP respectent le minimum du courtier
bool StopsAllowed()
{
   double minDist = MinStopDistance();
   if(StopLossPips * PipSize() < minDist || TakeProfitPips * PipSize() < minDist)
   {
      Print("SL/TP trop proches : minimum du courtier = ", minDist / PipSize(), " pips");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
void OpenBuy()
{
   double lots = CalculateLots();
   if(lots <= 0 || !StopsAllowed())
      return;

   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);   // on achète au Ask
   double sl    = NormalizeDouble(price - StopLossPips   * PipSize(), _Digits);
   double tp    = NormalizeDouble(price + TakeProfitPips * PipSize(), _Digits);

   if(trade.Buy(lots, _Symbol, price, sl, tp))
      Print("BUY exécuté | Lots=", lots, " SL=", sl, " TP=", tp);
   else
      Print("BUY refusé : ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
void OpenSell()
{
   double lots = CalculateLots();
   if(lots <= 0 || !StopsAllowed())
      return;

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);   // on vend au Bid
   double sl    = NormalizeDouble(price + StopLossPips   * PipSize(), _Digits);
   double tp    = NormalizeDouble(price - TakeProfitPips * PipSize(), _Digits);

   if(trade.Sell(lots, _Symbol, price, sl, tp))
      Print("SELL exécuté | Lots=", lots, " SL=", sl, " TP=", tp);
   else
      Print("SELL refusé : ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
// Break-even puis trailing stop, appelé à chaque tick
void ManagePositions()
{
   if(BreakEvenPips <= 0 && TrailingStopPips <= 0)
      return;

   double pip     = PipSize();
   double minDist = MinStopDistance();
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
         continue;

      long   type      = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double newSL     = currentSL;

      if(type == POSITION_TYPE_BUY)
      {
         double profit = bid - openPrice;

         if(BreakEvenPips > 0 && profit >= BreakEvenPips * pip)
            newSL = MathMax(newSL, openPrice + BreakEvenLockPips * pip);

         if(TrailingStopPips > 0 && profit >= TrailingStopPips * pip)
            newSL = MathMax(newSL, bid - TrailingStopPips * pip);

         newSL = NormalizeDouble(newSL, _Digits);

         // On ne bouge le SL que vers le haut, d'au moins un pas, et à distance autorisée
         if(newSL > currentSL + TrailingStepPips * pip * 0.999 &&
            bid - newSL >= minDist)
            trade.PositionModify(ticket, newSL, currentTP);
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double profit = openPrice - ask;

         if(BreakEvenPips > 0 && profit >= BreakEvenPips * pip)
            newSL = (newSL == 0) ? openPrice - BreakEvenLockPips * pip
                                 : MathMin(newSL, openPrice - BreakEvenLockPips * pip);

         if(TrailingStopPips > 0 && profit >= TrailingStopPips * pip)
            newSL = (newSL == 0) ? ask + TrailingStopPips * pip
                                 : MathMin(newSL, ask + TrailingStopPips * pip);

         newSL = NormalizeDouble(newSL, _Digits);

         // On ne bouge le SL que vers le bas, d'au moins un pas, et à distance autorisée
         if(newSL > 0 &&
            (currentSL == 0 || newSL < currentSL - TrailingStepPips * pip * 0.999) &&
            newSL - ask >= minDist)
            trade.PositionModify(ticket, newSL, currentTP);
      }
   }
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
   // La gestion des positions ouvertes se fait à chaque tick
   ManagePositions();

   // Les nouvelles entrées : une fois par bougie M1 clôturée
   if(!IsNewBar())
      return;

   if(!IsTradingHour())
      return;

   if(HasOpenPosition())
      return;

   int    tradesToday = 0;
   double profitToday = 0;
   GetTodayStats(tradesToday, profitToday);

   if(MaxTradesPerDay > 0 && tradesToday >= MaxTradesPerDay)
      return;

   if(MaxDailyLossPercent > 0 &&
      profitToday <= -AccountInfoDouble(ACCOUNT_BALANCE) * MaxDailyLossPercent / 100.0)
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
