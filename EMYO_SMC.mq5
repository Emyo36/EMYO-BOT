//+------------------------------------------------------------------+
//|          EMYO SMC - ORDER BLOCK + CONFIRMATION D'ENTRÉE           |
//|  Tendance H4/H1, order block M5, confirmation M1 (CHoCH /         |
//|  bougie englobante). Or, Bitcoin, NASDAQ - session américaine.    |
//+------------------------------------------------------------------+
#property copyright "EMYO"
#property version   "1.03"

#include <Trade\Trade.mqh>

enum ENUM_CONFIRMATION
{
   CONFIRM_CHOCH     = 0,  // CHoCH : cassure du dernier point haut / bas (la plus forte)
   CONFIRM_ENGULFING = 1,  // Bougie englobante sur la zone
   CONFIRM_EITHER    = 2   // L'une ou l'autre
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

input group "Positions"
input int    TradesPerSignal    = 3;     // Positions ouvertes ensemble à chaque signal
input double FirstTargetRR      = 1.0;   // TP de la 1re position, en multiple du risque (1 = 1R)
input double TargetStepRR       = 1.0;   // Écart entre les TP : 1R / 2R / 3R...
input int    MaxOpenPositions   = 6;     // Positions ouvertes en même temps au maximum (ce symbole)
input bool   AddOnlyWhenProtected = true; // Nouveau signal seulement si les positions ouvertes sont au break-even
input double BreakEvenRR        = 1.0;   // Passage au break-even quand le gain atteint ce multiple du risque (0 = off)
input double BreakEvenLockRR    = 0.1;   // Gain sécurisé au break-even (en multiple du risque)
input bool   UseRunner          = false; // Dernière position sans TP : elle suit le mouvement (trailing)
input double RunnerTrailAtr     = 2.0;   // Distance du trailing du runner (en ATR de l'unité de temps des blocs)

input group "Tendance de fond"
input ENUM_TIMEFRAMES BiasTimeframe1 = PERIOD_H1;  // 1re unité de temps de tendance
input ENUM_TIMEFRAMES BiasTimeframe2 = PERIOD_H4;  // 2e unité de temps de tendance
input bool            UseBiasTimeframe2 = true;    // Exiger aussi la 2e unité de temps
input int             BiasEmaPeriod  = 50;         // EMA de tendance (prix au-dessus = haussier)

input group "Order blocks (M5)"
input ENUM_TIMEFRAMES SetupTimeframe = PERIOD_M5;  // Unité de temps des order blocks
input int    ObLookback         = 100;   // Bougies analysées pour trouver les order blocks
input int    ImpulseBars        = 3;     // L'impulsion doit partir dans ces N bougies
input double ImpulseAtr         = 1.5;   // Taille minimale de l'impulsion (en ATR de l'unité de temps)
input int    MaxBlocksPerSide   = 3;     // Order blocks récents suivis dans chaque sens

input group "Confirmation d'entrée (M1)"
input ENUM_CONFIRMATION Confirmation = CONFIRM_CHOCH;
input int    ConfirmLookback    = 20;    // Bougies M1 où chercher le contact avec la zone
input int    PivotStrength      = 2;     // Bougies de chaque côté pour valider un point haut / bas
input int    ChochMaxBars       = 15;    // Distance max. entre le point bas et le point haut à casser
input double EngulfBodyAtr      = 0.5;   // Corps minimum de la bougie englobante (en ATR M1)
input double SlBufferAtr        = 0.2;   // Marge sous le plus bas / au-dessus du plus haut (ATR M1)
input double MinRiskAtr         = 0.5;   // Risque minimum (en ATR M1) : évite les SL trop serrés
input double MaxRiskAtr         = 6.0;   // Risque maximum (en ATR M1) : évite les SL trop larges

input group "Filtres"
input double MaxSpreadPercentOfRisk = 15; // Spread max. en % du risque (0 = off)
input double MaxSlippagePercentOfRisk = 10; // Glissement max. accepté en % du risque

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
input int    MaxTradesPerDay    = 30;    // Positions ouvertes par jour au maximum (0 = illimité)
input double MaxDailyLossPercent = 3;    // Arrêt du jour après cette perte en % (0 = off)
input double DailyProfitTargetMoney = 0; // Arrêt du jour une fois ce gain atteint (0 = off)
input ulong  MagicNumber        = 360037;
input bool   AutoCloseOnStop    = true;  // Fermer les positions quand le bot est retiré
input bool   ShowPanel          = true;  // Afficher le compteur de gains sur le graphique

//---------------------- VARIABLES GLOBALES --------------------------
struct OrderBlock
{
   datetime time;     // heure de la bougie qui forme le bloc (identifiant)
   double   top;
   double   bottom;
   int      dir;      // +1 haussier (zone d'achat), -1 baissier (zone de vente)
};

CTrade     trade;
int        biasHandle1 = INVALID_HANDLE;
int        biasHandle2 = INVALID_HANDLE;
int        atrM1Handle = INVALID_HANDLE;
int        atrSetupHandle = INVALID_HANDLE;
datetime   lastBarTime = 0;
OrderBlock blocks[];
datetime   usedBlocks[];  // blocs déjà tradés : un seul signal par bloc

//+------------------------------------------------------------------+
int OnInit()
{
   if(TradesPerSignal < 1 || FirstTargetRR <= 0 || TargetStepRR < 0 || MaxOpenPositions < 1 ||
      BreakEvenRR < 0 || BreakEvenLockRR < 0 || RunnerTrailAtr <= 0 || BiasEmaPeriod <= 0 ||
      ObLookback < 10 || ImpulseBars < 1 || ImpulseAtr <= 0 || MaxBlocksPerSide < 1 ||
      ConfirmLookback < 5 || PivotStrength < 1 || ChochMaxBars < 2 ||
      EngulfBodyAtr < 0 || SlBufferAtr < 0 || MinRiskAtr < 0 || MaxRiskAtr <= MinRiskAtr ||
      NyStartHour < 0 || NyStartHour > 23 || NyEndHour < 0 || NyEndHour > 23 ||
      NyStartMinute < 0 || NyStartMinute > 59 || NyEndMinute < 0 || NyEndMinute > 59 ||
      StartHour < 0 || StartHour > 23 || EndHour < 0 || EndHour > 23 ||
      Lots <= 0 || RiskPercent < 0 || TargetProfitMoney < 0 || MaxProfitAtMinLot < 0 || MaxLots <= 0)
   {
      Print("Erreur : paramètres invalides");
      return(INIT_PARAMETERS_INCORRECT);
   }

   biasHandle1    = iMA(_Symbol, BiasTimeframe1, BiasEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   biasHandle2    = iMA(_Symbol, BiasTimeframe2, BiasEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atrM1Handle    = iATR(_Symbol, PERIOD_M1, 14);
   atrSetupHandle = iATR(_Symbol, SetupTimeframe, 14);

   if(biasHandle1 == INVALID_HANDLE || biasHandle2 == INVALID_HANDLE ||
      atrM1Handle == INVALID_HANDLE || atrSetupHandle == INVALID_HANDLE)
   {
      Print("Erreur : impossible de créer les indicateurs");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);

   Print("EMYO SMC lancé sur ", _Symbol,
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
   Print("EMYO SMC arrêté");
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

//+----------------------- ORDER BLOCKS -----------------------------+
bool IsBlockUsed(datetime t)
{
   for(int i = 0; i < ArraySize(usedBlocks); i++)
      if(usedBlocks[i] == t)
         return true;
   return false;
}

void MarkBlockUsed(datetime t)
{
   int n = ArraySize(usedBlocks);
   if(n >= 200)                          // on garde les 200 derniers
   {
      ArrayRemove(usedBlocks, 0, 1);
      n--;
   }
   ArrayResize(usedBlocks, n + 1);
   usedBlocks[n] = t;
}

// Recherche des order blocks sur l'unité de temps des setups.
// Bloc haussier : dernière bougie baissière avant une impulsion haussière
// qui clôture au-dessus de son plus haut d'au moins ImpulseAtr x ATR.
// Le bloc est invalidé si une bougie a clôturé sous son plus bas depuis.
// (Symétrique pour les blocs baissiers.)
void FindOrderBlocks()
{
   ArrayResize(blocks, 0);

   int bars = ObLookback + ImpulseBars + 2;
   double open[], high[], low[], close[];
   datetime time[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time, true);

   if(CopyOpen (_Symbol, SetupTimeframe, 0, bars, open)  < bars ||
      CopyHigh (_Symbol, SetupTimeframe, 0, bars, high)  < bars ||
      CopyLow  (_Symbol, SetupTimeframe, 0, bars, low)   < bars ||
      CopyClose(_Symbol, SetupTimeframe, 0, bars, close) < bars ||
      CopyTime (_Symbol, SetupTimeframe, 0, bars, time)  < bars)
      return;

   double atr = LastValue(atrSetupHandle);
   if(atr <= 0)
      return;

   int bullCount = 0, bearCount = 0;

   // Du plus récent au plus ancien ; bougie i = bloc, bougies i-1 ... i-ImpulseBars = impulsion
   for(int i = ImpulseBars + 1; i <= ObLookback; i++)
   {
      if(bullCount >= MaxBlocksPerSide && bearCount >= MaxBlocksPerSide)
         break;

      double maxClose = close[i - 1];
      double minClose = close[i - 1];
      for(int k = 2; k <= ImpulseBars; k++)
      {
         maxClose = MathMax(maxClose, close[i - k]);
         minClose = MathMin(minClose, close[i - k]);
      }

      // Bloc haussier
      if(bullCount < MaxBlocksPerSide && close[i] < open[i] &&
         maxClose >= high[i] + ImpulseAtr * atr)
      {
         bool valid = true;
         for(int k = 1; k < i; k++)
            if(close[k] < low[i]) { valid = false; break; }

         if(valid)
         {
            int n = ArraySize(blocks);
            ArrayResize(blocks, n + 1);
            blocks[n].time   = time[i];
            blocks[n].top    = high[i];
            blocks[n].bottom = low[i];
            blocks[n].dir    = 1;
            bullCount++;
         }
      }

      // Bloc baissier
      if(bearCount < MaxBlocksPerSide && close[i] > open[i] &&
         minClose <= low[i] - ImpulseAtr * atr)
      {
         bool valid = true;
         for(int k = 1; k < i; k++)
            if(close[k] > high[i]) { valid = false; break; }

         if(valid)
         {
            int n = ArraySize(blocks);
            ArrayResize(blocks, n + 1);
            blocks[n].time   = time[i];
            blocks[n].top    = high[i];
            blocks[n].bottom = low[i];
            blocks[n].dir    = -1;
            bearCount++;
         }
      }
   }
}

//+----------------------- CONFIRMATIONS M1 -------------------------+
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

// Cherche une confirmation d'achat (dir = 1) ou de vente (dir = -1) sur la zone.
// Renvoie vrai et remplit 'stopPrice' (niveau d'invalidation du trade).
bool CheckConfirmation(const OrderBlock &ob, const datetime &time[], const double &open[],
                       const double &high[], const double &low[], const double &close[],
                       int size, double atr, double &stopPrice)
{
   int L = ConfirmLookback;

   // Le retour sur la zone doit avoir lieu après l'impulsion qui a créé le bloc
   datetime impulseEnd = ob.time + (ImpulseBars + 1) * PeriodSeconds(SetupTimeframe);

   if(ob.dir == 1)
   {
      // Point le plus bas de la correction (avant la bougie de confirmation)
      int lowIdx = ArrayMinimum(low, 2, L - 1);
      if(lowIdx < 2 || time[lowIdx] < impulseEnd)
         return false;

      // Le prix doit avoir touché la zone, sans clôturer sous le bloc
      if(low[lowIdx] > ob.top)
         return false;
      for(int k = 1; k <= lowIdx; k++)
         if(close[k] < ob.bottom)
            return false;

      // 1) CHoCH : clôture au-dessus du dernier point haut qui a précédé ce point bas
      if(Confirmation == CONFIRM_CHOCH || Confirmation == CONFIRM_EITHER)
      {
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
               return true;
            }
            break;   // seul le point haut le plus proche compte
         }
      }

      // 2) Bougie englobante haussière qui clôture dans la moitié haute de la zone ou au-dessus
      if(Confirmation == CONFIRM_ENGULFING || Confirmation == CONFIRM_EITHER)
      {
         if(close[1] > open[1] && close[2] < open[2] &&
            close[1] >= open[2] && open[1] <= close[2] &&
            close[1] - open[1] >= EngulfBodyAtr * atr &&
            MathMin(low[1], low[2]) <= ob.top &&
            close[1] > (ob.top + ob.bottom) / 2.0)
         {
            stopPrice = MathMin(low[1], low[2]) - SlBufferAtr * atr;
            return true;
         }
      }
      return false;
   }

   // Vente : symétrique
   int highIdx = ArrayMaximum(high, 2, L - 1);
   if(highIdx < 2 || time[highIdx] < impulseEnd)
      return false;

   if(high[highIdx] < ob.bottom)
      return false;
   for(int k = 1; k <= highIdx; k++)
      if(close[k] > ob.top)
         return false;

   if(Confirmation == CONFIRM_CHOCH || Confirmation == CONFIRM_EITHER)
   {
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
            return true;
         }
         break;
      }
   }

   if(Confirmation == CONFIRM_ENGULFING || Confirmation == CONFIRM_EITHER)
   {
      if(close[1] < open[1] && close[2] > open[2] &&
         close[1] <= open[2] && open[1] >= close[2] &&
         open[1] - close[1] >= EngulfBodyAtr * atr &&
         MathMax(high[1], high[2]) >= ob.bottom &&
         close[1] < (ob.top + ob.bottom) / 2.0)
      {
         stopPrice = MathMax(high[1], high[2]) + SlBufferAtr * atr;
         return true;
      }
   }
   return false;
}

//+----------------------- ALERTES ----------------------------------+
// Message du signal : entrée, SL et TP de chaque position.
// Envoyé sur le téléphone (application MetaTrader 5) et affiché sur le PC.
void SendSignalAlert(int dir, double entry, double stopPrice, int count, const OrderBlock &ob)
{
   double risk = (dir == 1) ? entry - stopPrice : stopPrice - entry;

   string msg = "EMYO SMC " + _Symbol + " : " + (dir == 1 ? "ACHAT" : "VENTE") +
                " vers " + DoubleToString(entry, _Digits) +
                " | SL " + DoubleToString(stopPrice, _Digits);

   for(int k = 0; k < count; k++)
   {
      double rr = FirstTargetRR + k * TargetStepRR;
      bool runner = UseRunner && count > 1 && k == count - 1;
      if(runner)
         msg += " | TP" + IntegerToString(k + 1) + " libre (trailing)";
      else
         msg += " | TP" + IntegerToString(k + 1) + " " +
                DoubleToString((dir == 1) ? entry + rr * risk : entry - rr * risk, _Digits);
   }

   msg += " | zone " + DoubleToString(ob.bottom, _Digits) + "-" + DoubleToString(ob.top, _Digits);

   Print(msg);
   if(MQLInfoInteger(MQL_TESTER))
      return;                              // pas d'alertes pendant les backtests

   Alert(msg);
   if(SendPushAlerts && !SendNotification(msg))
      Print("Notification non envoyée : vérifier le MetaQuotes ID (Outils > Options > Notifications)");
}

//+----------------------- ORDRES -----------------------------------+
// Ouvre TradesPerSignal positions avec le même SL et des TP à 1R, 2R, 3R...
// Renvoie le nombre de positions ouvertes.
int OpenBasket(int dir, double stopPrice, int count)
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
      double rr         = FirstTargetRR + k * TargetStepRR;
      double tpDistance = rr * risk;
      double lots       = CalculateLots(risk, tpDistance);
      if(lots <= 0)
         continue;

      // Runner : la dernière position du panier n'a pas de TP
      bool runner = UseRunner && count > 1 && k == count - 1;
      double tp = runner ? 0 : NormalizeDouble((dir == 1) ? price + tpDistance : price - tpDistance, _Digits);
      string info = (runner ? " | RUNNER sans TP" : " | TP " + DoubleToString(rr, 1) + "R") +
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

   Comment("EMYO SMC  |  ", _Symbol, (AlertsOnly ? "  |  MODE ALERTES (ne trade pas)" : ""), "\n",
           "Session : ", (IsTradingHour() ? "OUVERTE" : "fermée"),
           "  (New York ", TimeToString(NewYorkTime(), TIME_MINUTES), ")\n",
           "Tendance de fond : ", (bias == 1 ? "HAUSSIÈRE" : (bias == -1 ? "BAISSIÈRE" : "aucune")),
           "  |  order blocks suivis : ", ArraySize(blocks), "\n",
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

   FindOrderBlocks();
   UpdatePanel();

   if(!IsTradingHour())
      return;

   int openDirection = 0;
   int openCount     = CountOpenPositions(openDirection);
   int room          = MaxOpenPositions - openCount;
   if(room <= 0)
      return;

   if(openCount > 0 && AddOnlyWhenProtected && !AllPositionsProtected())
      return;

   int    tradesToday = 0;
   double profitToday = 0;
   GetTodayStats(tradesToday, profitToday);

   if(MaxTradesPerDay > 0 && tradesToday >= MaxTradesPerDay)
      return;

   if(MaxDailyLossPercent > 0 &&
      profitToday + FloatingProfit() <= -AccountInfoDouble(ACCOUNT_BALANCE) * MaxDailyLossPercent / 100.0)
      return;

   if(DailyProfitTargetMoney > 0 && profitToday >= DailyProfitTargetMoney)
      return;

   // 1) Tendance de fond
   int bias = GetBias();
   if(bias == 0)
      return;
   if(openDirection != 0 && openDirection != bias)
      return;

   // 2) Bougies M1 pour la confirmation
   int size = ConfirmLookback + ChochMaxBars + PivotStrength + 2;
   double open[], high[], low[], close[];
   datetime time[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time, true);

   if(CopyTime (_Symbol, PERIOD_M1, 0, size, time)  < size ||
      CopyOpen (_Symbol, PERIOD_M1, 0, size, open)  < size ||
      CopyHigh (_Symbol, PERIOD_M1, 0, size, high)  < size ||
      CopyLow  (_Symbol, PERIOD_M1, 0, size, low)   < size ||
      CopyClose(_Symbol, PERIOD_M1, 0, size, close) < size)
      return;

   double atr = LastValue(atrM1Handle);
   if(atr <= 0)
      return;

   // 3) Un order block dans le sens de la tendance + une confirmation
   for(int b = 0; b < ArraySize(blocks); b++)
   {
      if(blocks[b].dir != bias || IsBlockUsed(blocks[b].time))
         continue;

      double stopPrice = 0;
      if(!CheckConfirmation(blocks[b], time, open, high, low, close, size, atr, stopPrice))
         continue;

      double entry = (bias == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double risk  = (bias == 1) ? entry - stopPrice : stopPrice - entry;
      if(risk < MinRiskAtr * atr || risk > MaxRiskAtr * atr)
         continue;

      int count = (int)MathMin(TradesPerSignal, room);
      if(MaxTradesPerDay > 0)
         count = (int)MathMin(count, MaxTradesPerDay - tradesToday);

      Print("Signal ", (bias == 1 ? "ACHAT" : "VENTE"), " sur order block de ",
            TimeToString(blocks[b].time, TIME_DATE | TIME_MINUTES),
            " [", DoubleToString(blocks[b].bottom, _Digits), " - ", DoubleToString(blocks[b].top, _Digits), "]");

      MarkBlockUsed(blocks[b].time);   // un seul signal par bloc, même si l'ordre échoue
      SendSignalAlert(bias, entry, stopPrice, count, blocks[b]);

      if(!AlertsOnly)
         OpenBasket(bias, stopPrice, count);
      break;
   }
}
//+------------------------------------------------------------------+
