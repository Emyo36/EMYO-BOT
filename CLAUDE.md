# Mémoire du projet EMYO-BOT

Ce fichier est lu automatiquement au début de chaque session. Le tenir à jour à chaque
changement important (décision, nouvelle version, résultat de test).

## L'utilisateur

- Parle **français** : toujours répondre en français, simplement, sans jargon inutile.
- Écrit souvent par **dictée vocale** depuis son téléphone : des mots peuvent être mal
  transcrits. Exemples déjà rencontrés : « vote » = bot, « beau » / « boss » = bot,
  « petits chiens » = petits gains, « prendre le train » = suivre la tendance,
  « traits » = trades, « King » = gain. Interpréter selon le contexte et reformuler
  ce qu'on a compris.
- N'est souvent **pas devant son ordinateur** : il ne peut pas compiler ni tester tout
  de suite. Le code doit donc être relu avec un soin particulier.
- Fait confiance et laisse avancer, mais il faut rester **honnête sur les risques** :
  ne jamais promettre de gains, rappeler que la plupart des traders particuliers perdent.

## Objectif

Un Expert Advisor **MetaTrader 5** (`EMYO_BOT.mq5`) de scalping qui accumule
**beaucoup de petits gains** (1 à 3 € par position, « 1 € × 1000 »), de façon répétée.

## Décisions prises (et pourquoi)

| Décision | Raison |
|---|---|
| Unité de temps **M1** | Demande de l'utilisateur : scalping 1 minute |
| Marchés : **or (XAUUSD-STD) et Bitcoin (BTCUSD)** | Ce que l'utilisateur trade ; NASDAQ abandonné le 2026-09-25 à sa demande |
| Toutes les distances en **ATR** (mode pips gardé pour le forex) | Les pips n'ont pas de sens sur ces marchés |
| **Suivi de tendance** : EMA 20 / EMA 50 M1 (+ M15 en mode normal) | « Prendre le train » de la tendance |
| Entrées **momentum** (+ replis en mode agressif) | Demande : « beaucoup plus sur le momentum » |
| **3 positions par signal**, TP échelonnés 1 / 1,5 / 2 ATR | Demande : au moins 3 trades simultanés |
| Lot calculé pour un **gain fixe en euros** (`TargetProfitMoney = 2`) | Demande : petits gains de 1 à 5 € |
| **Style agressif** par défaut, jusqu'à 9 positions | Demande : « très agressif » |
| Nouveau panier seulement si les positions ouvertes sont au **break-even** | Garder la perte max. à un seul panier malgré l'agressivité |
| **Session américaine uniquement** (9h30–16h00 New York), fermeture en fin de session | Demande de l'utilisateur ; conversion heure serveur → New York avec heure d'été US |
| **Arrêt du jour à −3 %**, positions ouvertes comprises | Garde-fou indispensable : ne jamais le retirer sans en parler clairement |
| Compteur de gains du jour sur le graphique | L'utilisateur raisonne en gains cumulés |

## État actuel

- Version : **1.91**, branche `claude/bonjour-sbyppm`.
- **Compilé sans erreur** par l'utilisateur dans MetaEditor (v1.90) ; v1.91 = simple ajout de
  contrôles de paramètres, à recompiler. Backtests en cours (voir journal).
  Aucun compilateur MQL5 dans l'environnement cloud : toute modification doit être
  relue avec soin et recompilée par l'utilisateur.
- Le README détaille la stratégie et chaque paramètre ; le garder synchronisé avec le code.

## Deuxième bot : EMYO SMC (`EMYO_SMC.mq5`, v1.01, compilé OK)

Créé le 2026-09-24 à partir d'une vidéo ICT/SMC envoyée par l'utilisateur (transcription) :
tendance H1+H4 (EMA 50), order block M5 (dernière bougie contraire avant impulsion ≥ 1,5 ATR),
retour sur la zone, **confirmation M1** (CHoCH par défaut, ou bougie englobante), SL sous
l'extrême de la correction, 3 positions TP 1R/2R/3R, break-even à 1R, un signal par bloc.
Magic 360037. **Jamais compilé** au moment de sa création. EMYO_BOT reste inchangé pour comparer.

## Points de vigilance connus

- Un panier de 3 positions perdu avant le break-even ≈ 5,20 € de perte pour 6 € de gain
  si les 3 TP sont atteints : le taux de réussite doit être élevé.
- Avec de petits objectifs, spread et commissions pèsent lourd : regarder le gain **net**.
- En backtest, le décalage GMT du serveur est supposé GMT+2 / GMT+3 (`ServerGmtOffset`
  sinon) : vérifier que les trades tombent entre 15h30 et 22h00 heure de Paris.

## Prochaines étapes

1. ~~Compilation~~ : faite, 0 erreur.
2. Backtest M1 « ticks réels » sur chaque marché, 1 à 2 mois ; puis sur une autre période.
3. Démo 1 à 3 mois, puis petit compte réel seulement si tout est positif.
4. Idée en attente : l'utilisateur veut envoyer une stratégie vue en vidéo
   (captures + transcription) pour la reproduire et la comparer.

## Journal des résultats

_Noter ici chaque backtest / démo : date, marché, période, réglages modifiés,
nombre de trades, % gagnants, gain net, drawdown max, conclusions._

### 2026-09-23 — Premier backtest v1.90, réglages par défaut (style agressif)

Courtier VT Markets (compte Hedge). Optimisation multi-symboles, période et dépôt non
précisés (dépôt probablement ~1 000). **Tous les marchés perdent** :

| Symbole | Profit | Trades | Facteur de profit | Drawdown |
|---|---|---|---|---|
| BTCUSD | −277 | 1 593 | 0,71 | 29,6 % |
| USDCAD | −412 | 6 879 | 0,91 | 42,9 % |
| EURUSD | −456 | 5 817 | 0,88 | 46,7 % |
| XAUUSD-STD | −550 | 3 260 | 0,84 | 56,7 % |
| GBPUSD | −612 | 4 389 | 0,79 | 62,0 % |
| DJ30 | −634 | 3 286 | 0,79 | 67,8 % |

Conclusion : pas d'avantage statistique en l'état. Beaucoup de trades avec un facteur de
profit juste sous 1 → les coûts (spread ~1 700 points sur BTCUSD) et le rapport gain/perte
défavorable l'emportent. Pistes : comparer style normal / agressif, TP plus large par
rapport au spread, entrée momentum (achat en haut de bougie M1) à remettre en cause.

### 2026-09-24 — Optimisation XAUUSD-STD M1, 01/07/2026 → 01/09/2026

Dépôt 1 000 USD (compte en **dollars**, pas en euros), levier 500. Algorithme génétique,
4 122 passes. Paramètres optimisés : `TradingStyle`, `StopLoss` (1,2 → 12), `TakeProfit`
(1 → 7), `RsiMomentumLevel` (55 → 544 : plage invalide, RSI max = 100 → 3 686 passes à
0 trade, d'où l'ajout d'un contrôle en v1.91). Pas de résultats forward dans le fichier.

- 436 passes avec trades, dont **69 positives** seulement.
- **Agressif** : zone cohérente **TP 2,1 → 2,6 ATR** (30 passes positives sur 33).
  Meilleur : TP 2,2 / SL 6,72 → **+161 $**, 1 092 trades, facteur de profit 1,16,
  drawdown 17 %. Le SL change peu le résultat (la sortie sur retournement de tendance
  ferme avant) mais un SL large augmente la perte possible.
- **Normal** : meilleur TP 1,0 / SL 1,2 / RSI 71,5 → **+49 $**, 182 trades, facteur de
  profit 1,31, drawdown **4,4 %** (meilleur rapport gain / risque). Moyenne des passes
  normales ≈ −4 $, agressives ≈ −48 $.

Prudence : 2 mois, un seul marché, 4 000 combinaisons → risque élevé de sur-optimisation.
À valider **sans optimisation** sur une autre période (ex. 01/03 → 01/07/2026) :
candidat A = agressif TP 2,2 / SL 6 ; candidat B = normal TP 1,0 / SL 1,2 / RSI 70.

### 2026-09-24 — Test simple XAUUSD-STD M1, 01/07 → 01/09/2026, réglages par défaut (agressif)

Pas le test A/B demandé : réglages par défaut (agressif, TP 1,0 / SL 1,2), même période.
Qualité d'historique **22 % de ticks réels** seulement (résultats moins fiables).

- **−438 $** (−44 %), facteur de profit 0,82, drawdown 46 %, 2 249 trades, 57,5 % gagnants.
- Gain moyen 1,55 $ / perte moyenne 2,55 $ → il faudrait ~62 % de gagnants.
- Presque tout au **lot minimum 0,01** : l'objectif 2 $ ne pilote pas le lot sur l'or
  (TP moyen réel 2,87 $).
- Sorties : 648 TP (+2,87 $), **636 sorties au break-even** (+0,20 $ en moyenne),
  948 vraies pertes (−2,55 $). Le break-even à 0,6 ATR coupe beaucoup de trades qui
  auraient pu aller au TP → hypothèse : break-even trop serré sur M1.
- Heures (serveur GMT+3) : 16h–23h, session bien détectée. Pire heure : **17h serveur
  (≈ 10h New York, juste après l'ouverture) : −227 $**.
- Juillet −375 $, août −63 $.

Hypothèses à tester (sans sur-optimiser) : break-even plus large ou désactivé, éviter la
première heure après l'ouverture, TP ~2,2 ATR (zone vue en optimisation).

### 2026-09-24 — Test hors échantillon XAUUSD-STD M1, 01/03 → 01/07/2026

Réglages : agressif, momentum, TP 2,2 / SL 1,5, break-even 1,5, début 10h30 New York.
Qualité d'historique **0 % de ticks réels** (ticks générés : peu fiable pour du M1).

- **−474 $** (−47 %), facteur de profit **0,69**, 1 076 trades, **41,5 % gagnants**.
- Sorties : 243 TP (+993 $), 196 break-even (+30 $), **601 pertes (−1 470 $)**.
- Élargir le break-even n'a pas aidé : le taux de réussite chute, les pertes dominent.
- Aucun trade en juin : avec TP 2,2 ATR, la volatilité de juin rend le gain au lot minimum
  > `MaxProfitAtMinLot` (5 $) → trades ignorés (effet de bord à connaître).
- Mars −72 $, avril −325 $, mai −77 $ ; toutes les heures négatives.

**Conclusion** : 3 tests, 2 périodes, plusieurs réglages → toujours perdant. Les passes
positives de l'optimisation de juillet-août étaient de la sur-optimisation. Le signal
d'entrée (momentum M1 dans la tendance) n'a pas d'avantage sur l'or chez ce courtier.
Arrêter d'ajuster les paramètres ; changer l'idée de base (proposé à l'utilisateur :
retour à la moyenne sur M1, tendance sur M5/M15, ou stratégie de la vidéo).

### 2026-09-24 — Premier test EMYO SMC v1.00, XAUUSD-STD M1, 01/03 → 01/09/2026

Compilé et lancé sans problème. Réglages par défaut. Qualité d'historique 7 % de ticks réels.

- **−31 $** (−3 %), drawdown max **5 %**, facteur de profit 0,62, **27 trades seulement**
  en 6 mois (20 ventes, 7 achats), 41 % gagnants. Gain moyen 4,70 $ / perte moyenne 5,19 $.
- Aucun trade en juillet-août, et en général **1 seule position par signal au lieu de 3**.
  Cause : sur l'or, même le lot minimum 0,01 rapporte plus que `MaxProfitAtMinLot` (10 $)
  aux TP 2R/3R (le risque SMC fait plusieurs $) → positions ignorées.
- 27 trades = échantillon **beaucoup trop petit** pour conclure (ni bon ni mauvais).

Prochain test proposé : `TargetProfitMoney = 0`, `RiskPercent = 0`, `Lots = 0.01`
(lot fixe) pour que chaque signal ouvre ses 3 positions et avoir un vrai échantillon.
Conflit à expliquer : l'objectif « 2 $ par trade » est incompatible avec le lot minimum
de l'or quand le stop est placé sur la structure.

### 2026-09-25 — Test SMC renvoyé : identique au précédent

Le rapport montrait encore `TargetProfitMoney=2.0` : la modification dans l'onglet
« Placement » n'a pas été prise en compte (mêmes chiffres exactement). EMYO SMC passe en
v1.01 avec **`TargetProfitMoney = 0` par défaut** (lot fixe 0,01) pour éviter la
manipulation. Rappel : le testeur garde les dernières valeurs utilisées → vérifier la
section « Données d'entrée » du rapport.

### 2026-09-25 — EMYO SMC v1.01, lot fixe 0,01, XAUUSD-STD M1, 01/03 → 01/09/2026

Réglages par défaut (CHoCH, 3 positions 1R/2R/3R). Qualité d'historique 32 % ticks réels.

- **−38 $** (−4 %), facteur de profit **0,96** (proche de l'équilibre), 180 positions =
  **60 signaux**, 40 % gagnantes. Gain moyen **11,32 $** / perte moyenne 7,90 $ (1,43 : 1).
- Drawdown max **26 %** (−336 $), série de 15 pertes (−202 $) : le risque par signal varie
  beaucoup avec un lot fixe (SL sur la structure, jusqu'à −27 $ par position).
- Mois : mars +156, avril −105, mai +49, juin +66, juillet −101, août −103.
- Ventes +67 $, achats −106 $. Heures serveur 16h–20h (≈ 9h–14h NY) négatives,
  21h–23h (≈ 14h–16h NY) positives, sorties en fin de session +111 $.

Conclusion : bien meilleur qu'EMYO_BOT (−4 % contre −47 %, vrais gains > pertes), mais
**pas rentable** et 60 signaux = encore peu. Filtres tentants (après-midi seulement,
ventes seulement) = risque de sur-optimisation → à valider sur d'autres marchés/périodes
avant de les adopter. Idée de gestion : `RiskPercent` plutôt que lot fixe pour stabiliser
le risque par signal.

### 2026-09-25 — EMYO SMC v1.01, lot fixe 0,01, BTCUSD M1, 01/03 → 01/09/2026

Réglages par défaut. Qualité d'historique **100 % ticks réels** (le test le plus fiable).

- **−18 $** (−2 %), facteur de profit **0,90**, 147 positions = **49 signaux**,
  45 % gagnantes. Gain moyen 2,37 $ / perte moyenne 2,16 $ (1,1 : 1 seulement).
- Drawdown max **9 %**, série de 15 pertes (−42 $).
- Mois : mars +10, avril −48, mai −18, juin +30, juillet +14, août −5.
- Ventes +12 $, achats −30 $ (même sens que sur l'or, mais faible).
- Heures : **pas** le schéma de l'or (après-midi positif) → ce filtre horaire n'est pas
  confirmé, ne pas l'ajouter.

Bilan SMC après 2 marchés : proche de l'équilibre mais légèrement perdant partout.
Pas d'avantage démontré. NASDAQ abandonné (demande de l'utilisateur) : on continue sur or + Bitcoin.
