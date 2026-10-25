# German Vocab

Open-source German vocabulary trainer for iPhone and iPad: spaced repetition (FSRS), a daily study plan, Keycloak auth, and a self-hosted Node API + PostgreSQL.

The seed corpus is **4000 lemmas**, ordered so everyday sentences come first. The original 120 A1 words stay at the front. Later words move from function words and high-frequency verbs through concrete nouns into B2 and C1. CEFR labels are teaching bands, not an official exam list.

## Features

- Native **SwiftUI** app for iPhone, iPad, and Apple Watch (no Expo). iPhone study is typed; iPad study uses Apple Pencil, with typing as a fallback. The watch shows the German word, then **Learned** or **Not yet**.
- Reminders you can place through the day. Later ones mention the streak when today's session is still unfinished. Apple Watch shows them when the iPhone is locked.
- In-app login via **Keycloak** (password grant; no browser redirect)
- Daily plan: due reviews + limited new words
- **FSRS** scheduling (Again / Hard / Good / Easy)
- Stats: streak, words learned, reviews
- Docker / **Coolify**-ready backend

## Architecture

```text
iPhone / iPad / Apple Watch (SwiftUI)  →  Node API  →  PostgreSQL
                      ↓
                   Keycloak
```

| Path | Role |
|---|---|
| `ios/` | SwiftUI iPhone, iPad, and Apple Watch client |
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

### 3. iPhone or iPad app

1. Open `ios/GermanVocab.xcodeproj` in Xcode.
2. Select your development team (Signing & Capabilities).
3. Set `AppConfig.apiBaseURL` in `ios/GermanVocab/Config.swift`.
4. Choose your iPhone or iPad as the run destination and run (⌘R).

The Apple Watch app is installed with the iPhone app. Sign in on the iPhone, then open German Vocab on the watch. A word shows in German; tap **Show meaning**, then **Learned** or **Not yet**.

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
| PATCH | `/v1/settings` | Bearer |

Review ratings: `1=Again`, `2=Hard`, `3=Good`, `4=Easy`

## Learning model

1. Words are ordered by `sortOrder` / CEFR.
2. Each day: all **due** cards + up to **N** new words (default 20, changeable in Settings from 1 to 50).
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
