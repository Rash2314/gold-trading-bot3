import json
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from .risk import SessionRisk
from .strategy import IntradayGoldStrategy, Signal


class TradingEngine:
    def __init__(self, settings, broker, bars_provider, journal=Path("trade_journal.jsonl")):
        self.settings, self.broker, self.bars_provider = settings, broker, bars_provider
        self.strategy, self.journal = IntradayGoldStrategy(), journal
        self.risk = SessionRisk(
            datetime.now(timezone.utc), settings.entry_window_minutes, settings.max_entries,
            settings.cooldown_minutes, settings.max_gross_exposure_usd,
            settings.max_session_loss_usd,
        )
        self.opened_at = None
        self.active_side = None
        self.active_notional = 0.0

    def tick(self, now=None):
        now = now or datetime.now(timezone.utc)
        decision = self.strategy.decide(self.bars_provider(self.settings.symbol))
        event = {"timestamp": now.isoformat(), "symbol": self.settings.symbol,
                 "signal": decision.signal.value, "price": decision.price,
                 "confidence": round(decision.confidence, 4), "reason": decision.reason}
        must_close = self.opened_at and (
            now >= self.opened_at + timedelta(minutes=self.settings.max_hold_minutes)
            or decision.signal not in {Signal.HOLD, self.active_side}
        )
        if must_close:
            receipt = self.broker.close_position(self.settings.symbol)
            event.update(action="close", order_id=receipt.order_id, submitted=receipt.submitted)
            self.risk.record_exit(self.active_notional)
            self.opened_at, self.active_side, self.active_notional = None, None, 0.0
            self._journal(event)
            return event
        if decision.signal is not Signal.HOLD:
            if self.active_side not in {None, decision.signal}:
                event["risk"] = "opposite_position_open"
                self._journal(event)
                return event
            allowed, reason = self.risk.may_enter(now, self.settings.order_notional_usd)
            event["risk"] = reason
            if allowed:
                receipt = self.broker.submit_market_order(
                    self.settings.symbol, decision.signal, self.settings.order_notional_usd)
                self.risk.record_entry(now, self.settings.order_notional_usd)
                if self.opened_at is None:
                    self.opened_at = now
                    self.active_side = decision.signal
                self.active_notional += self.settings.order_notional_usd
                event.update(order_id=receipt.order_id, submitted=receipt.submitted)
        self._journal(event)
        return event

    def run(self):
        entry_deadline = self.risk.started_at.timestamp() + self.settings.entry_window_minutes * 60
        final_deadline = entry_deadline + self.settings.max_hold_minutes * 60
        try:
            while time.time() < entry_deadline or (self.opened_at and time.time() < final_deadline):
                print(json.dumps(self.tick(), sort_keys=True))
                time.sleep(self.settings.poll_seconds)
        except KeyboardInterrupt:
            print("Arrêt demandé : clôture de sécurité en cours.")
        finally:
            self._close_active("session_close")

    def _close_active(self, action):
        if not self.opened_at:
            return
        receipt = self.broker.close_position(self.settings.symbol)
        event = {"timestamp": datetime.now(timezone.utc).isoformat(),
                 "symbol": self.settings.symbol, "action": action,
                 "order_id": receipt.order_id, "submitted": receipt.submitted}
        self.risk.record_exit(self.active_notional)
        self.opened_at, self.active_side, self.active_notional = None, None, 0.0
        self._journal(event)

    def _journal(self, event):
        with self.journal.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(event, sort_keys=True) + "\n")
