from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from datetime import date
import hmac
import json
import sqlite3
from typing import Any, AsyncIterator

from cryptography.fernet import Fernet
from fastapi import BackgroundTasks, Depends, FastAPI, Header, HTTPException, Query, Request, status

from .config import Settings
from .db import Database
from .plaid import PlaidAPIError, PlaidClient
from .schemas import (
    AccountResponse,
    LinkTokenRequest,
    LinkTokenResponse,
    PublicTokenExchangeRequest,
    SyncResponse,
    TransactionCategoryOverride,
    TransactionSplitOverride,
    TransactionResponse,
)


DETAILED_CATEGORY_MAP = {
    "FOOD_AND_DRINK_GROCERIES": "Groceries",
    "FOOD_AND_DRINK_RESTAURANTS": "Dining",
    "FOOD_AND_DRINK_COFFEE": "Dining",
    "FOOD_AND_DRINK_FAST_FOOD": "Dining",
    "FOOD_AND_DRINK_FOOD_DELIVERY": "Dining",
    "TRANSPORTATION_GAS": "Transport",
    "TRANSPORTATION_PUBLIC_TRANSIT": "Transport",
    "TRANSPORTATION_TAXIS_AND_RIDE_SHARES": "Transport",
    "TRANSPORTATION_PARKING": "Transport",
    "TRANSPORTATION_TOLLS": "Transport",
    "TRANSPORTATION_OTHER_TRANSPORTATION": "Transport",
    "GENERAL_MERCHANDISE_ONLINE_MARKETPLACES": "Shopping",
    "GENERAL_MERCHANDISE_CLOTHING_AND_ACCESSORIES": "Shopping",
    "GENERAL_MERCHANDISE_CONVENIENCE_STORES": "Shopping",
    "GENERAL_MERCHANDISE_DEPARTMENT_STORES": "Shopping",
    "GENERAL_MERCHANDISE_DISCOUNT_STORES": "Shopping",
    "GENERAL_MERCHANDISE_ELECTRONICS": "Shopping",
    "GENERAL_MERCHANDISE_SUPERSTORES": "Shopping",
    "ENTERTAINMENT": "Entertainment",
    "MEDICAL": "Health",
    "PERSONAL_CARE": "Personal Care",
    "RENT_AND_UTILITIES_RENT": "Housing",
    "RENT_AND_UTILITIES_MORTGAGE": "Housing",
    "RENT_AND_UTILITIES_GAS_AND_ELECTRICITY": "Utilities",
    "RENT_AND_UTILITIES_INTERNET_AND_CABLE": "Utilities",
    "RENT_AND_UTILITIES_SEWAGE_AND_WASTE_MANAGEMENT": "Utilities",
    "RENT_AND_UTILITIES_TELEPHONE": "Utilities",
    "RENT_AND_UTILITIES_WATER": "Utilities",
    "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT": "Card Payment",
    "INCOME": "Income",
    "TRANSFER_IN": "Transfers",
    "TRANSFER_OUT": "Transfers",
}

# Enables the iOS app to receive OAuth handoffs from banks such as Chase.
# This must match the Apple team ID and bundle ID used to sign Expenses iOS.
APPLE_APP_SITE_ASSOCIATION = {
    "applinks": {
        "details": [{
            "appIDs": ["DPAY85Q94G.shivomdhamija.Expenses.iOS"],
            "components": [{"/": "/plaid/*"}],
        }]
    }
}

PRIMARY_CATEGORY_MAP = {
    "BANK_FEES": "Fees",
    "ENTERTAINMENT": "Entertainment",
    "FOOD_AND_DRINK": "Dining",
    "GENERAL_MERCHANDISE": "Shopping",
    "GENERAL_SERVICES": "Services",
    "GOVERNMENT_AND_NON_PROFIT": "Government & Nonprofit",
    "HOME_IMPROVEMENT": "Home Improvement",
    "INCOME": "Income",
    "LOAN_PAYMENTS": "Loan Payments",
    "MEDICAL": "Health",
    "PERSONAL_CARE": "Personal Care",
    "RENT_AND_UTILITIES": "Utilities",
    "TRANSPORTATION": "Transport",
    "TRANSFER_IN": "Transfers",
    "TRANSFER_OUT": "Transfers",
    "TRAVEL": "Travel",
}


def category_for(transaction: dict[str, Any]) -> tuple[str, str | None, str | None]:
    pfc = transaction.get("personal_finance_category") or {}
    primary = pfc.get("primary")
    detailed = pfc.get("detailed")
    if detailed in DETAILED_CATEGORY_MAP:
        return DETAILED_CATEGORY_MAP[detailed], primary, detailed
    if primary in PRIMARY_CATEGORY_MAP:
        return PRIMARY_CATEGORY_MAP[primary], primary, detailed
    return "Other", primary, detailed


class Service:
    def __init__(self, database: Database, plaid: PlaidClient, cipher: Fernet) -> None:
        self.database = database
        self.plaid = plaid
        self.cipher = cipher

    def _token(self, encrypted: str) -> str:
        return self.cipher.decrypt(encrypted.encode()).decode()

    async def exchange_public_token(self, request: PublicTokenExchangeRequest) -> int:
        return await self.exchange(
            public_token=request.public_token,
            institution_name=request.institution_name,
            institution_id=request.institution_id,
        )

    async def exchange(self, public_token: str, institution_name: str, institution_id: str | None = None) -> int:
        exchange = await self.plaid.exchange_public_token(public_token)
        encrypted_token = self.cipher.encrypt(exchange["access_token"].encode()).decode()
        with self.database.connect() as connection:
            connection.execute(
                """
                INSERT INTO plaid_items (plaid_item_id, access_token_encrypted, institution_id, institution_name)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(plaid_item_id) DO UPDATE SET
                    access_token_encrypted = excluded.access_token_encrypted,
                    institution_id = excluded.institution_id,
                    institution_name = excluded.institution_name,
                    updated_at = CURRENT_TIMESTAMP
                """,
                (exchange["item_id"], encrypted_token, institution_id, institution_name),
            )
            item_id = connection.execute(
                "SELECT id FROM plaid_items WHERE plaid_item_id = ?", (exchange["item_id"],)
            ).fetchone()["id"]
        await self.refresh_accounts(item_id, exchange["access_token"])
        return item_id

    async def complete_hosted_link(self, link_token: str, public_tokens: list[str]) -> None:
        session = await self.plaid.link_token_get(link_token)
        results = session.get("results", {}).get("item_add_results", [])
        for index, public_token in enumerate(public_tokens):
            metadata = results[index].get("metadata", {}) if index < len(results) else {}
            institution = metadata.get("institution") or {}
            item_id = await self.exchange(
                public_token,
                institution.get("name") or "Connected Institution",
                institution.get("institution_id"),
            )
            await self.sync_all(item_id)

    async def refresh_accounts(self, item_id: int, access_token: str) -> None:
        accounts = await self.plaid.accounts(access_token)
        with self.database.connect() as connection:
            for account in accounts:
                balances = account.get("balances") or {}
                connection.execute(
                    """
                    INSERT INTO accounts (
                        plaid_account_id, item_id, name, official_name, type, subtype, mask,
                        current_balance, available_balance, iso_currency_code
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(plaid_account_id) DO UPDATE SET
                        name = excluded.name, official_name = excluded.official_name,
                        type = excluded.type, subtype = excluded.subtype, mask = excluded.mask,
                        current_balance = excluded.current_balance,
                        available_balance = excluded.available_balance,
                        iso_currency_code = excluded.iso_currency_code,
                        updated_at = CURRENT_TIMESTAMP
                    """,
                    (
                        account["account_id"], item_id, account["name"], account.get("official_name"),
                        account["type"], account.get("subtype"), account.get("mask"),
                        balances.get("current"), balances.get("available"),
                        balances.get("iso_currency_code"),
                    ),
                )

    async def sync_item(self, item_id: int) -> tuple[int, int]:
        with self.database.connect() as connection:
            item = connection.execute(
                "SELECT access_token_encrypted, sync_cursor FROM plaid_items WHERE id = ?", (item_id,)
            ).fetchone()
        if item is None:
            return 0, 0
        access_token = self._token(item["access_token_encrypted"])
        original_cursor = item["sync_cursor"]
        cursor = original_cursor
        added_or_modified: list[dict[str, Any]] = []
        removed: list[str] = []
        try:
            while True:
                page = await self.plaid.sync(access_token, cursor)
                added_or_modified.extend(page.get("added", []))
                added_or_modified.extend(page.get("modified", []))
                removed.extend(transaction["transaction_id"] for transaction in page.get("removed", []))
                cursor = page["next_cursor"]
                if not page.get("has_more", False):
                    break
        except PlaidAPIError as error:
            # Plaid requires a full restart from the original cursor if its data mutates
            # during pagination. Do not persist a partially consumed cursor.
            if "MUTATION_DURING_PAGINATION" not in str(error):
                raise
            return await self.sync_item_from_cursor(item_id, original_cursor)

        with self.database.connect() as connection:
            for transaction in added_or_modified:
                category, primary, detailed = category_for(transaction)
                connection.execute(
                    """
                    INSERT INTO transactions (
                        plaid_transaction_id, item_id, plaid_account_id, name, merchant_name,
                        merchant_logo_url, amount, transaction_date, pending, iso_currency_code,
                        plaid_category, personal_finance_primary, personal_finance_detailed, raw_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(plaid_transaction_id) DO UPDATE SET
                        plaid_account_id = excluded.plaid_account_id, name = excluded.name,
                        merchant_name = excluded.merchant_name, merchant_logo_url = excluded.merchant_logo_url,
                        amount = excluded.amount, transaction_date = excluded.transaction_date,
                        pending = excluded.pending, iso_currency_code = excluded.iso_currency_code,
                        plaid_category = excluded.plaid_category,
                        personal_finance_primary = excluded.personal_finance_primary,
                        personal_finance_detailed = excluded.personal_finance_detailed,
                        raw_json = excluded.raw_json, updated_at = CURRENT_TIMESTAMP
                    """,
                    (
                        transaction["transaction_id"], item_id, transaction["account_id"],
                        transaction["name"], transaction.get("merchant_name"),
                        transaction.get("logo_url"), transaction["amount"], transaction["date"],
                        int(transaction.get("pending", False)), transaction.get("iso_currency_code"),
                        category, primary, detailed, json.dumps(transaction, separators=(",", ":")),
                    ),
                )
            if removed:
                connection.executemany(
                    "DELETE FROM transactions WHERE plaid_transaction_id = ?",
                    ((transaction_id,) for transaction_id in removed),
                )
            connection.execute(
                "UPDATE plaid_items SET sync_cursor = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                (cursor, item_id),
            )
        await self.refresh_accounts(item_id, access_token)
        return len(added_or_modified), len(removed)

    async def sync_item_from_cursor(self, item_id: int, cursor: str | None) -> tuple[int, int]:
        with self.database.connect() as connection:
            connection.execute("UPDATE plaid_items SET sync_cursor = ? WHERE id = ?", (cursor, item_id))
        return await self.sync_item(item_id)

    async def sync_all(self, item_id: int | None = None) -> SyncResponse:
        with self.database.connect() as connection:
            if item_id is None:
                items = [row["id"] for row in connection.execute("SELECT id FROM plaid_items")]
            else:
                items = [item_id]
        results = await asyncio.gather(*(self.sync_item(id_) for id_ in items))
        return SyncResponse(
            synced_items=len(items),
            upserted_transactions=sum(result[0] for result in results),
            removed_transactions=sum(result[1] for result in results),
        )

    def recategorize_transactions(self) -> int:
        with self.database.connect() as connection:
            rows = connection.execute(
                """
                SELECT id, personal_finance_primary, personal_finance_detailed
                FROM transactions
                WHERE manual_category IS NULL
                """
            ).fetchall()
            updates = []
            for row in rows:
                category, _, _ = category_for({
                    "personal_finance_category": {
                        "primary": row["personal_finance_primary"],
                        "detailed": row["personal_finance_detailed"],
                    }
                })
                updates.append((category, row["id"]))
            connection.executemany(
                "UPDATE transactions SET plaid_category = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                updates,
            )
        return len(updates)


def create_app(settings: Settings | None = None, plaid: PlaidClient | None = None) -> FastAPI:
    settings = settings or Settings.from_environment()
    database = Database(settings.database_path)
    cipher = Fernet(settings.token_encryption_key.encode())
    plaid = plaid or PlaidClient(settings)
    service = Service(database, plaid, cipher)

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        database.initialize()
        yield
        await plaid.close()

    app = FastAPI(title="Expenses API", version="0.1.0", lifespan=lifespan)
    app.state.settings = settings
    app.state.service = service

    async def require_api_token(authorization: str | None = Header(default=None)) -> None:
        expected = f"Bearer {settings.api_bearer_token}"
        if authorization is None or not hmac.compare_digest(authorization, expected):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")

    def transaction_response(row: sqlite3.Row) -> TransactionResponse:
        amount = float(row["amount"])
        custom_share_amount = row["custom_share_amount"]
        split_fraction = float(row["split_fraction"])
        if custom_share_amount is not None:
            effective_amount = abs(float(custom_share_amount)) * (-1 if amount < 0 else 1)
        else:
            effective_amount = amount * split_fraction
        return TransactionResponse(
            id=row["plaid_transaction_id"], account_id=row["plaid_account_id"],
            account_name=row["account_name"], merchant_name=row["merchant_name"],
            merchant_logo_url=row["merchant_logo_url"], name=row["name"], amount=amount,
            effective_amount=effective_amount, split_fraction=split_fraction,
            custom_share_amount=custom_share_amount,
            date=date.fromisoformat(row["transaction_date"]), pending=bool(row["pending"]),
            category=row["category"], category_overridden=row["manual_category"] is not None,
            currency=row["iso_currency_code"],
        )

    @app.get("/health")
    async def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/.well-known/apple-app-site-association", include_in_schema=False)
    async def apple_app_site_association() -> dict[str, Any]:
        return APPLE_APP_SITE_ASSOCIATION

    @app.post("/plaid/link-token", response_model=LinkTokenResponse, dependencies=[Depends(require_api_token)])
    async def create_link_token(request: LinkTokenRequest) -> LinkTokenResponse:
        try:
            token = await plaid.create_link_token(request.client_user_id, request.presentation)
        except PlaidAPIError as error:
            raise HTTPException(status_code=502, detail="Unable to create Plaid Link token") from error
        if request.presentation == "hosted":
            if not token.get("hosted_link_url"):
                raise HTTPException(status_code=502, detail="Plaid did not create a Hosted Link URL")
            with database.connect() as connection:
                connection.execute(
                    "INSERT OR REPLACE INTO link_sessions (link_token, presentation) VALUES (?, ?)",
                    (token["link_token"], request.presentation),
                )
        return LinkTokenResponse(
            link_token=token["link_token"],
            expiration=token["expiration"],
            hosted_link_url=token.get("hosted_link_url"),
        )

    @app.post("/plaid/exchange-public-token", status_code=status.HTTP_201_CREATED, dependencies=[Depends(require_api_token)])
    async def exchange_public_token(request: PublicTokenExchangeRequest) -> dict[str, str]:
        try:
            item_id = await service.exchange_public_token(request)
            await service.sync_all(item_id)
        except PlaidAPIError as error:
            raise HTTPException(status_code=502, detail="Unable to connect the account") from error
        return {"status": "connected"}

    @app.get("/accounts", response_model=list[AccountResponse], dependencies=[Depends(require_api_token)])
    async def accounts() -> list[AccountResponse]:
        with database.connect() as connection:
            rows = connection.execute(
                """
                SELECT a.plaid_account_id, i.institution_name, a.name, a.official_name, a.type,
                       a.subtype, a.mask, a.current_balance, a.available_balance, a.iso_currency_code
                FROM accounts a JOIN plaid_items i ON i.id = a.item_id
                ORDER BY i.institution_name, a.name
                """
            ).fetchall()
        return [
            AccountResponse(
                id=row["plaid_account_id"], institution_name=row["institution_name"], name=row["name"],
                official_name=row["official_name"], type=row["type"], subtype=row["subtype"],
                mask=row["mask"], current_balance=row["current_balance"],
                available_balance=row["available_balance"], currency=row["iso_currency_code"],
            )
            for row in rows
        ]

    @app.get("/transactions", response_model=list[TransactionResponse], dependencies=[Depends(require_api_token)])
    async def transactions(
        start_date: date | None = Query(default=None),
        end_date: date | None = Query(default=None),
        account_id: str | None = Query(default=None),
    ) -> list[TransactionResponse]:
        query = """
            SELECT t.*, a.name AS account_name, COALESCE(t.manual_category, t.plaid_category) AS category
            FROM transactions t JOIN accounts a ON a.plaid_account_id = t.plaid_account_id
            WHERE 1 = 1
        """
        values: list[Any] = []
        if start_date:
            query += " AND t.transaction_date >= ?"
            values.append(start_date.isoformat())
        if end_date:
            query += " AND t.transaction_date <= ?"
            values.append(end_date.isoformat())
        if account_id:
            query += " AND t.plaid_account_id = ?"
            values.append(account_id)
        query += " ORDER BY t.transaction_date DESC, t.id DESC"
        with database.connect() as connection:
            rows = connection.execute(query, values).fetchall()
        return [transaction_response(row) for row in rows]

    @app.patch("/transactions/{transaction_id}", response_model=TransactionResponse, dependencies=[Depends(require_api_token)])
    async def override_transaction_category(
        transaction_id: str, override: TransactionCategoryOverride
    ) -> TransactionResponse:
        with database.connect() as connection:
            connection.execute(
                "UPDATE transactions SET manual_category = ?, updated_at = CURRENT_TIMESTAMP WHERE plaid_transaction_id = ?",
                (override.category, transaction_id),
            )
            row = connection.execute(
                """
                SELECT t.*, a.name AS account_name, COALESCE(t.manual_category, t.plaid_category) AS category
                FROM transactions t JOIN accounts a ON a.plaid_account_id = t.plaid_account_id
                WHERE t.plaid_transaction_id = ?
                """,
                (transaction_id,),
            ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Transaction not found")
        return transaction_response(row)

    @app.delete("/transactions/{transaction_id}/category", response_model=TransactionResponse, dependencies=[Depends(require_api_token)])
    async def clear_transaction_category_override(transaction_id: str) -> TransactionResponse:
        with database.connect() as connection:
            connection.execute(
                "UPDATE transactions SET manual_category = NULL, updated_at = CURRENT_TIMESTAMP WHERE plaid_transaction_id = ?",
                (transaction_id,),
            )
            row = connection.execute(
                """
                SELECT t.*, a.name AS account_name, COALESCE(t.manual_category, t.plaid_category) AS category
                FROM transactions t JOIN accounts a ON a.plaid_account_id = t.plaid_account_id
                WHERE t.plaid_transaction_id = ?
                """,
                (transaction_id,),
            ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Transaction not found")
        return transaction_response(row)

    @app.patch("/transactions/{transaction_id}/split", response_model=TransactionResponse, dependencies=[Depends(require_api_token)])
    async def set_transaction_split(
        transaction_id: str, split: TransactionSplitOverride
    ) -> TransactionResponse:
        if (split.fraction is None) == (split.custom_amount is None):
            raise HTTPException(status_code=422, detail="Provide exactly one of fraction or custom_amount")
        with database.connect() as connection:
            row = connection.execute(
                "SELECT amount FROM transactions WHERE plaid_transaction_id = ?", (transaction_id,)
            ).fetchone()
            if row is None:
                raise HTTPException(status_code=404, detail="Transaction not found")
            if split.custom_amount is not None and split.custom_amount > abs(float(row["amount"])):
                raise HTTPException(status_code=422, detail="Custom share cannot exceed the transaction amount")
            connection.execute(
                """
                UPDATE transactions
                SET split_fraction = ?, custom_share_amount = ?, updated_at = CURRENT_TIMESTAMP
                WHERE plaid_transaction_id = ?
                """,
                (split.fraction if split.fraction is not None else 1, split.custom_amount, transaction_id),
            )
            updated = connection.execute(
                """
                SELECT t.*, a.name AS account_name, COALESCE(t.manual_category, t.plaid_category) AS category
                FROM transactions t JOIN accounts a ON a.plaid_account_id = t.plaid_account_id
                WHERE t.plaid_transaction_id = ?
                """,
                (transaction_id,),
            ).fetchone()
        return transaction_response(updated)

    @app.delete("/transactions/{transaction_id}/split", response_model=TransactionResponse, dependencies=[Depends(require_api_token)])
    async def clear_transaction_split(transaction_id: str) -> TransactionResponse:
        with database.connect() as connection:
            connection.execute(
                """
                UPDATE transactions
                SET split_fraction = 1, custom_share_amount = NULL, updated_at = CURRENT_TIMESTAMP
                WHERE plaid_transaction_id = ?
                """,
                (transaction_id,),
            )
            row = connection.execute(
                """
                SELECT t.*, a.name AS account_name, COALESCE(t.manual_category, t.plaid_category) AS category
                FROM transactions t JOIN accounts a ON a.plaid_account_id = t.plaid_account_id
                WHERE t.plaid_transaction_id = ?
                """,
                (transaction_id,),
            ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Transaction not found")
        return transaction_response(row)

    @app.post("/transactions/recategorize", dependencies=[Depends(require_api_token)])
    async def recategorize_transactions() -> dict[str, int]:
        return {"updated_transactions": service.recategorize_transactions()}

    @app.post("/sync", response_model=SyncResponse, dependencies=[Depends(require_api_token)])
    async def sync() -> SyncResponse:
        try:
            return await service.sync_all()
        except PlaidAPIError as error:
            raise HTTPException(status_code=502, detail="Unable to sync transactions") from error

    @app.delete("/data", dependencies=[Depends(require_api_token)])
    async def clear_data() -> dict[str, str]:
        """Remove locally stored Items, accounts, and transactions before an environment change."""
        with database.connect() as connection:
            connection.execute("DELETE FROM plaid_items")
            connection.execute("DELETE FROM link_sessions")
        return {"status": "cleared"}

    @app.post("/webhooks/plaid", status_code=status.HTTP_200_OK)
    async def plaid_webhook(request: Request, background_tasks: BackgroundTasks, token: str | None = Query(default=None)) -> dict[str, str]:
        if not settings.webhook_secret or token is None or not hmac.compare_digest(token, settings.webhook_secret):
            raise HTTPException(status_code=401, detail="Unauthorized")
        payload = await request.json()
        if payload.get("webhook_type") == "LINK" and payload.get("webhook_code") == "SESSION_FINISHED":
            if payload.get("status") != "SUCCESS":
                return {"status": "ignored"}
            link_token = payload.get("link_token")
            public_tokens = payload.get("public_tokens") or []
            with database.connect() as connection:
                row = connection.execute(
                    "SELECT id FROM link_sessions WHERE link_token = ?", (link_token,)
                ).fetchone()
            if row is None:
                return {"status": "unknown_link_session"}
            background_tasks.add_task(service.complete_hosted_link, link_token, public_tokens)
            return {"status": "accepted"}
        if payload.get("webhook_type") != "TRANSACTIONS":
            return {"status": "ignored"}
        if payload.get("webhook_code") not in {"SYNC_UPDATES_AVAILABLE", "INITIAL_UPDATE", "HISTORICAL_UPDATE"}:
            return {"status": "ignored"}
        with database.connect() as connection:
            row = connection.execute(
                "SELECT id FROM plaid_items WHERE plaid_item_id = ?", (payload.get("item_id"),)
            ).fetchone()
        if row is None:
            return {"status": "unknown_item"}
        background_tasks.add_task(service.sync_all, row["id"])
        return {"status": "accepted"}

    return app


app = create_app()
