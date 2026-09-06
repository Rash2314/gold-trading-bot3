from datetime import datetime, timedelta, timezone
from .broker import AlpacaPaperBroker
from .config import Settings
from .engine import TradingEngine


def provider(settings):
    from alpaca.data.historical import CryptoHistoricalDataClient, StockHistoricalDataClient
    from alpaca.data.requests import CryptoBarsRequest, StockBarsRequest
    from alpaca.data.timeframe import TimeFrame
    stock_client = StockHistoricalDataClient(settings.api_key, settings.secret_key)
    crypto_client = CryptoHistoricalDataClient(settings.api_key, settings.secret_key)

    def fetch(symbol):
        end = datetime.now(timezone.utc)
        request_type = CryptoBarsRequest if "/" in symbol else StockBarsRequest
        request = request_type(symbol_or_symbols=[symbol], timeframe=TimeFrame.Minute,
                               start=end - timedelta(hours=3), end=end)
        client = crypto_client if "/" in symbol else stock_client
        method = client.get_crypto_bars if "/" in symbol else client.get_stock_bars
        frame = method(request).df
        return frame.xs(symbol) if getattr(frame.index, "nlevels", 1) > 1 else frame
    return fetch


def main():
    settings = Settings.from_env()
    if not settings.api_key or not settings.secret_key:
        raise SystemExit("Configure Alpaca paper credentials as Codespaces secrets")
    TradingEngine(settings, AlpacaPaperBroker(settings), provider(settings)).run()


if __name__ == "__main__":
    main()
