//+------------------------------------------------------------------+
//| EMYO_Bot.mq5                                                     |
//| Scalping session New York : tendance UT supérieure, prise de     |
//| liquidité, Fibonacci 0.5-0.79, order block ou FVG, momentum.     |
//| Maximum 3 trades par jour.                                       |
//| Même logique que tradingview/EMYO_Strategy.pine                  |
//+------------------------------------------------------------------+
#property copyright "EMYO"
#property version   "1.00"
#property description "Scalping session NY : tendance + liquidité + Fibonacci + order block + FVG + momentum. 3 trades max/jour."

#include <Trade/Trade.mqh>

enum ENUM_CONFLUENCE
  {
   CONF_OB_OR_FVG = 0, // OB ou FVG
   CONF_OB        = 1, // OB
   CONF_FVG       = 2, // FVG
   CONF_NONE      = 3  // Aucune
  };

//--- Paramètres
input group "Tendance (UT supérieure)"
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H1;   // Unité de temps tendance
input int    InpEmaFast          = 50;          // EMA rapide
input int    InpEmaSlow          = 200;         // EMA lente

input group "Session (heure SERVEUR du broker)"
input int    InpSessStartHour    = 15;          // Début session - heure (15:00 = 8:00 NY pour un broker GMT+3)
input int    InpSessStartMin     = 0;           // Début session - minute
input int    InpSessEndHour      = 19;          // Fin session - heure
input int    InpSessEndMin       = 0;           // Fin session - minute
input bool   InpCloseAtSessionEnd = true;       // Fermer les positions à la fin de la session
input int    InpMaxTradesPerDay  = 3;           // Trades max par jour
input bool   InpCountAllSymbols  = true;        // Limite commune à tous les actifs (BTC, Gold, NAS, DJ)

input group "Setup"
input int    InpPivotLen         = 2;           // Longueur des swings (pivots)
input int    InpSetupExpiryBars  = 30;          // Expiration du setup (barres)
input double InpFibTop           = 0.5;         // Fibo - haut de zone
input double InpFibBottom        = 0.79;        // Fibo - bas de zone
input ENUM_CONFLUENCE InpConfluence = CONF_OB_OR_FVG; // Confluence exigée dans la zone Fibo
input int    InpRsiPeriod        = 14;          // RSI (momentum)

input group "Volatilité"
input bool   InpUseVolFilter     = true;        // Trader seulement si le marché est volatil
input int    InpAtrPeriod        = 14;          // ATR
input int    InpAtrMaPeriod      = 50;          // Moyenne de l'ATR
input double InpVolMult          = 0.8;         // ATR minimum (x la moyenne)

input group "Risque"
input double InpRiskPercent      = 1.0;         // Risque par trade (% du solde)
input double InpRiskReward       = 2.5;         // TP final (en R)
input double InpTp1R             = 1.0;         // TP1 (en R)
input double InpTp1ClosePct      = 50.0;        // Part de la position fermée au TP1 (%)
input double InpLockR            = 0.1;         // Stop après TP1 (en R, 0 = point d'entrée)
input double InpSlBufferAtr      = 0.1;         // Marge au-delà du stop (x ATR)
input ulong  InpMagic            = 36036;       // Numéro magique

//--- États : 0 = rien, 1 = liquidité prise (attente cassure de structure),
//---         2 = impulsion validée (attente retracement Fibo)
struct Setup
  {
   int               state;
   double            sweep;
   double            bos;
   double            imp;
   double            obTop;
   double            obBot;
   bool              fvg;
   double            fvgTop;
   double            fvgBot;
   bool              touched;
   int               age;
  };

CTrade   trade;
int      hEmaFast = INVALID_HANDLE;
int      hEmaSlow = INVALID_HANDLE;
int      hRsi     = INVALID_HANDLE;
int      hAtr     = INVALID_HANDLE;
datetime lastBarTime = 0;
double   lastPH = 0.0;   // 0 = aucun swing encore détecté
double   lastPL = 0.0;
Setup    L;
Setup    S;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpLockR < 0 || InpLockR > InpTp1R || InpTp1R >= InpRiskReward || InpTp1ClosePct < 0 || InpTp1ClosePct > 100)
     {
      Print("Il faut : 0 <= stop après TP1 (R) <= TP1 (R) < TP final (R), et une part fermée entre 0 et 100 %.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpFibTop >= InpFibBottom)
     {
      Print("Le Fibo haut de zone doit être inférieur au Fibo bas de zone (ex. 0.5 < 0.79).");
      return(INIT_PARAMETERS_INCORRECT);
     }
   hEmaFast = iMA(_Symbol, InpTrendTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hEmaSlow = iMA(_Symbol, InpTrendTF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   hRsi     = iRSI(_Symbol, _Period, InpRsiPeriod, PRICE_CLOSE);
   hAtr     = iATR(_Symbol, _Period, InpAtrPeriod);
   if(hEmaFast == INVALID_HANDLE || hEmaSlow == INVALID_HANDLE || hRsi == INVALID_HANDLE || hAtr == INVALID_HANDLE)
     {
      Print("Impossible de créer les indicateurs.");
      return(INIT_FAILED);
     }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);
   ZeroMemory(L);
   ZeroMemory(S);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(hEmaFast);
   IndicatorRelease(hEmaSlow);
   IndicatorRelease(hRsi);
   IndicatorRelease(hAtr);
   Comment("");
  }

//+------------------------------------------------------------------+
double BufferValue(const int handle, const int shift)
  {
   double v[1];
   if(CopyBuffer(handle, 0, shift, 1, v) != 1)
      return(EMPTY_VALUE);
   return(v[0]);
  }

//+------------------------------------------------------------------+
bool InSession(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   int m = dt.hour * 60 + dt.min;
   int a = InpSessStartHour * 60 + InpSessStartMin;
   int b = InpSessEndHour * 60 + InpSessEndMin;
   if(a <= b)
      return(m >= a && m < b);
   return(m >= a || m < b);
  }

//+------------------------------------------------------------------+
bool IsOurPosition(const ulong ticket)
  {
   return(PositionSelectByTicket(ticket)
          && PositionGetString(POSITION_SYMBOL) == _Symbol
          && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic);
  }

//+------------------------------------------------------------------+
bool HasPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(IsOurPosition(PositionGetTicket(i)))
         return(true);
   return(false);
  }

//+------------------------------------------------------------------+
void CloseAll()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(IsOurPosition(ticket))
         trade.PositionClose(ticket);
     }
  }

//+------------------------------------------------------------------+
//| Nombre de trades ouverts aujourd'hui (jour serveur)              |
//+------------------------------------------------------------------+
int TradesToday()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   if(!HistorySelect(StructToTime(dt), TimeCurrent() + 60))
      return(0);
   int n = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if(!InpCountAllSymbols && HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
         continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic)
         continue;
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
         n++;
     }
   return(n);
  }

//+------------------------------------------------------------------+
//| Swing haut / bas confirmé à la barre p (InpPivotLen barres de    |
//| chaque côté)                                                     |
//+------------------------------------------------------------------+
bool IsPivotHigh(const int p)
  {
   double h = iHigh(_Symbol, _Period, p);
   for(int k = 1; k <= InpPivotLen; k++)
      if(iHigh(_Symbol, _Period, p - k) >= h || iHigh(_Symbol, _Period, p + k) > h)
         return(false);
   return(true);
  }

bool IsPivotLow(const int p)
  {
   double l = iLow(_Symbol, _Period, p);
   for(int k = 1; k <= InpPivotLen; k++)
      if(iLow(_Symbol, _Period, p - k) <= l || iLow(_Symbol, _Period, p + k) < l)
         return(false);
   return(true);
  }

//+------------------------------------------------------------------+
//| Taille de lot pour risquer InpRiskPercent du solde               |
//+------------------------------------------------------------------+
double LotsForRisk(const double slDist)
  {
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double step      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(tickSize <= 0 || tickValue <= 0 || step <= 0 || slDist <= 0)
      return(0.0);

   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double lots = MathFloor(riskMoney / (slDist / tickSize * tickValue) / step) * step;
   if(lots < minLot)
      return(0.0);   // le lot minimum dépasserait le risque autorisé : pas de trade
   lots = MathMin(lots, maxLot);
   int digits = (int)MathMax(0, MathCeil(-MathLog10(step)));
   return(NormalizeDouble(lots, digits));
  }

//+------------------------------------------------------------------+
bool OpenTrade(const bool isLong, double sl)
  {
   double price   = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dist    = isLong ? price - sl : sl - price;
   double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(dist <= 0 || dist < minDist)
     {
      Print("Stop trop proche du prix, trade ignoré.");
      return(false);
     }
   double tp   = isLong ? price + InpRiskReward * dist : price - InpRiskReward * dist;
   double lots = LotsForRisk(dist);
   if(lots <= 0)
     {
      Print("Lot calculé inférieur au lot minimum pour ce risque, trade ignoré.");
      return(false);
     }
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   bool ok = isLong ? trade.Buy(lots, _Symbol, 0.0, sl, tp, "EMYO long")
                    : trade.Sell(lots, _Symbol, 0.0, sl, tp, "EMYO short");
   if(!ok)
      PrintFormat("Échec de l'ordre : %u %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
   return(ok);
  }

//+------------------------------------------------------------------+
//| Volume à fermer au TP1 (0 si la position est trop petite pour    |
//| être coupée)                                                     |
//+------------------------------------------------------------------+
double PartialVolume(const double volume)
  {
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(step <= 0 || InpTp1ClosePct <= 0)
      return(0.0);
   double part = MathFloor(volume * InpTp1ClosePct / 100.0 / step) * step;
   if(part < minLot || volume - part < minLot - step / 2)
      return(0.0);
   int digits = (int)MathMax(0, MathCeil(-MathLog10(step)));
   return(NormalizeDouble(part, digits));
  }

//+------------------------------------------------------------------+
//| TP1 touché : le stop du reste passe au point d'entrée (+ InpLockR) |
//| puis InpTp1ClosePct % de la position est encaissé. Le reste vise |
//| le TP final. Le risque initial est retrouvé à partir du TP :     |
//| TP = entrée ± InpRiskReward * risque.                            |
//| Une position déjà traitée a son stop du côté gagnant de l'entrée. |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket))
         continue;
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      double volume = PositionGetDouble(POSITION_VOLUME);
      if(tp <= 0)
         continue;
      double risk = MathAbs(tp - open) / InpRiskReward;
      if(risk <= 0)
         continue;

      double newSl;
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(sl >= open || bid < open + InpTp1R * risk)
            continue;
         newSl = NormalizeDouble(MathMin(open + InpLockR * risk, bid - minDist), _Digits);
         if(newSl < open)
            continue;   // prix trop proche pour placer le stop : on réessaie au tick suivant
        }
      else
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if((sl > 0 && sl <= open) || ask > open - InpTp1R * risk)
            continue;
         newSl = NormalizeDouble(MathMax(open - InpLockR * risk, ask + minDist), _Digits);
         if(newSl > open)
            continue;
        }

      if(!trade.PositionModify(ticket, newSl, tp))
        {
         PrintFormat("Déplacement du stop impossible : %u %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
         continue;
        }
      double part = PartialVolume(volume);
      if(part > 0 && !trade.PositionClosePartial(ticket, part))
         PrintFormat("Clôture partielle au TP1 impossible : %u %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   ManagePositions();
   if(InpCloseAtSessionEnd && !InSession(TimeCurrent()) && HasPosition())
      CloseAll();

   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 == 0 || t0 == lastBarTime)
      return;
   lastBarTime = t0;
   if(Bars(_Symbol, _Period) < 2 * InpPivotLen + 5)
      return;
   OnNewBar();
  }

//+------------------------------------------------------------------+
//| Analyse de la dernière bougie clôturée (shift 1)                 |
//+------------------------------------------------------------------+
void OnNewBar()
  {
   double o  = iOpen(_Symbol, _Period, 1);
   double h  = iHigh(_Symbol, _Period, 1);
   double l  = iLow(_Symbol, _Period, 1);
   double c  = iClose(_Symbol, _Period, 1);
   double h3 = iHigh(_Symbol, _Period, 3);
   double l3 = iLow(_Symbol, _Period, 3);
   bool inSess = InSession(iTime(_Symbol, _Period, 1));

   //--- Tendance sur la dernière bougie UT supérieure clôturée
   double ef = BufferValue(hEmaFast, 1);
   double es = BufferValue(hEmaSlow, 1);
   double hc = iClose(_Symbol, InpTrendTF, 1);
   bool dataOk    = (ef != EMPTY_VALUE && es != EMPTY_VALUE && hc > 0);
   bool bullTrend = dataOk && ef > es && hc > es;
   bool bearTrend = dataOk && ef < es && hc < es;

   //--- Momentum
   double r1 = BufferValue(hRsi, 1);
   double r2 = BufferValue(hRsi, 2);
   bool rsiOk = (r1 != EMPTY_VALUE && r2 != EMPTY_VALUE);
   bool momUp = rsiOk && r1 > r2 && c > o;
   bool momDn = rsiOk && r1 < r2 && c < o;

   //--- Volatilité : ATR au-dessus de sa moyenne
   double atrs[];
   bool   atrOk = (CopyBuffer(hAtr, 0, 1, InpAtrMaPeriod, atrs) == InpAtrMaPeriod);
   double atr   = atrOk ? atrs[InpAtrMaPeriod - 1] : 0.0;   // série non inversée : dernier élément = shift 1
   double atrMa = 0.0;
   if(atrOk)
     {
      for(int k = 0; k < InpAtrMaPeriod; k++)
         atrMa += atrs[k];
      atrMa /= InpAtrMaPeriod;
     }
   bool volOk = atrOk && (!InpUseVolFilter || atr > atrMa * InpVolMult);

   int  tradesToday = TradesToday();
   bool canTrade    = inSess && volOk && tradesToday < InpMaxTradesPerDay && !HasPosition();
   double buf       = InpSlBufferAtr * atr;

   //--- Swings connus avant cette bougie
   double phRef = lastPH;
   double plRef = lastPL;

   if(!inSess)
     {
      ZeroMemory(L);
      ZeroMemory(S);
     }

   //--- Expiration / invalidation
   if(L.state != 0 && ++L.age > InpSetupExpiryBars)
      ZeroMemory(L);
   if(L.state == 2 && c < L.sweep)
      ZeroMemory(L);
   if(S.state != 0 && ++S.age > InpSetupExpiryBars)
      ZeroMemory(S);
   if(S.state == 2 && c > S.sweep)
      ZeroMemory(S);

   //================= LONG =================
   bool   longSignal = false;
   double longPoiBot = 0.0;
   if(L.state == 2)
     {
      double rng  = L.imp - L.sweep;
      double z618 = L.imp - rng * InpFibTop;
      double z786 = L.imp - rng * InpFibBottom;
      bool obIn   = L.obTop >= z786 && L.obBot <= z618;
      bool fvgIn  = L.fvg && L.fvgTop >= z786 && L.fvgBot <= z618;
      bool confOk = InpConfluence == CONF_NONE
                    || (InpConfluence != CONF_FVG && obIn)
                    || (InpConfluence != CONF_OB && fvgIn);
      longPoiBot  = (obIn && InpConfluence != CONF_FVG) ? L.obBot : z786;
      if(l <= z618)
         L.touched = true;
      if(L.touched && momUp && c > L.sweep && c < L.imp && confOk && canTrade)
         longSignal = true;
      if(!L.touched && h > L.imp)
         L.imp = h;
     }
   if(L.state == 1)
     {
      if(l < L.sweep)
         L.sweep = l;
      if(c < o)
        {
         L.obTop = h;
         L.obBot = l;
        }
      if(l > h3)
        {
         L.fvgTop = L.fvg ? MathMax(L.fvgTop, l) : l;
         L.fvgBot = L.fvg ? MathMin(L.fvgBot, h3) : h3;
         L.fvg    = true;
        }
      if(c > L.bos)
        {
         L.state   = 2;
         L.imp     = h;
         L.touched = false;
        }
     }
   if(L.state == 0 && inSess && bullTrend && plRef > 0 && phRef > 0 && l < plRef && c > plRef && phRef > c)
     {
      L.state   = 1;
      L.sweep   = l;
      L.bos     = phRef;
      L.obTop   = h;
      L.obBot   = l;
      L.fvg     = false;
      L.touched = false;
      L.age     = 0;
     }

   //================= SHORT =================
   bool   shortSignal = false;
   double shortPoiTop = 0.0;
   if(S.state == 2)
     {
      double rng  = S.sweep - S.imp;
      double z618 = S.imp + rng * InpFibTop;
      double z786 = S.imp + rng * InpFibBottom;
      bool obIn   = S.obBot <= z786 && S.obTop >= z618;
      bool fvgIn  = S.fvg && S.fvgBot <= z786 && S.fvgTop >= z618;
      bool confOk = InpConfluence == CONF_NONE
                    || (InpConfluence != CONF_FVG && obIn)
                    || (InpConfluence != CONF_OB && fvgIn);
      shortPoiTop = (obIn && InpConfluence != CONF_FVG) ? S.obTop : z786;
      if(h >= z618)
         S.touched = true;
      if(S.touched && momDn && c < S.sweep && c > S.imp && confOk && canTrade)
         shortSignal = true;
      if(!S.touched && l < S.imp)
         S.imp = l;
     }
   if(S.state == 1)
     {
      if(h > S.sweep)
         S.sweep = h;
      if(c > o)
        {
         S.obTop = h;
         S.obBot = l;
        }
      if(h < l3)
        {
         S.fvgTop = S.fvg ? MathMax(S.fvgTop, l3) : l3;
         S.fvgBot = S.fvg ? MathMin(S.fvgBot, h) : h;
         S.fvg    = true;
        }
      if(c < S.bos)
        {
         S.state   = 2;
         S.imp     = l;
         S.touched = false;
        }
     }
   if(S.state == 0 && inSess && bearTrend && plRef > 0 && phRef > 0 && h > phRef && c < phRef && plRef < c)
     {
      S.state   = 1;
      S.sweep   = h;
      S.bos     = plRef;
      S.obTop   = h;
      S.obBot   = l;
      S.fvg     = false;
      S.touched = false;
      S.age     = 0;
     }

   //================= ORDRES =================
   if(longSignal)
     {
      double sl = MathMin(longPoiBot, l) - buf;
      if(OpenTrade(true, sl))
         tradesToday++;
      ZeroMemory(L);
     }
   if(shortSignal && !longSignal)
     {
      double sl = MathMax(shortPoiTop, h) + buf;
      if(OpenTrade(false, sl))
         tradesToday++;
      ZeroMemory(S);
     }

   //--- Mise à jour des swings après usage
   int p = 1 + InpPivotLen;
   if(IsPivotHigh(p))
      lastPH = iHigh(_Symbol, _Period, p);
   if(IsPivotLow(p))
      lastPL = iLow(_Symbol, _Period, p);

   Comment(StringFormat("EMYO Bot | Session : %s | Tendance : %s | Trades aujourd'hui : %d / %d",
                        inSess ? "OUVERTE" : "fermée",
                        bullTrend ? "haussière" : (bearTrend ? "baissière" : "neutre"),
                        tradesToday, InpMaxTradesPerDay));
  }
//+------------------------------------------------------------------+
