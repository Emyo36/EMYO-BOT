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
   vise `TargetProfitMoney` (2 € par défaut) : le lot de chacune est calculé pour ça.
4. **Protection** : le break-even protège les positions dès mi-chemin du premier TP ;
   tout est fermé si l'EMA 20 repasse de l'autre côté de l'EMA 50.

Jamais d'achats et de ventes en même temps sur un même symbole. Dès que des places
se libèrent (`MaxOpenPositions`), le bot reprend le train au signal suivant.
Objectif : beaucoup de petits gains répétés.

## Style agressif (par défaut)

Avec `TradingStyle = Agressif`, le bot cherche un maximum d'occasions :

| Réglage | Normal | Agressif |
|---|---|---|
| Entrées | Momentum | Momentum **et** replis sur l'EMA 20 |
| Confirmation M15 | Oui | Non : réagit directement à la tendance M1 |
| Pente de l'EMA 50 exigée | Oui | Non : EMA 20 / EMA 50 alignées suffisent |
| Bougie de momentum | Corps ≥ 0,8 ATR, casse 5 bougies, RSI > 55 | Corps ≥ 0,5 ATR, casse 3 bougies, RSI > 52 |
| Positions ouvertes max. | 3 | 9 (jusqu'à 3 paniers de 3) |
| Positions par jour | 60 | Illimité |

**Ajout de positions (pyramidage)** : un nouveau panier de 3 n'est ouvert que si toutes
les positions déjà ouvertes sont passées au break-even (`AddOnlyWhenProtected`). Seul le
dernier panier peut donc perdre : la perte maximale reste celle d'un panier, même avec
9 positions ouvertes.

Ce qui reste actif quel que soit le style : la session américaine, le filtre de spread,
le break-even et l'arrêt du jour à −3 % (`MaxDailyLossPercent`).

## Petits gains cumulés

L'idée : beaucoup de petits gains répétés plutôt que de gros coups. Avec
`TargetProfitMoney = 2`, chaque position vise 2 € (dans la devise du compte), quel que
soit le marché : le bot adapte le lot à la distance du TP. On peut descendre à 1 €.

- Si le lot minimum du courtier rapporte déjà plus que l'objectif, le bot le prend quand
  même tant que le gain reste sous `MaxProfitAtMinLot` (5 €), au lieu de rater le trade.
- Un compteur sur le graphique affiche la session, les positions ouvertes, le nombre de
  positions du jour et le **gain cumulé du jour**.

Attention : plus l'objectif est petit, plus le spread et les commissions en mangent une
part. Sur un compte avec commission, un gain brut de 1 € peut devenir 0,50 € net. Le gain
affiché par le compteur est net (commissions et swaps compris) : c'est lui qui compte.

Les 3 positions d'un signal partagent le même Stop Loss (1,2 ATR). Si le marché repart
contre vous avant le break-even, les 3 sont perdues ensemble : environ 2,40 € + 1,60 € +
1,20 € ≈ **5,20 € de perte** pour **6 € de gain** si les 3 TP sont atteints. Il faut donc
gagner nettement plus souvent que perdre : c'est le point à vérifier en backtest.

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
| `TargetProfitMoney` | Gain visé par position (2 €) ; le lot est calculé pour l'atteindre au TP |
| `RiskPercent` / `Lots` | Si `TargetProfitMoney = 0` : lot pour risquer ce % du solde, sinon lot fixe |
| `MaxProfitAtMinLot` | Gain max. accepté quand le lot minimum dépasse l'objectif |
| `ShowPanel` | Affiche le compteur de gains sur le graphique |
| `MaxLots` | Lot maximum par position, quel que soit le calcul |
| `TradingStyle` | Agressif (défaut) ou Normal ; en agressif, remplace les réglages indiqués plus haut |
| `AddOnlyWhenProtected` | N'ajoute un panier que si les positions ouvertes sont au break-even |
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

---

# EMYO SMC (`EMYO_SMC.mq5`)

Deuxième bot, séparé, qui reproduit la méthode d'une vidéo ICT / SMC : **on ne rentre
jamais directement sur une zone, on attend une confirmation**. Il se teste à côté
d'EMYO_BOT pour comparer (numéro magique différent : 360037).

1. **Tendance de fond** : dernière clôture H1 **et** H4 du même côté de leur EMA 50.
2. **Order block (M5)** : dernière bougie contraire avant une impulsion forte
   (clôture au-delà du bloc d'au moins 1,5 ATR en 3 bougies). Le bloc est abandonné si
   une bougie M5 clôture au travers.
3. **Retour sur la zone** : en M1, le prix revient toucher le bloc sans clôturer au travers.
4. **Confirmation M1** (`Confirmation`) :
   - **CHoCH** (défaut, « la plus forte » selon la vidéo) : la bougie clôture au-delà du
     dernier point haut (achat) / point bas (vente) qui a précédé l'extrême de la correction ;
   - **bougie englobante** sur la zone ;
   - ou l'une des deux.
5. **Ordres** : SL sous le plus bas de la correction (achat) avec une petite marge ;
   3 positions avec TP à **1R, 2R et 3R** (R = risque). Chaque position vise
   `TargetProfitMoney`. Break-even à 1R. Un seul signal par order block.

Option **runner** (`UseRunner`, désactivée par défaut) : la 3e position n'a pas de TP ;
une fois au break-even, son SL suit le prix à `RunnerTrailAtr` × ATR M5 et elle se ferme au
SL ou en fin de session. Idée tirée des backtests : les positions encore ouvertes en fin de
session sont gagnantes en moyenne sur l'or et le Bitcoin.

Mêmes protections qu'EMYO_BOT : session américaine, arrêt du jour à −3 %, filtre de
spread (en % du risque), fermeture en fin de session, compteur sur le graphique.

La vidéo annonce 75–80 % de réussite : c'est une affirmation marketing, seul le
backtest dira ce que donnent ces règles automatisées.
