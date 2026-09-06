from datetime import datetime, timedelta, timezone
import pandas as pd
import pytest
from gold_bot.config import Settings
from gold_bot.risk import SessionRisk
from gold_bot.strategy import IntradayGoldStrategy, Signal


def test_live_endpoint_is_impossible():
    with pytest.raises(ValueError, match="paper endpoint"):
        Settings(base_url="https://api.alpaca.markets").validate()


def test_uptrend_signal():
    bars = pd.DataFrame({"close": [100 + i * 0.2 for i in range(30)]})
    assert IntradayGoldStrategy().decide(bars).signal is Signal.BUY


def test_cooldown_and_window():
    now = datetime(2026, 9, 6, tzinfo=timezone.utc)
    risk = SessionRisk(now, 60, 10, 6, 1000, 25)
    risk.record_entry(now, 100)
    assert risk.may_enter(now + timedelta(minutes=5), 100)[1] == "cooldown_active"
    assert risk.may_enter(now + timedelta(minutes=60), 100)[1] == "entry_window_closed"
