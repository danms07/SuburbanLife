# Directory Structure

*Last Verified/Updated: 2026-09-28 (Added sanctions module, facility operating hours, booking approval instructions, and expanded test suites)*

Current state of project files and folders:

- `android/`: Native Android configuration and build files (including Google Services & Crashlytics Gradle plugins).
- `assets/`: Application asset directories.
    - `icon/`: Launcher and branding icon assets.
        - `app_launcher_icon.png`: Dedicated icon asset for mobile app launchers (Android, iOS, Web).
        - `app_logo.png`: Dedicated branding logo asset used across in-app UI surfaces (navigation drawer header, QR share cards).
        - `app_logo_1.png`: Alternate branding logo asset backup.
        - `app_icon.png`: Legacy master high-resolution icon asset.
- `docs/`: Technical plans and documentation archives.
    - `technical_overview.md`: Comprehensive technical description of the app, architecture, security measures, and data handling for non-technical users (English).
    - `technical_overview_es.md`: Comprehensive technical description of the app, architecture, security measures, and data handling for non-technical users (Spanish).
    - `admin_user_manual.md`: Comprehensive operational User Manual for system administrators (English).
    - `admin_user_manual_es.md`: Comprehensive operational User Manual for system administrators (Spanish).
    - `bulk_user_creation.md`: Complete guide and Cloud Function spec for bulk resident creation via CSV.
    - `plans/`: Future implementation plans.
        - `biometric_auth_plan.md`: Plan for persistent biometric gating.
        - `credential_manager_plan.md`: Plan for Passkeys and Credential Manager integration.
- `firebase.json.template`: Baseline Firebase project deployment configuration template mapping Firestore rules, Storage rules, functions, composite indexes, emulators, and Hosting Cache-Control headers (untracked `firebase.json` holds local and FlutterFire project bindings).
- `firestore.rules`: Hardened security rules for Cloud Firestore collections with type safety checks, status alignment, readBy array protection, and admin-only gating for config/smtp_settings.
- `firestore.indexes.json`: Comprehensive composite index definitions for Firestore queries (bookings, payments, qr_codes, documents, access_logs).
- `storage.rules`: Security rules for Firebase Cloud Storage buckets.
- `flutter_launcher_icons.yaml`: Configuration for generating platform-specific launcher icons.
- `functions/`: Cloud Functions for Firebase.
    - `index.js`: Core function logic holding Gemini translations, address-based access restriction, address unbinding, own-account deletion, roommate account linking, admin user creation (initializing residential addresses with 'paid' status and deferring recalculation to checkMonthlyPaymentStatuses to allow admins time to upload receipts), admin bulk resident creation (with in-memory address caching), bulk address CSV creation, SMTP connection testing, onPaymentWritten auto-recalculation trigger, checkMonthlyPaymentStatuses daily 00:00 CST scheduled job, bounded createBooking clashes query, and automated welcome email dispatch adhering to AppConfig branding colors and typography.
    - `brand_config.js`: Centralized brand color palette and typography constants mirroring `AppConfig` for HTML email templates.
- `ios/`: Native iOS configuration and build files.
- `LICENSE`: MIT No Attribution (MIT-0) license file.
- `PRIVACY_POLICY.md`: Bilingual Privacy Policy (LFPDPPP/ARCO compliant).
- `lib/`: Main Flutter source code.
    - `core/`: Core configuration and themes.
        - `backend/`: Agnostic BaaS service abstractions and service locator.
            - `backend.dart`: Base interfaces for Auth, Database (with `limit` and `startAfter` cursor pagination), Storage, Cloud Functions, and Crashlytics (`CrashlyticsService`).
            - `firebase_backend.dart`: Firebase concrete implementations of backend interfaces (including `FirebaseCrashlyticsService` with `kIsWeb` safety guard).
        - `config/app_config.dart`: Theming, palette, and app name strings.
        - `services/`: Core platform and application services.
            - `app_update_service.dart`: Automatic background version checker, idle/tab-switch detector, and seamless CacheStorage-cleared browser reload service for web.
            - `document_cache_service.dart`: Local document downloading, caching, and retrieval service preventing repeated network transfers.
            - `cache_io_helper.dart`: Cross-platform filesystem & memory storage bridge (`cache_io_helper_io.dart`, `cache_io_helper_web.dart`, `cache_io_helper_stub.dart`).
        - `widgets/`: Shared reusable UI components.
            - `storage_network_image.dart`: Cross-platform cached image loader with web CORS and memory fallbacks.
            - `web_image_view.dart`: Cross-platform conditional adapter for web HTML image element view registration (`web_image_view_web.dart` and `web_image_view_stub.dart`).
            - `interactive_image_dialog.dart`: Centralized full-screen interactive image viewer with pinch-to-zoom, pan, and dismiss controls.
            - `error_fallback_screen.dart`: User-friendly release-mode error screen presented on fatal framework rendering or build exceptions.
    - `features/`: Specific feature modules separated by domain.
        - `admin/`: Core management modules for administrators.
            - `admin_create_user_screen.dart`: Unified user creation interface supporting dynamic form switching for Resident (with street/number cascading selection and delivery date picker), Security Guard, and Administrator accounts (linked to fixed Admin office address).
            - `admin_resident_registration_screen.dart`: Direct resident and roommate onboarding view with address collision detection.
            - `admin_bulk_user_import_screen.dart`: Bulk resident account creation screen via CSV upload with optional/deterministic passwords, automated resident claim granting, SMTP status indicator, and email dispatch status reporting.
            - `admin_bulk_address_import_screen.dart`: Bulk address creation screen via CSV upload supporting number ranges, exclusions, and collision checks.
            - `admin_payment_approval_screen.dart`: Payment proofs review showing payment amount and covered periods chips, triggering status recalculation upon approval/rejection. Keyed stateful cards prevent redundant downloads/fetches.
            - `admin_upload_payment_screen.dart`: Admin interface to upload payment proofs on behalf of physical addresses, supporting delivery date inspection/editing, amount capture, and multi-period advance coverage.
            - `admin_booking_approval_screen.dart`: Admin interface to review pending amenity booking requests with resident info, time slots, facility streaming, custom/preset approval instructions (`approvalMessage`), and rejection reasons.
            - `admin_user_management_screen.dart`: User directory supporting whole-database search and filtering (by name, email, street dropdown, role chips) with 20-user batched query pagination when browsing unfiltered, in-memory address caching, address delivery date viewing & editing, client role switching, password resets, force-unbind actions, and permanent account removal.
            - `admin_facilities_screen.dart`: Interface to configure amenities with cooldown limits, daily operating hours windows (`openingTime` - `closingTime`), advance anticipation rules (`anticipationUnit`, `anticipationValue`), and preset approval instruction templates.
            - `admin_settings_screen.dart`: Global residency maintenance cutoff, grace period, and schedule timezone adjustments, SMTP email configuration, and customizable payment rejection reason templates pool manager stored in `config/app_settings`.
            - `admin_payment_report_screen.dart`: CSV payment matrix exporter per physical address.
            - `admin_access_logs_screen.dart`: Comprehensive access history & audit screen featuring whole-database query search & filtering (address dropdown, date ranges, visitor category: guest vs supplier, keyword search across guest/plates/guard/reason), 20-item batched query exploration for unfiltered browsing, real-time KPI overview cards, and pinch-to-zoom visitor photo dialog inspection.
            - `admin_guard_management_screen.dart`: Dedicated lifecycle module to provision and purge security guard accounts.
        - `announcements/`: Announcements system with AI auto-translations, orientation-aware thumbnail generation, responsive desktop/mobile layouts, clipboard image pasting, full-screen interactive image viewing, and quick emoji bar.
            - `announcement.dart`: Announcement data model with full-res image URL (`imageUrl`), proportional thumbnail URL (`thumbnailUrl`), audience targeting, and translations.
            - `announcements_screen.dart`: Visual responsive feed (side-by-side card on desktop, linear stack on mobile) and administrative announcement publishing dialog with gallery picker, clipboard image pasting, live thumbnail preview, interactive pinch-to-zoom viewer, and quick-access emojis.
            - `clipboard_image_helper.dart`: Cross-platform conditional adapter for web clipboard image reading and paste event listeners (`clipboard_image_helper_web.dart` and `clipboard_image_helper_stub.dart`).
        - `auth/`: Login and role detection logic.
            - `login_screen.dart`: Main login interface with navigation.
            - `signup_screen.dart`: Resident onboarding with password complexity enforcement (min 8 chars, uppercase, lowercase, digit) and address selection list.
            - `ownership_proof_screen.dart`: Mandatory proof of ownership capture with property handover date picker, and upload interface.
            - `admin_resident_approval_screen.dart`: Dedicated admin list view for validating property ownership proofs and propagating delivery date to address upon approval. Keyed stateful cards prevent redundant downloads/fetches.
            - `forgot_password_screen.dart`: Password recovery request interface.
            - `roommates_screen.dart`: Family group management interface with clear step-by-step onboarding guide, camera QR scanner with camera selector (back/front switch), and UID/email roommate addition options.
        - `booking/`: Facility booking screens and service logic.
            - `booking_screen.dart`: Main booking interface with submission loading spinner, operating hours badge & client validation, anticipation date lower bound, and anonymous confirmed-only schedule stream.
            - `manage_bookings_screen.dart`: History and management of bookings with dynamic next-steps instructions card displaying admin's approval instructions.
            - `booking_service.dart`: Service for cloud calls and confirmed booking queries (`getConfirmedBookings`).
        - `payments/`: Monthly payments and sanction fines screens and service logic.
            - `payment_screen.dart`: Payments interface with concept selector (monthly quota vs sanction), dynamic folio input, payment date picker, advance periods toggle switch with checkbox list view, responsive horizontal receipt photo capture button container, persistent missing-field inline warning banner with isolated ListenableBuilder, explicit FocusNodes and ValueKeys, memoized database streams, and top rejection recovery banner with automatic form pre-filling.
            - `payment_service.dart`: Service for payment operations, multi-period receipt uploads with amounts, selectable advance period generation, address status recalculation with sanction restriction checking (`hasActiveSanctions`), and `isWithinGracePeriod` calculation.
        - `sanctions/`: Address-level infractions and sanctions module.
            - `sanctions_screen.dart`: Resident sanctions viewer with security-rule-aligned query (`authorizedUids`), status chips, interactive pinch-to-zoom photo dialog, and direct "Pay Sanction" flow.
            - `admin_sanctions_screen.dart`: Admin sanctions management interface with status filter tabs, bottom-sheet sanction issuance form (address selector, resident UID resolution, photo upload), and sanction waiver/cancellation actions.
        - `qr_access/`: Access generation and scanning modules.
            - `qr_generator_screen.dart`: Generator interface.
            - `manage_qr_screen.dart`: History and management of QR codes.
            - `qr_scanner_screen.dart`: Security guard QR capture with camera selector (back/front switch), vertical step-by-step ID/plate evidence verification layout, centered decision action controls, and server-side atomic validation/access logging via `validateAndRegisterQrAccess`.
        - `transparency/`: Transparency documents module emulating a file explorer with virtual directory tree, local caching, native rendering, document category re-assignment, and category management with in-use deletion protection.
            - `transparency_screen.dart`: Main File Explorer screen with folder hierarchy navigation, breadcrumbs, search, category filter, document open delegation, category management, and admin folder/file management.
            - `document_viewer_screen.dart`: Native in-app viewer for Markdown (`.md`) and plain text (`.txt`) documents with font resizing and sharing.
            - `widgets/`:
                - `file_explorer_breadcrumb.dart`: Interactive breadcrumb navigation widget.
                - `folder_card.dart`: Virtual folder card with child item counter and admin actions.
                - `document_card.dart`: Document tile with type-specific iconography, metadata chips (category, publication date, size), cached status badge, and change category/move/delete actions.
    - `l10n/`: Localization definitions in Spanish and English.
        - `app_en.arb`: English strings.
        - `app_es.arb`: Spanish strings.
- `scripts/`: Helper scripts holding service accounts and automation runners.
    - `set_role.js`: Claims and role assignment utility supporting both Firebase Emulator (`--emulator`) and production modes with auto user provisioning.
    - `populate_addresses.js`: Batched write logic for address import on csv files.
    - `set_resident_addresses_paid.js`: Batch maintenance utility iterating across all physical addresses linked to a resident and updating their paymentStatus to 'paid' (with emulator, dry-run, force, and batching support).
    - `seed_emulator.js`: Automated Firebase database seeder supporting both local Emulators (default) and remote/staging projects (`--remote` / `--staging`), provisioning CSV addresses, admin, resident, roommate, and guard accounts (with role claims), app settings, neighborhood facilities with operating hours, and sample announcements.
    - `run_rollout_tests.sh`: Zero-touch test runner orchestrating emulator execution and automated integration testing.
    - `test/`: Node.js test suite for script automation (`set_resident_addresses_paid.test.js`).
- `test_driver/`: Flutter Driver host scripts.
    - `integration_test.dart`: Standard integration test driver entry point.
- `test/`: Project unit, widget, and integration test suites.
    - `core/backend/backend_models_test.dart`: Model tests for AppUser, AuthResult, DbFieldValue, StringDbReference, QueryFilter, and QuerySort.
    - `features/`:
        - `admin/`:
            - `admin_booking_approval_test.dart`: Admin booking approval and rejection lifecycle tests.
            - `admin_user_management_test.dart`: User deletion, address unbinding, role promotion/revocation lifecycle, 20-user batched query pagination, search (name/email/street), and street dropdown filter widget tests.
            - `bulk_address_csv_parser_test.dart`: CSV delimiter auto-detection, UTF-8 BOM removal, and address range count calculation tests.
            - `bulk_user_csv_parser_test.dart`: Header alias mapping, quoted field parsing, and result CSV compilation tests.
            - `payment_report_matrix_test.dart`: Month boundary generation and financial status matrix tests.
            - `access_logs_filter_test.dart`: Access logs filtering, 20-item batched query pagination, address dropdown filter, date range filter, and keyword search widget tests.
            - `admin_facilities_test.dart`: Facility configuration, in-place edit dialog (changing/removing cooldowns), and deletion widget tests.
            - `admin_create_user_test.dart`: Admin resident creation, future delivery date validation (rejection of future dates vs acceptance of valid dates), address claiming, and widget tests.
        - `announcements/announcement_model_test.dart`: Announcement serialization and timestamp parsing tests.
        - `auth/password_validation_test.dart`: Password complexity constraint validation tests.
        - `booking/booking_service_test.dart`: Booking filters, user booking sorting, cloud function invocation, and full booking lifecycle (schedule -> reject with reason -> re-book -> approve -> cooldown blocked -> time elapsed -> re-book review) tests.
        - `payments/`:
            - `payment_service_test.dart`: Period generation, payment status state machine with `pending` on proof submission, grace period status checks, multi-period arrays, and status stream tests.
            - `payment_screen_test.dart`: Payment screen UI widget tests verifying responsive layout, concept switching, and horizontal receipt evidence container rendering on narrow screens without text squeezing.
        - `qr_access/`:
            - `qr_code_model_test.dart`: QrCode model serialization and default parsing tests.
            - `qr_service_test.dart`: QR stream sorting and code invalidation tests.
            - `qr_camera_selector_test.dart`: Widget tests verifying camera switch button presence on guard QR scanner and roommate QR scanner sheet.
        - `transparency/transparency_explorer_test.dart`: Virtual folder hierarchy, document filtering, move operations, and in-app file type identification tests.
    - `integration/`:
        - `rollout_workflow_test.dart`: Complete headless end-to-end rollout test suite covering roommate linking (Suite A), announcements (Suite B), multi-period advance payments (Suite C), past due debt recovery with feature gating (Suite D), partial settlement restriction persistence & grace period pending unrestricted access (Suite E), facility booking full lifecycle (Suite F), admin resident creation with delivery date validation (Suite G), and Ticket-01 sanctions enforcement, payment redirection, and facility operating hours window (Suite H).
    - `helpers/fake_backend.dart`: In-memory BaaS fake service locator for testing services in isolation.
    - `import_boundary_test.dart`: Static boundary verification test enforcing zero direct Firebase SDK imports in `lib/features/` and zero raw `print()` calls in `lib/`.
    - `widget_test.dart`: Smoke test placeholder.
- `web/`: Web entry point and assets including `index.html`, `manifest.json`, `favicon.ico`, `favicon.png`, `icons/`, and base `version.json`.
- `resident_import_template.csv`: Sample CSV template for administrator bulk user account import.
- `Structure.md`: This inventory map file.

## Architectural Decisions & Coding Guidelines

To keep the codebase consistent and secure, developers should adhere to the following decisions:

1. **Feature-First Organization**: Group components and logic inside `lib/features/` by feature module/domain. Shared assets, configuration, and helpers reside in `lib/core/`.
2. **Strict Backend Abstraction**: Never call Firebase or Firestore APIs directly inside UI files. Instead, fetch/save data using helper methods in `Backend` interface files, allowing the database backend to be swapped out without changes to the screens.
3. **App Check Verification**: In production, client requests and Cloud Functions verify App Check validity context (`enforceAppCheck: true, consumeAppCheckToken: true`). In local Firebase emulator environments, App Check activation, token auto-refresh, and callable token enforcement are disabled on both client and backend (`AppConfig.useFirebaseEmulator`) to facilitate local debugging and testing without requiring ReCAPTCHA tokens.
4. **Console Output Rule**: Never use raw `print()` for debugging. Always use `debugPrint()` to prevent logs from spilling into release builds.
5. **No Hardcoded Copy**: Every user-facing message must use localized keys mapped via `AppLocalizations.of(context)` to maintain English/Spanish compatibility.
