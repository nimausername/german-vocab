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
4. Run on an iPad or simulator.

## Guidelines

- Do not commit secrets (`.env`, tokens, passwords).
- Prefer small, focused pull requests.
- Keep API responses camelCase and shaped as `{ data, meta }` / `{ error, meta }`.
- Add or update docs when behavior changes.

## Ideas welcome

- Larger CEFR word lists (A1→C1 toward ~4000)
- Cloze / typing drills
- Audio (TTS)
- Offline sync
- Localization of the UI
