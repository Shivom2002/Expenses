# Expenses backend

The FastAPI service is the only component that talks to Plaid. It holds the Plaid secret and encrypts access tokens with Fernet before persisting them in SQLite. The iOS and macOS apps use an Authorization Bearer token stored in Keychain.

## Local setup

1. Copy .env.example to .env, then fill in Plaid Sandbox values and the two generated secrets.
2. Export those values in your shell (or use a process manager that loads .env).
3. Start the server with uv sync --all-groups, then uv run uvicorn app.main:app --reload.
4. Confirm the service responds: curl http://127.0.0.1:8000/health.
5. Verify a Sandbox Link token without putting Plaid credentials in the client:

    curl -X POST http://127.0.0.1:8000/plaid/link-token \
      -H "Authorization: Bearer $API_BEARER_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"client_user_id":"personal-user"}'

After the iOS Link flow returns a public token, post it to /plaid/exchange-public-token with the selected institution's name and ID. The service then stores only the encrypted access token and begins an incremental /transactions/sync stream.

## Fly.io deployment

From backend/, choose a unique app name in fly.toml, then:

    fly volumes create expenses_data --size 1 --region sjc
    fly secrets set PLAID_CLIENT_ID=... PLAID_SECRET=... TOKEN_ENCRYPTION_KEY=... API_BEARER_TOKEN=... WEBHOOK_SECRET=...
    fly deploy

Set PLAID_WEBHOOK_URL to https://<your-app>.fly.dev/webhooks/plaid?token=<WEBHOOK_SECRET> as a Fly secret, then redeploy. The expenses_data volume mounts at /data, so the SQLite database survives image deploys and restarts. Back up the volume before moving regions or rebuilding the application.
