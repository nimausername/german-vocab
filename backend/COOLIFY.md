# Deploy backend on Coolify

## Coolify resource settings

| Setting | Value |
|---|---|
| Source | This GitHub repo |
| Base Directory | `backend` |
| Build Pack | **Dockerfile** |
| Dockerfile Location | `Dockerfile` (inside base directory) |
| Port | `3080` (or match Coolify `PORT`) |
| Health check path | `/health` |

## Environment variables

Set these in Coolify (never commit secrets):

```env
DATABASE_URL=postgres://USER:PASSWORD@HOST:PORT/DATABASE
PORT=3080
HOST=0.0.0.0
KEYCLOAK_ISSUER=https://auth.nimakhabbazi.de/realms/german-vocab
KEYCLOAK_CLIENT_ID=german-vocab-app
KEYCLOAK_TOKEN_URL=https://auth.nimakhabbazi.de/realms/german-vocab/protocol/openid-connect/token
CORS_ORIGIN=*
```

Notes:

- Coolify often injects `PORT` itself — keep the app reading `PORT` (already does).
- Postgres must allow connections from the Coolify server IP.
- Prefer a private network / firewall; do not expose Postgres to the whole internet.

## Domain

Attach a domain in Coolify, e.g. `https://vocab-api.yourdomain.de`, enable HTTPS.

Then set the iPad app:

```swift
// ios/GermanVocab/Config.swift
static let apiBaseURL = URL(string: "https://vocab-api.yourdomain.de")!
```

Rebuild the iOS app after changing the URL.

## First-time database setup

Schema/seed are not run automatically on every deploy. After the first successful deploy, run once (Coolify terminal / one-off command) from the app container or a one-off job with the same env:

```bash
pnpm db:push
pnpm db:seed
```

Or from your laptop with production `DATABASE_URL` in a local `.env` (do not commit it):

```bash
cd backend
pnpm db:setup
```

`db:seed` is safe to re-run: it skips if words already exist.

## Verify

```bash
curl https://vocab-api.yourdomain.de/health
```

Expected: `{"data":{"status":"ok"},...}`
