from __future__ import annotations

import sqlite3
from pathlib import Path


SCHEMA = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS plaid_items (
    id INTEGER PRIMARY KEY,
    plaid_item_id TEXT NOT NULL UNIQUE,
    access_token_encrypted TEXT NOT NULL,
    institution_id TEXT,
    institution_name TEXT NOT NULL,
    sync_cursor TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS accounts (
    id INTEGER PRIMARY KEY,
    plaid_account_id TEXT NOT NULL UNIQUE,
    item_id INTEGER NOT NULL REFERENCES plaid_items(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    official_name TEXT,
    type TEXT NOT NULL,
    subtype TEXT,
    mask TEXT,
    current_balance REAL,
    available_balance REAL,
    iso_currency_code TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS link_sessions (
    id INTEGER PRIMARY KEY,
    link_token TEXT NOT NULL UNIQUE,
    presentation TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS transactions (
    id INTEGER PRIMARY KEY,
    plaid_transaction_id TEXT NOT NULL UNIQUE,
    item_id INTEGER NOT NULL REFERENCES plaid_items(id) ON DELETE CASCADE,
    plaid_account_id TEXT NOT NULL,
    name TEXT NOT NULL,
    merchant_name TEXT,
    merchant_logo_url TEXT,
    amount REAL NOT NULL,
    transaction_date TEXT NOT NULL,
    pending INTEGER NOT NULL DEFAULT 0,
    iso_currency_code TEXT,
    plaid_category TEXT NOT NULL,
    manual_category TEXT,
    personal_finance_primary TEXT,
    personal_finance_detailed TEXT,
    raw_json TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS transactions_date_idx ON transactions(transaction_date DESC);
CREATE INDEX IF NOT EXISTS transactions_account_idx ON transactions(plaid_account_id);
"""


class Database:
    def __init__(self, path: Path) -> None:
        self.path = path

    def connect(self) -> sqlite3.Connection:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(self.path)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA journal_mode = WAL")
        return connection

    def initialize(self) -> None:
        with self.connect() as connection:
            connection.executescript(SCHEMA)
