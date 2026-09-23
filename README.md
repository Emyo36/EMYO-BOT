# EMYO-BOT

Expert Advisor MetaTrader 5 de scalping en M1 qui suit la tendance (`EMYO_BOT.mq5`),
pensé pour l'**or (XAUUSD)**, le **Bitcoin (BTCUSD)** et le **NASDAQ (NAS100 / USTEC)**.

## Stratégie : suivre la tendance sur M1

1. **Tendance** : EMA 20 au-dessus de l'EMA 50, EMA 50 qui monte, et prix au-dessus
   (inverse pour une tendance baissière). La tendance doit aussi être confirmée
   sur M15 (prix du même côté de son EMA 50). Sans tendance claire, le bot ne trade pas.
2. **Entrée à chaque repli** : en tendance haussière, dès que le prix revient toucher
   l'EMA 20 puis qu'une bougie clôture en hausse au-dessus d'elle (RSI > 50), le bot achète.
   Symétrique à la vente en tendance baissière.
3. **Petit gain rapide** : le Take Profit est placé à 1 ATR et le lot est calculé pour
   que ce TP rapporte `TargetProfitMoney` (3 € par défaut). Le break-even protège
   le trade dès qu'il est à mi-chemin ; la position est fermée si l'EMA 20 repasse
   de l'autre côté de l'EMA 50.

Une seule position à la fois par symbole ; dès qu'elle est fermée, le bot reprend
le train au repli suivant. Objectif : beaucoup de petits gains répétés.

## Gain fixe en euros

Avec `TargetProfitMoney = 3`, chaque trade vise 3 € (dans la devise du compte),
quel que soit le marché : le bot adapte le lot à la distance du TP. Le journal
(onglet Experts) affiche à chaque trade le gain visé et la perte maximale.

Attention au rapport gain / perte : avec les réglages par défaut (TP 1 ATR,
SL 1,2 ATR), un gain de 3 € s'accompagne d'une perte maximale d'environ 3,60 €.
Il faut donc gagner plus de 55 % des trades pour être rentable, commissions
comprises. Une perte efface plus d'un gain : c'est le point à vérifier en backtest.

Si le lot minimum du courtier donne déjà un gain supérieur à l'objectif, le bot ne
prend pas le trade (plutôt que de risquer plus que prévu) et l'indique dans le journal.

## Distances en ATR

L'or, le Bitcoin et le NASDAQ n'ont pas de « pip » comparable au forex. Toutes les
distances (SL, TP, break-even, trailing, repli) sont donc exprimées en **multiples de
l'ATR M1**, le mouvement moyen d'une bougie. Le bot s'adapte ainsi tout seul à chaque
marché et à sa volatilité du moment. Exemple : si l'ATR de l'or vaut 0,80 $,
`StopLoss = 1.5` place le SL à 1,20 $ du prix d'entrée.

Le mode `DistanceMode = Pips` reste disponible pour le forex.

## Réglages conseillés

Un bot par graphique **M1** : un sur XAUUSD, un sur BTCUSD, un sur NAS100.
Les réglages par défaut conviennent aux trois ; seule la plage horaire change.
Les heures sont celles du **serveur du courtier** (souvent GMT+2 en hiver, GMT+3 en été,
visible dans l'Observateur de marché).

| Marché | `StartHour` → `EndHour` (serveur GMT+3) | Pourquoi |
|---|---|---|
| Or | 10 → 22 | Sessions de Londres et New York, spread faible |
| NASDAQ | 16 → 23 | Ouverture de Wall Street (16h30) jusqu'à la clôture |
| Bitcoin | 0 → 0 (24h/24) | Marché ouvert en continu ; réduire à 10 → 23 si trop de faux signaux la nuit |

Le lot est calculé automatiquement par `TargetProfitMoney` ; `MaxLots` sert de garde-fou.

## Paramètres

| Paramètre | Rôle |
|---|---|
| `TargetProfitMoney` | Gain visé par trade en devise du compte ; le lot est calculé pour l'atteindre au TP |
| `RiskPercent` / `Lots` | Si `TargetProfitMoney = 0` : lot pour risquer ce % du solde, sinon lot fixe |
| `MaxLots` | Lot maximum, quel que soit le calcul |
| `DistanceMode` / `AtrPeriod` | Distances en ATR (défaut) ou en pips |
| `StopLoss` / `TakeProfit` | SL et TP en ATR ; `TakeProfit = 0` laisse le trailing gérer la sortie |
| `BreakEvenTrigger` / `BreakEvenLock` | Remonte le SL au prix d'entrée + une marge une fois en gain |
| `TrailingStop` / `TrailingStep` | Fait suivre le SL derrière le prix (0 = désactivé) |
| `PullbackTolerance` | Distance max. à l'EMA 20 pour considérer que le prix a fait son repli |
| `FastEmaPeriod` / `SlowEmaPeriod` | EMA de repli et EMA de direction sur M1 |
| `UseHigherTimeframe` / `TrendTimeframe` / `TrendEmaPeriod` | Confirmation de la tendance sur M15 |
| `CloseOnTrendReversal` | Ferme la position quand la tendance M1 s'inverse |
| `RsiPeriod` / `RsiMidLevel` | Filtre de momentum (RSI au-dessus / en dessous de 50) |
| `MaxSpreadPercentOfSL` / `MaxSpreadPoints` | Refuse d'entrer si le spread est trop grand |
| `MaxSlippagePercentOfSL` | Glissement maximum accepté à l'exécution |
| `StartHour` / `EndHour` | Plage horaire de trading, heure du serveur (égales = 24h/24) |
| `MaxTradesPerDay` | Nombre maximum de trades par jour et par symbole |
| `MaxDailyLossPercent` | Arrête d'ouvrir des trades pour la journée après cette perte |
| `DailyProfitTargetMoney` | Arrête d'ouvrir des trades pour la journée une fois ce gain atteint (0 = off) |
| `MagicNumber` | Identifie les positions du bot (les autres ne sont jamais touchées) |
| `AutoCloseOnStop` | Ferme les positions du bot quand on le retire du graphique |

## Installation

1. Copier `EMYO_BOT.mq5` dans `MQL5/Experts/` (menu Fichier → Ouvrir le dossier des données).
2. Compiler dans MetaEditor (F7).
3. Tester d'abord dans le Strategy Tester (modèle « Chaque tick basé sur les ticks réels »),
   puis sur un compte **démo**.
