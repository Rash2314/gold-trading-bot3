# Bot Bitcoin BTC-USD

Version Bitcoin du bot Gold, avec la même logique de croisements :

- SMA 10 en bleu
- SMA 20 en orange
- BUY vert et SELL rouge
- capital de backtest initial : 1 000
- graphique généré : `bitcoin_graph.png`

## Backtest dans le Codespace

```bash
cd bitcoin_bot
python -m pip install -r requirements.txt
python main.py
```

Le backtest utilise les 30 derniers jours de données horaires BTC-USD et
n'envoie aucun ordre réel.

## Diagnostic Vantage MetaTrader 5 (Windows)

L'intégration Python officielle de MetaTrader 5 doit être exécutée sous Windows,
sur la même machine que le terminal MT5 Vantage ouvert.

```powershell
cd bitcoin_bot
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-mt5.txt
Copy-Item .env.example .env
notepad .env
python mt5_diagnose.py
```

Dans `.env`, renseigner localement `MT5_LOGIN` et `MT5_PASSWORD`.
Le serveur est préconfiguré sur `VantageMarkets-demo`. Ne jamais publier
le fichier `.env`.

`mt5_diagnose.py` se limite à la connexion, la détection du symbole Bitcoin,
la lecture de bougies H1 et la création de `bitcoin_mt5_graph.png`.
Il ne contient aucun appel à `order_send` et ne peut donc pas placer d'ordre.
