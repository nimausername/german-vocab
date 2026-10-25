# German Vocab

Open-source German vocabulary trainer for iPad: spaced repetition (FSRS), a daily study plan, Keycloak auth, and a self-hosted Node API + PostgreSQL.

The seed corpus is **4000 lemmas**, ordered so everyday sentences come first. The original 120 A1 words stay at the front. Later words move from function words and high-frequency verbs through concrete nouns into B2 and C1. CEFR labels are teaching bands, not an official exam list.

## Features

- Native **SwiftUI** iPad app (no Expo)
- In-app login via **Keycloak** (password grant; no browser redirect)
- Daily plan: due reviews + limited new words
- **FSRS** scheduling (Again / Hard / Good / Easy)
- Stats: streak, words learned, reviews
- Docker / **Coolify**-ready backend

## Architecture

```text
iPad (SwiftUI)  →  Node API  →  PostgreSQL
                      ↓
                   Keycloak
```

| Path | Role |
|---|---|
| `ios/` | SwiftUI iPad client |
| `backend/` | Hono + TypeScript API, FSRS, Drizzle |
| `backend/COOLIFY.md` | Deploy on Coolify |

## Quick start

### 1. Backend

Requirements: Node 20+, pnpm, PostgreSQL, a Keycloak realm (see below).

```bash
cd backend
cp .env.example .env
# edit DATABASE_URL and KEYCLOAK_* values
pnpm install
pnpm db:setup
pnpm start:dev
```

API: `http://localhost:3080` — health check: `GET /health`

### 2. Keycloak

Create a realm (e.g. `german-vocab`) and a **public** OpenID client with:

- Standard flow: off (for in-app login)
- Direct access grants: **on**
- Client ID matching `KEYCLOAK_CLIENT_ID`

Create at least one user, then log in from the app.

### 3. iPad app

1. Open `ios/GermanVocab.xcodeproj` in Xcode.
2. Select your development team (Signing & Capabilities).
3. Set `AppConfig.apiBaseURL` in `ios/GermanVocab/Config.swift`.
4. Run on your iPad (⌘R).

## Deploy (Coolify)

See **[backend/COOLIFY.md](backend/COOLIFY.md)**.

After deploy, point `Config.swift` at your HTTPS API URL and rebuild the app.

## API overview

| Method | Path | Auth |
|---|---|---|
| GET | `/health` | no |
| POST | `/v1/auth/login` | no |
| POST | `/v1/auth/refresh` | no |
| GET | `/v1/plans/today` | Bearer |
| POST | `/v1/reviews` | Bearer |
| GET | `/v1/stats` | Bearer |

Review ratings: `1=Again`, `2=Hard`, `3=Good`, `4=Easy`

## Learning model

1. Words are ordered by `sortOrder` / CEFR.
2. Each day: all **due** cards + up to **N** new words (default 20).
3. You recall, reveal, and rate; FSRS sets the next `due` time.
4. Progress is stored per Keycloak user in PostgreSQL.

## Roadmap

- Cloze / production drills
- Audio (TTS)
- Offline cache
- In-app registration via Keycloak Admin API

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and PRs welcome.

## License

[MIT](LICENSE)
