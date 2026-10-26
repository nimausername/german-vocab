# German Vocab

Open-source German vocabulary trainer for iPhone and iPad: spaced repetition (FSRS), a daily study plan, Keycloak auth, and a self-hosted Node API + PostgreSQL.

The seed corpus is **4000 lemmas**, ordered so everyday sentences come first. The original 120 A1 words stay at the front. Later words move from function words and high-frequency verbs through concrete nouns into B2 and C1. CEFR labels are teaching bands, not an official exam list.

## Features

- Native **SwiftUI** app for iPhone, iPad, and Apple Watch (no Expo). The iPhone and iPad app requires **iOS 26 or later** and uses Liquid Glass navigation, tabs, and controls. iPhone study is typed; iPad study uses Apple Pencil, with typing as a fallback. The watch shows the German word, then **Show meaning** and **Next**, without grading the card.
- Reminders you can place through the day. Later ones mention the streak when today's session is still unfinished. Apple Watch shows them when the iPhone is locked.
- In-app login and **Create Account** via **Keycloak** (password grant + Admin API registration; no browser redirect)
- Daily plan: due reviews + limited new words, with a **today’s goal** progress bar for finishing that queue
- Review-pressure pacing: when due reviews are busy (≥25) or heavy (≥40), new words are capped or paused for the day
- Word detail: study sentence, Premium German audio, and review history (reps, next due)
- Offline study: today’s plan is cached on device; reviews queue and sync when you’re back online
- Study reminders on iPhone/iPad and Apple Watch; later reminders mention the streak when today’s goal is still open
- Progress export: CSV backup or Anki-importable tab-separated notes from Settings
- **FSRS** scheduling. A miss is saved as Again. A correct card is Good or Easy.
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

Create a realm (e.g. `german-vocab`) and one **confidential** OpenID client (e.g. `german-vocab-app`) with:

- Client authentication: **On**
- Standard flow: **Off**
- Direct access grants: **On** (Sign In)
- Service accounts: **On** (Create Account)
- Service account roles: `realm-management` → `manage-users`
- Copy the client secret into `KEYCLOAK_CLIENT_SECRET` on the API (never in the iOS app)

The phone only talks to your API. The API holds the secret and proxies login, refresh, and registration. Without `KEYCLOAK_CLIENT_SECRET`, login may still work for a public client; Create Account returns `REGISTER_DISABLED`.

Session length lives in Keycloak, not only in the app. For daily study without constant re-login, in the realm set roughly:

- **Access Token Lifespan**: 15–30 minutes (or keep 5 minutes; the app refreshes automatically)
- **SSO Session Idle**: 7 days or more
- **SSO Session Max**: 30 days or more
- **Client → Advanced → Refresh Token Max Reuse**: leave refresh token rotation on; the app refreshes once at a time so parallel requests do not burn the token

Create at least one user, then log in from the app.

### 3. iPhone or iPad app

1. Open `ios/GermanVocab.xcodeproj` in Xcode. The iPhone and iPad target requires iOS 26 or later.
2. Select your development team (Signing & Capabilities).
3. Set `AppConfig.apiBaseURL` in `ios/GermanVocab/Config.swift`.
4. Choose your iPhone or iPad as the run destination and run (⌘R).

The Apple Watch app is installed with the iPhone app. Sign in on the iPhone, then open German Vocab on the watch. A word shows in German; tap **Show meaning**, then **Next**. That stays on the watch and does not grade the card.

## Deploy (Coolify)

See **[backend/COOLIFY.md](backend/COOLIFY.md)**.

After deploy, point `Config.swift` at your HTTPS API URL and rebuild the app.

## API overview

| Method | Path | Auth |
|---|---|---|
| GET | `/health` | no |
| POST | `/v1/auth/login` | no |
| POST | `/v1/auth/register` | no |
| POST | `/v1/auth/refresh` | no |
| GET | `/v1/plans/today` | Bearer |
| POST | `/v1/reviews` | Bearer |
| GET | `/v1/stats` | Bearer |
| PATCH | `/v1/settings` | Bearer |
| GET | `/v1/exports/progress?format=csv\|anki` | Bearer |

Review ratings: `1=Again`, `2=Hard`, `3=Good`, `4=Easy`

## Learning model

1. Words are ordered by `sortOrder` / CEFR.
2. Each day: all **due** cards + up to **N** new words (default 8 for a new account, changeable in Settings from 1 to 50). An account that already chose a limit keeps it. If reviews are busy (≥25 due), new words cap at 3; if heavy (≥40 due), new words pause. Today’s goal is finishing that mixed queue.
3. A new word starts as a German sentence, played with the device’s Premium German voice when one is installed. The English stays hidden until you ask for it. You then write the word from the English, and fill that same word into the sentence. When a Premium voice is installed, blank practice is listen-first: the German line stays hidden until you ask to show it. Mature noun reviews also rotate in plural and article drills. A young review skips the first reveal and still does both writing steps. Once a review interval is a week or longer, the session is only that production step. A miss is saved as **Again**. **Good** and **Easy** are offered only after a correct answer.
4. FSRS sets the next `due` time from that result.
5. Progress is stored per Keycloak user in PostgreSQL.

## Roadmap

- Shared family / classroom accounts
- Optional browser-based OIDC for web clients

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and PRs welcome.

## License

[MIT](LICENSE)
