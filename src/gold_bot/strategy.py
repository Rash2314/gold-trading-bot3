from dataclasses import dataclass
from enum import Enum
import pandas as pd


class Signal(str, Enum):
    BUY = "buy"
    SELL = "sell"
    HOLD = "hold"


@dataclass(frozen=True)
class Decision:
    signal: Signal
    price: float
    confidence: float
    reason: str


class IntradayGoldStrategy:
    def __init__(self, fast=5, slow=13, momentum_period=3):
        if not 1 < fast < slow:
            raise ValueError("Expected 1 < fast < slow")
        self.fast, self.slow, self.momentum_period = fast, slow, momentum_period

    def decide(self, bars: pd.DataFrame) -> Decision:
        if "close" not in bars or len(bars) < self.slow + self.momentum_period:
            return Decision(Signal.HOLD, 0.0, 0.0, "not_enough_bars")
        close = bars["close"].astype(float)
        fast = close.ewm(span=self.fast, adjust=False).mean().iloc[-1]
        slow = close.ewm(span=self.slow, adjust=False).mean().iloc[-1]
        price = float(close.iloc[-1])
        spread = float((fast - slow) / price)
        momentum = float(close.pct_change(self.momentum_period).iloc[-1])
        volatility = close.pct_change().rolling(self.slow).std().iloc[-1]
        noise = max(float(volatility) if pd.notna(volatility) else 0, 0.0001)
        confidence = min(abs(spread) / noise, 1.0)
        if spread > 0 and momentum > 0 and confidence >= 0.15:
            return Decision(Signal.BUY, price, confidence, "uptrend_confirmed")
        if spread < 0 and momentum < 0 and confidence >= 0.15:
            return Decision(Signal.SELL, price, confidence, "downtrend_confirmed")
        return Decision(Signal.HOLD, price, confidence, "filters_not_aligned")

