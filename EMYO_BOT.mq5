//+------------------------------------------------------------------+
//|              EMYO BOT - SCALPING M1 SUIVI DE TENDANCE             |
//|        Or (XAUUSD), Bitcoin (BTCUSD), NASDAQ (NAS100/USTEC)       |
//+------------------------------------------------------------------+
#property copyright "EMYO"
#property version   "1.80"

#include <Trade\Trade.mqh>

enum ENUM_TRADING_STYLE
{
   STYLE_NORMAL     = 0,  // Normal (réglages ci-dessous)
   STYLE_AGGRESSIVE = 1   // Agressif (plus d'entrées, plus de positions)
};

enum ENUM_ENTRY_MODE
{
   ENTRY_MOMENTUM = 0,  // Momentum (cassure avec une bougie forte)
   ENTRY_PULLBACK = 1,  // Repli sur l'EMA rapide
   ENTRY_BOTH     = 2   // Les deux
};

enum ENUM_SESSION_MODE
{
   SESSION_NEW_YORK = 0,  // Session américaine (heure de New York)
   SESSION_SERVER   = 1,  // Plage StartHour / EndHour (heure serveur)
   SESSION_ALWAYS   = 2   // 24h/24
};

enum ENUM_DISTANCE_MODE
{
   DISTANCE_ATR  = 0,   // ATR (s'adapte à chaque marché)
   DISTANCE_PIPS = 1    // Pips fixes (forex)
};

//---------------------- PARAMÈTRES DU BOT --------------------------
input group "Style"
input ENUM_TRADING_STYLE TradingStyle = STYLE_AGGRESSIVE;

input group "Taille des positions"
input double TargetProfitMoney  = 3;     // Gain visé par trade, en devise du compte (0 = off)
input double RiskPercent        = 0;     // % du solde risqué par trade (si TargetProfitMoney = 0)
input double Lots               = 0.01;  // Lot fixe (si TargetProfitMoney = 0 et RiskPercent = 0)
input double MaxLots            = 1.0;   // Lot maximum autorisé par position, quel que soit le calcul

input group "Positions simultanées"
input int    TradesPerSignal    = 3;     // Positions ouvertes ensemble à chaque signal
input int    MaxOpenPositions   = 3;     // Positions ouvertes en même temps au maximum (ce symbole)
input bool   AddOnlyWhenProtected = true; // Nouvelles positions seulement si les ouvertes sont au break-even
input double TakeProfitStep     = 0.5;   // Écart entre les TP des positions (en ATR) : 1 / 1.5 / 2...

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
input ENUM_ENTRY_MODE EntryMode = ENTRY_MOMENTUM;
input int    MomentumLookback   = 5;     // La bougie doit casser le plus haut / bas de ces N bougies
input double MomentumBody       = 0.8;   // Corps minimum de la bougie de momentum (en ATR)
input double MomentumCloseRatio = 0.7;   // Clôture dans les 30 % hauts (achat) / bas (vente) de la bougie
input int    RsiPeriod          = 14;    // Période du RSI
input double RsiMidLevel        = 50;    // Repli : RSI > niveau pour acheter, < niveau pour vendre
input double RsiMomentumLevel   = 55;    // Momentum : RSI > niveau (achat) ou < 100 - niveau (vente)

input group "Filtres"
input double MaxSpreadPercentOfSL  = 20; // Spread max. en % du Stop Loss (0 = off)
input double MaxSpreadPoints       = 0;  // Spread max. en points (0 = off)
input double MaxSlippagePercentOfSL = 10; // Glissement max. accepté en % du Stop Loss

input group "Session de trading"
input ENUM_SESSION_MODE SessionMode = SESSION_NEW_YORK;
input int    NyStartHour        = 9;     // Début, heure de New York
input int    NyStartMinute      = 30;
input int    NyEndHour          = 16;    // Fin, heure de New York
input int    NyEndMinute        = 0;
input bool   WeekdaysOnly       = true;  // Lundi à vendredi uniquement (heure de New York)
input bool   CloseOutsideSession = true; // Fermer les positions à la fin de la session
input int    ServerGmtOffset    = 99;    // Décalage GMT du serveur en heures (99 = auto)
input int    StartHour          = 0;     // Mode serveur : heure de début
input int    EndHour            = 0;     // Mode serveur : heure de fin (exclue)

input group "Sécurité"
input int    MaxTradesPerDay    = 60;    // Positions ouvertes par jour au maximum (0 = illimité)
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

// Réglages effectifs : ceux des paramètres, ou ceux du style agressif
ENUM_ENTRY_MODE gEntryMode;
bool            gUseHigherTimeframe;
bool            gRequireSlope;
int             gMomentumLookback;
double          gMomentumBody;
double          gMomentumCloseRatio;
double          gRsiMomentumLevel;
int             gMaxOpenPositions;
int             gMaxTradesPerDay;

void ApplyTradingStyle()
{
   gEntryMode          = EntryMode;
   gUseHigherTimeframe = UseHigherTimeframe;
   gRequireSlope       = true;
   gMomentumLookback   = MomentumLookback;
   gMomentumBody       = MomentumBody;
   gMomentumCloseRatio = MomentumCloseRatio;
   gRsiMomentumLevel   = RsiMomentumLevel;
   gMaxOpenPositions   = MaxOpenPositions;
   gMaxTradesPerDay    = MaxTradesPerDay;

   if(TradingStyle == STYLE_AGGRESSIVE)
   {
      gEntryMode          = ENTRY_BOTH;  // momentum ET replis
      gUseHigherTimeframe = false;       // réagit à la tendance M1 sans attendre le M15
      gRequireSlope       = false;       // EMA 20 / EMA 50 alignées suffisent
      gMomentumLookback   = 3;           // cassure des 3 dernières bougies
      gMomentumBody       = 0.5;         // bougies moins grandes acceptées
      gMomentumCloseRatio = 0.6;
      gRsiMomentumLevel   = 52;
      gMaxOpenPositions   = (int)MathMax(MaxOpenPositions, 9);  // jusqu'à 3 paniers de 3
      gMaxTradesPerDay    = 0;           // pas de limite de nombre
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(StopLoss <= 0 || TakeProfit < 0 || AtrPeriod <= 0 || RsiPeriod <= 0 ||
      FastEmaPeriod <= 0 || SlowEmaPeriod <= FastEmaPeriod || TrendEmaPeriod <= 0 ||
      StartHour < 0 || StartHour > 23 || EndHour < 0 || EndHour > 23 ||
      NyStartHour < 0 || NyStartHour > 23 || NyEndHour < 0 || NyEndHour > 23 ||
      NyStartMinute < 0 || NyStartMinute > 59 || NyEndMinute < 0 || NyEndMinute > 59 ||
      Lots <= 0 || RiskPercent < 0 || TargetProfitMoney < 0 || MaxLots <= 0 ||
      (TargetProfitMoney > 0 && TakeProfit <= 0) ||
      TradesPerSignal < 1 || MaxOpenPositions < 1 || TakeProfitStep < 0 ||
      MomentumLookback < 1 || MomentumBody < 0 ||
      MomentumCloseRatio < 0 || MomentumCloseRatio > 1)
   {
      Print("Erreur : paramètres invalides");
      return(INIT_PARAMETERS_INCORRECT);
   }

   ApplyTradingStyle();

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

   Print("Bot lancé sur ", _Symbol,
         " | style ", TradingStyle == STYLE_AGGRESSIVE ? "AGRESSIF" : "normal",
         " | heure de New York : ",
         TimeToString(NewYorkTime(), TIME_DATE | TIME_MINUTES),
         " | session ", IsTradingHour() ? "ouverte" : "fermée");
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

// Date du n-ième dimanche d'un mois (à minuit)
datetime NthSunday(int year, int month, int n)
{
   MqlDateTime dt;
   ZeroMemory(dt);
   dt.year = year;
   dt.mon  = month;
   dt.day  = 1;
   datetime first = StructToTime(dt);
   TimeToStruct(first, dt);

   int firstSunday = 1 + (7 - dt.day_of_week) % 7;
   return first + (firstSunday - 1 + 7 * (n - 1)) * 86400;
}

// Heure d'été américaine : du 2e dimanche de mars 2h (7h GMT)
// au 1er dimanche de novembre 2h (6h GMT)
bool IsUsDst(datetime gmt)
{
   MqlDateTime dt;
   TimeToStruct(gmt, dt);

   datetime start = NthSunday(dt.year, 3, 2)  + 7 * 3600;
   datetime end   = NthSunday(dt.year, 11, 1) + 6 * 3600;
   return gmt >= start && gmt < end;
}

// Décalage GMT du serveur, en secondes
int ServerOffsetSeconds()
{
   if(ServerGmtOffset != 99)
      return ServerGmtOffset * 3600;

   // En backtest, TimeGMT() n'est pas fiable : on suppose le réglage le plus
   // courant des courtiers MT5 (GMT+2 l'hiver, GMT+3 pendant l'heure d'été US).
   if(MQLInfoInteger(MQL_TESTER))
      return (IsUsDst(TimeCurrent() - 2 * 3600) ? 3 : 2) * 3600;

   // En réel : écart entre l'heure du serveur et l'heure GMT, arrondi à 30 min
   double diff = (double)(TimeTradeServer() - TimeGMT());
   return (int)(MathRound(diff / 1800.0) * 1800);
}

// Heure actuelle à New York
datetime NewYorkTime()
{
   datetime gmt = TimeCurrent() - ServerOffsetSeconds();
   return gmt + (IsUsDst(gmt) ? -4 : -5) * 3600;
}

// Vrai si l'on est dans la session de trading choisie
bool IsTradingHour()
{
   if(SessionMode == SESSION_ALWAYS)
      return true;

   MqlDateTime now;

   if(SessionMode == SESSION_NEW_YORK)
   {
      TimeToStruct(NewYorkTime(), now);

      if(WeekdaysOnly && (now.day_of_week == 0 || now.day_of_week == 6))
         return false;

      int minutes = now.hour * 60 + now.min;
      int start   = NyStartHour * 60 + NyStartMinute;
      int end     = NyEndHour   * 60 + NyEndMinute;

      if(start < end)
         return minutes >= start && minutes < end;
      return minutes >= start || minutes < end;   // plage qui passe minuit
   }

   // Mode serveur
   if(StartHour == EndHour)
      return true;

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

// Vrai si toutes les positions du bot ont leur SL au prix d'entrée ou au-delà
// (elles ne peuvent plus perdre)
bool AllPositionsProtected()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);

      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         if(sl < openPrice)
            return false;
      }
      else if(sl == 0 || sl > openPrice)
         return false;
   }
   return true;
}

// Nombre de positions du bot sur ce symbole ; 'direction' reçoit
// +1 (achats), -1 (ventes) ou 0 (aucune position)
int CountOpenPositions(int &direction)
{
   int count = 0;
   direction = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber)
      {
         count++;
         direction = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      }
   }
   return count;
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
// Ouvre une position dans le sens demandé (POSITION_TYPE_BUY / SELL),
// avec un TP à 'tpMultiple' unités (0 = pas de TP)
void OpenPosition(long type, double unit, double tpMultiple)
{
   double slDistance = StopLoss   * unit;
   double tpDistance = tpMultiple * unit;

   if(!StopsAllowed(slDistance, tpDistance))
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
         Print("BUY exécuté | TP à ", DoubleToString(tpMultiple, 1), " | Lots=", lots, " SL=", sl, " TP=", tp, moneyInfo);
      else
         Print("BUY refusé : ", trade.ResultRetcodeDescription());
   }
   else
   {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);   // on vend au Bid
      double sl    = NormalizeDouble(price + slDistance, _Digits);
      double tp    = (tpDistance > 0) ? NormalizeDouble(price - tpDistance, _Digits) : 0;

      if(trade.Sell(lots, _Symbol, price, sl, tp))
         Print("SELL exécuté | TP à ", DoubleToString(tpMultiple, 1), " | Lots=", lots, " SL=", sl, " TP=", tp, moneyInfo);
      else
         Print("SELL refusé : ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
// Ouvre 'count' positions ensemble, avec des TP échelonnés :
// TakeProfit, TakeProfit + TakeProfitStep, TakeProfit + 2 x TakeProfitStep...
void OpenBasket(long type, double unit, int count)
{
   if(!CheckSpread(StopLoss * unit))
      return;

   for(int k = 0; k < count; k++)
   {
      double tpMultiple = (TakeProfit > 0) ? TakeProfit + k * TakeProfitStep : 0;
      OpenPosition(type, unit, tpMultiple);
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

   if(fast[1] > slow[1] && (!gRequireSlope || slow[1] > slow[3]) && close[1] > slow[1])
      trend = 1;
   else if(fast[1] < slow[1] && (!gRequireSlope || slow[1] < slow[3]) && close[1] < slow[1])
      trend = -1;

   if(trend == 0 || !gUseHigherTimeframe)
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
   // Fin de session : on ne garde aucune position en dehors
   if(CloseOutsideSession && !IsTradingHour())
   {
      int direction = 0;
      if(CountOpenPositions(direction) > 0)
      {
         ClosePositions(-1);
         Print("Fin de session : positions fermées.");
      }
   }

   // La gestion des positions ouvertes se fait à chaque tick
   ManagePositions();

   // Les nouvelles entrées : une fois par bougie M1 clôturée
   if(!IsNewBar())
      return;

   // Index 1 = dernière bougie clôturée, index 2 = celle d'avant, etc.
   int bars = MathMax(4, gMomentumLookback + 2);

   double fast[], slow[], rsi[], open[], high[], low[], close[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   if(CopyBuffer(fastHandle, 0, 0, bars, fast) < bars ||
      CopyBuffer(slowHandle, 0, 0, bars, slow) < bars ||
      CopyBuffer(rsiHandle,  0, 0, bars, rsi)  < bars ||
      CopyOpen (_Symbol, PERIOD_M1, 0, bars, open)  < bars ||
      CopyHigh (_Symbol, PERIOD_M1, 0, bars, high)  < bars ||
      CopyLow  (_Symbol, PERIOD_M1, 0, bars, low)   < bars ||
      CopyClose(_Symbol, PERIOD_M1, 0, bars, close) < bars)
      return;   // données pas encore prêtes

   // Sortie si la tendance M1 s'est retournée contre les positions
   if(CloseOnTrendReversal)
   {
      if(fast[1] < slow[1]) ClosePositions(POSITION_TYPE_BUY);
      if(fast[1] > slow[1]) ClosePositions(POSITION_TYPE_SELL);
   }

   if(!IsTradingHour())
      return;

   int openDirection = 0;
   int openCount     = CountOpenPositions(openDirection);
   int room          = gMaxOpenPositions - openCount;
   if(room <= 0)
      return;

   int    tradesToday = 0;
   double profitToday = 0;
   GetTodayStats(tradesToday, profitToday);

   if(gMaxTradesPerDay > 0 && tradesToday >= gMaxTradesPerDay)
      return;

   if(MaxDailyLossPercent > 0 &&
      profitToday <= -AccountInfoDouble(ACCOUNT_BALANCE) * MaxDailyLossPercent / 100.0)
      return;

   if(DailyProfitTargetMoney > 0 && profitToday >= DailyProfitTargetMoney)
      return;

   int trend = GetTrend(fast, slow, close);
   if(trend == 0)
      return;

   // Jamais de positions dans les deux sens en même temps
   if(openDirection != 0 && openDirection != trend)
      return;

   // On n'ajoute un panier que si les positions déjà ouvertes ne peuvent plus perdre
   if(openCount > 0 && AddOnlyWhenProtected && !AllPositionsProtected())
      return;

   double unit = DistanceUnit();
   if(unit <= 0)
      return;

   bool buySignal  = false;
   bool sellSignal = false;

   // Momentum : bougie forte dans le sens de la tendance, qui clôture près
   // de son extrême et casse le plus haut / plus bas des dernières bougies.
   if(gEntryMode == ENTRY_MOMENTUM || gEntryMode == ENTRY_BOTH)
   {
      double range     = high[1] - low[1];
      double priorHigh = high[ArrayMaximum(high, 2, gMomentumLookback)];
      double priorLow  = low [ArrayMinimum(low,  2, gMomentumLookback)];

      if(range > 0)
      {
         buySignal = buySignal ||
                     (trend == 1 &&
                      close[1] - open[1] >= gMomentumBody * unit &&
                      (close[1] - low[1]) / range >= gMomentumCloseRatio &&
                      close[1] > priorHigh &&
                      rsi[1] > gRsiMomentumLevel && rsi[1] > rsi[2]);

         sellSignal = sellSignal ||
                      (trend == -1 &&
                       open[1] - close[1] >= gMomentumBody * unit &&
                       (high[1] - close[1]) / range >= gMomentumCloseRatio &&
                       close[1] < priorLow &&
                       rsi[1] < 100 - gRsiMomentumLevel && rsi[1] < rsi[2]);
      }
   }

   // Repli : le prix revient toucher l'EMA rapide puis repart dans la tendance
   if(gEntryMode == ENTRY_PULLBACK || gEntryMode == ENTRY_BOTH)
   {
      double tolerance = PullbackTolerance * unit;

      buySignal = buySignal ||
                  (trend == 1 &&
                   MathMin(low[1], low[2]) <= fast[1] + tolerance &&
                   close[1] > fast[1] &&
                   close[1] > open[1] &&
                   rsi[1] > RsiMidLevel);

      sellSignal = sellSignal ||
                   (trend == -1 &&
                    MathMax(high[1], high[2]) >= fast[1] - tolerance &&
                    close[1] < fast[1] &&
                    close[1] < open[1] &&
                    rsi[1] < RsiMidLevel);
   }

   int count = MathMin(TradesPerSignal, room);
   if(gMaxTradesPerDay > 0)
      count = MathMin(count, gMaxTradesPerDay - tradesToday);

   if(buySignal)
      OpenBasket(POSITION_TYPE_BUY, unit, count);
   else if(sellSignal)
      OpenBasket(POSITION_TYPE_SELL, unit, count);
}
//+------------------------------------------------------------------+
