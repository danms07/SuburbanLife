# Suburban Life

A white-label residential management platform built using **Flutter** and **Firebase**. Suburban Life provides secure, multi-platform solutions for residents, security staff, and administrators.

---

## Features

- **Secure Multi-Role Access Control**: Integrated with Firebase Auth and Cloud Functions.
- **Bulk Resident Creation via CSV**: Administrator bulk account creation supporting optional/deterministic temporary password generation and instant resident claims.
- **Configurable SMTP Email Service**: Automated delivery of welcome emails containing login credentials upon user provisioning and bulk import.
- **QR-based Visitor Access**: Live validation logs and ID uploads for security personnel.
- **Facility Booking & Document Viewers**: Seamless management of common spaces and important residential files.
- **AI-Powered Announcement Translations**: Integrated with Gemini 2.5 Flash for automated Spanish-to-English translations.

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
- **Streams & Futures**: High-fidelity live bindings to Firestore (e.g., watching active guard lists, facility bookings) via `StreamBuilder` and `FutureBuilder` to deliver instantaneous database state synchronization.

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
3. Configure the app to target the emulator backend when running locally.

### Running the App
Run the application on your target device:
```bash
flutter run
```

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

## Bulk Resident Account Creation via CSV

Administrators can create resident user accounts in bulk by uploading a CSV file through the app UI or calling the Cloud Function backend.

### Quick Start:
1. Refer to the sample template at [resident_import_template.csv](resident_import_template.csv).
2. Populate the CSV with `name`, `email`, `password` (optional), `street` (optional), and `number` (optional).
3. Open the app as an admin, tap **Bulk User Creation (CSV)** on the dashboard, and select your file.
4. Accounts are created server-side with instant **`resident`** claims (`{ resident: true }`). If `password` is omitted, the system generates a deterministic password (`Suburban#<localPart>2026`).

For complete architectural details, formula specs, and Cloud Function documentation, see [docs/bulk_user_creation.md](docs/bulk_user_creation.md).

For a complete guide to all administrative tools (address import, payment approvals, user directory, amenities configurator, security guard management, and reporting), consult the Administrator User Manual available in:
- [English Administrator User Manual](docs/admin_user_manual.md)
- [Manual de Usuario para Administradores en Español](docs/admin_user_manual_es.md)



