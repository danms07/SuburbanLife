# Changelog

All notable changes to **Suburban Life** are documented here.

## [1.0.50+51] — 2026-11-23

### Changed (WebAssembly Compatibility)
- Replaced `universal_html` (`dart:html`) with `package:web` (`^1.1.2`) and `dart:js_interop` across all 13 Web call sites to enable full `flutter build web --wasm` compilation and clean Wasm dry runs.
- Extracted shared conditional-import (`dart.library.js_interop`) web bridges: `WebFileTransferHelper` (`web_file_transfer*.dart`, consolidating browser `<input type="file">` picking, sanitized Blob downloads, and `noopener,noreferrer` new-tab opening across helpers/admin/QR/Transparency screens), `AppUpdateWebBridge` (`app_update_web_bridge*.dart`, plus `package:http` for `/version.json`), and `firebase_web_bridge*.dart`.
- Updated `temp_image_cleanup_service.dart`, `cache_io_helper.dart`, `web_image_view*.dart`, `temp_image_cleanup_web.dart`, and `clipboard_image_helper*.dart` to use `dart.library.js_interop` and `package:web`.
- Added Wasm-safe import boundary test in `test/import_boundary_test.dart` and bridge/sanitization unit tests in `test/core/services/core_services_test.dart`.

## [Unreleased] — 2026-11-23

### Changed (Documentation & Agent Token Efficiency)
- Added Context Routing Table and doc-conciseness guidelines in [`AGENTS.md`](AGENTS.md) so agents read only task-relevant docs and avoid multi-file duplication.
- Created [`functions/README.md`](functions/README.md) documenting all 25 `onCall` callables, 10 Firestore triggers, `checkMonthlyPaymentStatuses` daily cron, and `functions/notifications.js`.
- Refactored [`Structure.md`](Structure.md) (~70 KB -> concise index), [`widget_catalog.md`](widget_catalog.md) (~54 KB -> compact component/key catalog), [`README.md`](README.md), [`database_schema.md`](database_schema.md) (added RTDB, Storage prefixes, and missing `documents` visibility indexes while removing duplicate ERD field listings), and `CHANGELOG.md`.
- Updated [`terraform/README.md`](terraform/README.md) links from local filesystem URLs to repository-relative paths.

## [1.0.49+50] — 2026-11-23

### Added
- **Guard QR Scanner Destination Address (`qr_code.dart`, `qr_scanner_screen.dart`, `functions/index.js`)**:
  - Added `destinationAddress` and `QrCode.formatAddressParts` omitting placeholder `'0'` numbers (`admin_office`).
  - Added `formatAccessAddressDisplay` and `openLog.addressDisplay` exit fallback in `validateAndRegisterQrAccess`; `QrScannerScreen` highlights localized `Admin office` / destination address (`ValueKey('qr_scanner_destination_address')`) via payload or Firestore fallback on both entry and exit scans.
  - Added unit/widget tests in `functions/test/helpers.test.js`, `functions/test/handlers.test.js`, `test/features/qr_access/qr_code_model_test.dart`, and `test/features/qr_access/qr_exit_scanner_and_settings_test.dart`.

## [Unreleased] — 2026-11-19

### Added
- **Terraform Firebase & GCP IaC (`terraform/`)**:
  - Provisioned GCP/Firebase project setup, APIs, Web/Android/Apple apps, Hosting, Email/Password Auth, Firestore DB + 33 indexes + 3 TTLs + `firestore.rules`, RTDB, Storage + `storage.rules`, reCAPTCHA Enterprise + App Check, `functions_runtime`/`docs_publisher` SAs, and optional GitHub OIDC WIF.
  - Added [`terraform/generate_imports.js`](terraform/generate_imports.js), [`terraform/generate_imports.test.js`](terraform/generate_imports.test.js), [`terraform/README.md`](terraform/README.md), and `.gitignore` rules (`terraform/imports.tf`).

## [1.0.47+48] — 2026-11-18

### Added & Fixed
- **Cross-Platform Push Notifications & RTDB Inbox (`notifications_screen.dart`, `notification_router.dart`, `functions/notifications.js`, `database.rules.json`)**:
  - Added FCM delivery mirrored to RTDB (`/notifications/{uid}`, `/user_notification_settings/{uid}`) across 7 categories with 30-day / 100-item retention, Android (7 channels), iOS (APNs), Web (`firebase-messaging-sw.js` + VAPID), bell badge (`99+`), dismissible `InAppNotificationBanner`, `NotificationsScreen`, `NotificationPreferencesSheet`, `FakeNotificationService`, and tests.
- **Server-Side Ownership Claim Review**: Replaced client-side claim mutations with `reviewOwnershipClaim` callable (atomic role/address binding, Storage proof cleanup, optional rejection reason, notification dispatch).
- **Transparency Visibility Race Fix**: Promoted folder visibility to `'all'` before updating document visibility so triggers read consistent visibility.

## [1.0.46+47] — 2026-11-18

### Fixed
- **Mobile Web Duplicate Password Eye (`web/index.html`)**: Suppressed native browser `::-ms-reveal` / `::-ms-clear` password icons across mobile browsers; added regression test in `test/features/auth/auth_screens_test.dart`.

## [1.0.45+46] — 2026-11-18

### Added & Fixed
- **Guard Panel Footer & QR Scanner Concurrency Locks (`main.dart`, `qr_scanner_screen.dart`)**:
  - Added `AppVersionLabel` (`guard_app_version_label`) in Guard panel footer and `_isOpeningQrScanner` double-tap guard.
  - Added `_isValidating`, `_isCapturingPhoto`, `_isUploadingImages`, `_activeValidationToken`, disabled `_isBusy` controls, and blocking `qr_scanner_loading_overlay`; verified via `Completer` tests in EN/ES.

## [1.0.44+45] — 2026-11-18

### Added
- **Drawer Version Labels (`app_version_label.dart`, `main.dart`, `admin_shell_screen.dart`)**: Bundled `web/version.json` asset and rendered cached localized `AppVersionLabel` (`resident_app_version_label`, `admin_app_version_label`) below Logout in EN/ES drawers; added tests in `core_services_test.dart`, `widget_test.dart`, and `admin_shell_screen_test.dart`.

## [1.0.43+44] — 2026-11-18

### Changed
- **Admin Booking Approval Master-Detail (`admin_booking_approval_screen.dart`)**: Split inline queue cards into button-free `_BookingSummaryCard` (`booking_card_<bookingId>`) -> responsive `AdminBookingDetailScreen` (`> 650px` side-by-side **Submitted Documentation** pane, `<= 650px` stacked), with Spanish `360x760` layout/test updates.

## [1.0.42+43] — 2026-11-18

### Fixed
- **Callable Serialization (`createBooking`)**: Added `toSerializableBookingResponse` omitting Firestore `DocumentReference` (`addressRef`) to prevent `onCall` JSON HTTP 500 errors and false Storage rollbacks.
- **Flutter 3.50 / Dart 3.14 Compatibility & Lints**:
  - Migrated `clipboard_image_helper_web.dart` from `dart:js_util` to `dart:js_interop` extension types.
  - Bound non-nullable `uploadBytes` across async gap in `transparency_screen.dart`.
  - Migrated `RadioGroup<String>` (`admin_resident_registration_screen.dart`), `SharePlus.instance.share(ShareParams(...))` (`document_viewer_screen.dart`), `QrEyeStyle`/`QrDataModuleStyle` (`qr_generator_screen.dart`), `mounted`/`context.mounted` guards, `super.key`, public `State<T>`, and `analysis_options.yaml` exclusions. *(Evaluated and reverted `material_ui` migration due to `flutter_markdown` `ThemeData` and `flutter_localizations` collisions; 94 `deprecated_member_use` infos allowed by `--no-fatal-infos`.)*

## [1.0.41+42] — 2026-11-17

### Changed
- **Sanctions Portrait Wrapping (`admin_sanctions_screen.dart`)**: Replaced horizontal scroll filter bar with multi-row `Wrap` for all 5 `FilterChip`s and responsive `Wrap` card headers (`360x800` EN/ES portrait tests).

## [1.0.40+41] — 2026-11-17

### Fixed
- **Admin Sanctions Copy & Modal (`admin_sanctions_screen.dart`)**: Added community-wide `adminNoSanctions` / `adminNoActiveSanctions`, `uploadEvidencePhoto` label, and `Expanded` modal header wrapping.

## [1.0.39+40] — 2026-11-17

### Changed
- **User Directory FAB & Pull-to-Refresh (`admin_user_management_screen.dart`)**: Replaced header/icon refresh buttons with `FloatingActionButton.extended` (`manage_users_create_user_button`) and cross-device `RefreshIndicator` (`manage_users_refresh_indicator`).

## [1.0.38+39] — 2026-11-17

### Added
- **CSV Template Downloads (`csv_download_helper.dart`)**: Added cross-platform sanitized `CsvDownloadHelper` and responsive **Download CSV Template** buttons on `AdminBulkAddressImportScreen` and `AdminBulkUserImportScreen`.

## [1.0.37+38] — 2026-11-17

### Added
- **Bilingual Financial Transparency & Explorer Localization**:
  - Published single bilingual (`en`/`es`) financial summary `documents/{docId}` entries (`translatedTitles`, `translatedFiles`, epoch-versioned filenames, `syncTransparencyDocument` Storage cleanup).
  - Added `TransparencyLocalizationHelper` hybrid system-folder/category resolution and `DocumentViewerScreen` `ES | EN` `SegmentedButton` switcher with stale-request guarding.

## [1.0.36+37] — 2026-11-17

### Added
- **Storage Web CORS (`storage_cors.json`)**: Enabled `GET`/`HEAD` browser fetches from Firebase Hosting/Web clients + documented `gcloud` & Gen 2 Cloud Run invoker setup.
- **Auth User Directory & Email Edit (`adminListAuthUsers`, `adminUpdateEmail`)**: Merged Firebase Auth users with Firestore profiles to flag `Onboarding Incomplete` accounts and allow admin email updates.

## [1.0.35+36] — 2026-11-16

### Added & Fixed
- **Onboarding Sign Out (`main.dart`)**: Added `onboarding_logout_button` across Claim/Roommate tabs and memoized onboarding streams.

## [1.0.34+35] — 2026-11-16

### Changed
- **Welcome Email Template Layout (`admin_settings_screen.dart`)**: Pre-filled `defaultWelcomeBody` when unset and stacked reset button cleanly `< 520px`.

## [1.0.33+34] — 2026-11-16

### Changed & Fixed
- **Financial Reports Rebrand & Layout (`admin_payment_report_screen.dart`)**: Rebranded to *Financial Reports*, moved KPI summary card to top, and fixed narrow mobile text overflow.

## [1.0.32+33] — 2026-11-16

### Fixed
- **Bulk Payment Import Mobile Layout (`admin_bulk_payment_import_screen.dart`)**: Added `< 520px` / `< 600px` breakpoints for period selector, buttons, preview header, and scrollable reconciliation/period dialogs.

## [1.0.31+32] — 2026-11-16

### Added
- **Admin Expenses, Accumulated Budget & Multi-Report Financial Export (`admin_expenses_screen.dart`, `expense_service.dart`, `financial_report_calculator.dart`, `functions/index.js`)**:
  - Added `createExpense` / `voidExpense` callables (magic-byte + UID Storage path validation), `/expenses` rules/indexes, dual evidence capture, integer-cent accumulated budget KPIs & CSV bundle (`CWE-1236` sanitized), PII-free Markdown summary publishing, and Opening Balance settings (`initialBudgetBalance` / `initialBalancePeriod`).

## [1.0.30+31] — 2026-11-16

### Fixed
- **Web File Picker Fix (`admin_bulk_payment_import_screen.dart`)**: Replaced removed `FilePicker.platform.pickFiles` API with `kIsWeb` HTML picker + `FilePicker.pickFiles`.

## [1.0.29+30] — 2026-11-14

### Added
- **Bulk Historical Payment Import (`admin_bulk_payment_import_screen.dart`, `adminPreCheckPaymentImport`, `adminBulkImportPayments`)**: Interactive period range picker, dual CSV templates, EN/ES `mmm-yy` parser, sequential mismatch reconciliation, and results CSV export.

## [1.0.28+29] — 2026-11-13

### Changed
- **Login Keyboard Submit (`login_screen.dart`)**: Added `TextInputAction.next`/`.done`, `onSubmitted`, duplicate-submit guard, and controller disposal.

## [1.0.27+28] — 2026-11-11

### Added & Changed
- **`RotatableImagePreview` (`rotatable_image_preview.dart`)**: Shared inline `90°` rotate + full-screen zoom component unified across Payment, Booking, Sanctions, and Resident Approval screens.

## [1.0.26+27] — 2026-11-10

### Added & Changed
- **Resident Approval Master-Detail & Proof Rotation (`admin_resident_approval_screen.dart`, `interactive_image_dialog.dart`)**: Keyed `_ResidentSummaryCard` queue -> responsive `AdminResidentDetailScreen` with masked email, inline/full-screen `initialQuarterTurns` rotation, proof-deletion notice, and rotated emulator seed claims.

## [1.0.25+26] — 2026-11-08

### Added
- **Facility Documentation, Booking Attachments & Retention**:
  - Admin `facilityDocuments` templates (`mandatory_return`, `optional_return`, `informative`), household/admin-isolated `booking_attachments/{bookingId}`, dual magic-byte verification, rejection resubmission with attachment replacement, `cancelBooking` Storage purge, 30d/7d/60d Firestore TTLs + triggers (`onBookingAttachmentDeleted`, `onAccessLogDeleted`), 62d/125d GCS lifecycle rules, and `README.md` `gcloud` prerequisite guide.
