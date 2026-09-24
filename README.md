# EMYO-BOT

Bot de scalping pour la **session de New York**, **3 trades maximum par jour**.

| Fichier | Rôle |
|---|---|
| `tradingview/EMYO_Strategy.pine` | Stratégie TradingView (Pine Script v6) : analyse, affichage des zones et backtest |
| `mt5/EMYO_Bot.mq5` | Expert Advisor MetaTrader 5 : prend les trades automatiquement avec la même logique |

## Logique du setup

1. **Tendance** : sur l'UT supérieure (H1 par défaut), EMA 50 au-dessus de l'EMA 200 et clôture au-dessus de l'EMA 50 pour les achats (l'inverse pour les ventes). On ne trade que dans ce sens.
2. **Session US** : les setups ne sont cherchés que pendant la session (9h30–12h00 heure de New York par défaut).
3. **Prise de liquidité** : une mèche passe sous le dernier plus bas (achat) ou au-dessus du dernier plus haut (vente), puis la bougie clôture de l'autre côté.
4. **Cassure de structure** : le prix clôture au-delà du swing opposé, ce qui valide l'impulsion.
5. **Fibonacci** : sur l'impulsion (du point de liquidité jusqu'à l'extrême), on attend un retour dans la zone **0.618–0.786**.
6. **Order block** : la dernière bougie opposée avant la cassure doit chevaucher la zone Fibonacci (désactivable).
7. **FVG / imbalance** : en option, l'impulsion doit contenir un Fair Value Gap.
8. **Momentum** : entrée à la clôture d'une bougie dans le sens du trade avec un RSI qui monte (achat) ou qui baisse (vente).
9. **Gestion** : stop sous l'order block (ou au-dessus pour une vente) plus une marge, take profit à 2R, risque de 1 % par trade. Les positions sont fermées à la fin de la session et le bot s'arrête après 3 trades dans la journée.

Tous ces éléments sont réglables dans les paramètres.

## Installation

### TradingView
1. Ouvrir l'éditeur Pine, coller le contenu de `tradingview/EMYO_Strategy.pine`, puis cliquer sur « Ajouter au graphique ».
2. Mettre le graphique en **M1 ou M5** (unité de temps de scalping).
3. Consulter le « Testeur de stratégie » pour les résultats sur l'historique.

### MetaTrader 5
1. Copier `mt5/EMYO_Bot.mq5` dans `MQL5/Experts/` (menu Fichier → Ouvrir le dossier des données).
2. Compiler avec MetaEditor (F7).
3. Glisser l'EA sur un graphique **M1 ou M5** et activer le trading algorithmique.
4. **Important** : régler les heures de session en **heure serveur du broker**. Par défaut, 16:30–19:00 correspond à 9h30–12h00 à New York pour un broker en GMT+3 (le cas de la plupart des brokers MT5 l'été). Vérifier l'heure dans l'onglet « Market Watch ».

Tester d'abord dans le **testeur de stratégie MT5**, puis sur un **compte démo**, avant tout compte réel.
