from __future__ import annotations

from datetime import date
from typing import Literal

from pydantic import BaseModel, Field


class LinkTokenRequest(BaseModel):
    client_user_id: str = Field(default="personal-user", min_length=1, max_length=128)
    presentation: Literal["native", "hosted"] = "native"


class LinkTokenResponse(BaseModel):
    link_token: str
    expiration: str
    hosted_link_url: str | None = None


class PublicTokenExchangeRequest(BaseModel):
    public_token: str
    institution_name: str = Field(min_length=1, max_length=200)
    institution_id: str | None = Field(default=None, max_length=100)


class AccountResponse(BaseModel):
    id: str
    institution_name: str
    name: str
    official_name: str | None
    type: str
    subtype: str | None
    mask: str | None
    current_balance: float | None
    available_balance: float | None
    currency: str | None


class TransactionResponse(BaseModel):
    id: str
    account_id: str
    account_name: str
    merchant_name: str | None
    merchant_logo_url: str | None
    name: str
    amount: float
    effective_amount: float
    split_fraction: float
    custom_share_amount: float | None
    date: date
    pending: bool
    category: str
    category_overridden: bool
    currency: str | None


class TransactionCategoryOverride(BaseModel):
    category: str = Field(min_length=1, max_length=60)


class TransactionSplitOverride(BaseModel):
    fraction: float | None = Field(default=None, gt=0, le=1)
    custom_amount: float | None = Field(default=None, gt=0)


class SyncResponse(BaseModel):
    synced_items: int
    upserted_transactions: int
    removed_transactions: int
