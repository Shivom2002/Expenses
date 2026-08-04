# Expenses

A native personal-finance tracker for iOS and macOS, built with SwiftUI and a secure FastAPI backend. The apps share `Packages/ExpensesCore`; the backend will be deployed to Fly.io with a persistent SQLite volume.

## Project layout

- `Expenses/` — native iOS target
- `ExpensesMac/` — native macOS target
- `Packages/ExpensesCore/` — models, view models, networking, and business logic shared by both apps
- `backend/` — FastAPI and Plaid integration (introduced in the next build step)

## Development requirements

- Xcode 16 or later
- Swift 6
- Python 3.12 or later (for the backend)

The default app environment points to `http://localhost:8000`. It contains no secrets; production API configuration will be supplied by an Xcode configuration file, while credentials remain in the backend and platform Keychain.
