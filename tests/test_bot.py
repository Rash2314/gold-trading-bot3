from datetime import datetime, timedelta, timezone
import pandas as pd
import pytest
from gold_bot.config import Settings
from gold_bot.risk import SessionRisk
from gold_bot.strategy import IntradayGoldStrategy, Signal
from gold_bot.broker import AlpacaPaperBroker


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


def test_crypto_dry_run_never_submits():
    receipt = AlpacaPaperBroker(Settings()).submit_market_order("BTC/USD", Signal.BUY, 10)
    assert receipt.submitted is False


def test_no_position_means_no_close(tmp_path):
    from gold_bot.engine import TradingEngine

    class Broker:
        def close_position(self, symbol):
            raise AssertionError("nothing should be closed")

    engine = TradingEngine(Settings(), Broker(), lambda _: pd.DataFrame(), tmp_path / "j.jsonl")
    engine._close_active("session_close")
