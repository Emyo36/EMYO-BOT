# EMYO-BOT

Expert Advisor MetaTrader 5 de scalping (`EMYO_BOT.mq5`), unité de temps M1.

## Stratégie : suivre la tendance sur M1

1. **Tendance** : EMA 20 au-dessus de l'EMA 50, EMA 50 qui monte, et prix au-dessus
   (inverse pour une tendance baissière). Option : la tendance doit aussi être confirmée
   sur M15 (prix du même côté de son EMA 50). Sans tendance claire, le bot ne trade pas.
2. **Entrée à chaque repli** : en tendance haussière, dès que le prix revient toucher
   l'EMA 20 puis qu'une bougie clôture en hausse au-dessus d'elle (RSI > 50), le bot achète.
   Symétrique à la vente en tendance baissière.
3. **Laisser courir** : break-even puis trailing stop pour suivre le mouvement ;
   la position est fermée si l'EMA 20 repasse de l'autre côté de l'EMA 50.

Une seule position à la fois ; dès qu'elle est fermée, le bot reprend le train au repli suivant.

## Protections

| Paramètre | Rôle |
|---|---|
| `FastEmaPeriod` / `SlowEmaPeriod` | EMA de repli et EMA de direction sur M1 |
| `UseHigherTimeframe` / `TrendTimeframe` / `TrendEmaPeriod` | Confirmation de la tendance sur une unité de temps supérieure |
| `CloseOnTrendReversal` | Ferme la position quand la tendance M1 s'inverse |
| `PullbackTolerancePips` / `RsiMidLevel` | Précision du repli et filtre de momentum |
| `RiskPercent` | Calcule le lot pour risquer ce % du solde sur le SL (0 = lot fixe `Lots`) |
| `BreakEvenPips` / `BreakEvenLockPips` | Remonte le SL au prix d'entrée + quelques pips une fois en gain |
| `TrailingStopPips` / `TrailingStepPips` | Fait suivre le SL derrière le prix (0 = désactivé) |
| `MaxSpreadPoints` / `MaxSlippagePoints` | Refuse d'entrer si le spread ou le glissement est trop grand |
| `StartHour` / `EndHour` | Plage horaire de trading, heure du serveur (égales = 24h/24) |
| `MaxTradesPerDay` | Nombre maximum de trades par jour |
| `MaxDailyLossPercent` | Arrête d'ouvrir des trades pour la journée après cette perte |
| `MagicNumber` | Identifie les positions du bot (les autres ne sont jamais touchées) |
| `AutoCloseOnStop` | Ferme les positions du bot quand on le retire du graphique |

## Installation

1. Copier `EMYO_BOT.mq5` dans `MQL5/Experts/` (menu Fichier → Ouvrir le dossier des données).
2. Compiler dans MetaEditor (F7).
3. Tester d'abord dans le Strategy Tester, puis sur un compte **démo**.
