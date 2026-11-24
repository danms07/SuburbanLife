## Do
- Write all code, comments, and variable names in English, even when instructions are in another language.
- Before loading docs, read only what your task needs:
  - **File locations / module map**: [`Structure.md`](Structure.md)
  - **Setup / emulator / test / CLI scripts**: [`README.md`](README.md)
  - **Firestore collections, RTDB paths, Storage prefixes, indexes & TTLs**: [`database_schema.md`](database_schema.md)
  - **Cloud Functions callables, triggers, cron & FCM/RTDB notifications**: [`functions/README.md`](functions/README.md)
  - **Shared UI widgets, layout breakpoints & key identifiers**: [`widget_catalog.md`](widget_catalog.md)
  - **GCP / Firebase Terraform IaC**: [`terraform/README.md`](terraform/README.md)
  - *(Skip `docs/*.md` and `CHANGELOG.md` during normal coding tasks; `docs/*.md` are end-user PDF sources.)*
- Upon each change:
  - Update [`Structure.md`](Structure.md) (1 concise line per changed/added file), [`widget_catalog.md`](widget_catalog.md), [`functions/README.md`](functions/README.md), [`README.md`](README.md), [`firestore.rules`](firestore.rules), [`firestore.indexes.json`](firestore.indexes.json), [`storage.rules`](storage.rules), [`database.rules.json`](database.rules.json), [`.gitignore`](.gitignore), and `test/` as needed.
  - Check [`database_schema.md`](database_schema.md) for schema conflicts before changing fields/queries; if a conflict exists, plan a refactor strategy.
  - Bump the app version in both [`pubspec.yaml`](pubspec.yaml) and [`web/version.json`](web/version.json) whenever frontend code changes.
  - Record detailed changes in [`CHANGELOG.md`](CHANGELOG.md) and create a short, concise git commit.
- Documentation hygiene (keep token usage low):
  - Keep [`Structure.md`](Structure.md) to 1 crisp line per file (exported symbols/responsibility only; never paste test-case lists or schema fields).
  - Do not duplicate collection fields, Cloud Function params, or UI essays across multiple `.md` files—update the canonical doc and link if needed.
  - Keep [`CHANGELOG.md`](CHANGELOG.md) entries as concise, high-signal bullets per version.
- Before running the Firebase emulator, switch to the default Node version with `nvm default`.
- Always add Spanish translations for all UI text (`lib/l10n/app_en.arb` + `lib/l10n/app_es.arb`).
- Keep code comments updated and concise.
- Use `white_logo.png` for favicon icons in the web version.

## Don't
- Hardcode UI strings; always use the `l10n` localization system.
- Use deprecated `value:` in `DropdownButtonFormField`; use `initialValue:` instead.
- Use `print()`; always use `debugPrint()` for console logs.
- Use `primaryColor.withOpacity()`; use `Theme.of(context).colorScheme.withValues()` (or `color.withValues(alpha: ...)`) for UI transparency.
