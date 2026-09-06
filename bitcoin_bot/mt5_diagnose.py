"""Diagnostic Vantage MT5 et graphique Bitcoin en lecture seule.

À exécuter sous Windows, sur la même machine que le terminal MetaTrader 5.
Aucun ordre n'est envoyé par ce programme.
"""

from __future__ import annotations

import os
from pathlib import Path

import matplotlib.pyplot as plt
import MetaTrader5 as mt5
import pandas as pd
from dotenv import load_dotenv

load_dotenv()

SERVER = os.getenv("MT5_SERVER", "VantageMarkets-demo")
LOGIN_TEXT = os.getenv("MT5_LOGIN", "")
PASSWORD = os.getenv("MT5_PASSWORD", "")
SYMBOL_HINT = os.getenv("MT5_SYMBOL", "BTCUSD")
BARS = int(os.getenv("MT5_BARS", "720"))
FAST_WINDOW = 10
SLOW_WINDOW = 20
GRAPH_FILE = Path("bitcoin_mt5_graph.png")


def require_credentials() -> tuple[int, str]:
    if not LOGIN_TEXT or not PASSWORD:
        raise RuntimeError(
            "MT5_LOGIN et MT5_PASSWORD doivent être définis dans le fichier .env."
        )
    try:
        return int(LOGIN_TEXT), PASSWORD
    except ValueError as exc:
        raise RuntimeError("MT5_LOGIN doit être un numéro de compte.") from exc


def connect() -> None:
    login, password = require_credentials()
    if not mt5.initialize(login=login, password=password, server=SERVER):
        error = mt5.last_error()
        raise RuntimeError(f"Connexion MT5 impossible: {error}")

    account = mt5.account_info()
    terminal = mt5.terminal_info()
    if account is None or terminal is None:
        raise RuntimeError(f"Informations MT5 indisponibles: {mt5.last_error()}")

    print(f"Connexion MT5 réussie: compte {account.login}")
    print(f"Serveur: {account.server}")
    print(f"Compte démo: {bool(account.trade_mode == mt5.ACCOUNT_TRADE_MODE_DEMO)}")
    print(f"Trading autorisé par le terminal: {terminal.trade_allowed}")


def find_bitcoin_symbol() -> str:
    symbols = mt5.symbols_get()
    if symbols is None:
        raise RuntimeError(f"Liste des symboles indisponible: {mt5.last_error()}")

    exact = [item.name for item in symbols if item.name.upper() == SYMBOL_HINT.upper()]
    if exact:
        return exact[0]

    candidates = [
        item.name
        for item in symbols
        if "BTC" in item.name.upper() and "USD" in item.name.upper()
    ]
    if not candidates:
        raise RuntimeError(
            "Aucun symbole Bitcoin/USD trouvé. Vérifie son nom dans Market Watch."
        )

    print("Symboles Bitcoin/USD détectés:", ", ".join(candidates))
    return candidates[0]


def load_rates(symbol: str) -> pd.DataFrame:
    if not mt5.symbol_select(symbol, True):
        raise RuntimeError(f"Impossible d'activer {symbol}: {mt5.last_error()}")

    rates = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_H1, 0, BARS)
    if rates is None or len(rates) == 0:
        raise RuntimeError(f"Aucune bougie reçue pour {symbol}: {mt5.last_error()}")

    data = pd.DataFrame(rates)
    data["time"] = pd.to_datetime(data["time"], unit="s", utc=True)
    data = data.set_index("time")
    data["SMA_10"] = data["close"].rolling(FAST_WINDOW).mean()
    data["SMA_20"] = data["close"].rolling(SLOW_WINDOW).mean()
    data = data.dropna()

    above = data["SMA_10"] > data["SMA_20"]
    data["BUY"] = above & ~above.shift(1, fill_value=False)
    data["SELL"] = ~above & above.shift(1, fill_value=False)
    return data


def save_graph(data: pd.DataFrame, symbol: str) -> None:
    fig, ax = plt.subplots(figsize=(15, 8))
    ax.plot(data.index, data["close"], color="black", linewidth=1.2, label=symbol)
    ax.plot(data.index, data["SMA_10"], color="blue", label="SMA 10")
    ax.plot(data.index, data["SMA_20"], color="orange", label="SMA 20")

    buys = data[data["BUY"]]
    sells = data[data["SELL"]]
    ax.scatter(buys.index, buys["close"], marker="^", color="green", s=200, label="BUY")
    ax.scatter(sells.index, sells["close"], marker="v", color="red", s=200, label="SELL")

    ax.set_title(f"{symbol} via Vantage MT5 — lecture seule")
    ax.set_xlabel("Date UTC")
    ax.set_ylabel("Prix")
    ax.grid(alpha=0.25)
    ax.legend()
    fig.autofmt_xdate()
    fig.tight_layout()
    fig.savefig(GRAPH_FILE, dpi=150)
    plt.close(fig)


def main() -> None:
    try:
        connect()
        symbol = find_bitcoin_symbol()
        print(f"Symbole sélectionné: {symbol}")
        data = load_rates(symbol)
        save_graph(data, symbol)
        print(f"Bougies H1 chargées: {len(data)}")
        print(f"Dernier cours: {float(data['close'].iloc[-1]):.2f}")
        print(f"Signaux BUY: {int(data['BUY'].sum())}")
        print(f"Signaux SELL: {int(data['SELL'].sum())}")
        print(f"Graphique sauvegardé -> {GRAPH_FILE}")
        print("Mode diagnostic: aucun ordre envoyé.")
    finally:
        mt5.shutdown()


if __name__ == "__main__":
    main()
