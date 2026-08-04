from __future__ import annotations

from typing import Any

import httpx

from .config import Settings


class PlaidAPIError(RuntimeError):
    pass


class PlaidClient:
    """Small async Plaid client that never exposes credentials to the app."""

    def __init__(self, settings: Settings, client: httpx.AsyncClient | None = None) -> None:
        self.settings = settings
        self.client = client or httpx.AsyncClient(base_url=settings.plaid_base_url, timeout=30)
        self._owns_client = client is None

    async def close(self) -> None:
        if self._owns_client:
            await self.client.aclose()

    async def post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        response = await self.client.post(
            path,
            json={
                "client_id": self.settings.plaid_client_id,
                "secret": self.settings.plaid_secret,
                **payload,
            },
        )
        data = response.json()
        if response.is_error:
            raise PlaidAPIError(data.get("error_message", "Plaid request failed"))
        return data

    async def create_link_token(self, client_user_id: str, presentation: str) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "client_name": "Expenses",
            "country_codes": ["US"],
            "language": "en",
            "user": {"client_user_id": client_user_id},
            "products": ["transactions"],
        }
        if self.settings.plaid_webhook_url:
            payload["webhook"] = self.settings.plaid_webhook_url
        if self.settings.plaid_redirect_uri:
            payload["redirect_uri"] = self.settings.plaid_redirect_uri
        if presentation == "hosted":
            payload["hosted_link"] = {
                "is_mobile_app": True,
                "completion_redirect_uri": "expenses://hosted-link-complete",
            }
        return await self.post("/link/token/create", payload)

    async def exchange_public_token(self, public_token: str) -> dict[str, Any]:
        return await self.post("/item/public_token/exchange", {"public_token": public_token})

    async def link_token_get(self, link_token: str) -> dict[str, Any]:
        return await self.post("/link/token/get", {"link_token": link_token})

    async def accounts(self, access_token: str) -> list[dict[str, Any]]:
        return (await self.post("/accounts/get", {"access_token": access_token}))["accounts"]

    async def sync(self, access_token: str, cursor: str | None) -> dict[str, Any]:
        payload: dict[str, Any] = {"access_token": access_token, "count": 500}
        if cursor is not None:
            payload["cursor"] = cursor
        return await self.post("/transactions/sync", payload)
