"""Backtest pédagogique BTC-USD avec croisements SMA 10/20.

Télécharge 30 jours de bougies horaires, détecte les croisements et produit
bitcoin_graph.png. Ce script ne passe aucun ordre réel.
"""

from __future__ import annotations

import matplotlib.pyplot as plt
import pandas as pd
import yfinance as yf

SYMBOL = "BTC-USD"
PERIOD = "30d"
INTERVAL = "1h"
FAST_WINDOW = 10
SLOW_WINDOW = 20
INITIAL_BALANCE = 1_000.0
GRAPH_FILE = "bitcoin_graph.png"


def load_data() -> pd.DataFrame:
    data = yf.download(
        SYMBOL,
        period=PERIOD,
        interval=INTERVAL,
        auto_adjust=True,
        progress=False,
    )
    if data.empty:
        raise RuntimeError(f"Aucune donnée reçue pour {SYMBOL}.")

    if isinstance(data.columns, pd.MultiIndex):
        data.columns = data.columns.get_level_values(0)

    data = data[["Close"]].dropna().copy()
    data["SMA_10"] = data["Close"].rolling(FAST_WINDOW).mean()
    data["SMA_20"] = data["Close"].rolling(SLOW_WINDOW).mean()
    return data.dropna()


def add_signals(data: pd.DataFrame) -> pd.DataFrame:
    result = data.copy()
    above = result["SMA_10"] > result["SMA_20"]
    result["BUY"] = above & ~above.shift(1, fill_value=False)
    result["SELL"] = ~above & above.shift(1, fill_value=False)
    return result


def backtest(data: pd.DataFrame) -> tuple[float, int]:
    cash = INITIAL_BALANCE
    bitcoin = 0.0
    completed_trades = 0

    for row in data.itertuples():
        price = float(row.Close)
        if row.BUY and bitcoin == 0.0:
            bitcoin = cash / price
            cash = 0.0
        elif row.SELL and bitcoin > 0.0:
            cash = bitcoin * price
            bitcoin = 0.0
            completed_trades += 1

    final_balance = cash + bitcoin * float(data["Close"].iloc[-1])
    if bitcoin > 0.0:
        completed_trades += 1
    return final_balance, completed_trades


def save_graph(data: pd.DataFrame) -> None:
    fig, ax = plt.subplots(figsize=(15, 8))
    ax.plot(data.index, data["Close"], color="black", linewidth=1.2, label="BTC-USD")
    ax.plot(data.index, data["SMA_10"], color="blue", linewidth=1.1, label="SMA 10")
    ax.plot(data.index, data["SMA_20"], color="orange", linewidth=1.1, label="SMA 20")

    buys = data[data["BUY"]]
    sells = data[data["SELL"]]
    ax.scatter(
        buys.index,
        buys["Close"],
        marker="^",
        color="green",
        s=200,
        label="BUY",
        zorder=5,
    )
    ax.scatter(
        sells.index,
        sells["Close"],
        marker="v",
        color="red",
        s=200,
        label="SELL",
        zorder=5,
    )

    ax.set_title("Bitcoin BTC-USD — signaux SMA 10/20")
    ax.set_xlabel("Date")
    ax.set_ylabel("Prix (USD)")
    ax.grid(alpha=0.25)
    ax.legend()
    fig.autofmt_xdate()
    fig.tight_layout()
    fig.savefig(GRAPH_FILE, dpi=150)
    plt.close(fig)


def main() -> None:
    data = add_signals(load_data())
    final_balance, trades = backtest(data)
    save_graph(data)

    gain = final_balance - INITIAL_BALANCE
    performance = (gain / INITIAL_BALANCE) * 100
    print(f"Symbole: {SYMBOL}")
    print(f"Nombre de trades: {trades}")
    print(f"Balance finale: {final_balance:.2f}")
    print(f"Gain net: {gain:+.2f}")
    print(f"Performance: {performance:+.2f}%")
    print(f"Graphique sauvegardé -> {GRAPH_FILE}")


if __name__ == "__main__":
    main()
