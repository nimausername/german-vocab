# Contributing

Thanks for helping improve German Vocab.

## Development

### Backend

```bash
cd backend
cp .env.example .env
# fill DATABASE_URL + Keycloak settings
pnpm install
pnpm db:setup
pnpm start:dev
```

### iOS

1. Open `ios/GermanVocab.xcodeproj` in Xcode.
2. Set your Apple ID team under Signing.
3. Point `AppConfig.apiBaseURL` at your API.
4. Run on an iPhone, iPad, or simulator.

## Guidelines

- Do not commit secrets (`.env`, tokens, passwords).
- Prefer small, focused pull requests.
- Keep API responses camelCase and shaped as `{ data, meta }` / `{ error, meta }`.
- Add or update docs when behavior changes.
- The seed corpus is 4000 lemmas. New words belong in `backend/src/data/lexicon/`, and every lemma must stay unique. Check with `pnpm --dir backend corpus:check`.

## Ideas welcome

- Cloze / typing drills
- Audio (TTS)
- Offline sync
- Localization of the UI
