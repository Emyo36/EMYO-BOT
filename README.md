# EMYO-BOT

Expert Advisor MetaTrader 5 de scalping en M1 qui suit la tendance (`EMYO_BOT.mq5`),
pensé pour l'**or (XAUUSD)**, le **Bitcoin (BTCUSD)** et le **NASDAQ (NAS100 / USTEC)**.

## Stratégie : suivre la tendance sur M1

1. **Tendance** : EMA 20 au-dessus de l'EMA 50, EMA 50 qui monte, et prix au-dessus
   (inverse pour une tendance baissière). La tendance doit aussi être confirmée
   sur M15 (prix du même côté de son EMA 50). Sans tendance claire, le bot ne trade pas.
2. **Entrée sur le momentum** (par défaut) : en tendance haussière, le bot achète quand
   une bougie M1 forte (corps ≥ 0,8 ATR) clôture près de son plus haut, casse le plus
   haut des 5 bougies précédentes, avec un RSI au-dessus de 55 et en hausse.
   Symétrique à la vente. `EntryMode` permet aussi d'entrer sur les replis vers
   l'EMA 20, ou sur les deux.
3. **3 positions ouvertes ensemble** : à chaque signal, le bot ouvre 3 positions avec
   le même Stop Loss et des Take Profit échelonnés (1 / 1,5 / 2 ATR). Chaque position
   vise `TargetProfitMoney` (3 € par défaut) : le lot de chacune est calculé pour ça.
4. **Protection** : le break-even protège les positions dès mi-chemin du premier TP ;
   tout est fermé si l'EMA 20 repasse de l'autre côté de l'EMA 50.

Jamais d'achats et de ventes en même temps sur un même symbole. Dès que des places
se libèrent (`MaxOpenPositions`), le bot reprend le train au signal suivant.
Objectif : beaucoup de petits gains répétés.

## Gain fixe en euros

Avec `TargetProfitMoney = 3`, chaque trade vise 3 € (dans la devise du compte),
quel que soit le marché : le bot adapte le lot à la distance du TP. Le journal
(onglet Experts) affiche à chaque trade le gain visé et la perte maximale.

Attention au rapport gain / perte : les 3 positions partagent le même Stop Loss
(1,2 ATR). Si le marché repart contre vous avant le break-even, les 3 sont perdues
ensemble : environ 3,60 € + 2,40 € + 1,80 € ≈ **7,80 € de perte** pour **9 € de gain**
si les 3 TP sont atteints. C'est le point à vérifier en backtest.

Si le lot minimum du courtier donne déjà un gain supérieur à l'objectif, le bot ne
prend pas le trade (plutôt que de risquer plus que prévu) et l'indique dans le journal.

## Distances en ATR

L'or, le Bitcoin et le NASDAQ n'ont pas de « pip » comparable au forex. Toutes les
distances (SL, TP, break-even, trailing, repli) sont donc exprimées en **multiples de
l'ATR M1**, le mouvement moyen d'une bougie. Le bot s'adapte ainsi tout seul à chaque
marché et à sa volatilité du moment. Exemple : si l'ATR de l'or vaut 0,80 $,
`StopLoss = 1.5` place le SL à 1,20 $ du prix d'entrée.

Le mode `DistanceMode = Pips` reste disponible pour le forex.

## Session américaine

Par défaut (`SessionMode = Session américaine`), le bot ne trade que pendant la
session de New York, **9h30 → 16h00 heure de New York**, du lundi au vendredi,
et ferme ses positions à la fin de la session (`CloseOutsideSession`).

Les heures sont en heure de New York : le bot convertit tout seul depuis l'heure du
serveur du courtier, en tenant compte de l'heure d'été américaine (qui ne change pas
aux mêmes dates qu'en Europe). En heure de Paris, la session correspond en général à
15h30 → 22h00, mais à 14h30 → 21h00 quelques semaines en mars et fin octobre.

- En réel, le décalage du serveur est détecté automatiquement.
- En backtest, le bot suppose un serveur en GMT+2 l'hiver / GMT+3 l'été (réglage le
  plus courant). Si votre courtier est différent, indiquez son décalage dans
  `ServerGmtOffset`.
- Au lancement, le journal affiche l'heure de New York calculée et si la session est
  ouverte : vérifiez-la une fois.

Pour l'or, dont l'activité américaine démarre plus tôt, on peut mettre
`NyStartHour = 8`, `NyStartMinute = 0`.

## Réglages conseillés

Un bot par graphique **M1** : un sur XAUUSD, un sur BTCUSD, un sur NAS100, avec les
réglages par défaut. Le lot est calculé automatiquement par `TargetProfitMoney` ;
`MaxLots` sert de garde-fou.

## Paramètres

| Paramètre | Rôle |
|---|---|
| `TargetProfitMoney` | Gain visé par trade en devise du compte ; le lot est calculé pour l'atteindre au TP |
| `RiskPercent` / `Lots` | Si `TargetProfitMoney = 0` : lot pour risquer ce % du solde, sinon lot fixe |
| `MaxLots` | Lot maximum par position, quel que soit le calcul |
| `TradesPerSignal` | Positions ouvertes ensemble à chaque signal (3) |
| `MaxOpenPositions` | Positions ouvertes en même temps au maximum sur le symbole (3) |
| `TakeProfitStep` | Écart entre les TP des positions, en ATR |
| `EntryMode` | Momentum (défaut), repli sur l'EMA 20, ou les deux |
| `MomentumLookback` / `MomentumBody` / `MomentumCloseRatio` | Définition d'une bougie de momentum |
| `RsiMomentumLevel` | RSI minimum (achat) ou maximum (100 − niveau, vente) pour le momentum |
| `DistanceMode` / `AtrPeriod` | Distances en ATR (défaut) ou en pips |
| `StopLoss` / `TakeProfit` | SL et TP en ATR ; `TakeProfit = 0` laisse le trailing gérer la sortie |
| `BreakEvenTrigger` / `BreakEvenLock` | Remonte le SL au prix d'entrée + une marge une fois en gain |
| `TrailingStop` / `TrailingStep` | Fait suivre le SL derrière le prix (0 = désactivé) |
| `PullbackTolerance` | Distance max. à l'EMA 20 pour considérer que le prix a fait son repli |
| `FastEmaPeriod` / `SlowEmaPeriod` | EMA de repli et EMA de direction sur M1 |
| `UseHigherTimeframe` / `TrendTimeframe` / `TrendEmaPeriod` | Confirmation de la tendance sur M15 |
| `CloseOnTrendReversal` | Ferme la position quand la tendance M1 s'inverse |
| `RsiPeriod` / `RsiMidLevel` | Filtre RSI des entrées sur repli (au-dessus / en dessous de 50) |
| `MaxSpreadPercentOfSL` / `MaxSpreadPoints` | Refuse d'entrer si le spread est trop grand |
| `MaxSlippagePercentOfSL` | Glissement maximum accepté à l'exécution |
| `SessionMode` | Session américaine (défaut), plage en heure serveur, ou 24h/24 |
| `NyStartHour` / `NyStartMinute` / `NyEndHour` / `NyEndMinute` | Horaires de la session, heure de New York |
| `WeekdaysOnly` | Pas de trading le week-end (utile pour le Bitcoin) |
| `CloseOutsideSession` | Ferme les positions à la fin de la session |
| `ServerGmtOffset` | Décalage GMT du serveur (99 = automatique) |
| `StartHour` / `EndHour` | Mode serveur : plage horaire en heure du serveur |
| `MaxTradesPerDay` | Nombre maximum de positions ouvertes par jour et par symbole (60) |
| `MaxDailyLossPercent` | Arrête d'ouvrir des trades pour la journée après cette perte |
| `DailyProfitTargetMoney` | Arrête d'ouvrir des trades pour la journée une fois ce gain atteint (0 = off) |
| `MagicNumber` | Identifie les positions du bot (les autres ne sont jamais touchées) |
| `AutoCloseOnStop` | Ferme les positions du bot quand on le retire du graphique |

## Installation

1. Copier `EMYO_BOT.mq5` dans `MQL5/Experts/` (menu Fichier → Ouvrir le dossier des données).
2. Compiler dans MetaEditor (F7).
3. Tester d'abord dans le Strategy Tester (modèle « Chaque tick basé sur les ticks réels »),
   puis sur un compte **démo**.
