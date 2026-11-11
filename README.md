# Suburban Life

A white-label residential management platform built using **Flutter** and **Firebase**. Suburban Life provides secure, multi-platform solutions for residents, security staff, and administrators.

---

## Features

- **Adaptive Admin NavDrawer Workspace**: Persistent left sidebar on desktop (`>= 900px`) and modal hamburger `Drawer` on mobile (`< 900px`) organizing administrative workflows into **Overview** (with pending approval cards and live community KPIs that collapse into expandable cards on mobile, conditional **Visitors currently inside** KPI shown when **Scan on exit** is enabled, 6 quick **Shortcuts** cards, and an Overview-only **Generate Access QR** FAB), collapsible category groups (**User Management**, **Residential Management**, **Finance**, **Transparency & Community**) with roll-up notification badges, and a direct single-tap **General Settings** item.
- **Secure Multi-Role Access Control & Master-Detail Resident Onboarding Approval**: Integrated with Firebase Auth and Cloud Functions, including self-service resident signup with ownership proof capture, compact button-free pending claim cards, and a responsive **Resident Approval Detail** screen with PII-masked applicant email, inline + full-screen 90-degree rotatable document inspection, and privacy-by-design Cloud Storage cleanup upon decision.
- **Bulk Resident & Address Import via CSV**: Administrator bulk creation with temporary passwords and automated claim granting.
- **Address-Level Sanctions System**: Neighborhood infraction issuance with photographic evidence, automated standing restrictions, inline 90-degree rotation and full-screen interactive zoom controls on infraction evidence cards, and direct payment flows.
- **Enhanced Payment Form, Receipt Review & Rejection Recovery**: Strict validation for folio, concept (quota vs sanction), and payment date, advance periods toggle with checklist view, persistent missing-field warnings, admin approval detail screens with inline 90-degree rotation + full-screen 20%-padded zoom controls on both payment receipts and linked sanction evidence (`RotatableImagePreview`), customizable admin rejection reason pool, and one-tap recovery pre-filling for rejected payments.
- **Facility Booking Policies, Cooldowns, Quotas & Documentation Attachments**: Household-scoped (`addressRef`) booking policies supporting either a waiting **Cooldown Period** (`hours | days | months | years` measured from booking end to next booking start) or a calendar **Booking Quota** (`daily | monthly | yearly` max bookings per household in the community timezone), configurable **Amenity Documentation** templates (`mandatory_return`, `optional_return`, or `informative` across `PDF`, `Word`, `Excel`, `JPG`, `PNG`, `WEBP` up to 10 MB with magic-byte verification and `Content-Disposition: attachment`), resident document download and completed-file/photo attachment slots isolated in `booking_attachments/{bookingId}` with automated **30-day post-booking TTL cleanup**, advance anticipation windows, daily operating hours boundaries (`openingTime` - `closingTime`), live quota usage badges, anonymous confirmed-only schedule calendar streaming, admin attachment inspection (including inline rotatable & full-screen previews for image attachments), custom rejection rationale, atomic rejected-booking resubmission (with attachment replacement), and preset approval instruction templates.
- **Rich Media & Emoji Community Announcements**: Broadcast announcements featuring high-resolution banner images, interactive full-screen viewer, quick-access announcement emojis, audience filtering (Everyone / Residents), and keyless Gemini AI Spanish-to-English translations.
- **Collapsible Auto-Saving Admin Settings & SMTP Email Service**: Expandable/collapsible settings cards with real-time auto-save for switches and general settings, plus dedicated manual saving and handshake testing for SMTP server credentials and custom welcome email templates.
- **QR-based Visitor Access, Optional Exit Scanning, Audit Logs & Automated TTL Retention**: Live validation logs, memory-bounded ID and license plate photo capture on entry with automatic local device cleanup immediately after Cloud Storage upload, automated **60-day TTL retention** for `access_logs` and linked Cloud Storage photos (`visitor_ids/**` and `visitor_plates/**` via `onAccessLogDeleted`, daily fallback sweeps, and a 62-day GCS Object Lifecycle safety net), automated **7-day TTL cleanup** for expired/validated/revoked QR passes (preserving active permanent passes and open visits), optional admin-configurable **Scan on exit** (`Escanear para salir`) mode with fast one-tap guard departure logging (supporting automatic entry/exit detection and legacy same-day QR passes), live **INSIDE** badges on resident QR passes, and an administrator audit screen with **Currently Inside** KPIs, entry/exit timestamps, adaptive multi-filter exploration (wrapping `ChoiceChip`s on mobile), wrapping search summary bars, and 20-event batches for unfiltered browsing.
- **User Directory & Account Management**: Unified user and security guard directory with whole-database query search (by street, name, or email), street dropdown and adaptive role filtering (`SegmentedButton` on wide viewports and wrapping `ChoiceChip`s on mobile), wrapping search summary bars, 20-user batched query pagination for unfiltered browsing, and compact button-free summary cards that open a dedicated **User Account Details** screen separating standard actions (password resets, role toggling, delivery date editing) from sensitive actions (address unbinding and account removals).
- **Facility Booking & Document Viewers**: Seamless management of common spaces and important residential files.

---

## Prerequisites

Before configuring and deploying **Suburban Life**, ensure the following SDKs and CLI tools are installed on your workstation:

- **Flutter SDK** (with Dart SDK `^3.9.0`)
- **Node.js `22.x`** (managed via `nvm`, required for Cloud Functions and administrative scripts)
- **Firebase CLI**:
  ```bash
  npm i -g firebase-tools
  ```
- **FlutterFire CLI**:
  ```bash
  dart pub global activate flutterfire_cli
  ```
- **Google Cloud CLI (`gcloud`)**: Required for one-time infrastructure policies that `firebase deploy` does not configure directly (native Cloud Firestore Time-to-Live policies and Google Cloud Storage Object Lifecycle rules). Install via [Google Cloud SDK docs](https://cloud.google.com/sdk/docs/install) (or on macOS via Homebrew):
  ```bash
  brew install --cask google-cloud-sdk
  ```

### Google Cloud CLI (`gcloud`) One-Time Retention Setup

Authenticate `gcloud`, set your target Firebase/GCP project, and apply the Firestore TTL and Cloud Storage lifecycle policies once per environment (run **after** deploying `firestore.indexes.json` via `firebase deploy --only firestore:indexes` so single-field `expireAt` index exemptions are active):

```bash
# 1. Authenticate and select your Firebase/GCP project
gcloud auth login
gcloud config set project <PROJECT_ID>

# 2. Enable native Cloud Firestore TTL policies on `expireAt`
# 60-day Gatehouse access log retention (cascades visitor photo cleanup via onAccessLogDeleted)
gcloud firestore fields ttls update expireAt \
  --collection-group=access_logs \
  --enable-ttl \
  --project=<PROJECT_ID>

# 7-day post-expiration / post-revocation QR pass cleanup
gcloud firestore fields ttls update expireAt \
  --collection-group=qr_codes \
  --enable-ttl \
  --project=<PROJECT_ID>

# 30-day post-booking resident attachment cleanup (cascades file cleanup via onBookingAttachmentDeleted)
gcloud firestore fields ttls update expireAt \
  --collection-group=booking_attachments \
  --enable-ttl \
  --project=<PROJECT_ID>

# 3. Apply Cloud Storage Object Lifecycle safety-net rules (62d visitor media, 125d booking attachments)
gcloud storage buckets update gs://<STORAGE_BUCKET> \
  --lifecycle-file=storage_lifecycle.json

# 4. (Optional) Verify async Firestore TTL operations and active bucket lifecycle config
gcloud firestore operations list --project=<PROJECT_ID>
gcloud storage buckets describe gs://<STORAGE_BUCKET> --format="json(lifecycle_config)"
```

---

## Setup & Configuration

### 1. Create a Firebase Project
1. Navigate to the [Firebase Console](https://console.firebase.google.com/).
2. Click on **Add Project** and name it `Suburban Life` or your community's custom name.
3. Enable **Google Analytics** (optional).
4. Initialize Firebase in this repository by running:
   ```bash
   flutterfire configure
   ```
5. Ensure that **Firebase Auth**, **Cloud Firestore**, **Cloud Storage** and **Cloud Functions** are enabled in the console.

### 2. Setup Vertex AI Permissions (Keyless Server-Side Model Execution)
The Suburban Life platform uses Google Cloud's native Vertex AI platform to translate announcements keylessly (without managing insecure, manual API keys inside Secret Manager). 

To authorize the Cloud Function's runner Service Account to interact with Vertex AI:
1. Navigate to the [IAM & Admin console](https://console.cloud.google.com/iam-admin/iam) in the Google Cloud Platform.
2. Locate the default Compute Engine or Cloud Functions Service Account used by your project:
   - Typically formatted as: `[PROJECT_ID]@appspot.gserviceaccount.com`
3. Grant the **Vertex AI User** (`roles/aiplatform.user`) role to this service account.
4. Enable the **Vertex AI API** (`aiplatform.googleapis.com`) in the APIs & Services dashboard.

### 3. Setup Firebase App Check (for production/release)
App Check protects your backend resources from abuse by verifying that incoming traffic is originating from your actual app.

#### Web Platform (reCAPTCHA Enterprise)
1. Navigate to the **Firebase Console** and select **App Check** in the left navigation.
2. Go to the **Apps** tab, select your Web App, and choose **reCAPTCHA Enterprise**.
3. Generate a public **reCAPTCHA site key** in the Google Cloud / Firebase Console.
4. Open [app_config.dart](lib/core/config/app_config.dart) and update the `recaptchaSiteKey` placeholder with your site key:
   ```dart
   static const String recaptchaSiteKey = 'your-actual-site-key';
   ```

#### Android (Play Integrity)
1. Enable Play Integrity in the **Google Play Console**.
2. In the **Firebase Console** under **App Check** > **Apps**, register Play Integrity for your Android App.

#### iOS (DeviceCheck / App Attest)
1. In the **Firebase Console** under **App Check** > **Apps**, register DeviceCheck or App Attest for your iOS App.

### 4. Firebase Crashlytics & Error Reporting
The app includes automated global exception trapping and error reporting via `CrashlyticsService`:
- **Global Error Hooks**: `FlutterError.onError` intercepts framework build and layout errors, while `PlatformDispatcher.instance.onError` intercepts unhandled asynchronous errors (Futures, timers).
- **Graceful Web Fallback**: On Web (where Crashlytics is currently unsupported or limited), calls are absorbed seamlessly with structured `debugPrint` logs, preventing runtime crashes while keeping the codebase ready for Web Crashlytics support.
- **Collection Gating**: Error reporting is disabled automatically in debug and Firebase Emulator environments (`kDebugMode` or `useFirebaseEmulator: true`).
- **User Association**: Crashlytics user identifiers (`setUserIdentifier`) are synced with Firebase Auth state transitions.

### 5. Enable Gatehouse & Booking Attachment Data Retention (Firestore TTL & Storage Lifecycle)
Gatehouse access logs (`access_logs`) and visitor photos (`visitor_ids/**`, `visitor_plates/**`) are automatically purged after **60 days**, inactive QR passes (`qr_codes`) are purged **7 days** after expiration or deactivation, and resident booking attachments (`booking_attachments` and `booking_attachments/**`) are purged **30 days** after the booking's scheduled end time.

Deploy Firestore indexes (including single-field `expireAt` exemptions), security rules, Storage rules, and Cloud Functions first, then execute the one-time `gcloud` TTL and bucket lifecycle commands listed under [Google Cloud CLI (`gcloud`) One-Time Retention Setup](#google-cloud-cli-gcloud-one-time-retention-setup):
```bash
firebase deploy --only firestore:indexes,firestore:rules,storage,functions
```

---

## Architecture & State Management

The Suburban Life application follows a layered design to decouple the UI from the database provider, allowing for high maintainability and testability.

### Layered Architecture

```
┌────────────────────────────────────────────────────────┐
│                      UI Layer                          │
│     (Flutter Widgets: screens, cards, forms)           │
└──────────────────────────┬─────────────────────────────┘
                           │ Calls
                           ▼
┌────────────────────────────────────────────────────────┐
│                  Service/Logic Layer                   │
│     (e.g., AuthService, PaymentService, QRService)     │
└──────────────────────────┬─────────────────────────────┘
                           │ Interfaces
                           ▼
┌────────────────────────────────────────────────────────┐
│                  BaaS Abstraction Layer                │
│             (backend.dart - locator/interfaces)        │
└──────────────────────────┬─────────────────────────────┘
                           │ Concrete Impls
                           ▼
┌────────────────────────────────────────────────────────┐
│                   Concrete Backend                     │
│ (firebase_backend.dart implementing Backend interfaces)│
└────────────────────────────────────────────────────────┘
```

- **UI Layer**: Composed of Flutter screens, custom widgets, and dialogs.
- **Service/Logic Layer**: Orchestrates complex domain operations (e.g., validating dates, structuring payments, verifying QR rules) before passing them to the database services.
- **BaaS Abstraction**: Defined in [backend.dart](lib/core/backend/backend.dart), providing abstract interfaces for Auth, Database, Storage, and Cloud Functions.
- **Concrete Backend**: Firebase specific services defined in [firebase_backend.dart](lib/core/backend/firebase_backend.dart).

### State Management
State is managed using a clean mix of:
- **Local Widget State**: Enforcing strict lifecycle control on text fields, form validators, and single-card state scopes (e.g., keyed widgets preventing redraws).
- **Streams & Futures**: High-fidelity live bindings to Firestore (e.g., watching payment status, pending approvals, facility bookings) via `StreamBuilder` and `FutureBuilder` to deliver instantaneous database state synchronization.

---

## BaaS Abstraction & Custom Backends

Suburban Life is built with a backend-agnostic abstraction layer. This allows you to easily switch from Firebase to another BaaS (like Supabase, Appwrite, or a custom REST API) without modifying your UI screens.

All interactions with Auth, Database, Storage, and Cloud Functions are routed through the `Backend` service locator in [backend.dart](lib/core/backend/backend.dart).

### Custom Backend Implementation

To plug in a custom backend:
1. Implement the abstract service interfaces:
   - `AuthService`
   - `DatabaseService`
   - `StorageService`
   - `FunctionsService`
2. Initialize the backend in your main entry point [main.dart](lib/main.dart) by calling `Backend.initialize()` with your custom implementations:
   ```dart
   Backend.initialize(
     auth: MyCustomAuthService(),
     db: MyCustomDatabaseService(),
     storage: MyCustomStorageService(),
     functions: MyCustomFunctionsService(),
   );
   ```

By default, the application is pre-configured with Firebase implementations located in [firebase_backend.dart](lib/core/backend/firebase_backend.dart).

---

## Development Workflow

### Local Development Setup

1. Install dependencies:
   ```bash
   flutter pub get
   ```
2. Navigate to the functions folder and install dependencies:
   ```bash
   cd functions
   npm install
   ```

### Running Local Firebase Emulators
To test cloud functions, firestore rules, and authentication flows locally:
1. Ensure the Firebase CLI is installed:
   ```bash
   npm install -g firebase-tools
   ```
2. Start the local emulators:
   ```bash
   firebase emulators:start --only firestore,functions,storage,auth
   ```
3. In a separate terminal, seed the emulator with sample addresses, facilities, settings, announcements, pending payment & ownership claims, and default users (`admin@example.com`, `resident@test.com`, `roommate@test.com`, `guard@test.com`, `applicant@test.com`):
   ```bash
   node scripts/seed_emulator.js
   ```
   *(To seed a remote/staging Firebase project using `scripts/serviceAccountKey.json`, run `node scripts/seed_emulator.js --remote`)*
4. Configure the app to target the emulator backend when running locally (automatically enabled on `localhost` / `127.0.0.1` on Web, or via `--dart-define=USE_FIREBASE_EMULATOR=true`).

### Running the App
Run the application on your target device:
```bash
flutter run
```

### Running Automated Tests

To run the complete suite of Flutter unit, widget, workflow, and architectural boundary tests:
```bash
flutter test
```

To run Cloud Functions callable handler, helper, and static Security Rules audit tests:
```bash
npm --prefix functions test
```

To run Node.js automation script tests:
```bash
npm --prefix scripts test
```

To run the full end-to-end emulator rollout suite (starts Firebase Auth, Firestore, Functions, and Storage emulators, runs live `@firebase/rules-unit-testing` security rules verification, script tests, and all Flutter tests):
```bash
./scripts/run_rollout_tests.sh
```

On GitHub, [`.github/workflows/ci_tests.yml`](.github/workflows/ci_tests.yml) automatically runs `flutter gen-l10n`, `flutter analyze --no-fatal-infos`, `flutter test`, `npm --prefix functions test`, and `npm --prefix scripts test` on every push and pull request.

### Adding Translations (l18n)
All user-facing UI copy must have Spanish translations.
1. Add new keys and English text to [app_en.arb](lib/l10n/app_en.arb).
2. Add the corresponding translation to [app_es.arb](lib/l10n/app_es.arb).
3. Regenerate files using:
   ```bash
   flutter gen-l10n
   ```

### Assets and Branding Icons
If the app icon asset changes, regenerate native icons:
```bash
dart run flutter_launcher_icons
```

### Web Hosting & Automatic Upgrades
When deployed to Firebase Hosting, the web application includes an automated background update mechanism (`AppUpdateService`):
- **Cache-Busting Headers**: `firebase.json` specifies `no-cache, no-store, must-revalidate` for `index.html`, `flutter_bootstrap.js`, `flutter_service_worker.js`, `/version.json`, `/manifest.json`, and `/icons/**`.
- **Seamless Inactivity / Tab-Switch Reload**: The app periodically polls `/version.json` in the background. When a new deployment version is detected, it automatically purges browser `CacheStorage` and refreshes the application seamlessly when the user switches tabs or becomes idle.

---

## Address Population

A template for importing addresses has been included as [addresses_import.csv](addresses_import.csv) in the project root. You can open it in any spreadsheet editor.

### Formatting Guidelines:
*   **`street_name`**: The exact name of the street.
*   **`initial_number`**: The starting house number on that street.
*   **`final_number`**: The ending house number on that street.
*   **`exclusions`**: A comma-separated list of house numbers that do not exist between the initial and final numbers. Leave empty (`""`) if no exclusions exist.

**Example row:**
```csv
"1st Avenue",99,101,"100"
```

---

## Importing Addresses via Admin SDK

A helper script [populate_addresses.js](scripts/populate_addresses.js) is provided in the `scripts/` directory. 

### Prerequisites:
* Ensure `serviceAccountKey.json` is placed in the `scripts/` directory.
* Make sure your [addresses_import.csv](addresses_import.csv) is populated.

### Run the script:
```bash
cd scripts
node populate_addresses.js
```

---

## Assigning User Roles via Admin SDK

Use [set_role.js](scripts/set_role.js) to assign roles (`admin`, `resident`, `guard`, `roommate`) and synchronize Firebase Auth custom claims with Firestore. When promoting an existing resident to `admin`, the script preserves their `resident` claim and residential `addressRef` so they can switch freely between Admin and Resident views.

```bash
# Promote a user to admin in production:
node scripts/set_role.js user@example.com admin

# Assign a role against local Firebase Emulators:
node scripts/set_role.js admin@example.com admin --emulator
```

---

## Batch Address Payment Status Maintenance

A maintenance script [set_resident_addresses_paid.js](scripts/set_resident_addresses_paid.js) iterates through all addresses in Firestore that are already linked to a resident and transitions their `paymentStatus` to `'paid'`.

### Features:
* **Safe Dry-Run Mode**: Inspect matching addresses and preview status transitions without altering Firestore.
* **Firebase Emulator Support**: Run seamlessly against local emulators (`--emulator`) without credentials.
* **Batched Writes**: Updates are committed in chunks of 400 operations to respect Firestore's batch limits.
* **System Address Safeguards**: Safely ignores system offices (`admin_office`).
* **Bidirectional Link Detection**: Detects links via both `addresses.residentUid` and `users.addressRef`.

### Usage:
```bash
# Preview in local emulator (dry-run):
node scripts/set_resident_addresses_paid.js --emulator --dry-run

# Apply in local emulator:
node scripts/set_resident_addresses_paid.js --emulator

# Preview in production:
node scripts/set_resident_addresses_paid.js --dry-run

# Apply in production:
node scripts/set_resident_addresses_paid.js
```

---

## Bulk Resident Account Creation via CSV

Administrators can create resident user accounts in bulk by uploading a CSV file through the app UI or calling the Cloud Function backend.

### Quick Start:
1. Refer to the sample template at [resident_import_template.csv](resident_import_template.csv).
2. Populate the CSV with `name`, `email`, `password` (optional), `street` (optional), and `number` (optional).
3. Open the app as an admin, tap **Bulk User Creation (CSV)** on the dashboard, and select your file.
4. Accounts are created server-side with instant **`resident`** claims (`{ resident: true }`). If `password` is omitted or does not satisfy complexity requirements, the system generates a cryptographically secure password meeting all Firebase Auth complexity rules (uppercase, lowercase, number, symbol, 12 chars).

For complete architectural details, formula specs, and Cloud Function documentation, see [docs/bulk_user_creation.md](docs/bulk_user_creation.md).

For a complete guide to all administrative tools (address import, payment approvals, user directory, amenities configurator, security guard management, and reporting), consult the Administrator User Manual available in:
- [English Administrator User Manual](docs/admin_user_manual.md)
- [Manual de Usuario para Administradores en Español](docs/admin_user_manual_es.md)

---

## Automated Documentation-to-PDF Pipeline & Transparency Sync

The repository includes an automated pipeline ([scripts/build_and_publish_docs.js](scripts/build_and_publish_docs.js)) and GitHub Actions workflow ([.github/workflows/docs_pipeline.yml](.github/workflows/docs_pipeline.yml)) that converts Markdown documentation into branded PDF files with pre-rendered `.png` diagrams and populates them into the **Transparency** section of the app.

### Key Capabilities:
1. **Declarative Document Selection (`parse`)**: Configure which documents to compile and publish in [docs/docs_pipeline.json](docs/docs_pipeline.json) using `"parse": true | false` (or override via CLI `--only=admin_user_manual_es`).
2. **Mermaid Diagram-to-PNG Pre-Rendering**: Extracts `mermaid` blocks, renders high-resolution `.png` images via headless Chromium, and embeds them directly into the branded PDF layout.
3. **Role-Based Document Visibility (`visibility`)**: Each document and folder specifies `"visibility": "admin" | "all"`. All documentation manuals generated by the pipeline (`Manual_Usuario_Administrador_ES.pdf`, `Descripcion_Tecnica_General_ES.pdf`, etc.) and their `official_manuals` folder are configured with `"visibility": "admin"`, restricting access exclusively to administrators in the Transparency UI, Firestore security rules, and Cloud Storage (`/documents/admin_only/`).
4. **Automatic Cloud Storage & Firestore Sync**: Whenever Firebase credentials (`scripts/serviceAccountKey.json` locally, or `FIREBASE_SERVICE_ACCOUNT` / `FIREBASE_SERVICE_ACCOUNT_JSON` secrets in GitHub Actions) are present, running `npm run docs:pdf` or `npm run docs:publish` automatically uploads the generated PDF binaries to Firebase Storage and updates the Firestore `documents` collection.

### Usage:
```bash
cd scripts

# 1. Generate PDFs and automatically upload to Firebase Storage + Firestore (when credentials exist):
npm run docs:pdf
# or explicitly:
npm run docs:publish

# 2. Generate PDFs locally only (skip Firebase upload):
node build_and_publish_docs.js --no-publish

# 3. Publish to local Firebase Emulators:
npm run docs:publish:emulator
```

---

## Automated Pre-Rollout Testing Suite

To ensure flawless operation across all resident and administrative workflows before deployment, run the zero-touch test pipeline:

```bash
./scripts/run_rollout_tests.sh
```

This single command starts the Firebase Emulators, seeds all 170 physical addresses, app settings, amenities, and default test accounts, executes all integration suites (roommate linking, announcements, advance multi-period payments, debt recovery & feature gating, partial settlement, and facility booking lifecycle), and cleanly shuts down the emulator instances upon completion.






