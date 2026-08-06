from __future__ import annotations

import os
from pathlib import Path

from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

os.environ.setdefault("PLAID_CLIENT_ID", "test-client")
os.environ.setdefault("PLAID_SECRET", "test-secret")
os.environ.setdefault("TOKEN_ENCRYPTION_KEY", Fernet.generate_key().decode())
os.environ.setdefault("API_BEARER_TOKEN", "test-token")

from app.config import Settings
from app.main import category_for, create_app


class FakePlaid:
    async def close(self) -> None:
        pass

    async def create_link_token(self, client_user_id: str, presentation: str):
        result = {"link_token": f"link-{client_user_id}", "expiration": "2030-01-01T00:00:00Z"}
        if presentation == "hosted":
            result["hosted_link_url"] = "https://secure.plaid.test/hosted-link"
        return result

    async def link_token_get(self, link_token: str):
        return {"results": {"item_add_results": []}}

    async def exchange_public_token(self, public_token: str):
        return {"access_token": "access-token", "item_id": "item-123"}

    async def accounts(self, access_token: str):
        return [{
            "account_id": "account-123", "name": "Checking", "official_name": "Primary Checking",
            "type": "depository", "subtype": "checking", "mask": "0000",
            "balances": {"current": 1000, "available": 950, "iso_currency_code": "USD"},
        }]

    async def sync(self, access_token: str, cursor: str | None):
        return {
            "added": [] if cursor else [{
                "transaction_id": "transaction-123", "account_id": "account-123",
                "name": "Whole Foods", "merchant_name": "Whole Foods",
                "amount": 42.50, "date": "2026-08-01", "pending": False,
                "iso_currency_code": "USD",
                "personal_finance_category": {"primary": "FOOD_AND_DRINK", "detailed": "FOOD_AND_DRINK_GROCERIES"},
            }],
            "modified": [], "removed": [], "next_cursor": "cursor-1", "has_more": False,
        }


def client(tmp_path: Path) -> TestClient:
    settings = Settings(
        database_path=tmp_path / "expenses.sqlite3", plaid_client_id="client", plaid_secret="secret",
        plaid_environment="sandbox", token_encryption_key=Fernet.generate_key().decode(),
        api_bearer_token="test-token", plaid_webhook_url=None, plaid_redirect_uri=None,
        webhook_secret="webhook-secret",
    )
    return TestClient(create_app(settings, FakePlaid()))


def headers() -> dict[str, str]:
    return {"Authorization": "Bearer test-token"}


def test_api_requires_authentication(tmp_path: Path) -> None:
    with client(tmp_path) as api:
        assert api.get("/accounts").status_code == 401


def test_creates_link_token_server_side(tmp_path: Path) -> None:
    with client(tmp_path) as api:
        response = api.post("/plaid/link-token", headers=headers(), json={"client_user_id": "personal-user"})
        assert response.status_code == 200
        assert response.json()["link_token"] == "link-personal-user"


def test_creates_hosted_link_for_macos(tmp_path: Path) -> None:
    with client(tmp_path) as api:
        response = api.post(
            "/plaid/link-token",
            headers=headers(),
            json={"client_user_id": "personal-user", "presentation": "hosted"},
        )
        assert response.status_code == 200
        assert response.json()["hosted_link_url"] == "https://secure.plaid.test/hosted-link"


def test_exchange_sync_list_and_override_category(tmp_path: Path) -> None:
    with client(tmp_path) as api:
        exchange = api.post(
            "/plaid/exchange-public-token",
            headers=headers(),
            json={"public_token": "public-token", "institution_name": "First Bank"},
        )
        assert exchange.status_code == 201
        assert api.get("/accounts", headers=headers()).json()[0]["mask"] == "0000"
        transaction = api.get("/transactions", headers=headers()).json()[0]
        assert transaction["category"] == "Groceries"
        override = api.patch(
            "/transactions/transaction-123", headers=headers(), json={"category": "Dining"}
        )
        assert override.status_code == 200
        assert override.json()["category"] == "Dining"
        assert override.json()["category_overridden"] is True
        restored = api.delete("/transactions/transaction-123/category", headers=headers())
        assert restored.status_code == 200
        assert restored.json()["category"] == "Groceries"
        assert restored.json()["category_overridden"] is False
        recategorized = api.post("/transactions/recategorize", headers=headers())
        assert recategorized.status_code == 200
        assert recategorized.json()["updated_transactions"] == 1


def test_category_mapping_uses_detailed_then_primary_category() -> None:
    assert category_for({"personal_finance_category": {
        "primary": "TRAVEL", "detailed": "TRAVEL_FLIGHTS",
    }})[0] == "Travel"
    assert category_for({"personal_finance_category": {
        "primary": "BANK_FEES", "detailed": "BANK_FEES_OTHER_BANK_FEES",
    }})[0] == "Fees"
    assert category_for({"personal_finance_category": {
        "primary": "RENT_AND_UTILITIES", "detailed": "RENT_AND_UTILITIES_RENT",
    }})[0] == "Housing"
    assert category_for({"personal_finance_category": {
        "primary": "LOAN_PAYMENTS", "detailed": "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT",
    }})[0] == "Card Payment"


def test_clear_data_removes_synced_sandbox_items(tmp_path: Path) -> None:
    with client(tmp_path) as api:
        api.post(
            "/plaid/exchange-public-token",
            headers=headers(),
            json={"public_token": "public-token", "institution_name": "First Bank"},
        )

        response = api.delete("/data", headers=headers())

        assert response.status_code == 200
        assert response.json() == {"status": "cleared"}
        assert api.get("/accounts", headers=headers()).json() == []
        assert api.get("/transactions", headers=headers()).json() == []
