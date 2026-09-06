import os
from dataclasses import dataclass


def env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    return default if value is None else value.lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    api_key: str = ""
    secret_key: str = ""
    base_url: str = "https://paper-api.alpaca.markets"
    paper_only: bool = True
    enable_orders: bool = False
    symbol: str = "GLD"
    poll_seconds: int = 60
    entry_window_minutes: int = 60
    max_entries: int = 10
    max_hold_minutes: int = 60
    cooldown_minutes: int = 6
    order_notional_usd: float = 100.0
    max_gross_exposure_usd: float = 1000.0
    max_session_loss_usd: float = 25.0

    @classmethod
    def from_env(cls):
        value = cls(
            api_key=os.getenv("APCA_API_KEY_ID", ""),
            secret_key=os.getenv("APCA_API_SECRET_KEY", ""),
            base_url=os.getenv("APCA_API_BASE_URL", "https://paper-api.alpaca.markets"),
            paper_only=env_bool("PAPER_ONLY", True),
            enable_orders=env_bool("ENABLE_PAPER_ORDERS", False),
            symbol=os.getenv("SYMBOL", "GLD").upper(),
            poll_seconds=int(os.getenv("POLL_SECONDS", "60")),
            entry_window_minutes=int(os.getenv("ENTRY_WINDOW_MINUTES", "60")),
            max_entries=int(os.getenv("MAX_ENTRIES", "10")),
            max_hold_minutes=int(os.getenv("MAX_HOLD_MINUTES", "60")),
            cooldown_minutes=int(os.getenv("COOLDOWN_MINUTES", "6")),
            order_notional_usd=float(os.getenv("ORDER_NOTIONAL_USD", "100")),
            max_gross_exposure_usd=float(os.getenv("MAX_GROSS_EXPOSURE_USD", "1000")),
            max_session_loss_usd=float(os.getenv("MAX_SESSION_LOSS_USD", "25")),
        )
        value.validate()
        return value

    def validate(self):
        if not self.paper_only:
            raise ValueError("PAPER_ONLY must remain true")
        if self.base_url.rstrip("/") != "https://paper-api.alpaca.markets":
            raise ValueError("Only Alpaca's paper endpoint is allowed")
        if not 1 <= self.max_entries <= 10:
            raise ValueError("MAX_ENTRIES must be between 1 and 10")
        if min(self.entry_window_minutes, self.max_hold_minutes, self.cooldown_minutes) <= 0:
            raise ValueError("Durations must be positive")
        if min(self.order_notional_usd, self.max_gross_exposure_usd) <= 0:
            raise ValueError("Risk amounts must be positive")
        if self.enable_orders and (not self.api_key or not self.secret_key):
            raise ValueError("Paper API credentials are required")

