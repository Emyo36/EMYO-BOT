# EMYO-BOT

Bot de scalping pour la **session de New York**, **3 trades maximum par jour**.

| Fichier | Rôle |
|---|---|
| `tradingview/EMYO_Strategy.pine` | Stratégie TradingView (Pine Script v6) : analyse, affichage des zones et backtest |
| `mt5/EMYO_Bot.mq5` | Expert Advisor MetaTrader 5 : prend les trades automatiquement avec la même logique |

## Logique du setup

1. **Tendance** : sur l'UT supérieure (H1 par défaut), EMA 50 au-dessus de l'EMA 200 et clôture au-dessus de l'EMA 200 pour les achats (l'inverse pour les ventes). On ne trade que dans ce sens.
2. **Session US** : les setups ne sont cherchés que pendant la session (8h00–12h00 heure de New York par défaut, soit 14h–18h à Paris : annonces économiques US de 8h30 puis ouverture de Wall Street à 9h30).
3. **Prise de liquidité** : une mèche passe sous le dernier plus bas (achat) ou au-dessus du dernier plus haut (vente), puis la bougie clôture de l'autre côté.
4. **Cassure de structure** : le prix clôture au-delà du swing opposé, ce qui valide l'impulsion.
5. **Fibonacci** : sur l'impulsion (du point de liquidité jusqu'à l'extrême), on attend un retour dans la zone **0.5–0.79**.
6. **Confluence** : un **order block** (dernière bougie opposée avant la cassure) **ou** un **FVG / imbalance** de l'impulsion doit se trouver dans la zone Fibonacci. Le paramètre permet d'exiger seulement l'OB, seulement le FVG, ou rien.
7. **Swings** : pivots de 2 bougies de chaque côté, pour repérer plus de zones de liquidité en M5.
8. **Momentum** : entrée à la clôture d'une bougie dans le sens du trade avec un RSI qui monte (achat) ou qui baisse (vente).
9. **Volatilité** : le bot ne trade que si l'ATR vaut au moins 0,8 fois sa moyenne, ce qui écarte les marchés endormis.
10. **Gestion** : stop sous l'order block (ou sous le bas de la zone Fibonacci si c'est un FVG), plus une marge de 0,1 ATR, risque de 1 % par trade.
    - **TP1 à 1R** : **50 % de la position est encaissée** et le stop du reste passe **au point d'entrée + 0,1R** (le trade ne peut plus perdre).
    - Le reste court jusqu'au **TP final à 2,5R**, ou jusqu'au stop déplacé.
    - Résultat par trade : **-1R** (stop initial), **+0,55R** (TP1 puis retour à l'entrée) ou **+1,75R** (TP1 puis TP final).
    - Les positions sont fermées à la fin de la session. Le bot s'arrête après **3 trades dans la journée, tous actifs confondus**.

## Actifs et unité de temps

- Actifs : **Bitcoin (BTCUSD), or (XAUUSD), NASDAQ (NAS100 / US100), Dow Jones (US30)**. Dans MT5, un graphique par actif avec le bot attaché sur chacun.
- Unité de temps conseillée : **M5**. En M1, le spread et le bruit sur le Bitcoin et l'or déclenchent trop de faux signaux.

Tous ces éléments sont réglables dans les paramètres.

## Installation

### TradingView
1. Ouvrir l'éditeur Pine, coller le contenu de `tradingview/EMYO_Strategy.pine`, puis cliquer sur « Ajouter au graphique ».
2. Mettre le graphique en **M5** (M1 possible, mais plus de faux signaux).
3. Consulter le « Testeur de stratégie » pour les résultats sur l'historique.

### MetaTrader 5
1. Copier `mt5/EMYO_Bot.mq5` dans `MQL5/Experts/` (menu Fichier → Ouvrir le dossier des données).
2. Compiler avec MetaEditor (F7).
3. Glisser l'EA sur un graphique **M5** de chaque actif (BTCUSD, XAUUSD, NAS100, US30) et activer le trading algorithmique. Garder le même numéro magique partout pour que la limite de 3 trades soit commune.
4. **Important** : régler les heures de session en **heure serveur du broker**. Par défaut, 15:00–19:00 correspond à 8h00–12h00 à New York pour un broker en GMT+3 (le cas de la plupart des brokers MT5 l'été). Vérifier l'heure dans l'onglet « Market Watch ».

Tester d'abord dans le **testeur de stratégie MT5**, puis sur un **compte démo**, avant tout compte réel.
