# gold-trading-bot3

Bot intraday **strictement Alpaca Paper Trading** pour `GLD`. Il ouvre au maximum dix
entrées dans une fenêtre d'une heure, sans fabriquer de signal pour atteindre un quota.
Alpaca agrégeant les ordres d'un même symbole, ces entrées renforcent une position nette ;
le moteur clôt cette position après 60 minutes au maximum ou sur signal opposé.

## Sécurité

- endpoint live refusé par le code ;
- ordres désactivés par défaut (`ENABLE_PAPER_ORDERS=false`) ;
- cooldown de 6 minutes, plafonds d'exposition et de perte ;
- décisions consignées dans un journal JSONL ;
- clés lues uniquement depuis les secrets d'environnement.

## Installation et tests

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e '.[dev]'
pytest
```

Créer les secrets Codespaces `APCA_API_KEY_ID` et `APCA_API_SECRET_KEY`, puis lancer
`gold-bot`. Le premier lancement est un dry-run. Une fois le journal vérifié, définir
`ENABLE_PAPER_ORDERS=true` pour autoriser uniquement les ordres Alpaca simulés.

Une architecture robuste ne garantit pas la rentabilité. Valider sur plusieurs régimes de
marché avant toute évolution.

## Vantage / MetaTrader 5

Une version native MQL5 verrouillée sur les comptes Vantage Demo est disponible dans
[`mt5/`](mt5/). Elle travaille directement sur `XAUUSD` et peut envoyer des notifications
à l'application MetaTrader 5 sur iPhone.

## Test crypto 24/7

Le même moteur peut être validé sur Alpaca Paper avec `SYMBOL=BTC/USD`. Les ordres crypto
utilisent automatiquement la durée `GTC`, tandis que les actions utilisent `DAY`. Commencer
toujours avec `ENABLE_PAPER_ORDERS=false`.
