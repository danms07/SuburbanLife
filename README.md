# Suburban Life

White-label residential community management platform built with **Flutter** and **Firebase** for residents, security guards, and administrators.

## Documentation Map

| Doc | Use For |
| :--- | :--- |
| [`Structure.md`](Structure.md) | File index, exported Dart symbols, and architectural boundary rules |
| [`database_schema.md`](database_schema.md) | Firestore collections, RTDB paths, Storage rules, 33 composite indexes & TTL policies |
| [`functions/README.md`](functions/README.md) | 27 Cloud Function callables, 10 Firestore triggers, 5 daily crons & FCM/RTDB notifications |
| [`widget_catalog.md`](widget_catalog.md) | Reusable UI widgets, responsive breakpoints, and stable widget keys |
| [`terraform/README.md`](terraform/README.md) | Automated GCP & Firebase provisioning via Terraform + existing-project importer |
| [`CHANGELOG.md`](CHANGELOG.md) | Release history |

*(End-user PDF manuals and future feature plans live in `docs/`.)*

---

## Core Capabilities

- **Multi-Role Workspace**: Adaptive Admin sidebar/drawer workspace (`Overview` KPIs, roll-up badges, shortcuts), Resident dashboard & multi-property header switcher, and Security Guard QR panel.
- **Resident & Roommate Onboarding**: Password-validated signup, cascading address picker, ownership-proof upload & master-detail admin approval (`reviewOwnershipClaim`), plus QR/UID roommate linking.
- **Financials, Expenses & Sanctions**: Monthly & advance multi-period payments with master-detail proof review and rejection recovery; admin expense ledger with dual evidence & soft-voiding (`createExpense`/`voidExpense`); opening balance + integer-cent accumulated budget reporting (CSV bundle & PII-free bilingual Transparency Markdown); address-level sanctions with inline/full-screen rotatable evidence.
- **Amenity Bookings & Document Attachments**: Household-scoped cooldowns (`hours`–`years`) or calendar quotas (`daily`–`yearly`), operating hours, anticipation windows, required/optional returnable document templates (`booking_attachments/{bookingId}` w/ 30d TTL), master-detail approval, and atomic resubmission.
- **Gatehouse QR Access & Audit Logs**: Single-flight guard QR scanner displaying destination addresses (`Admin office` aware), optional Scan-on-Exit fast departure mode, live `INSIDE` pass badges, bounded ID/plate temp capture cleanup, and 60d retention audit logs (`access_logs`).
- **Transparency & Announcements**: Virtual folder/category file explorer with hybrid EN/ES localization, `ES | EN` in-app document viewer, role-based `all`/`admin` visibility, and announcements with Web clipboard paste + Vertex AI translation.
- **Cross-Platform Notifications**: FCM push + RTDB inbox (`/notifications/{uid}` w/ 30d / 100-item retention) across Android (7 channels), iOS, and Web (`firebase-messaging-sw.js` + VAPID), bell badge, foreground banner, and per-category preferences.

---

## Prerequisites

- **Flutter SDK** (Dart `^3.9.0`)
- **Node.js `24`** (managed via `nvm default`; required by Cloud Functions & scripts)
- **Firebase CLI**: `npm i -g firebase-tools`
- **FlutterFire CLI**: `dart pub global activate flutterfire_cli`
- **Google Cloud CLI (`gcloud`)** *(for one-time Firestore TTL, GCS lifecycle, and Storage CORS policies)*
- **Terraform (`>= 1.6.0`, optional)** *(for [`terraform/README.md`](terraform/README.md) IaC provisioning)*

### One-Time `gcloud` Retention & Storage CORS Setup

Run once per environment **after** deploying `firestore.indexes.json` (`firebase deploy --only firestore:indexes`):

```bash
gcloud auth login
gcloud config set project <PROJECT_ID>

# Native Firestore TTL policies (60d access logs, 7d terminal QRs, 30d booking attachments)
gcloud firestore fields ttls update expireAt --collection-group=access_logs --enable-ttl --project=<PROJECT_ID>
gcloud firestore fields ttls update expireAt --collection-group=qr_codes --enable-ttl --project=<PROJECT_ID>
gcloud firestore fields ttls update expireAt --collection-group=booking_attachments --enable-ttl --project=<PROJECT_ID>

# GCS 62d/125d safety-net lifecycle + Web CORS for Transparency downloads
gcloud storage buckets update gs://<STORAGE_BUCKET> --lifecycle-file=storage_lifecycle.json
gcloud storage buckets update gs://<STORAGE_BUCKET> --cors-file=storage_cors.json

# Optional verification
gcloud firestore operations list --project=<PROJECT_ID>
gcloud storage buckets describe gs://<STORAGE_BUCKET> --format="json(lifecycle_config,cors_config)"
```

> **Gen 2 `onCall` Cloud Run Note:** Firebase `onCall` functions verify App Check & Auth in code, so their Cloud Run services require `roles/run.invoker` for `allUsers`. If a callable returns `[firebase_functions/internal] internal [0]` on preflight/ingress, grant `allUsers` invoker access on that lowercase function service while keeping triggers/cron services restricted.

---

## Setup & Configuration

### Option A: Automated Provisioning via Terraform (Recommended)

See [`terraform/README.md`](terraform/README.md):

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Existing project? Inspect & generate imports: node ./generate_imports.js --project <PROJECT_ID>
terraform init && terraform apply
terraform output -raw next_steps
```

### Option B: Manual Setup

1. **Firebase Project & Config**: Create project in [Firebase Console](https://console.firebase.google.com/), enable Auth, Firestore, RTDB, Storage, and Functions, then run `flutterfire configure`.
2. **Vertex AI (Announcement Translation)**: Enable `aiplatform.googleapis.com` and grant `roles/aiplatform.user` to the Cloud Functions runtime service account (`[PROJECT_ID]@appspot.gserviceaccount.com` or Terraform `functions_runtime` SA).
3. **App Check & Crashlytics**:
   - Web: Register **reCAPTCHA Enterprise** site key in Firebase Console -> App Check and set `AppConfig.recaptchaSiteKey` (plus `webPushVapidKey` / `rtdbDatabaseUrl`) in [`lib/core/config/app_config.dart`](lib/core/config/app_config.dart).
   - Android / iOS: Register **Play Integrity** / **App Attest** in App Check.
   - `CrashlyticsService` auto-captures `FlutterError.onError` & `PlatformDispatcher.instance.onError` in release builds (safe no-op in Web, debug, and Emulator modes).
4. **Deploy Rules, Indexes & Functions**:
   ```bash
   firebase deploy --only firestore:indexes,firestore:rules,database,storage,functions
   ```

---

## Architecture & BaaS Abstraction

```
UI Layer (lib/features/*) -> Service Layer (*Service) -> Backend Locator (backend.dart) -> FirebaseBackend (firebase_backend.dart)
```

- `lib/features/` never imports Firebase SDKs directly (enforced by [`test/import_boundary_test.dart`](test/import_boundary_test.dart)).
- Swap Firebase for another backend by implementing `AuthService`, `DatabaseService`, `StorageService`, `FunctionsService`, `CrashlyticsService`, and `NotificationService` from [`lib/core/backend/backend.dart`](lib/core/backend/backend.dart) and registering them in [`lib/main.dart`](lib/main.dart) via `Backend.initialize(...)`.

---

## Development, Testing & CI

### Local Run & Emulators

```bash
flutter pub get
npm --prefix functions install

# Start local emulators & seed addresses, settings, facilities, claims & default users
nvm default
firebase emulators:start --only firestore,database,functions,storage,auth
node scripts/seed_emulator.js   # Or --remote with scripts/serviceAccountKey.json

# Run app (Web localhost auto-connects to emulators; override with --dart-define=USE_FIREBASE_EMULATOR=true)
flutter run
```

### Automated Verification

```bash
flutter gen-l10n && flutter analyze --no-fatal-infos && flutter test
npm --prefix functions test
npm --prefix scripts test
./scripts/run_rollout_tests.sh   # Full emulator rollout (Rules unit tests + Node + Flutter tests)
```

GitHub Actions ([`.github/workflows/ci_tests.yml`](.github/workflows/ci_tests.yml)) runs `flutter gen-l10n`, `flutter analyze --no-fatal-infos`, `flutter test`, `functions` tests, and `scripts` tests on every push and PR.

### Localization (`l10n`) & Launcher Icons

- Add keys in both [`app_en.arb`](lib/l10n/app_en.arb) and [`app_es.arb`](lib/l10n/app_es.arb), then run `flutter gen-l10n`.
- After icon asset updates, run `dart run flutter_launcher_icons`.

### Web Hosting Cache Busting

[`firebase.json.template`](firebase.json.template) sets `Cache-Control: no-cache, no-store, must-revalidate` on `index.html`, `flutter_bootstrap.js`, `flutter_service_worker.js`, `firebase-messaging-sw.js`, `/version.json`, `/manifest.json`, and `/icons/**`. `AppUpdateService` polls `/version.json`, clears `CacheStorage`, and reloads on idle or tab switch.

---

## Admin SDK & Automation Scripts (`scripts/`)

| Script | Purpose | Command Example |
| :--- | :--- | :--- |
| `populate_addresses.js` | Batch import [`addresses_import.csv`](addresses_import.csv) (`street_name,initial_number,final_number,exclusions`) | `node scripts/populate_addresses.js` |
| `set_role.js` | Set custom claims (`admin`, `resident`, `guard`, `roommate`) keeping `addressRef` | `node scripts/set_role.js user@example.com admin [--emulator]` |
| `set_resident_addresses_paid.js` | Mark linked addresses `'paid'` (`--dry-run`, `--emulator`, batches of 400) | `node scripts/set_resident_addresses_paid.js --emulator --dry-run` |
| `seed_emulator.js` | Seed test addresses, settings, facilities, pending claims & users | `node scripts/seed_emulator.js [--remote]` |
| `build_and_publish_docs.js` | Render [`docs/docs_pipeline.json`](docs/docs_pipeline.json) + Mermaid PNGs to PDF & publish to Transparency ([`.github/workflows/docs_pipeline.yml`](.github/workflows/docs_pipeline.yml)) | `npm --prefix scripts run docs:pdf` (`--no-publish`, `--emulator`) |
| `run_rollout_tests.sh` | Zero-touch emulator + Rules + Node + Flutter rollout test suite | `./scripts/run_rollout_tests.sh` |

- For bulk resident CSV creation spec, see [`docs/bulk_user_creation.md`](docs/bulk_user_creation.md) and [`resident_import_template.csv`](resident_import_template.csv).
- End-user operational admin manuals: [`docs/admin_user_manual.md`](docs/admin_user_manual.md) (EN) and [`docs/admin_user_manual_es.md`](docs/admin_user_manual_es.md) (ES).
