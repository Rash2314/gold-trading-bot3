# Expert Advisor Vantage MT5 — Demo uniquement

`GoldVantageDemoEA.mq5` est la version native MetaTrader 5 du bot. Elle est conçue pour
un graphique `XAUUSD` en M1 et refuse de démarrer si le compte n'est pas un compte Demo
sur le serveur configuré (`VantageMarkets-Demo` par défaut).

## Protections

- ordres désactivés par défaut ;
- compte MT5 Demo et nom du serveur vérifiés à l'initialisation et à chaque tick ;
- dix entrées maximum pendant la première heure ;
- cooldown de six minutes ;
- exposition maximale de 0,10 lot ;
- perte de session maximale paramétrable ;
- stop-loss, take-profit et filtre de spread ;
- clôture après 60 minutes maximum ou sur signal opposé ;
- notifications push facultatives vers MT5 iPhone.

## Installation

1. Ouvrir MetaEditor depuis MetaTrader 5.
2. Copier `GoldVantageDemoEA.mq5` dans `MQL5/Experts/GoldTradingBot3/`.
3. Compiler avec F7 et vérifier qu'il n'y a aucune erreur.
4. Tester dans le Strategy Tester sur `XAUUSD`, période M1.
5. Attacher l'EA au graphique XAUUSD du compte Vantage Demo.
6. Conserver `EnableDemoOrders=false` pour le premier test visuel.

Pour les notifications, saisir le MetaQuotes ID de l'iPhone dans les options Notifications
de MT5 desktop, envoyer un message de test, puis activer `SendPushNotifications`.

Ne jamais modifier le verrou Demo pour utiliser un compte réel sans une revue séparée.
