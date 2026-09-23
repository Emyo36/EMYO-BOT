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
| Marchés : **or (XAUUSD), Bitcoin (BTCUSD), NASDAQ (NAS100)** | Ce que l'utilisateur trade |
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

- Version : **1.90**, branche `claude/bonjour-sbyppm`.
- **Jamais compilé ni testé** : aucun compilateur MQL5 dans l'environnement cloud.
  La première étape reste la compilation (F7 dans MetaEditor) par l'utilisateur.
- Le README détaille la stratégie et chaque paramètre ; le garder synchronisé avec le code.

## Points de vigilance connus

- Un panier de 3 positions perdu avant le break-even ≈ 5,20 € de perte pour 6 € de gain
  si les 3 TP sont atteints : le taux de réussite doit être élevé.
- Avec de petits objectifs, spread et commissions pèsent lourd : regarder le gain **net**.
- En backtest, le décalage GMT du serveur est supposé GMT+2 / GMT+3 (`ServerGmtOffset`
  sinon) : vérifier que les trades tombent entre 15h30 et 22h00 heure de Paris.

## Prochaines étapes

1. Compilation par l'utilisateur ; corriger les erreurs qu'il envoie (captures d'écran).
2. Backtest M1 « ticks réels » sur chaque marché, 1 à 2 mois ; puis sur une autre période.
3. Démo 1 à 3 mois, puis petit compte réel seulement si tout est positif.
4. Idée en attente : l'utilisateur veut envoyer une stratégie vue en vidéo
   (captures + transcription) pour la reproduire et la comparer.

## Journal des résultats

_Aucun test pour l'instant. Noter ici chaque backtest / démo : date, marché, période,
réglages modifiés, nombre de trades, % gagnants, gain net, drawdown max, conclusions._
