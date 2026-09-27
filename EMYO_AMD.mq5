//+------------------------------------------------------------------+
//|          EMYO AMD - ACCUMULATION / MANIPULATION / DISTRIBUTION    |
//|  Accumulation = range asiatique ; manipulation = le prix casse    |
//|  un côté du range contre la tendance (chasse aux stops) ;         |
//|  distribution = retour dans le range + CHoCH M1 dans le sens de   |
//|  la tendance, objectif sur la liquidité de l'autre côté.          |
//+------------------------------------------------------------------+
#property copyright "EMYO"
#property version   "1.00"

#include <Trade\Trade.mqh>

enum ENUM_TARGET_MODE
{
   TARGET_LIQUIDITY = 0,  // 1er TP sur l'autre côté du range asiatique (liquidité)
   TARGET_RR        = 1   // TP à 1R / 2R / 3R comme EMYO SMC
};

enum ENUM_SESSION_MODE
{
   SESSION_NEW_YORK = 0,  // Session américaine (heure de New York)
   SESSION_SERVER   = 1,  // Plage StartHour / EndHour (heure serveur)
   SESSION_ALWAYS   = 2   // 24h/24
};

//---------------------- PARAMÈTRES DU BOT --------------------------
input group "Mode"
input bool   AlertsOnly         = false; // Ne pas trader : envoyer seulement les signaux (entrée, SL, TP)
input bool   SendPushAlerts     = true;  // Envoyer chaque signal sur le téléphone (MetaQuotes ID)

input group "Taille des positions"
input double TargetProfitMoney  = 0;     // Gain visé par position au TP, devise du compte (0 = off)
input double MaxProfitAtMinLot  = 10;    // Si le lot minimum dépasse l'objectif : accepté jusqu'à ce gain
input double RiskPercent        = 0;     // % du solde risqué par position (si TargetProfitMoney = 0)
input double Lots               = 0.01;  // Lot fixe (si TargetProfitMoney = 0 et RiskPercent = 0)
input double MaxLots            = 1.0;   // Lot maximum par position

input group "Positions et objectifs"
input int    TradesPerSignal    = 3;     // Positions ouvertes ensemble à chaque signal
input ENUM_TARGET_MODE TargetMode = TARGET_LIQUIDITY;
input double MinFirstTargetRR   = 1.0;   // Mode liquidité : l'autre côté du range doit être à au moins N x le risque
input double FirstTargetRR      = 1.0;   // Mode R : TP de la 1re position (1 = 1R)
input double TargetStepRR       = 1.0;   // Écart entre les TP suivants, en multiple du risque
input int    MaxOpenPositions   = 3;     // Positions ouvertes en même temps au maximum (ce symbole)
input double BreakEvenRR        = 1.0;   // Passage au break-even quand le gain atteint ce multiple du risque (0 = off)
input double BreakEvenLockRR    = 0.1;   // Gain sécurisé au break-even (en multiple du risque)
input bool   UseRunner          = false; // Dernière position sans TP : elle suit le mouvement (trailing)
input double RunnerTrailAtr     = 2.0;   // Distance du trailing du runner (en ATR M5)

input group "Tendance de fond"
input ENUM_TIMEFRAMES BiasTimeframe1 = PERIOD_H1;  // 1re unité de temps de tendance
input ENUM_TIMEFRAMES BiasTimeframe2 = PERIOD_H4;  // 2e unité de temps de tendance
input bool            UseBiasTimeframe2 = true;    // Exiger aussi la 2e unité de temps
input int             BiasEmaPeriod  = 50;         // EMA de tendance (prix au-dessus = haussier)

input group "Accumulation (range asiatique, heure de New York)"
input int    AsiaStartHour      = 20;    // Début du range (la veille au soir)
input int    AsiaEndHour        = 0;     // Fin du range (0 = minuit ; 8 = inclure Londres)
input int    MinAsiaBars        = 60;    // Bougies M1 minimum dans le range (sinon jour ignoré)

input group "Manipulation + confirmation (M1)"
input int    ConfirmLookback    = 30;    // La chasse aux stops doit dater de moins de N bougies M1
input int    PivotStrength      = 2;     // Bougies de chaque côté pour valider un point haut / bas
input int    ChochMaxBars       = 15;    // Distance max. entre l'extrême et le point à casser
input double SlBufferAtr        = 0.2;   // Marge au-delà de la mèche de manipulation (ATR M1)
input double MinRiskAtr         = 0.5;   // Risque minimum (en ATR M1)
input double MaxRiskAtr         = 6.0;   // Risque maximum (en ATR M1)

input group "Filtres"
input double MaxSpreadPercentOfRisk = 15; // Spread max. en % du risque (0 = off)
input double MaxSlippagePercentOfRisk = 10; // Glissement max. accepté en % du risque

input group "Session de trading (entrées)"
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
input int    MaxSignalsPerDay   = 1;     // Signaux par jour au maximum (1 AMD par jour)
input double MaxDailyLossPercent = 3;    // Arrêt du jour après cette perte en % (0 = off)
input ulong  MagicNumber        = 360039;
input bool   AutoCloseOnStop    = true;  // Fermer les positions quand le bot est retiré
input bool   ShowPanel          = true;  // Afficher le compteur de gains sur le graphique

//---------------------- VARIABLES GLOBALES --------------------------
CTrade   trade;
int      biasHandle1 = INVALID_HANDLE;
int      biasHandle2 = INVALID_HANDLE;
int      atrM1Handle = INVALID_HANDLE;
int      atrSetupHandle = INVALID_HANDLE;   // ATR M5 (trailing du runner)
datetime lastBarTime = 0;

datetime asiaDay    = 0;      // jour (New York, minuit) du range calculé
bool     asiaValid  = false;
double   asiaHigh   = 0;
double   asiaLow    = 0;
datetime asiaEndSrv = 0;      // fin du range, heure serveur
double   postHigh   = 0;      // plus haut / plus bas depuis la fin du range
double   postLow    = 0;
datetime signalDay  = 0;
int      signalsToday = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if(TradesPerSignal < 1 || MinFirstTargetRR < 0 || FirstTargetRR <= 0 || TargetStepRR < 0 ||
      MaxOpenPositions < 1 || BreakEvenRR < 0 || BreakEvenLockRR < 0 || RunnerTrailAtr <= 0 ||
      BiasEmaPeriod <= 0 || AsiaStartHour < 0 || AsiaStartHour > 23 || AsiaEndHour < 0 ||
      AsiaEndHour > 23 || AsiaStartHour == AsiaEndHour || MinAsiaBars < 1 ||
      ConfirmLookback < 5 || PivotStrength < 1 || ChochMaxBars < 2 ||
      SlBufferAtr < 0 || MinRiskAtr < 0 || MaxRiskAtr <= MinRiskAtr ||
      NyStartHour < 0 || NyStartHour > 23 || NyEndHour < 0 || NyEndHour > 23 ||
      NyStartMinute < 0 || NyStartMinute > 59 || NyEndMinute < 0 || NyEndMinute > 59 ||
      StartHour < 0 || StartHour > 23 || EndHour < 0 || EndHour > 23 || MaxSignalsPerDay < 1 ||
      Lots <= 0 || RiskPercent < 0 || TargetProfitMoney < 0 || MaxProfitAtMinLot < 0 || MaxLots <= 0)
   {
      Print("Erreur : paramètres invalides");
      return(INIT_PARAMETERS_INCORRECT);
   }

   biasHandle1    = iMA(_Symbol, BiasTimeframe1, BiasEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   biasHandle2    = iMA(_Symbol, BiasTimeframe2, BiasEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atrM1Handle    = iATR(_Symbol, PERIOD_M1, 14);
   atrSetupHandle = iATR(_Symbol, PERIOD_M5, 14);

   if(biasHandle1 == INVALID_HANDLE || biasHandle2 == INVALID_HANDLE ||
      atrM1Handle == INVALID_HANDLE || atrSetupHandle == INVALID_HANDLE)
   {
      Print("Erreur : impossible de créer les indicateurs");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);

   Print("EMYO AMD lancé sur ", _Symbol,
         " | heure de New York : ", TimeToString(NewYorkTime(), TIME_DATE | TIME_MINUTES),
         " | session ", (IsTradingHour() ? "ouverte" : "fermée"));
   UpdatePanel();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(AutoCloseOnStop &&
      reason != REASON_CHARTCHANGE &&
      reason != REASON_PARAMETERS  &&
      reason != REASON_RECOMPILE)
      ClosePositions(-1);

   if(biasHandle1    != INVALID_HANDLE) IndicatorRelease(biasHandle1);
   if(biasHandle2    != INVALID_HANDLE) IndicatorRelease(biasHandle2);
   if(atrM1Handle    != INVALID_HANDLE) IndicatorRelease(atrM1Handle);
   if(atrSetupHandle != INVALID_HANDLE) IndicatorRelease(atrSetupHandle);

   Comment("");
   Print("EMYO AMD arrêté");
}

//+----------------------- SESSION / HEURES -------------------------+
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

   double diff = (double)(TimeTradeServer() - TimeGMT());
   return (int)(MathRound(diff / 1800.0) * 1800);
}

datetime NewYorkTime()
{
   datetime gmt = TimeCurrent() - ServerOffsetSeconds();
   return gmt + (IsUsDst(gmt) ? -4 : -5) * 3600;
}

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
      return minutes >= start || minutes < end;
   }

   if(StartHour == EndHour)
      return true;

   TimeToStruct(TimeCurrent(), now);

   if(StartHour < EndHour)
      return now.hour >= StartHour && now.hour < EndHour;
   return now.hour >= StartHour || now.hour < EndHour;
}

bool IsNewBar()
{
   datetime barTime = iTime(_Symbol, PERIOD_M1, 0);
   if(barTime == lastBarTime)
      return false;

   lastBarTime = barTime;
   return true;
}

//+----------------------- COMPTE / POSITIONS -----------------------+
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

bool IsOwnPosition()
{
   return PositionGetString(POSITION_SYMBOL) == _Symbol &&
          PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber;
}

double FloatingProfit()
{
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0 || !IsOwnPosition())
         continue;
      total += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return total;
}

// Nombre de positions du bot ; 'direction' reçoit +1 (achats), -1 (ventes) ou 0
int CountOpenPositions(int &direction)
{
   int count = 0;
   direction = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0 || !IsOwnPosition())
         continue;
      count++;
      direction = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
   }
   return count;
}

// Vrai si toutes les positions du bot ont leur SL au prix d'entrée ou au-delà
bool AllPositionsProtected()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0 || !IsOwnPosition())
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

// type = -1 pour toutes, sinon POSITION_TYPE_BUY ou POSITION_TYPE_SELL
void ClosePositions(long type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOwnPosition())
         continue;

      if(type < 0 || PositionGetInteger(POSITION_TYPE) == type)
         trade.PositionClose(ticket);
   }
}

//+----------------------- TAILLE DES LOTS --------------------------+
double MoneyPerLot(double distance)
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0)
      return 0;
   return distance / tickSize * tickValue;
}

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

   if(lots < minLot && TargetProfitMoney > 0 &&
      MoneyPerLot(tpDistance) * minLot <= MaxProfitAtMinLot)
      lots = minLot;

   if(lots < minLot)
   {
      Print("Lot calculé trop petit (", lots, "), minimum du courtier : ", minLot,
            " | gain au TP avec le lot minimum : ",
            DoubleToString(MoneyPerLot(tpDistance) * minLot, 2), " ", AccountInfoString(ACCOUNT_CURRENCY));
      return 0;
   }

   return NormalizeDouble(MathMin(lots, maxLot), lotDigits);
}

//+----------------------- INDICATEURS ------------------------------+
double LastValue(int handle)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, 0, 2, buf) < 2)
      return 0;
   return buf[1];
}

// Tendance de fond : +1 si la dernière clôture est au-dessus de l'EMA
// sur la (les) unité(s) de temps de tendance, -1 si en dessous, 0 sinon
int GetBias()
{
   double ema1 = LastValue(biasHandle1);
   double close1 = iClose(_Symbol, BiasTimeframe1, 1);
   if(ema1 <= 0 || close1 <= 0)
      return 0;

   int bias = (close1 > ema1) ? 1 : (close1 < ema1 ? -1 : 0);
   if(bias == 0 || !UseBiasTimeframe2)
      return bias;

   double ema2 = LastValue(biasHandle2);
   double close2 = iClose(_Symbol, BiasTimeframe2, 1);
   if(ema2 <= 0 || close2 <= 0)
      return 0;

   if(bias ==  1 && close2 > ema2) return  1;
   if(bias == -1 && close2 < ema2) return -1;
   return 0;
}

//+----------------------- CONFIRMATION M1 --------------------------+
// Point haut confirmé : plus haut que les PivotStrength bougies de chaque côté
bool IsPivotHigh(const double &high[], int j, int size)
{
   for(int k = 1; k <= PivotStrength; k++)
   {
      if(j - k < 1 || j + k >= size)
         return false;
      if(high[j] <= high[j - k] || high[j] < high[j + k])
         return false;
   }
   return true;
}

bool IsPivotLow(const double &low[], int j, int size)
{
   for(int k = 1; k <= PivotStrength; k++)
   {
      if(j - k < 1 || j + k >= size)
         return false;
      if(low[j] >= low[j - k] || low[j] > low[j + k])
         return false;
   }
   return true;
}

// Zone OTE : la correction doit revenir entre OteMinLevel et OteMaxLevel de l'impulsion
// (0 % = extrême de l'impulsion, 100 % = départ du bloc). 'price' = extrême de la correction.
bool InOteZone(const OrderBlock &ob, double price)
{
   if(!RequireOte)
      return true;

   double start = (ob.dir == 1) ? ob.bottom : ob.top;
   double range = MathAbs(ob.extreme - start);
   if(range <= 0)
      return false;

   double retracement = MathAbs(ob.extreme - price) / range;
   return retracement >= OteMinLevel && retracement <= OteMaxLevel;
}

//+----------------------- GESTION ----------------------------------+
// Break-even : quand le gain atteint BreakEvenRR fois le risque initial,
// le SL passe au prix d'entrée + BreakEvenLockRR fois le risque.
// Runner (position sans TP) : une fois protégé, son SL suit le prix à
// RunnerTrailAtr x ATR ; il se ferme au SL ou en fin de session.
void ManagePositions()
{
   if(BreakEvenRR <= 0 && !UseRunner)
      return;

   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double trail   = UseRunner ? RunnerTrailAtr * LastValue(atrSetupHandle) : 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOwnPosition())
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      bool   isRunner  = UseRunner && tp == 0;

      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         if(sl > 0 && sl < openPrice)
         {
            // Pas encore protégée : break-even
            double risk = openPrice - sl;
            if(BreakEvenRR > 0 && bid - openPrice >= BreakEvenRR * risk)
            {
               double newSL = NormalizeDouble(openPrice + BreakEvenLockRR * risk, _Digits);
               if(bid - newSL >= minDist)
                  trade.PositionModify(ticket, newSL, tp);
            }
         }
         else if(isRunner && trail > 0 && sl > 0)
         {
            // Protégée : le SL du runner suit le prix vers le haut
            double newSL = NormalizeDouble(bid - trail, _Digits);
            if(newSL > sl + 0.1 * trail && bid - newSL >= minDist)
               trade.PositionModify(ticket, newSL, tp);
         }
      }
      else
      {
         if(sl > 0 && sl > openPrice)
         {
            double risk = sl - openPrice;
            if(BreakEvenRR > 0 && openPrice - ask >= BreakEvenRR * risk)
            {
               double newSL = NormalizeDouble(openPrice - BreakEvenLockRR * risk, _Digits);
               if(newSL - ask >= minDist)
                  trade.PositionModify(ticket, newSL, tp);
            }
         }
         else if(isRunner && trail > 0 && sl > 0)
         {
            double newSL = NormalizeDouble(ask + trail, _Digits);
            if(newSL < sl - 0.1 * trail && newSL - ask >= minDist)
               trade.PositionModify(ticket, newSL, tp);
         }
      }
   }
}

//+----------------------- RANGE ASIATIQUE --------------------------+
// Calcule le range d'accumulation du jour (heure de New York) puis le plus haut
// et le plus bas atteints depuis sa fin (bougies M1 clôturées).
// Renvoie faux tant que le range du jour n'est pas terminé ou pas exploitable.
bool UpdateAsiaRange()
{
   datetime nyNow = NewYorkTime();
   datetime nyDay = nyNow - (nyNow % 86400);
   long     shift = (long)(TimeCurrent() - nyNow);   // heure serveur - heure de New York

   datetime startNy = nyDay + AsiaStartHour * 3600 - (AsiaStartHour > AsiaEndHour ? 86400 : 0);
   datetime endNy   = nyDay + AsiaEndHour * 3600;
   if(nyNow < endNy)
      return false;                                  // range du jour pas encore terminé

   if(nyDay != asiaDay)
   {
      MqlRates rates[];
      int n = CopyRates(_Symbol, PERIOD_M1, (datetime)(startNy + shift), (datetime)(endNy + shift - 1), rates);
      if(n < 0)
         return false;                               // historique pas encore chargé : on réessaiera

      asiaDay    = nyDay;
      asiaEndSrv = (datetime)(endNy + shift);
      asiaValid  = (n >= MinAsiaBars);
      if(asiaValid)
      {
         asiaHigh = rates[0].high;
         asiaLow  = rates[0].low;
         for(int i = 1; i < n; i++)
         {
            asiaHigh = MathMax(asiaHigh, rates[i].high);
            asiaLow  = MathMin(asiaLow,  rates[i].low);
         }
      }
   }

   if(!asiaValid)
      return false;

   datetime lastClosed = iTime(_Symbol, PERIOD_M1, 1);
   if(lastClosed < asiaEndSrv)
      return false;

   MqlRates post[];
   int m = CopyRates(_Symbol, PERIOD_M1, asiaEndSrv, lastClosed, post);
   if(m <= 0)
      return false;

   postHigh = post[0].high;
   postLow  = post[0].low;
   for(int i = 1; i < m; i++)
   {
      postHigh = MathMax(postHigh, post[i].high);
      postLow  = MathMin(postLow,  post[i].low);
   }
   return true;
}

//+----------------------- SIGNAL AMD -------------------------------+
// Achat (dir = 1) : dans les ConfirmLookback dernières bougies, une mèche est passée sous
// le range asiatique (manipulation) et c'est le plus bas depuis la fin du range ; le prix
// est revenu dans le range et la bougie clôture au-dessus du dernier point haut qui a
// précédé ce plus bas (CHoCH). Vente : symétrique.
// Remplit 'stopPrice' (au-delà de la mèche) et 'target' (liquidité de l'autre côté).
bool CheckAmdSignal(int dir, const datetime &time[], const double &high[], const double &low[],
                    const double &close[], int size, double atr, double &stopPrice, double &target)
{
   int L = ConfirmLookback;

   if(dir == 1)
   {
      int lowIdx = ArrayMinimum(low, 2, L - 1);
      if(lowIdx < 2 || time[lowIdx] < asiaEndSrv)
         return false;
      if(low[lowIdx] >= asiaLow || low[lowIdx] > postLow)
         return false;                               // pas de chasse aux stops sous le range
      if(close[1] <= asiaLow)
         return false;                               // pas encore revenu dans le range
      if(TargetMode == TARGET_LIQUIDITY && postHigh >= asiaHigh)
         return false;                               // la liquidité visée a déjà été prise

      for(int j = lowIdx + 1; j <= lowIdx + ChochMaxBars && j + PivotStrength < size; j++)
      {
         if(!IsPivotHigh(high, j, size))
            continue;

         double level = high[j];
         bool alreadyBroken = false;
         for(int k = 2; k < lowIdx; k++)
            if(close[k] > level) { alreadyBroken = true; break; }

         if(!alreadyBroken && close[1] > level)
         {
            stopPrice = low[lowIdx] - SlBufferAtr * atr;
            target    = asiaHigh;
            return true;
         }
         break;   // seul le point haut le plus proche compte
      }
      return false;
   }

   int highIdx = ArrayMaximum(high, 2, L - 1);
   if(highIdx < 2 || time[highIdx] < asiaEndSrv)
      return false;
   if(high[highIdx] <= asiaHigh || high[highIdx] < postHigh)
      return false;
   if(close[1] >= asiaHigh)
      return false;
   if(TargetMode == TARGET_LIQUIDITY && postLow <= asiaLow)
      return false;

   for(int j = highIdx + 1; j <= highIdx + ChochMaxBars && j + PivotStrength < size; j++)
   {
      if(!IsPivotLow(low, j, size))
         continue;

      double level = low[j];
      bool alreadyBroken = false;
      for(int k = 2; k < highIdx; k++)
         if(close[k] < level) { alreadyBroken = true; break; }

      if(!alreadyBroken && close[1] < level)
      {
         stopPrice = high[highIdx] + SlBufferAtr * atr;
         target    = asiaLow;
         return true;
      }
      break;
   }
   return false;
}

// Distance du TP de la k-ième position (0 = première)
double TargetDistance(int k, int dir, double price, double risk, double target)
{
   if(TargetMode == TARGET_LIQUIDITY)
   {
      double first = (dir == 1) ? target - price : price - target;
      return first + k * TargetStepRR * risk;
   }
   return (FirstTargetRR + k * TargetStepRR) * risk;
}

//+----------------------- ALERTES ----------------------------------+
void SendSignalAlert(int dir, double entry, double stopPrice, double target, int count)
{
   double risk = (dir == 1) ? entry - stopPrice : stopPrice - entry;

   string msg = "EMYO AMD " + _Symbol + " : " + (dir == 1 ? "ACHAT" : "VENTE") +
                " vers " + DoubleToString(entry, _Digits) +
                " | SL " + DoubleToString(stopPrice, _Digits);

   for(int k = 0; k < count; k++)
   {
      bool runner = UseRunner && count > 1 && k == count - 1;
      if(runner)
         msg += " | TP" + IntegerToString(k + 1) + " libre (trailing)";
      else
      {
         double dist = TargetDistance(k, dir, entry, risk, target);
         msg += " | TP" + IntegerToString(k + 1) + " " +
                DoubleToString((dir == 1) ? entry + dist : entry - dist, _Digits);
      }
   }

   msg += " | range Asie " + DoubleToString(asiaLow, _Digits) + "-" + DoubleToString(asiaHigh, _Digits);

   Print(msg);
   if(MQLInfoInteger(MQL_TESTER))
      return;                              // pas d'alertes pendant les backtests

   Alert(msg);
   if(SendPushAlerts && !SendNotification(msg))
      Print("Notification non envoyée : vérifier le MetaQuotes ID (Outils > Options > Notifications)");
}

//+----------------------- ORDRES -----------------------------------+
// Ouvre 'count' positions avec le même SL ; TP selon TargetMode. Renvoie le nombre ouvert.
int OpenBasket(int dir, double stopPrice, double target, int count)
{
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = (dir == 1) ? ask : bid;
   double risk  = (dir == 1) ? price - stopPrice : stopPrice - price;

   if(risk <= 0)
      return 0;

   if(MaxSpreadPercentOfRisk > 0 && ask - bid > risk * MaxSpreadPercentOfRisk / 100.0)
   {
      Print("Spread trop élevé : ", DoubleToString((ask - bid) / risk * 100.0, 1), " % du risque");
      return 0;
   }

   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(risk < minDist)
      return 0;

   trade.SetDeviationInPoints((ulong)MathMax(1, risk * MaxSlippagePercentOfRisk / 100.0 / _Point));

   string currency = AccountInfoString(ACCOUNT_CURRENCY);
   double sl = NormalizeDouble(stopPrice, _Digits);
   int opened = 0;

   for(int k = 0; k < count; k++)
   {
      double tpDistance = TargetDistance(k, dir, price, risk, target);
      if(tpDistance <= minDist)
         continue;

      double lots = CalculateLots(risk, tpDistance);
      if(lots <= 0)
         continue;

      // Runner : la dernière position du panier n'a pas de TP
      bool runner = UseRunner && count > 1 && k == count - 1;
      double tp = runner ? 0 : NormalizeDouble((dir == 1) ? price + tpDistance : price - tpDistance, _Digits);
      string info = (runner ? " | RUNNER sans TP" : " | TP à " + DoubleToString(tpDistance / risk, 1) + "R") +
                    " | Lots=" + DoubleToString(lots, 2) +
                    " | Gain visé=" + DoubleToString(MoneyPerLot(tpDistance) * lots, 2) + " " + currency +
                    " Perte max=" + DoubleToString(MoneyPerLot(risk) * lots, 2) + " " + currency;

      bool ok = (dir == 1) ? trade.Buy(lots, _Symbol, price, sl, tp)
                           : trade.Sell(lots, _Symbol, price, sl, tp);
      if(ok)
      {
         opened++;
         Print((dir == 1 ? "BUY" : "SELL"), " exécuté", info);
      }
      else
         Print((dir == 1 ? "BUY" : "SELL"), " refusé : ", trade.ResultRetcodeDescription());
   }
   return opened;
}

//+----------------------- AFFICHAGE --------------------------------+
void UpdatePanel()
{
   if(!ShowPanel)
      return;

   int    tradesToday = 0;
   double profitToday = 0;
   GetTodayStats(tradesToday, profitToday);

   int direction = 0;
   int openCount = CountOpenPositions(direction);
   int bias      = GetBias();
   string currency = AccountInfoString(ACCOUNT_CURRENCY);
   string range = asiaValid ? DoubleToString(asiaLow, _Digits) + " - " + DoubleToString(asiaHigh, _Digits)
                            : "pas encore disponible";

   Comment("EMYO AMD  |  ", _Symbol, (AlertsOnly ? "  |  MODE ALERTES (ne trade pas)" : ""), "\n",
           "Session : ", (IsTradingHour() ? "OUVERTE" : "fermée"),
           "  (New York ", TimeToString(NewYorkTime(), TIME_MINUTES), ")\n",
           "Tendance de fond : ", (bias == 1 ? "HAUSSIÈRE" : (bias == -1 ? "BAISSIÈRE" : "aucune")), "\n",
           "Range asiatique : ", range, "\n",
           "Positions ouvertes : ", openCount,
           "  |  en cours : ", DoubleToString(FloatingProfit(), 2), " ", currency, "\n",
           "Positions du jour : ", tradesToday,
           "  |  gain du jour : ", DoubleToString(profitToday, 2), " ", currency);
}

void OnTrade()
{
   UpdatePanel();
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(CloseOutsideSession && !IsTradingHour())
   {
      int direction = 0;
      if(CountOpenPositions(direction) > 0)
      {
         ClosePositions(-1);
         Print("Fin de session : positions fermées.");
      }
   }

   ManagePositions();

   // Tout le reste : une fois par bougie M1 clôturée
   if(!IsNewBar())
      return;

   bool rangeReady = UpdateAsiaRange();
   UpdatePanel();

   if(!rangeReady || !IsTradingHour())
      return;

   if(signalDay != asiaDay)
   {
      signalDay    = asiaDay;
      signalsToday = 0;
   }
   if(signalsToday >= MaxSignalsPerDay)
      return;

   int openDirection = 0;
   int openCount     = CountOpenPositions(openDirection);
   int room          = MaxOpenPositions - openCount;
   if(room <= 0)
      return;

   if(openCount > 0 && !AllPositionsProtected())
      return;

   int    tradesToday = 0;
   double profitToday = 0;
   GetTodayStats(tradesToday, profitToday);

   if(MaxDailyLossPercent > 0 &&
      profitToday + FloatingProfit() <= -AccountInfoDouble(ACCOUNT_BALANCE) * MaxDailyLossPercent / 100.0)
      return;

   // 1) Tendance de fond : la manipulation doit aller contre elle
   int bias = GetBias();
   if(bias == 0)
      return;
   if(openDirection != 0 && openDirection != bias)
      return;

   // 2) Bougies M1
   int size = ConfirmLookback + ChochMaxBars + PivotStrength + 2;
   double high[], low[], close[];
   datetime time[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time, true);

   if(CopyTime (_Symbol, PERIOD_M1, 0, size, time)  < size ||
      CopyHigh (_Symbol, PERIOD_M1, 0, size, high)  < size ||
      CopyLow  (_Symbol, PERIOD_M1, 0, size, low)   < size ||
      CopyClose(_Symbol, PERIOD_M1, 0, size, close) < size)
      return;

   double atr = LastValue(atrM1Handle);
   if(atr <= 0)
      return;

   // 3) Manipulation + retour dans le range + CHoCH
   double stopPrice = 0, target = 0;
   if(!CheckAmdSignal(bias, time, high, low, close, size, atr, stopPrice, target))
      return;

   double entry = (bias == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double risk  = (bias == 1) ? entry - stopPrice : stopPrice - entry;
   if(risk < MinRiskAtr * atr || risk > MaxRiskAtr * atr)
      return;

   if(TargetMode == TARGET_LIQUIDITY)
   {
      double toTarget = (bias == 1) ? target - entry : entry - target;
      if(toTarget < MinFirstTargetRR * risk)
         return;                                    // objectif trop proche pour le risque pris
   }

   int count = (int)MathMin(TradesPerSignal, room);
   signalsToday++;

   Print("Signal AMD ", (bias == 1 ? "ACHAT" : "VENTE"), " | range asiatique [",
         DoubleToString(asiaLow, _Digits), " - ", DoubleToString(asiaHigh, _Digits), "]");

   SendSignalAlert(bias, entry, stopPrice, target, count);

   if(!AlertsOnly)
      OpenBasket(bias, stopPrice, target, count);
}
//+------------------------------------------------------------------+
