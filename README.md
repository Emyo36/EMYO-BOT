# EMYO-BOT

Expert Advisor MetaTrader 5 de scalping (`EMYO_BOT.mq5`), unité de temps M1.

## Stratégie

- **Achat** : le RSI sort de la zone de survente (repasse au-dessus de `RsiOversold`)
  et la dernière bougie clôture au-dessus de la moyenne mobile `MaPeriod`.
- **Vente** : le RSI repasse sous `RsiOverbought` et la clôture est sous la moyenne mobile.
- Une seule position à la fois, analyse une fois par bougie M1 clôturée.

## Protections

| Paramètre | Rôle |
|---|---|
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
