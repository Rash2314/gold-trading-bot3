# Bot Bitcoin BTC-USD

Version Bitcoin du bot Gold, avec la même logique de croisements :

- SMA 10 en bleu
- SMA 20 en orange
- BUY vert et SELL rouge
- capital de backtest initial : 1 000
- graphique généré : `bitcoin_graph.png`

## Exécution

```bash
cd bitcoin_bot
python -m pip install -r requirements.txt
python main.py
```

Le script utilise les 30 derniers jours de données horaires BTC-USD. Il s'agit
d'un backtest pédagogique : aucun ordre réel n'est envoyé.
