//+------------------------------------------------------------------+
//|              EMYO BOT - SCALPING M1 SUIVI DE TENDANCE             |
//+------------------------------------------------------------------+
#property copyright "EMYO"
#property version   "1.30"

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
input double TrailingStopPips   = 10;    // Distance du trailing stop (0 = off)
input double TrailingStepPips   = 1;     // Déplacement minimum du trailing

input group "Tendance"
input int             FastEmaPeriod     = 20;          // EMA rapide M1 (zone de repli)
input int             SlowEmaPeriod     = 50;          // EMA lente M1 (direction)
input bool            UseHigherTimeframe = true;       // Confirmer avec une unité de temps supérieure
input ENUM_TIMEFRAMES TrendTimeframe    = PERIOD_M15;  // Unité de temps de confirmation
input int             TrendEmaPeriod    = 50;          // EMA de confirmation
input bool            CloseOnTrendReversal = true;     // Fermer si la tendance M1 s'inverse

input group "Entrée"
input double PullbackTolerancePips = 1;  // Distance max. à l'EMA rapide pour valider le repli
input int    RsiPeriod          = 14;    // Période du RSI
input double RsiMidLevel        = 50;    // RSI > niveau pour acheter, < niveau pour vendre

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
int      fastHandle  = INVALID_HANDLE;
int      slowHandle  = INVALID_HANDLE;
int      htfHandle   = INVALID_HANDLE;
int      rsiHandle   = INVALID_HANDLE;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if(StopLossPips <= 0 || TakeProfitPips <= 0 || RsiPeriod <= 0 ||
      FastEmaPeriod <= 0 || SlowEmaPeriod <= FastEmaPeriod || TrendEmaPeriod <= 0 ||
      StartHour < 0 || StartHour > 23 ||
      EndHour < 0 || EndHour > 23 || Lots <= 0 || RiskPercent < 0)
   {
      Print("Erreur : paramètres invalides");
      return(INIT_PARAMETERS_INCORRECT);
   }

   fastHandle = iMA(_Symbol, PERIOD_M1, FastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA(_Symbol, PERIOD_M1, SlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   htfHandle  = iMA(_Symbol, TrendTimeframe, TrendEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle  = iRSI(_Symbol, PERIOD_M1, RsiPeriod, PRICE_CLOSE);

   if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE ||
      htfHandle  == INVALID_HANDLE || rsiHandle  == INVALID_HANDLE)
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

   if(fastHandle != INVALID_HANDLE) IndicatorRelease(fastHandle);
   if(slowHandle != INVALID_HANDLE) IndicatorRelease(slowHandle);
   if(htfHandle  != INVALID_HANDLE) IndicatorRelease(htfHandle);
   if(rsiHandle  != INVALID_HANDLE) IndicatorRelease(rsiHandle);

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

   int trend = GetTrend(fast, slow, close);
   if(trend == 0)
      return;

   double tolerance = PullbackTolerancePips * PipSize();

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

   if(!buySignal && !sellSignal)
      return;

   if(!CheckSpread())
      return;

   if(buySignal)
      OpenBuy();
   else
      OpenSell();
}
//+------------------------------------------------------------------+
