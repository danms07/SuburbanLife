# Changelog

All notable changes to the **Suburban Life** project are documented in this file.

## [1.0.36+37] — 2026-11-17

### Added & Fixed
- **Cloud Storage Web CORS Policy & Prerequisite Setup (`storage_cors.json` & `README.md`)**:
  - Added [`storage_cors.json`](storage_cors.json) configuring `GET`/`HEAD` `Access-Control-Allow-Origin` and exposed response headers on Firebase Cloud Storage so Flutter Web clients (`DocumentCacheService`, `DocumentViewerScreen`) can fetch Transparency `.md`/`.pdf`/`.csv` files without `ClientException: Failed to fetch` CORS blocks, and applied it to the project Storage bucket.
  - Updated `README.md` prerequisites & `gcloud` setup commands (covering `storage_cors.json`, `storage_lifecycle.json`, and Gen 2 Cloud Run `onCall` Public access IAM recovery notes) and added a static audit assertion for `storage_cors.json` in `functions/test/helpers.test.js`.
- **Admin Auth User Directory & Onboarding Visibility (`adminListAuthUsers` & `AdminUserManagementScreen`)**:
  - Added the `adminListAuthUsers` HTTPS callable Cloud Function in `functions/index.js` (protected by `admin` RBAC) using `admin.auth().listUsers()` (`getAuth().listUsers()`) paginated across batches and cross-referenced with Firestore `users` metadata (`hasFirestoreProfile`, `hasAddress`, `onboardingCompleted`) without exposing sensitive fields.
  - Updated `AdminUserManagementScreen` to fetch and merge Auth users with Firestore `users`, render an `Onboarding Incomplete` badge and Auth-only notice on incomplete accounts (`!hasFirestoreProfile` or non-staff accounts missing `addressRef`), and add an `onboarding_incomplete_filter_chip` (`FilterChip`) to isolate incomplete-onboarding users.
- **Admin User Email Updates (`adminUpdateEmail` & `AdminUserDetailScreen`)**:
  - Added `adminUpdateEmail` in `functions/index.js` using `admin.auth().updateUser(uid, { email })` (updating Auth email, validating format via `isValidEmail`, mapping Auth conflict/not-found errors, and syncing `users/{uid}.email` when the Firestore profile exists).
  - Added `EmailValidator` in `lib/core/backend/backend.dart` and an **Update User Email** action (`user_detail_update_email_button`) in `AdminUserDetailScreen`, plus bilingual localization keys (`updateEmailTitle`, `newEmailLabel`, `emailUpdatedSuccess`, `invalidEmailError`, `onboardingIncompleteBadge`, `incompleteOnboardingFilter`, `onboardingIncompleteDetailsNotice`, `authOnlyAccountNotice`) in `app_en.arb` and `app_es.arb`.
  - Updated `functions/test/handlers.test.js` and `test/features/admin/admin_user_management_test.dart` with coverage for `adminListAuthUsers`, `adminUpdateEmail`, incomplete-onboarding filtering, and Auth-only profile visibility.

## [1.0.35+36] — 2026-11-16

### Added & Fixed
- **Sign Out Button on Address Claim / Family Group Onboarding Screen (`lib/main.dart`)**:
  - Added a persistent `TextButton.icon` (`onboarding_logout_button`) at the bottom of `_buildAddressSelectionAndProofForm` calling `Backend.auth.signOut()` with localized `l10n.logout` copy, ensuring newly registered or unassigned users can sign out regardless of whether they are on the **Claim Property** or **Join as Roommate / Family Group** tab (or when no unclaimed addresses are listed).
  - Memoized resident address, ownership claim, and unclaimed address streams in `MyHomePageState` (`_getUnclaimedAddressesStream`, `_getUserAddressesStream`, `_getClaimsStream`) so rebuilding the onboarding screen does not miss initial stream snapshots or re-subscribe `StreamBuilder`s unnecessarily.
  - Added a widget test in `test/widget_test.dart` verifying button visibility across both onboarding tabs and verifying `Backend.auth.signOut()` execution on tap.

## [1.0.34+35] — 2026-11-16

### Changed & Fixed
- **Welcome Message Template Mobile Layout & Default Body Pre-Fill (`AdminSettingsScreen`)**:
  - Replaced the fixed `Row` inside the Custom Welcome Message card in `lib/features/admin/admin_settings_screen.dart` with a responsive `LayoutBuilder` (`< 520px` breakpoint) that renders the description across the full card width and stacks a compact `reset_default_template_button` right-aligned beneath it on mobile devices, eliminating severe vertical text squishing.
  - Updated `_loadSettings()` so that when no custom email body has been persisted in `config/smtp_settings` (`customBody` missing or blank), `_customBodyController.text` automatically pre-fills with the localized `l10n.defaultWelcomeBody`.
  - Added widget tests in `test/features/qr_access/qr_exit_scanner_and_settings_test.dart` covering default template body pre-fill, preservation of saved custom bodies, and Spanish `360x780` mobile layout positioning without overflow or text squishing.

## [1.0.33+34] — 2026-11-16

### Changed & Fixed
- **Financial Reports Screen Rebrand, Reordering & Mobile Overflow Fix (`AdminPaymentReportScreen`)**:
  - Rebranded `downloadReportMenu` and `generateReportTitle` in `lib/l10n/app_en.arb` and `lib/l10n/app_es.arb` from *Download Payment Report* / *Payment Matrix Report* (`Descargar Reporte de Pagos` / `Reporte Matriz de Pagos`) to **Download Financial Reports** / **Financial Reports** (**Descargar Reportes Financieros** / **Reportes Financieros**).
  - Reordered sections in `lib/features/admin/admin_payment_report_screen.dart` so the **Financial Summary Preview** card (`financial_summary_preview_card`) renders at the top below the screen header, followed by the **Start Month** / **End Month** dropdown pickers (`isExpanded: true` with text ellipsis), and all download/publish/bulk-import options grouped at the bottom (stacking secondary buttons cleanly on `< 520px` mobile viewports).
  - Fixed horizontal text overflow inside `_buildFinancialPreviewCard` on narrow mobile viewports (e.g., `"Vista Previa del Resumen Financiero"`) by wrapping the card heading in `Expanded`, adding gap spacing and top alignment to `_PreviewLine`, and applying compact responsive screen/card padding below `600px`.
  - Added Spanish mobile (`360x780`) layout/order/overflow regression test in `test/features/admin/payment_report_matrix_test.dart` and updated label assertions in `test/features/admin/admin_shell_screen_test.dart`.

## [1.0.32+33] — 2026-11-16

### Fixed
- **Mobile Responsive Layout in `AdminBulkPaymentImportScreen`**:
  - Fixed unreadable vertical character-by-character wrapping and overlapping controls in the Starting Period selector on narrow mobile viewports (`< 520px`) by introducing `LayoutBuilder` breakpoints in `lib/features/admin/admin_bulk_payment_import_screen.dart` (`_buildPeriodRangeSelector`) that stack the full-width `Select Starting Period` button below the `Starting Period -> End Period` summary row (and switch to a vertical column below `220px`).
  - Added responsive page/card padding (`12px`/`16px` on `< 600px` mobile vs. `24px`/`20px` on wider viewports) centered within a `960px` `ConstrainedBox`.
  - Stacked template download/copy and results export action buttons cleanly at full width on compact screens (`_buildTemplateActions`, `_buildResultActions`, `_buildResponsiveButtonGroup`) with balanced vertical button padding.
  - Replaced the fixed `Row` in the CSV Preview header (`_buildPreviewHeader`) with a responsive `LayoutBuilder` (`< 560px` vertical stack) to prevent horizontal overflow when previewing imported rows.
  - Wrapped `_pickStartingPeriod` and `_showReconciliationDialog` dialog contents in `SingleChildScrollView`, added `isExpanded: true` to the Month/Year `DropdownButtonFormField`s (plus localized `l10n.ok` button text), and stacked comparison cards vertically on ultra-narrow dialogs (`< 260px`).
- **Automated Responsive Widget Tests (`test/features/admin/admin_bulk_payment_import_test.dart`)**:
  - Added Spanish mobile (`360x780`) and English desktop (`1024x800`) widget layout tests asserting zero overflow exceptions, readable label dimensions, stacked period/template controls on mobile, inline controls on desktop, and overflow-free period picker dialog rendering.

## [1.0.31+32] — 2026-11-16

### Added
- **Admin Expense Recording & Soft-Void Audit System**:
  - Added Cloud Functions `createExpense` and `voidExpense` in `functions/index.js` along with `extractScopedStoragePath`, `extractExpenseStoragePath`, and `validateAndNormalizeExpenseEvidence` enforcing admin RBAC, UID-scoped Storage ownership (`expenses/<uid>/`), magic-byte header inspection (rejecting and deleting spoofed uploads), and immutable soft-void audit metadata (`status: 'voided'`, `voidedBy`, `voidedByName`, `voidedAt`, `voidReason`).
  - Added admin-only Firestore rules for `/expenses/{expenseId}` (`allow read: if isAdmin(); allow write: if false;`), Storage rules for `/expenses/{uploaderUid}/**` (10 MB limit, `isAllowedExpenseEvidence()` for `pdf`/`jpg`/`png`/`webp`), and composite indexes on `expenses` in `firestore.indexes.json`.
  - Created `lib/features/admin/expense_service.dart` (`ExpenseCategory`, `ExpenseEvidence`, `ExpenseRecord`, `ExpenseService`) with CSPRNG Storage path generation, `Content-Disposition: attachment` metadata, Storage object rollback on callable failures, and local temp camera cleanup via `TempImageCleanupService`.
  - Created `lib/features/admin/admin_expenses_screen.dart` (`AdminExpensesScreen`, `AdminExpenseDetailScreen`, `_RecordExpenseModal`, `_VoidExpenseDialog`) with live net accumulated budget strip, period/category/status filters, dual evidence pickers (photo for acquired product/service + image/PDF for receipt/invoice), `RotatableImagePreview` inline rotation + full-screen inspection, PDF view/download delegation, and soft-void workflow.
  - Added `AdminSection.expenses` under **Finance -> Community Expenses** in `AdminShellScreen`.
- **Accumulated Budget Calculator & Multi-Report Financial Export Bundle**:
  - Created `lib/features/admin/financial_report_calculator.dart` (`MonthlyLedgerRow`, `FinancialLedgerResult`, `FinancialReportCalculator`) performing integer-cent precision accounting across approved/paid maintenance quotas, approved/paid sanction fines, active (non-voided) expenses, and configurable opening balances, plus CSV formula injection neutralization (`sanitizeCsvTextCell`), `buildFinancialLedgerCsv`, and PII-free `buildTransparencyMarkdownReport`.
  - Upgraded `AdminPaymentReportScreen` to preview live financial totals (Brought-Forward Balance, Maintenance Income, Sanction Income, Active Expenses, Ending Accumulated Budget) and export a **Multi-Report Financial Bundle** (private Address Payment Status Matrix CSV + Financial Ledger & Accumulated Budget Summary CSV) alongside individual download buttons.
  - Added **Publish Financial Summary to Transparency** dialog (`_PublishTransparencyDialog`) and extended `syncTransparencyDocument` MIME handling (`.md`, `.csv`, `.txt`, images, `.pdf`). **Privacy Guarantee**: Only aggregated community totals and expense summaries are published as Markdown; the address payment status matrix and resident PII are strictly never disclosed publicly.
- **Opening Balance Configuration in General Settings**:
  - Added `initialBudgetBalance` and optional `initialBalancePeriod` (`YYYY-MM`) fields inside the **Payment & Grace Period** card in `AdminSettingsScreen`, persisted via auto-save to `config/app_settings`.
- **Shared Transfer Helpers, Localization & Automated Tests**:
  - Extended `DocumentTransferHelper` with `pickAllowedImage`, `pickExpenseReceipt`, and parameterized `pickAllowedDocument`.
  - Added complete English and Spanish localization keys in `lib/l10n/app_en.arb` and `lib/l10n/app_es.arb` and regenerated `lib/l10n/app_localizations*.dart`.
  - Added backend unit/handler/security rules tests (`functions/test/helpers.test.js`, `functions/test/handlers.test.js`, `functions/test/security_rules.test.js`) and Flutter unit/widget tests (`financial_report_calculator_test.dart`, `expense_service_test.dart`, `admin_expenses_screen_test.dart`, plus updates to `payment_report_matrix_test.dart`, `qr_exit_scanner_and_settings_test.dart`, and `admin_shell_screen_test.dart`).

## [1.0.30+31] — 2026-11-16

### Fixed
- **Web Build & Cross-Platform CSV Upload in `AdminBulkPaymentImportScreen`**:
  - Fixed compilation failure in `lib/features/admin/admin_bulk_payment_import_screen.dart` caused by `FilePicker.platform.pickFiles(...)` (removed in `file_picker ^11.0.2`), which broke `flutter build web`, `flutter analyze`, and Flutter test suites.
  - Added `kIsWeb` HTML file picker (`html.FileUploadInputElement` + `html.FileReader`) on Web and updated native picking to `FilePicker.pickFiles(...)` with disk-path fallback, matching the codebase pattern in `AdminBulkUserImportScreen` and `AdminBulkAddressImportScreen`.
  - Added handling for empty CSV errors (`parsed['error'] == 'empty'`), safe `num` to `int` coercions for Cloud Function summary counts, and replaced the hardcoded template-load error snackbar in `_downloadAllAddressesTemplate` with `l10n.errorPrefix(...)` (resolving the `unused_local_variable` warning).
- **Bulk Payment Import Test Suite (`test/features/admin/admin_bulk_payment_import_test.dart`)**:
  - Escaped the literal `$1,500.00` string interpolation error in the `splitCsvLine` unit test fixture and added parser tests for empty CSVs and semicolon delimiters.
- **Generated Localizations (`lib/l10n/`)**:
  - Regenerated localization outputs via `flutter gen-l10n` to keep generated files synchronized with `app_en.arb` and `app_es.arb`.

## [1.0.29+30] — 2026-11-14

### Added
- **Bulk Previous Payments Import Interface (`AdminBulkPaymentImportScreen`)**:
  - Implemented `lib/features/admin/admin_bulk_payment_import_screen.dart` allowing administrators to upload historical resident payments in bulk via CSV.
  - Added interactive **Starting Period** calendar picker selector defaulting the end period to the current calendar month.
  - Added dual template downloads: **Sample Template** (with dummy amounts) and **All Addresses Template** (pre-populating all registered community addresses with empty month columns).
  - Built client-side parser supporting case-insensitive street matching, bilingual English/Spanish `mmm-yy` periods, monetary amount extraction (`$1,500.00`, `1500`), and empty/0 unpaid handling.
  - Created sequential pre-import reconciliation dialog guiding admins through amount discrepancies (`existingAmount != csvAmount`) to choose "Keep Existing" vs. "Overwrite with CSV" prior to committing.
  - Added comprehensive results reporting displaying summary metrics, color-coded per-address breakdown, and downloadable results CSV export.
- **Callable Cloud Functions for Pre-Check & Bulk Import**:
  - Added `adminPreCheckPaymentImport` in `functions/index.js` to resolve addresses, match existing approved payments, and detect amount mismatches in a single request.
  - Added `adminBulkImportPayments` in `functions/index.js` to batch-create approved `payments` documents, apply reconciliation directives, skip identical periods idempotently, and trigger automatic `recalculateAddressPaymentStatus` on affected addresses.
- **Admin Shell Navigation & Screen Shortcuts**:
  - Activated `AdminSection.importPaymentHistory` in `admin_shell_screen.dart` under the **Finance** menu.
  - Added direct navigation shortcut buttons in `AdminUploadPaymentScreen` and `AdminPaymentReportScreen`.
- **Localization & Automated Tests**:
  - Added complete English and Spanish translation keys in `lib/l10n/app_en.arb` and `lib/l10n/app_es.arb`.
  - Added unit tests in `functions/test/helpers.test.js` and `functions/test/handlers.test.js` verifying period parsing, street normalization, and RBAC enforcement.
  - Added Flutter widget and parser tests in `test/features/admin/admin_bulk_payment_import_test.dart`.

## [1.0.28+29] — 2026-11-13

### Changed
- **Desktop & Keyboard Sign-In Flow on `LoginScreen`**:
  - Added `textInputAction: TextInputAction.done` and `onSubmitted: (_) => _login()` to the password text field across both desktop/wide and mobile layouts, allowing users to authenticate by pressing Enter without having to manually click the Sign In button.
  - Added `textInputAction: TextInputAction.next` to the email text field to advance focus naturally to the password field.
  - Added `if (_isLoading) return;` guard to `_login()` to prevent accidental duplicate submission.
  - Implemented `dispose()` for `_emailController` and `_passwordController` to prevent memory leaks.
- **Automated Widget Tests**:
  - Added widget test in `test/features/auth/auth_screens_test.dart` verifying that submitting the password field triggers the sign-in workflow on desktop web.

## [1.0.27+28] — 2026-11-11

### Added
- **Shared Rotatable Evidence Preview Component (`RotatableImagePreview`)**:
  - Created `lib/core/widgets/rotatable_image_preview.dart` encapsulating `RotatedBox`, `StorageNetworkImage`, full-surface clickable `InkWell`, and the two top-right circular overlay buttons: **Rotate Image (`90°`)** (`Icons.rotate_right`) and **View Full Image** (`Icons.open_in_full`), forwarding the active inline orientation (`initialQuarterTurns`) into `showInteractiveImageDialog`.

### Changed
- **Unified Inline Rotate & Full-Screen Controls Across All Evidence Approval Flows**:
  - **Payment Approval (`AdminPaymentDetailScreen`)**: Upgraded both the primary proof-of-payment receipt viewer and the linked sanction infraction photo viewer (`concept == 'sanction'`) to `RotatableImagePreview`, with constrained scrollable payment metadata on mobile (`<= 650px`) to prevent vertical overflow.
  - **Amenity Booking Approval (`AdminBookingApprovalScreen`)**: Rendered inline `RotatableImagePreview` containers with top-right rotate and full-screen buttons beneath image attachments (`jpg`, `jpeg`, `png`, `webp`) in the **Submitted Documentation** section while preserving `View / Download` actions for all document types.
  - **Sanctions Evidence (`AdminSanctionsScreen` & `SanctionsScreen`)**: Replaced plain `StorageNetworkImage` thumbnails (and removed the legacy hardcoded `'Zoom'` badge in `SanctionsScreen`) with `RotatableImagePreview` so administrators and residents can rotate and expand infraction evidence directly on sanction cards.
  - **Resident Ownership Approval (`AdminResidentDetailScreen`)**: Refactored `buildProofPreview()` to consume the shared `RotatableImagePreview` widget while preserving all existing keys and layout behavior.
- **Automated Widget Tests**:
  - Expanded `test/features/admin/admin_payment_approval_test.dart`, `test/features/admin/admin_booking_approval_test.dart`, and `test/features/sanctions/sanctions_screens_test.dart` to assert inline 90-degree rotation and `initialQuarterTurns` synchronization into the full-screen viewer across receipts, linked sanction evidence, image booking attachments, and sanction cards.

## [1.0.26+27] — 2026-11-10

### Changed
- **Master-Detail Resident Ownership Approval UI (`AdminResidentApprovalScreen` & `AdminResidentDetailScreen`)**:
  - Redesigned `AdminResidentApprovalScreen` (`lib/features/auth/admin_resident_approval_screen.dart`) to match the `AdminPaymentApprovalScreen` master-detail workflow:
    - Added branded `AppConfig.primaryColor` `AppBar` when opened standalone while hiding it seamlessly when embedded inside `AdminShellScreen` (`isEmbedded: true`).
    - Replaced inline approve/reject list cards with compact, button-free, keyed stateful `_ResidentSummaryCard` widgets displaying physical address (`Street #Number`), `Pending Review` status badge, applicant name chip, property handover date chip, and trailing chevron to eliminate accidental mobile misclicks.
    - Added dedicated `AdminResidentDetailScreen` adapting via `LayoutBuilder`: side-by-side split layout (`> 650px`) with expanded ownership proof preview on the left and claim metadata + `Reject` / `Approve Resident` actions on the right, and a stacked vertical layout (`<= 650px`) with constrained scrollable metadata and expanded proof preview on mobile.
    - Masked applicant email addresses (`_maskEmail`) on the detail screen and added a localized privacy-by-design notice (`adminProofDeletionNotice`) explaining automatic Cloud Storage proof deletion upon approval or rejection.

### Added
- **Inline & Full-Screen 90-Degree Rotatable Ownership Proof Viewer (`AdminResidentDetailScreen` & `showInteractiveImageDialog`)**:
  - Added inline 90-degree rotation button (`inline_rotate_image_button` / `inline_proof_rotated_box`) and full-screen expand trigger (`fullscreen_proof_button` / `ownership_proof_thumbnail`) directly on `AdminResidentDetailScreen` so sideways deeds or utility bills can be oriented immediately.
  - Added optional `initialQuarterTurns` parameter to `showInteractiveImageDialog` (`lib/core/widgets/interactive_image_dialog.dart`) so inline rotation carries seamlessly into the full-screen 20%-padded pinch-to-zoom and rotatable viewer.
- **Emulator Seed, Localization & Widget Tests**:
  - Added `unknownAddress`, `residentRejectedSuccess`, and `adminProofDeletionNotice` in `lib/l10n/app_en.arb` and `lib/l10n/app_es.arb`.
  - Updated `scripts/seed_emulator.js` to support unverified (`role: null`) accounts and `quarterTurns` PNG pixel rotation, seeding 3 pending `ownership_claims` (`applicant@test.com`, `applicant2@test.com`, `applicant3@test.com`) with sideways, upside-down, and portrait proof images.
  - Expanded `test/features/auth/auth_screens_test.dart` to test empty state, master-detail summary card navigation, wide `> 650px` side-by-side layout, PII email masking, inline + full-screen 90-degree rotation synchronization, approval workflow, and mobile Spanish rejection workflow.

## [1.0.25+26] — 2026-11-08

### Added
- **Admin Amenity Documentation (`AdminFacilitiesScreen`)**:
  - Administrators can attach multiple facility templates, waivers, guest-list forms, or reference rules (`PDF`, `DOC`, `DOCX`, `XLS`, `XLSX`, `JPG`, `JPEG`, `PNG`, `WEBP` up to 10 MB each) when creating or editing an amenity (`facilities.facilityDocuments[]`).
  - Added per-document requirement modes: `mandatory_return` (resident must attach a completed copy), `optional_return` (optional attachment), and `informative` (download/view reference only).
  - Implemented Cancel-safe staged document editing inside `_EditFacilityDialog`, automatic Cloud Storage cleanup for removed templates on Save, and full `facility_documents/{facilityId}/**` cleanup on facility deletion.
- **Resident Facility Document Download & Booking Attachments (`BookingScreen`, `ManageBookingsScreen`, `FacilityDocumentsSection`)**:
  - Residents can download/view amenity documentation (cached locally via `DocumentCacheService`) and attach completed files or bounded camera photos (`1600px` max + `TempImageCleanupService`) to their booking requests.
  - Enforced client- and server-side blocking when any `mandatory_return` document is missing.
  - Added submitted attachment `ActionChip` viewers and a localized 30-day purged notice (`bookingAttachmentsPurgedNotice`) in `ManageBookingsScreen`, plus attachment preloading and replacement inside `_ResubmitBookingDialog` when resubmitting rejected bookings (`resubmitBookingId`).
  - Added automatic Cloud Storage rollback (`BookingService.rollbackUploadedUrls`) if `createBooking` fails after uploading attachments.
- **Admin Booking Approval Attachment Review (`AdminBookingApprovalScreen`)**:
  - Added real-time **Submitted Documentation** panel streaming `booking_attachments/{bookingId}` with requirement mode badges and one-tap **View / Download** actions before approving or rejecting a request.
- **Security, Privacy Isolation & Automated 30-Day Retention**:
  - Created isolated `booking_attachments/{bookingId}` Firestore collection readable exclusively by administrators, the booking creator (`userUid`), or linked household roommates (`isCallerAddressResident(addressId)`), keeping neighbor-readable `bookings` documents free of private Storage URLs (`hasAttachments`, `attachmentCount`, `attachmentsPurgedAt`).
  - Enforced dual client + server 16-byte magic-byte signature verification (`PDF`, `PNG`, `JPEG`, `WEBP`, `ZIP/OOXML`, `OLE2`), strict exclusion of `SVG` and `HTML` MIME/extensions, CSPRNG Storage object paths, filename path-traversal sanitization, and `Content-Disposition: attachment` metadata headers.
  - Added immediate attachment cleanup in `cancelBooking`, 30-day post-booking Firestore TTL (`booking_attachments.expireAt = endTime + 30d` with single-field index exemption), cascading `onBookingAttachmentDeleted` Cloud Storage cleanup, daily `purgeExpiredBookingAttachments` scheduled fallback sweep (querying indexed `bookingEndTime`), and a 125-day GCS Object Lifecycle rule in `storage_lifecycle.json`.
- **Localization & Automated Tests**:
  - Added 21 English and Spanish localization keys in `lib/l10n/app_en.arb` and `lib/l10n/app_es.arb`.
  - Added unit, widget, Cloud Functions handler/helper, and Security Rules static audit tests across `test/features/booking/booking_documents_test.dart`, `test/features/admin/admin_facilities_test.dart`, `test/features/admin/admin_booking_approval_test.dart`, and `functions/test/`.

### Documentation
- **Project Prerequisites & `gcloud` Retention Provisioning (`README.md`)**:
  - Added a top-level `## Prerequisites` section documenting required SDK/CLI toolchains and installation commands (`Flutter`, `Node.js 22`, `firebase-tools`, `flutterfire_cli`, and Google Cloud CLI `gcloud`).
  - Documented the one-time `gcloud` authentication, native Cloud Firestore TTL policy enablement (`access_logs.expireAt`, `qr_codes.expireAt`, and `booking_attachments.expireAt`), Cloud Storage Object Lifecycle bucket update (`storage_lifecycle.json`), and verification commands, linked from Setup Step 5.

