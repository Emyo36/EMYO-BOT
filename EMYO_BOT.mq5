//+------------------------------------------------------------------+
//|              EMYO BOT - SCALPING M1 SUIVI DE TENDANCE             |
//|        Or (XAUUSD), Bitcoin (BTCUSD), NASDAQ (NAS100/USTEC)       |
//+------------------------------------------------------------------+
#property copyright "EMYO"
#property version   "1.50"

#include <Trade\Trade.mqh>

enum ENUM_DISTANCE_MODE
{
   DISTANCE_ATR  = 0,   // ATR (s'adapte à chaque marché)
   DISTANCE_PIPS = 1    // Pips fixes (forex)
};

//---------------------- PARAMÈTRES DU BOT --------------------------
input group "Taille des positions"
input double TargetProfitMoney  = 3;     // Gain visé par trade, en devise du compte (0 = off)
input double RiskPercent        = 0;     // % du solde risqué par trade (si TargetProfitMoney = 0)
input double Lots               = 0.01;  // Lot fixe (si TargetProfitMoney = 0 et RiskPercent = 0)
input double MaxLots            = 1.0;   // Lot maximum autorisé, quel que soit le calcul

input group "Distances (en ATR, ou en pips si mode Pips)"
input ENUM_DISTANCE_MODE DistanceMode = DISTANCE_ATR;
input int    AtrPeriod          = 14;    // Période de l'ATR M1
input double StopLoss           = 1.2;   // Stop Loss
input double TakeProfit         = 1.0;   // Take Profit (0 = pas de TP, le trailing gère la sortie)
input double BreakEvenTrigger   = 0.6;   // Gain qui déclenche le break-even (0 = off)
input double BreakEvenLock      = 0.1;   // Gain sécurisé au break-even
input double TrailingStop       = 0;     // Distance du trailing stop (0 = off)
input double TrailingStep       = 0.2;   // Déplacement minimum du trailing
input double PullbackTolerance  = 0.2;   // Distance max. à l'EMA rapide pour valider le repli

input group "Tendance"
input int             FastEmaPeriod     = 20;          // EMA rapide M1 (zone de repli)
input int             SlowEmaPeriod     = 50;          // EMA lente M1 (direction)
input bool            UseHigherTimeframe = true;       // Confirmer avec une unité de temps supérieure
input ENUM_TIMEFRAMES TrendTimeframe    = PERIOD_M15;  // Unité de temps de confirmation
input int             TrendEmaPeriod    = 50;          // EMA de confirmation
input bool            CloseOnTrendReversal = true;     // Fermer si la tendance M1 s'inverse

input group "Entrée"
input int    RsiPeriod          = 14;    // Période du RSI
input double RsiMidLevel        = 50;    // RSI > niveau pour acheter, < niveau pour vendre

input group "Filtres"
input double MaxSpreadPercentOfSL  = 20; // Spread max. en % du Stop Loss (0 = off)
input double MaxSpreadPoints       = 0;  // Spread max. en points (0 = off)
input double MaxSlippagePercentOfSL = 10; // Glissement max. accepté en % du Stop Loss
input int    StartHour          = 0;     // Heure serveur de début (StartHour = EndHour : 24h/24)
input int    EndHour            = 0;     // Heure serveur de fin (exclue)

input group "Sécurité"
input int    MaxTradesPerDay    = 30;    // 0 = illimité
input double MaxDailyLossPercent = 3;    // Arrêt du jour après cette perte en % (0 = off)
input double DailyProfitTargetMoney = 0; // Arrêt du jour une fois ce gain atteint (0 = off)
input ulong  MagicNumber        = 360036;
input bool   AutoCloseOnStop    = true;  // Fermer les positions quand le bot est retiré

//---------------------- VARIABLES GLOBALES --------------------------
CTrade   trade;
int      fastHandle  = INVALID_HANDLE;
int      slowHandle  = INVALID_HANDLE;
int      htfHandle   = INVALID_HANDLE;
int      rsiHandle   = INVALID_HANDLE;
int      atrHandle   = INVALID_HANDLE;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if(StopLoss <= 0 || TakeProfit < 0 || AtrPeriod <= 0 || RsiPeriod <= 0 ||
      FastEmaPeriod <= 0 || SlowEmaPeriod <= FastEmaPeriod || TrendEmaPeriod <= 0 ||
      StartHour < 0 || StartHour > 23 || EndHour < 0 || EndHour > 23 ||
      Lots <= 0 || RiskPercent < 0 || TargetProfitMoney < 0 || MaxLots <= 0 ||
      (TargetProfitMoney > 0 && TakeProfit <= 0))
   {
      Print("Erreur : paramètres invalides");
      return(INIT_PARAMETERS_INCORRECT);
   }

   fastHandle = iMA(_Symbol, PERIOD_M1, FastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA(_Symbol, PERIOD_M1, SlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   htfHandle  = iMA(_Symbol, TrendTimeframe, TrendEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle  = iRSI(_Symbol, PERIOD_M1, RsiPeriod, PRICE_CLOSE);
   atrHandle  = iATR(_Symbol, PERIOD_M1, AtrPeriod);

   if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE ||
      htfHandle  == INVALID_HANDLE || rsiHandle  == INVALID_HANDLE ||
      atrHandle  == INVALID_HANDLE)
   {
      Print("Erreur : impossible de créer les indicateurs");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);

   Print("Bot lancé sur ", _Symbol);
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

   if(fastHandle != INVALID_HANDLE) IndicatorRelease(fastHandle);
   if(slowHandle != INVALID_HANDLE) IndicatorRelease(slowHandle);
   if(htfHandle  != INVALID_HANDLE) IndicatorRelease(htfHandle);
   if(rsiHandle  != INVALID_HANDLE) IndicatorRelease(rsiHandle);
   if(atrHandle  != INVALID_HANDLE) IndicatorRelease(atrHandle);

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

// Unité de distance en prix : l'ATR de la dernière bougie clôturée,
// ou un pip. Toutes les distances (SL, TP, trailing...) en sont des multiples.
// Renvoie 0 si l'ATR n'est pas encore disponible.
double DistanceUnit()
{
   if(DistanceMode == DISTANCE_PIPS)
      return PipSize();

   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(atrHandle, 0, 0, 2, atr) < 2)
      return 0;
   return atr[1];
}

// Distance minimale imposée par le courtier entre le prix et le SL/TP
double MinStopDistance()
{
   return SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
}

// Refuse d'entrer si le spread est trop grand par rapport au Stop Loss
bool CheckSpread(double slDistance)
{
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;

   if(MaxSpreadPoints > 0 && spread / _Point > MaxSpreadPoints)
   {
      Print("Spread trop élevé : ", spread / _Point, " points");
      return false;
   }

   if(MaxSpreadPercentOfSL > 0 && spread > slDistance * MaxSpreadPercentOfSL / 100.0)
   {
      Print("Spread trop élevé : ", DoubleToString(spread / slDistance * 100.0, 1), " % du Stop Loss");
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

// Valeur en devise du compte d'un mouvement de prix de 'distance' pour 1 lot
double MoneyPerLot(double distance)
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0)
      return 0;
   return distance / tickSize * tickValue;
}

// Taille du lot, par ordre de priorité :
//  1. TargetProfitMoney : le TP rapporte ce montant
//  2. RiskPercent       : le SL coûte ce % du solde
//  3. Lots              : lot fixe
double CalculateLots(double slDistance, double tpDistance)
{
   double lots = Lots;

   if(TargetProfitMoney > 0)
   {
      double gainPerLot = MoneyPerLot(tpDistance);
      if(gainPerLot <= 0)
         return 0;
      lots = TargetProfitMoney / gainPerLot;
   }
   else if(RiskPercent > 0)
   {
      double lossPerLot = MoneyPerLot(slDistance);
      if(lossPerLot <= 0)
         return 0;
      lots = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0 / lossPerLot;
   }

   lots = MathMin(lots, MaxLots);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(lotStep <= 0)
      return 0;

   lots = MathFloor(lots / lotStep + 1e-9) * lotStep;
   int lotDigits = (int)MathMax(0, MathCeil(-MathLog10(lotStep)));

   if(lots < minLot)
   {
      // On n'augmente pas le lot tout seul : le gain et la perte dépasseraient l'objectif
      Print("Lot calculé trop petit (", lots, "), minimum du courtier : ", minLot,
            " | gain au TP avec le lot minimum : ",
            DoubleToString(MoneyPerLot(tpDistance) * minLot, 2), " ", AccountInfoString(ACCOUNT_CURRENCY));
      return 0;
   }

   return NormalizeDouble(MathMin(lots, maxLot), lotDigits);
}

// Vrai si les distances SL/TP respectent le minimum du courtier
bool StopsAllowed(double slDistance, double tpDistance)
{
   double minDist = MinStopDistance();
   if(slDistance < minDist || (tpDistance > 0 && tpDistance < minDist))
   {
      Print("SL/TP trop proches : minimum du courtier = ", minDist, " en prix");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
// Ouvre une position dans le sens demandé (POSITION_TYPE_BUY / SELL)
void OpenPosition(long type, double unit)
{
   double slDistance = StopLoss   * unit;
   double tpDistance = TakeProfit * unit;

   if(!CheckSpread(slDistance) || !StopsAllowed(slDistance, tpDistance))
      return;

   double lots = CalculateLots(slDistance, tpDistance);
   if(lots <= 0)
      return;

   string currency   = AccountInfoString(ACCOUNT_CURRENCY);
   string moneyInfo  = " | Gain visé=" + DoubleToString(MoneyPerLot(tpDistance) * lots, 2) + " " + currency +
                       " Perte max=" + DoubleToString(MoneyPerLot(slDistance) * lots, 2) + " " + currency;

   trade.SetDeviationInPoints((ulong)MathMax(1, slDistance * MaxSlippagePercentOfSL / 100.0 / _Point));

   if(type == POSITION_TYPE_BUY)
   {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);   // on achète au Ask
      double sl    = NormalizeDouble(price - slDistance, _Digits);
      double tp    = (tpDistance > 0) ? NormalizeDouble(price + tpDistance, _Digits) : 0;

      if(trade.Buy(lots, _Symbol, price, sl, tp))
         Print("BUY exécuté | Lots=", lots, " SL=", sl, " TP=", tp, moneyInfo);
      else
         Print("BUY refusé : ", trade.ResultRetcodeDescription());
   }
   else
   {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);   // on vend au Bid
      double sl    = NormalizeDouble(price + slDistance, _Digits);
      double tp    = (tpDistance > 0) ? NormalizeDouble(price - tpDistance, _Digits) : 0;

      if(trade.Sell(lots, _Symbol, price, sl, tp))
         Print("SELL exécuté | Lots=", lots, " SL=", sl, " TP=", tp, moneyInfo);
      else
         Print("SELL refusé : ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
// Break-even puis trailing stop, appelé à chaque tick
void ManagePositions()
{
   if(BreakEvenTrigger <= 0 && TrailingStop <= 0)
      return;

   double unit = DistanceUnit();
   if(unit <= 0)
      return;

   double minDist = MinStopDistance();
   double step    = TrailingStep * unit;
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

         if(BreakEvenTrigger > 0 && profit >= BreakEvenTrigger * unit)
            newSL = MathMax(newSL, openPrice + BreakEvenLock * unit);

         if(TrailingStop > 0 && profit >= TrailingStop * unit)
            newSL = MathMax(newSL, bid - TrailingStop * unit);

         newSL = NormalizeDouble(newSL, _Digits);

         // On ne bouge le SL que vers le haut, d'au moins un pas, et à distance autorisée
         if(newSL > currentSL + step * 0.999 && bid - newSL >= minDist)
            trade.PositionModify(ticket, newSL, currentTP);
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double profit = openPrice - ask;

         if(BreakEvenTrigger > 0 && profit >= BreakEvenTrigger * unit)
            newSL = (newSL == 0) ? openPrice - BreakEvenLock * unit
                                 : MathMin(newSL, openPrice - BreakEvenLock * unit);

         if(TrailingStop > 0 && profit >= TrailingStop * unit)
            newSL = (newSL == 0) ? ask + TrailingStop * unit
                                 : MathMin(newSL, ask + TrailingStop * unit);

         newSL = NormalizeDouble(newSL, _Digits);

         // On ne bouge le SL que vers le bas, d'au moins un pas, et à distance autorisée
         if(newSL > 0 &&
            (currentSL == 0 || newSL < currentSL - step * 0.999) &&
            newSL - ask >= minDist)
            trade.PositionModify(ticket, newSL, currentTP);
      }
   }
}

//+------------------------------------------------------------------+
// Ferme les positions du bot sur ce symbole ; type = -1 pour toutes,
// sinon seulement POSITION_TYPE_BUY ou POSITION_TYPE_SELL
void ClosePositions(long type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber &&
         (type < 0 || PositionGetInteger(POSITION_TYPE) == type))
         trade.PositionClose(ticket);
   }
}

void CloseAllTrades()
{
   ClosePositions(-1);
   Print("Toutes les positions du bot ont été fermées automatiquement.");
}

//+------------------------------------------------------------------+
// Tendance : +1 haussière, -1 baissière, 0 pas de tendance claire.
// M1 : EMA rapide au-dessus de l'EMA lente, EMA lente qui monte, et
// clôture au-dessus de l'EMA lente (inverse pour la baisse).
// Option : clôture de l'unité de temps supérieure du même côté de son EMA.
int GetTrend(const double &fast[], const double &slow[], const double &close[])
{
   int trend = 0;

   if(fast[1] > slow[1] && slow[1] > slow[3] && close[1] > slow[1])
      trend = 1;
   else if(fast[1] < slow[1] && slow[1] < slow[3] && close[1] < slow[1])
      trend = -1;

   if(trend == 0 || !UseHigherTimeframe)
      return trend;

   double htfEma[], htfClose[];
   ArraySetAsSeries(htfEma, true);
   ArraySetAsSeries(htfClose, true);

   if(CopyBuffer(htfHandle, 0, 0, 2, htfEma) < 2 ||
      CopyClose(_Symbol, TrendTimeframe, 0, 2, htfClose) < 2)
      return 0;

   if(trend ==  1 && htfClose[1] > htfEma[1]) return  1;
   if(trend == -1 && htfClose[1] < htfEma[1]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
void OnTick()
{
   // La gestion des positions ouvertes se fait à chaque tick
   ManagePositions();

   // Les nouvelles entrées : une fois par bougie M1 clôturée
   if(!IsNewBar())
      return;

   // Index 1 = dernière bougie clôturée, index 2 = celle d'avant, etc.
   double fast[], slow[], rsi[], open[], high[], low[], close[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   if(CopyBuffer(fastHandle, 0, 0, 4, fast) < 4 ||
      CopyBuffer(slowHandle, 0, 0, 4, slow) < 4 ||
      CopyBuffer(rsiHandle,  0, 0, 4, rsi)  < 4 ||
      CopyOpen (_Symbol, PERIOD_M1, 0, 4, open)  < 4 ||
      CopyHigh (_Symbol, PERIOD_M1, 0, 4, high)  < 4 ||
      CopyLow  (_Symbol, PERIOD_M1, 0, 4, low)   < 4 ||
      CopyClose(_Symbol, PERIOD_M1, 0, 4, close) < 4)
      return;   // données pas encore prêtes

   // Sortie si la tendance M1 s'est retournée contre la position
   if(CloseOnTrendReversal)
   {
      if(fast[1] < slow[1]) ClosePositions(POSITION_TYPE_BUY);
      if(fast[1] > slow[1]) ClosePositions(POSITION_TYPE_SELL);
   }

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

   if(DailyProfitTargetMoney > 0 && profitToday >= DailyProfitTargetMoney)
      return;

   int trend = GetTrend(fast, slow, close);
   if(trend == 0)
      return;

   double unit = DistanceUnit();
   if(unit <= 0)
      return;

   double tolerance = PullbackTolerance * unit;

   // Achat : en tendance haussière, le prix revient toucher l'EMA rapide
   // puis la bougie clôture en hausse au-dessus d'elle (on reprend le train).
   bool buySignal = trend == 1 &&
                    MathMin(low[1], low[2]) <= fast[1] + tolerance &&
                    close[1] > fast[1] &&
                    close[1] > open[1] &&
                    rsi[1] > RsiMidLevel;

   // Vente : symétrique en tendance baissière
   bool sellSignal = trend == -1 &&
                     MathMax(high[1], high[2]) >= fast[1] - tolerance &&
                     close[1] < fast[1] &&
                     close[1] < open[1] &&
                     rsi[1] < RsiMidLevel;

   if(buySignal)
      OpenPosition(POSITION_TYPE_BUY, unit);
   else if(sellSignal)
      OpenPosition(POSITION_TYPE_SELL, unit);
}
//+------------------------------------------------------------------+
