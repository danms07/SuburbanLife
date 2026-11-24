# Directory Structure

*Last Verified/Updated: 2026-11-23 (v1.0.49+50 — Agent-Optimized Documentation)*

Concise map of repository files and primary symbols. See [`AGENTS.md`](AGENTS.md) for which deep doc to read per task.

---

## Root & Configuration

- `AGENTS.md`: Agent coding rules, workflow checklist, and context routing table.
- `README.md`: Project overview, SDK prerequisites, setup, BaaS architecture, CLI scripts, and test commands.
- `Structure.md`: This concise repository index and architectural rules.
- `database_schema.md`: Firestore collections/indexes/TTLs, RTDB notification schema, and Storage rules map.
- `widget_catalog.md`: Reusable UI widgets, layout breakpoints, and test `ValueKey`s.
- `CHANGELOG.md`: Chronological release history.
- `PRIVACY_POLICY.md`: Bilingual LFPDPPP/ARCO privacy notice.
- `pubspec.yaml` / `l10n.yaml` / `analysis_options.yaml`: Flutter dependencies, app version (`1.0.49+50`), l10n codegen, and analyzer exclusions.
- `firebase.json.template`: Firebase deployment & emulator port config template (`firebase.json` is gitignored).
- `firestore.rules` / `firestore.indexes.json`: Firestore security rules, 33 composite indexes, and 3 `expireAt` single-field exemptions.
- `database.rules.json`: RTDB owner-only notification & preference rules.
- `storage.rules` / `storage_cors.json` / `storage_lifecycle.json`: Storage access/MIME/10 MB rules, CORS policy, and 62d/125d GCS lifecycle rules.
- `flutter_launcher_icons.yaml` / `addresses_import.csv` / `resident_import_template.csv`: Icon generator config and CSV templates.
- `.github/workflows/`:
  - `ci_tests.yml`: CI (`flutter gen-l10n`, `flutter analyze --no-fatal-infos`, `flutter test`, `functions/` tests, `scripts/` tests).
  - `docs_pipeline.yml`: Renders `docs/*.md` + Mermaid diagrams into PDFs and publishes to Transparency.

## Platform Assets & Documentation

- `android/`: Android Gradle setup, permissions (`POST_NOTIFICATIONS`), and 7 FCM channels (`MainActivity.kt`).
- `ios/`: iOS Xcode setup, APNs push entitlement (`Runner.entitlements`), and `AppDelegate.swift` notification delegate.
- `assets/icon/`: `app_launcher_icon.png`, `app_logo.png`, `app_icon.png`.
- `web/`: `index.html` (with Edge/mobile password reveal CSS suppression), `firebase-messaging-sw.js` (FCM Web worker), `manifest.json`, `favicon.png`, `icons/`, `version.json`.
- `docs/`: *End-user/admin PDF sources & future plans (skip during coding tasks unless editing docs pipeline).*
  - `docs_pipeline.json`: PDF build/Transparency publish manifest; outputs live under `docs/pdf/`.
  - `admin_user_manual.md` / `admin_user_manual_es.md`: Operational administrator manuals (EN/ES).
  - `technical_overview.md` / `technical_overview_es.md`: Non-technical architecture/security overviews (EN/ES).
  - `bulk_user_creation.md`: Bulk CSV resident creation spec & formula reference.
  - `plans/`: `biometric_auth_plan.md`, `credential_manager_plan.md`.
- `mockups/Resident/home.md`: Initial home UI placeholder notes.

## Backend, Infrastructure & Scripts

- `functions/`: Node.js 24 Cloud Functions v2 (detailed in [`functions/README.md`](functions/README.md)).
  - `index.js`: 25 `onCall` callables, 10 Firestore triggers, and `checkMonthlyPaymentStatuses` daily cron.
  - `notifications.js`: Notification category/route validation, bilingual builders, FCM multicast + token pruning, RTDB mirror/pruner.
  - `brand_config.js`: Brand color/typography constants shared with emails/PDFs.
  - `test/`: `helpers.test.js`, `notifications.test.js`, `handlers.test.js`, `security_rules.test.js` (`npm --prefix functions test`).
- `scripts/`: Admin SDK & automation utilities (documented in [`README.md`](README.md)).
  - `build_and_publish_docs.js`: Puppeteer/Mermaid Markdown-to-PDF compiler & Transparency publisher.
  - `seed_emulator.js`: Local emulator & remote staging database/Storage seeder.
  - `set_role.js` / `populate_addresses.js` / `set_resident_addresses_paid.js`: Role/claim, address CSV, and payment batch scripts.
  - `run_rollout_tests.sh`: Full Firebase Emulator + rules + Node + Flutter test runner.
  - `test/`: `build_and_publish_docs.test.js`, `set_resident_addresses_paid.test.js`, `set_role.test.js`.
- `terraform/`: GCP & Firebase IaC suite (detailed in [`terraform/README.md`](terraform/README.md)).
  - `versions.tf`, `providers.tf`, `variables.tf`, `project.tf`, `apis.tf`, `apps.tf`, `auth.tf`, `firestore.tf`, `database.tf`, `storage.tf`, `appcheck.tf`, `iam.tf`, `outputs.tf`, `terraform.tfvars.example`.
  - `generate_imports.js` / `generate_imports.test.js`: Read-only GCP/Firebase importer (`node --test`).

## Flutter Application (`lib/`)

- `main.dart`: `MyApp`, `MyHomePage` (Resident dashboard/drawer, Guard panel + footer, Admin wrapper, unlinked onboarding, foreground notification banner), global Crashlytics hooks.
- `firebase_options.dart`: Generated `DefaultFirebaseOptions` (`flutterfire configure`).
- `l10n/`: `app_en.arb`, `app_es.arb`, and generated `app_localizations*.dart` (`flutter gen-l10n`).
- `core/`:
  - `backend/backend.dart`: BaaS interfaces (`AuthService`, `DatabaseService`, `StorageService`, `FunctionsService`, `CrashlyticsService`, `NotificationService`), models (`AppUser`, `AppNotification`, `UserNotificationSettings`), query/mutation types, validators (`PasswordValidator`, `EmailValidator`), `Backend` locator.
  - `backend/firebase_backend.dart`: Firebase implementations (`FirebaseAuthService`, `FirebaseDatabaseService`, `FirebaseStorageService`, `FirebaseFunctionsService`, `FirebaseCrashlyticsService`, `FirebaseNotificationService`, `FirebaseBackend`).
  - `config/app_config.dart`: Palette, typography, branding assets, reCAPTCHA/VAPID/RTDB config, `useFirebaseEmulator` toggle.
  - `services/`:
    - `app_update_service.dart`: `AppUpdateService` web `/version.json` polling and CacheStorage reload.
    - `cache_io_helper*.dart`: Conditional cross-platform cache I/O (`cache_io_helper_io.dart`, `cache_io_helper_web.dart`, `cache_io_helper_stub.dart`).
    - `csv_download_helper.dart`: `CsvDownloadHelper` sanitized native file export and web Blob download.
    - `document_cache_service.dart`: `DocumentCacheService` cached download/eviction manager.
    - `document_transfer_helper.dart`: `DocumentTransferHelper` & `PickedDocumentData` (cross-platform picker, magic-byte validation, bounded camera capture, CSPRNG Storage paths).
    - `notification_router.dart`: `NotificationRouter` allow-listed deep linking from notifications.
    - `temp_image_cleanup*.dart`: `TempImageCleanupService` cross-platform temp camera capture & Web `blob:` cleanup (`_io`, `_web`, `_stub`).
  - `widgets/`:
    - `app_version_label.dart`: `AppVersionLabel` reading bundled `web/version.json`.
    - `error_fallback_screen.dart`: `ErrorFallbackScreen` release `ErrorWidget.builder` UI.
    - `interactive_image_dialog.dart`: `showInteractiveImageDialog` full-screen zoom/pan/90° rotation modal.
    - `rotatable_image_preview.dart`: `RotatableImagePreview` card with inline 90° rotate & full-screen buttons.
    - `storage_network_image.dart`: `StorageNetworkImage` cross-platform cached/network image widget.
    - `web_image_view*.dart`: Conditional `HtmlElementView` adapter for Web CORS images (`_web`, `_stub`).
- `features/`:
  - `admin/`:
    - `admin_shell_screen.dart`: `AdminShellScreen` & `AdminSection` responsive sidebar/drawer workspace, roll-up badges, Overview KPIs & shortcuts.
    - `admin_access_logs_screen.dart`: `AdminAccessLogsScreen` gatehouse audit viewer, filters, 20-item pagination, Currently Inside KPIs.
    - `admin_booking_approval_screen.dart`: `AdminBookingApprovalScreen` & `AdminBookingDetailScreen` master-detail booking & attachment review.
    - `admin_bulk_address_import_screen.dart`: `AdminBulkAddressImportScreen` CSV address range creator.
    - `admin_bulk_payment_import_screen.dart`: `AdminBulkPaymentImportScreen` historical payment CSV importer with mismatch reconciliation.
    - `admin_bulk_user_import_screen.dart`: `AdminBulkUserImportScreen` bulk resident CSV creator.
    - `admin_create_user_screen.dart`: `AdminCreateUserScreen` single Resident/Guard/Admin account form.
    - `admin_expenses_screen.dart`: `AdminExpensesScreen` & `AdminExpenseDetailScreen` expense ledger, dual-evidence capture, soft-void flow.
    - `admin_facilities_screen.dart`: `AdminFacilitiesScreen` amenity settings, cooldown/quota rules, and staged document templates.
    - `admin_payment_approval_screen.dart`: `AdminPaymentApprovalScreen` & `AdminPaymentDetailScreen` master-detail receipt & linked sanction review.
    - `admin_payment_report_screen.dart`: `AdminPaymentReportScreen` accumulated budget KPIs, CSV matrix/ledger exports, PII-free Transparency publishing.
    - `admin_resident_registration_screen.dart`: `AdminResidentRegistrationScreen` direct resident/roommate assignment.
    - `admin_settings_screen.dart`: `AdminSettingsScreen` 5 collapsible cards (payment/opening balance, QR exit, rejection reasons, SMTP, welcome email).
    - `admin_upload_payment_screen.dart`: `AdminUploadPaymentScreen` admin-on-behalf payment proof uploader.
    - `admin_user_management_screen.dart`: `AdminUserManagementScreen` & `AdminUserDetailScreen` Auth+Firestore directory, filters, account actions.
    - `expense_service.dart`: `ExpenseCategory`, `ExpenseEvidence`, `ExpenseRecord`, `ExpenseService` (`createExpense`/`voidExpense` + Storage rollback).
    - `financial_report_calculator.dart`: `MonthlyLedgerRow`, `FinancialLedgerResult`, `FinancialReportCalculator` integer-cent accounting, CWE-1236 CSV sanitization, bilingual Markdown export.
  - `announcements/`:
    - `announcement.dart`: `Announcement` model (images, translations, audience, `readBy`).
    - `announcements_screen.dart`: `AnnouncementsScreen` responsive feed and rich media/emoji publishing modal.
    - `clipboard_image_helper*.dart`: Web clipboard image & paste listener (`clipboard_image_helper_web.dart` via `dart:js_interop`, `_stub.dart`).
  - `auth/`:
    - `auth_service.dart`: Re-exports `AuthService` from `backend.dart`.
    - `login_screen.dart` / `signup_screen.dart` / `forgot_password_screen.dart`: `LoginScreen`, `SignupScreen`, `ForgotPasswordScreen`.
    - `ownership_proof_screen.dart`: `OwnershipProofScreen` handover date & proof capture overlay.
    - `admin_resident_approval_screen.dart`: `AdminResidentApprovalScreen` & `AdminResidentDetailScreen` master-detail ownership claim review.
    - `roommates_screen.dart`: `RoommatesScreen` family group management with camera QR scanner.
  - `booking/`:
    - `facility_document_models.dart`: `FacilityDocRequirementMode`, `FacilityDocumentTemplate`, `DraftBookingAttachment`, `SubmittedBookingAttachment`, validation helper.
    - `booking_service.dart`: `BookingRestrictionConfig`, `BookingRestrictionEvaluation`, `BookingService` cooldown/quota math & booking submission/rollback.
    - `booking_screen.dart`: `BookingScreen` hours/quota/cooldown/mandatory-doc validation & confirmed calendar stream.
    - `manage_bookings_screen.dart`: `ManageBookingsScreen` booking list, approval instructions, attachment chips, rejected resubmission.
    - `widgets/facility_documents_section.dart`: `FacilityDocumentsSection` template download & resident return-file/photo capture card.
  - `notifications/`:
    - `notifications_screen.dart`: `NotificationBellButton`, `InAppNotificationBanner`, `NotificationsScreen`, `NotificationPreferencesSheet`.
  - `payments/`:
    - `payment_service.dart`: `PaymentService` billing periods, proof upload, grace period & address status recalculation.
    - `payment_screen.dart`: `PaymentScreen` monthly quota/sanction form, advance periods, rejection recovery banner.
  - `qr_access/`:
    - `qr_code.dart`: `QrType`, `QrCode`, `formatAddressParts` (`admin_office` `'0'` suppression).
    - `qr_service.dart`: `QrService` QR stream, status resolution, `isVisitorInside`, pass revocation.
    - `qr_generator_screen.dart` / `manage_qr_screen.dart`: `QrGeneratorScreen` branded PNG card share/download; `ManageQrScreen` pass list & `INSIDE` badges.
    - `qr_scanner_screen.dart`: `QrScannerScreen` concurrency-locked guard scanner, entry/exit detection, destination display, bounded photo capture.
  - `sanctions/`:
    - `sanctions_screen.dart` / `admin_sanctions_screen.dart`: `SanctionsScreen` resident view & payment redirect; `AdminSanctionsScreen` filter chips, issuance modal, evidence preview.
  - `transparency/`:
    - `transparency_localization_helper.dart`: `TransparencyLocalizationHelper` bilingual folder/category/doc/cleanup resolution.
    - `transparency_screen.dart`: `TransparencyScreen` hierarchical file explorer, role visibility, upload/move/category controls.
    - `document_viewer_screen.dart`: `DocumentViewerScreen` Markdown/text reader with `ES | EN` language switcher.
    - `widgets/`: `file_explorer_breadcrumb.dart` (`BreadcrumbItem`, `FileExplorerBreadcrumb`), `folder_card.dart` (`FolderCard`), `document_card.dart` (`DocumentCard`).

## Tests (`test/` & `test_driver/`)

- `test_driver/integration_test.dart`: Flutter Driver integration runner.
- `test/helpers/fake_backend.dart`: In-memory `FakeBackend` + `FakeNotificationService` test doubles.
- `test/import_boundary_test.dart`: Enforces BaaS import boundaries, zero `print()`, zero `.withOpacity()`, `initialValue:` usage, and EN/ES ARB key parity.
- `test/widget_test.dart`: `MyHomePage` role switching, drawers, `AppVersionLabel`, and onboarding logout tests.
- `test/integration/rollout_workflow_test.dart`: End-to-end resident, booking, payment, sanction, and admin workflows.
- `test/core/`: `backend/backend_models_test.dart`, `crashlytics_service_test.dart`, `services/core_services_test.dart`, `services/temp_image_cleanup_test.dart`.
- `test/features/`:
  - `admin/`: `access_logs_filter_test.dart`, `admin_booking_approval_test.dart`, `admin_bulk_payment_import_test.dart`, `admin_create_user_test.dart`, `admin_expenses_screen_test.dart`, `admin_facilities_test.dart`, `admin_payment_approval_test.dart`, `admin_shell_screen_test.dart`, `admin_user_management_test.dart`, `bulk_address_csv_parser_test.dart`, `bulk_user_csv_parser_test.dart`, `expense_service_test.dart`, `financial_report_calculator_test.dart`, `payment_report_matrix_test.dart`.
  - `announcements/`: `announcement_model_test.dart`.
  - `auth/`: `auth_screens_test.dart`, `password_validation_test.dart`.
  - `booking/`: `booking_documents_test.dart`, `booking_service_test.dart`.
  - `notifications/`: `notifications_screen_test.dart`.
  - `payments/`: `payment_screen_test.dart`, `payment_service_test.dart`.
  - `qr_access/`: `qr_camera_selector_test.dart`, `qr_code_model_test.dart`, `qr_exit_scanner_and_settings_test.dart`, `qr_service_test.dart`.
  - `sanctions/`: `sanctions_screens_test.dart`.
  - `transparency/`: `transparency_explorer_test.dart`.

---

## Architectural Decisions & Coding Guidelines

1. **Feature-First Organization**: Domain modules under `lib/features/`, shared infrastructure/widgets under `lib/core/`.
2. **Strict Backend Abstraction**: `lib/features/` must never import Firebase SDKs directly; route all backend operations through `lib/core/backend/backend.dart` (enforced by `import_boundary_test.dart`).
3. **App Check**: Production callables enforce App Check; Emulator mode disables enforcement automatically.
4. **Console Output**: Never use `print()`; always use `debugPrint()`.
5. **Localization**: All user-facing copy must live in `app_en.arb` + `app_es.arb` and be accessed via `AppLocalizations.of(context)`.
