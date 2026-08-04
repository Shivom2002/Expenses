from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    database_path: Path
    plaid_client_id: str
    plaid_secret: str
    plaid_environment: str
    token_encryption_key: str
    api_bearer_token: str
    plaid_webhook_url: str | None
    plaid_redirect_uri: str | None
    webhook_secret: str | None

    @property
    def plaid_base_url(self) -> str:
        environments = {
            "sandbox": "https://sandbox.plaid.com",
            "development": "https://development.plaid.com",
            "production": "https://production.plaid.com",
        }
        try:
            return environments[self.plaid_environment]
        except KeyError as error:
            raise ValueError("PLAID_ENV must be sandbox, development, or production") from error

    @classmethod
    def from_environment(cls) -> "Settings":
        def required(name: str) -> str:
            value = os.environ.get(name)
            if not value:
                raise RuntimeError(f"{name} must be configured")
            return value

        return cls(
            database_path=Path(os.environ.get("DATABASE_PATH", "./data/expenses.sqlite3")),
            plaid_client_id=required("PLAID_CLIENT_ID"),
            plaid_secret=required("PLAID_SECRET"),
            plaid_environment=os.environ.get("PLAID_ENV", "sandbox"),
            token_encryption_key=required("TOKEN_ENCRYPTION_KEY"),
            api_bearer_token=required("API_BEARER_TOKEN"),
            plaid_webhook_url=os.environ.get("PLAID_WEBHOOK_URL") or None,
            plaid_redirect_uri=os.environ.get("PLAID_REDIRECT_URI") or None,
            webhook_secret=os.environ.get("WEBHOOK_SECRET") or None,
        )
