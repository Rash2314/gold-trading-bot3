from dataclasses import dataclass
from datetime import datetime, timedelta


@dataclass
class SessionRisk:
    started_at: datetime
    entry_window_minutes: int
    max_entries: int
    cooldown_minutes: int
    max_gross_exposure_usd: float
    max_session_loss_usd: float
    entries: int = 0
    gross_exposure_usd: float = 0
    realized_pnl_usd: float = 0
    last_entry_at: datetime | None = None

    def may_enter(self, now, notional):
        if now >= self.started_at + timedelta(minutes=self.entry_window_minutes):
            return False, "entry_window_closed"
        if self.entries >= self.max_entries:
            return False, "entry_limit_reached"
        if self.realized_pnl_usd <= -self.max_session_loss_usd:
            return False, "session_loss_limit_reached"
        if self.gross_exposure_usd + notional > self.max_gross_exposure_usd:
            return False, "exposure_limit_reached"
        if self.last_entry_at and now < self.last_entry_at + timedelta(minutes=self.cooldown_minutes):
            return False, "cooldown_active"
        return True, "approved"

    def record_entry(self, now, notional):
        allowed, reason = self.may_enter(now, notional)
        if not allowed:
            raise ValueError(reason)
        self.entries += 1
        self.gross_exposure_usd += notional
        self.last_entry_at = now

    def record_exit(self, notional, realized_pnl=0.0):
        self.gross_exposure_usd = max(0.0, self.gross_exposure_usd - notional)
        self.realized_pnl_usd += realized_pnl
