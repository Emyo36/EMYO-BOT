//+------------------------------------------------------------------+
//|             EMYO TREND - SUIVI DE TENDANCE (H4 par défaut)        |
//|  Filtre EMA 200, entrée sur cassure du canal de Donchian (sur H4  |
//|  ou sur une unité plus courte, ex. M5), stop initial en ATR,      |
//|  sortie par stop suiveur sur le canal court (H4 par défaut).      |
//|  Peu de trades, gains laissés courir, positions sur plusieurs     |
//|  jours (week-ends compris).                                       |
//+------------------------------------------------------------------+
#property copyright "EMYO"
#property version   "1.01"

#include <Trade\Trade.mqh>

//---------------------- PARAMÈTRES DU BOT --------------------------
input group "Risque"
input double RiskPercent        = 1.0;   // % du solde risqué par trade (distance au stop initial)
input double MaxRiskPercentAtMinLot = 3.0; // Si le lot minimum risque plus que ce %, le trade est ignoré
input double MaxLots            = 1.0;   // Lot maximum

input group "Signal"
input ENUM_TIMEFRAMES TrendTimeframe = PERIOD_H4; // Unité de temps de la tendance (EMA)
input ENUM_TIMEFRAMES EntryTimeframe = PERIOD_H4; // Unité de temps de l'entrée (cassure + ATR du stop), ex. M5
input ENUM_TIMEFRAMES ExitTimeframe  = PERIOD_H4; // Unité de temps de la sortie (stop suiveur)
input int    TrendEmaPeriod     = 200;   // Filtre : achats au-dessus de l'EMA, ventes en dessous
input int    EntryChannel       = 20;    // Entrée : clôture au-delà du plus haut / plus bas des N bougies précédentes
input int    ExitChannel        = 10;    // Sortie : stop suiveur sur le plus bas / plus haut des N dernières bougies
input int    AtrPeriod          = 20;    // Période de l'ATR (unité de temps de l'entrée)
input double StopAtr            = 2.0;   // Stop initial à N x ATR du prix d'entrée
input bool   AllowLong          = true;  // Autoriser les achats
input bool   AllowShort         = true;  // Autoriser les ventes

input group "Filtres"
input double MaxSpreadPercentOfRisk = 10; // Spread max. en % du risque (0 = off)

input group "Sécurité"
input int    MaxTradesPerDay    = 0;     // Entrées par jour au maximum (0 = illimité ; conseillé 3 en entrée M5)
input double MaxDailyLossPercent = 3;    // Pas de nouvelle entrée après cette perte du jour, positions ouvertes comprises (0 = off)
input ulong  MagicNumber        = 360040;
input bool   SendPushAlerts     = true;  // Envoyer chaque entrée sur le téléphone (MetaQuotes ID)
input bool   AutoCloseOnStop    = false; // Fermer la position si le bot est retiré (déconseillé : trades sur plusieurs jours)
input bool   ShowPanel          = true;  // Afficher les informations sur le graphique

//---------------------- VARIABLES GLOBALES --------------------------
CTrade   trade;
int      emaHandle   = INVALID_HANDLE;
int      atrHandle   = INVALID_HANDLE;
datetime lastBarTime = 0;
double   lastUpper   = 0;   // niveaux du dernier calcul, pour l'affichage
double   lastLower   = 0;
double   lastEma     = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if(RiskPercent <= 0 || MaxRiskPercentAtMinLot < 0 || MaxLots <= 0 || TrendEmaPeriod < 1 ||
      EntryChannel < 2 || ExitChannel < 2 || AtrPeriod < 1 || StopAtr <= 0 ||
      MaxSpreadPercentOfRisk < 0 || MaxDailyLossPercent < 0 || MaxTradesPerDay < 0 || (!AllowLong && !AllowShort))
   {
      Print("Erreur : paramètres invalides");
      return(INIT_PARAMETERS_INCORRECT);
   }

   emaHandle = iMA(_Symbol, TrendTimeframe, TrendEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, EntryTimeframe, AtrPeriod);
   if(emaHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("Erreur : impossible de créer les indicateurs");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);

   Print("EMYO TREND lancé sur ", _Symbol, " | tendance ", EnumToString(TrendTimeframe),
         " | entrée ", EnumToString(EntryTimeframe), " | sortie ", EnumToString(ExitTimeframe),
         " | risque ", DoubleToString(RiskPercent, 2), " % par trade");
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
      ClosePositions();

   if(emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);

   Comment("");
   Print("EMYO TREND arrêté");
}

//+----------------------- COMPTE / POSITIONS -----------------------+
bool IsOwnPosition()
{
   return PositionGetString(POSITION_SYMBOL) == _Symbol &&
          PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber;
}

// Sélectionne la position du bot ; renvoie son ticket (0 si aucune)
ulong SelectOwnPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && IsOwnPosition())
         return ticket;
   }
   return 0;
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

void ClosePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && IsOwnPosition())
         trade.PositionClose(ticket);
   }
}

// Résultat des trades du bot depuis 'from' (profit + swap + commission)
double ClosedProfitSince(datetime from)
{
   double total = 0;
   if(!HistorySelect(from, TimeCurrent()))
      return 0;

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol ||
         HistoryDealGetInteger(deal, DEAL_MAGIC) != (long)MagicNumber)
         continue;

      total += HistoryDealGetDouble(deal, DEAL_PROFIT)
             + HistoryDealGetDouble(deal, DEAL_SWAP)
             + HistoryDealGetDouble(deal, DEAL_COMMISSION);
   }
   return total;
}

// Nombre d'entrées du bot depuis 'from'
int EntriesSince(datetime from)
{
   int count = 0;
   if(!HistorySelect(from, TimeCurrent()))
      return 0;

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) == _Symbol &&
         HistoryDealGetInteger(deal, DEAL_MAGIC) == (long)MagicNumber &&
         HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
         count++;
   }
   return count;
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

// Lot pour risquer RiskPercent % du solde jusqu'au stop initial.
// Si ce lot est sous le minimum du courtier, le lot minimum est utilisé seulement
// s'il ne risque pas plus de MaxRiskPercentAtMinLot % ; sinon le trade est ignoré.
double CalculateLots(double risk)
{
   double lossPerLot = MoneyPerLot(risk);
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   if(lossPerLot <= 0 || balance <= 0)
      return 0;

   double lots    = MathMin(balance * RiskPercent / 100.0 / lossPerLot, MaxLots);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0)
      return 0;

   lots = MathFloor(lots / lotStep + 1e-9) * lotStep;
   int lotDigits = (int)MathMax(0, MathCeil(-MathLog10(lotStep)));

   if(lots < minLot)
   {
      double minLotRisk = lossPerLot * minLot / balance * 100.0;
      if(minLotRisk > MaxRiskPercentAtMinLot)
      {
         Print("Trade ignoré : même le lot minimum (", minLot, ") risquerait ",
               DoubleToString(minLotRisk, 1), " % du solde (maximum ",
               DoubleToString(MaxRiskPercentAtMinLot, 1), " %)");
         return 0;
      }
      lots = minLot;
   }

   return NormalizeDouble(MathMin(lots, maxLot), lotDigits);
}

//+----------------------- INDICATEURS ------------------------------+
// Valeur de l'indicateur sur la dernière bougie clôturée
double ClosedValue(int handle)
{
   double buf[];
   if(CopyBuffer(handle, 0, 1, 1, buf) < 1)
      return 0;
   return buf[0];
}

//+----------------------- ALERTES ----------------------------------+
void SendEntryAlert(int dir, double entry, double stop, double lots)
{
   string msg = "EMYO TREND " + _Symbol + " : " + (dir == 1 ? "ACHAT" : "VENTE") +
                " vers " + DoubleToString(entry, _Digits) +
                " | SL " + DoubleToString(stop, _Digits) +
                " | lots " + DoubleToString(lots, 2) + " | pas de TP (stop suiveur)";
   Print(msg);
   if(MQLInfoInteger(MQL_TESTER))
      return;

   Alert(msg);
   if(SendPushAlerts && !SendNotification(msg))
      Print("Notification non envoyée : vérifier le MetaQuotes ID (Outils > Options > Notifications)");
}

//+----------------------- GESTION DE LA POSITION -------------------+
// Stop suiveur : SL au plus bas (achat) / plus haut (vente) des ExitChannel dernières
// bougies clôturées de ExitTimeframe, seulement s'il protège mieux que le SL actuel.
void TrailPosition(ulong ticket, const double &high[], const double &low[])
{
   if(!PositionSelectByTicket(ticket))
      return;

   double sl      = PositionGetDouble(POSITION_SL);
   double tp      = PositionGetDouble(POSITION_TP);
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
   {
      double level = NormalizeDouble(low[ArrayMinimum(low, 0, ExitChannel)], _Digits);
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(level > sl + _Point && bid - level >= minDist)
         trade.PositionModify(ticket, level, tp);
      else if(bid <= level)
         trade.PositionClose(ticket);        // le prix est déjà sous le niveau de sortie
   }
   else
   {
      double level = NormalizeDouble(high[ArrayMaximum(high, 0, ExitChannel)], _Digits);
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if((sl == 0 || level < sl - _Point) && level - ask >= minDist)
         trade.PositionModify(ticket, level, tp);
      else if(ask >= level)
         trade.PositionClose(ticket);
   }
}

//+----------------------- AFFICHAGE --------------------------------+
void UpdatePanel()
{
   if(!ShowPanel)
      return;

   datetime now      = TimeCurrent();
   datetime dayStart = now - (now % 86400);
   string   currency = AccountInfoString(ACCOUNT_CURRENCY);
   string   position = "aucune";

   ulong ticket = SelectOwnPosition();
   if(ticket != 0)
      position = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "ACHAT " : "VENTE ") +
                 DoubleToString(PositionGetDouble(POSITION_VOLUME), 2) + " lot | SL " +
                 DoubleToString(PositionGetDouble(POSITION_SL), _Digits);

   string trend = (lastEma <= 0) ? "en attente" :
                  (SymbolInfoDouble(_Symbol, SYMBOL_BID) > lastEma ? "HAUSSIÈRE (achats seulement)"
                                                                   : "BAISSIÈRE (ventes seulement)");

   Comment("EMYO TREND  |  ", _Symbol, "  |  tendance ", EnumToString(TrendTimeframe),
           "  |  entrée ", EnumToString(EntryTimeframe), "  |  sortie ", EnumToString(ExitTimeframe), "\n",
           "Tendance (EMA ", TrendEmaPeriod, ") : ", trend, "\n",
           "Achat si clôture > ", DoubleToString(lastUpper, _Digits),
           "  |  Vente si clôture < ", DoubleToString(lastLower, _Digits), "\n",
           "Position : ", position, "  |  en cours : ", DoubleToString(FloatingProfit(), 2), " ", currency, "\n",
           "Résultat du jour : ", DoubleToString(ClosedProfitSince(dayStart), 2), " ", currency);
}

void OnTrade()
{
   UpdatePanel();
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Tout se décide une fois par bougie clôturée de l'unité de temps de l'entrée
   datetime barTime = iTime(_Symbol, EntryTimeframe, 0);
   if(barTime == 0 || barTime == lastBarTime)
      return;

   // Bougies clôturées : indice 0 = dernière bougie clôturée
   int need = EntryChannel + 1;
   double high[], low[], close[], exitHigh[], exitLow[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(exitHigh, true);
   ArraySetAsSeries(exitLow, true);

   if(CopyHigh (_Symbol, EntryTimeframe, 1, need, high)  < need ||
      CopyLow  (_Symbol, EntryTimeframe, 1, need, low)   < need ||
      CopyClose(_Symbol, EntryTimeframe, 1, need, close) < need ||
      CopyHigh (_Symbol, ExitTimeframe, 1, ExitChannel, exitHigh) < ExitChannel ||
      CopyLow  (_Symbol, ExitTimeframe, 1, ExitChannel, exitLow)  < ExitChannel)
      return;                                       // historique pas prêt : on réessaie au tick suivant

   double ema = ClosedValue(emaHandle);
   double atr = ClosedValue(atrHandle);
   if(ema <= 0 || atr <= 0)
      return;

   lastBarTime = barTime;
   lastEma     = ema;
   lastUpper   = high[ArrayMaximum(high, 1, EntryChannel)];   // canal des N bougies AVANT la dernière
   lastLower   = low [ArrayMinimum(low,  1, EntryChannel)];

   // 1) Position ouverte : on ne fait que suivre le stop (une seule position à la fois)
   ulong ticket = SelectOwnPosition();
   if(ticket != 0)
   {
      TrailPosition(ticket, exitHigh, exitLow);
      UpdatePanel();
      return;
   }

   // 2) Garde-fous : nombre d'entrées et perte maximale du jour
   datetime now      = TimeCurrent();
   datetime dayStart = now - (now % 86400);
   if(MaxTradesPerDay > 0 && EntriesSince(dayStart) >= MaxTradesPerDay)
   {
      UpdatePanel();
      return;
   }
   if(MaxDailyLossPercent > 0 &&
      ClosedProfitSince(dayStart) + FloatingProfit() <=
      -AccountInfoDouble(ACCOUNT_BALANCE) * MaxDailyLossPercent / 100.0)
   {
      UpdatePanel();
      return;
   }

   // 3) Signal : cassure du canal dans le sens de l'EMA
   int dir = 0;
   if(AllowLong && close[0] > lastUpper && close[0] > ema)
      dir = 1;
   else if(AllowShort && close[0] < lastLower && close[0] < ema)
      dir = -1;

   if(dir == 0)
   {
      UpdatePanel();
      return;
   }

   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = (dir == 1) ? ask : bid;
   double stop  = NormalizeDouble((dir == 1) ? price - StopAtr * atr : price + StopAtr * atr, _Digits);
   double risk  = MathAbs(price - stop);

   if(MaxSpreadPercentOfRisk > 0 && ask - bid > risk * MaxSpreadPercentOfRisk / 100.0)
   {
      Print("Spread trop élevé : ", DoubleToString((ask - bid) / risk * 100.0, 1), " % du risque");
      UpdatePanel();
      return;
   }

   double lots = CalculateLots(risk);
   if(lots <= 0)
   {
      UpdatePanel();
      return;
   }

   bool ok = (dir == 1) ? trade.Buy(lots, _Symbol, price, stop, 0)
                        : trade.Sell(lots, _Symbol, price, stop, 0);
   if(ok)
   {
      Print((dir == 1 ? "BUY" : "SELL"), " exécuté | lots ", DoubleToString(lots, 2),
            " | perte max ", DoubleToString(MoneyPerLot(risk) * lots, 2), " ", AccountInfoString(ACCOUNT_CURRENCY));
      SendEntryAlert(dir, price, stop, lots);
   }
   else
      Print((dir == 1 ? "BUY" : "SELL"), " refusé : ", trade.ResultRetcodeDescription());

   UpdatePanel();
}
//+------------------------------------------------------------------+
