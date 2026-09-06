from dataclasses import dataclass
from .strategy import Signal


@dataclass(frozen=True)
class OrderReceipt:
    order_id: str
    submitted: bool


class AlpacaPaperBroker:
    def __init__(self, settings):
        settings.validate()
        self.settings = settings

    def submit_market_order(self, symbol, side, notional):
        if side not in {Signal.BUY, Signal.SELL}:
            raise ValueError("Only BUY or SELL can be submitted")
        if not self.settings.enable_orders:
            return OrderReceipt("dry-run", False)
        from alpaca.trading.client import TradingClient
        from alpaca.trading.enums import OrderSide, TimeInForce
        from alpaca.trading.requests import MarketOrderRequest
        client = TradingClient(self.settings.api_key, self.settings.secret_key, paper=True)
        request = MarketOrderRequest(
            symbol=symbol,
            notional=round(notional, 2),
            side=OrderSide.BUY if side is Signal.BUY else OrderSide.SELL,
            time_in_force=TimeInForce.GTC if "/" in symbol else TimeInForce.DAY,
        )
        order = client.submit_order(order_data=request)
        return OrderReceipt(str(order.id), True)

    def close_position(self, symbol):
        if not self.settings.enable_orders:
            return OrderReceipt("dry-run-close", False)
        from alpaca.trading.client import TradingClient
        client = TradingClient(self.settings.api_key, self.settings.secret_key, paper=True)
        order = client.close_position(symbol)
        return OrderReceipt(str(order.id), True)
