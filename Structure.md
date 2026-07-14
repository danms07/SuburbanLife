# Directory Structure

*Last Verified/Updated: 2026-06-10 (Refactored all custom header bars to use responsive MediaQuery top padding, resolving high padding alignment issues on web/desktop)*

Current state of project files and folders:

- `android/`: Native Android configuration and build files.
- `assets/`: Application asset directories.
    - `icon/`: Launcher and branding icon assets.
        - `app_icon.png`: Original high-resolution premium app icon.
- `docs/`: Technical plans and documentation archives.
    - `plans/`: Future implementation plans.
        - `biometric_auth_plan.md`: Plan for persistent biometric gating.
        - `credential_manager_plan.md`: Plan for Passkeys and Credential Manager integration.
- `flutter_launcher_icons.yaml`: Configuration for generating platform-specific launcher icons.
- `functions/`: Cloud Functions for Firebase.
    - `index.js`: Core function logic holding Gemini translations, address-based access restriction, address unbinding, and own-account deletion.
- `ios/`: Native iOS configuration and build files.
- `LICENSE`: MIT No Attribution (MIT-0) license file.
- `PRIVACY_POLICY.md`: Bilingual Privacy Policy (LFPDPPP/ARCO compliant).
- `lib/`: Main Flutter source code.
    - `core/`: Core configuration and themes.
        - `backend/`: Agnostic BaaS service abstractions and service locator.
            - `backend.dart`: Base interfaces for Auth, Database, Storage, and Cloud Functions.
            - `firebase_backend.dart`: Firebase concrete implementations of the backend interfaces.
        - `config/app_config.dart`: Theming, palette, and app name strings.
    - `features/`: Specific feature modules separated by domain.
        - `admin/`: Core management modules for administrators.
            - `admin_resident_registration_screen.dart`: Direct resident and roommate onboarding view with address collision detection.
            - `admin_payment_approval_screen.dart`: Payment proofs review showing payment period, and triggering status recalculation. Keyed stateful cards prevent redundant downloads/fetches.
            - `admin_upload_payment_screen.dart`: Interface for uploading maintenance receipts on behalf of addresses via cascading street name and house number dropdown filters.
            - `admin_user_management_screen.dart`: User directory mapping client role switching, claim state tables, and admin force-unbind actions.
            - `admin_facilities_screen.dart`: Interface to configure dynamic unique vs multi-item amenities.
            - `admin_settings_screen.dart`: Global residency maintenance cutoff and grace period adjustments.
            - `admin_payment_report_screen.dart`: CSV payment matrix exporter per physical address.
            - `admin_guard_management_screen.dart`: Dedicated lifecycle module to provision and purge security guard accounts.
        - `announcements/`: Announcements system with translations support.
        - `auth/`: Login and role detection logic.
            - `login_screen.dart`: Main login interface with navigation.
            - `signup_screen.dart`: Resident onboarding and address selection list.
            - `ownership_proof_screen.dart`: Mandatory proof of ownership capture with property handover date picker, and upload interface.
            - `admin_resident_approval_screen.dart`: Dedicated admin list view for validating property ownership proofs and propagating delivery date to address upon approval. Keyed stateful cards prevent redundant downloads/fetches.
            - `forgot_password_screen.dart`: Password recovery request interface.
            - `roommates_screen.dart`: Family group management interface.
        - `booking/`: Facility booking screens and service logic.
            - `booking_screen.dart`: Main booking interface.
            - `manage_bookings_screen.dart`: History and management of bookings.
            - `booking_service.dart`: Service for cloud calls.
        - `payments/`: Monthly payments screen and service logic.
            - `payment_screen.dart`: Monthly payments screen displaying status, showing missing periods, and enabling period-based photo upload.
            - `payment_service.dart`: Service for payment operations and address status recalculation.
        - `qr_access/`: Access generation and scanning modules.
            - `qr_generator_screen.dart`: Generator interface.
            - `manage_qr_screen.dart`: History and management of QR codes.
            - `qr_scanner_screen.dart`: Security guard QR capture, ID/plate photo verification, and entry logging interface.
            - `qr_service.dart`: Service for QR operations.
        - `transparency/`: Transparency documents module.
    - `l10n/`: Localization definitions in Spanish and English.
        - `app_en.arb`: English strings.
        - `app_es.arb`: Spanish strings.
- `scripts/`: Helper scripts holding service accounts.
    - `create_admin.js`: Claims merge logic handled in console scripts.
    - `populate_addresses.js`: Batched write logic for address import on csv files.
- `test/`: Project unit and widget test suites.
    - `import_boundary_test.dart`: Static boundary verification test enforcing zero direct Firebase SDK imports inside `lib/features/`.
- `Structure.md`: This inventory map file.

## Architectural Decisions & Coding Guidelines

To keep the codebase consistent and secure, developers should adhere to the following decisions:

1. **Feature-First Organization**: Group components and logic inside `lib/features/` by feature module/domain. Shared assets, configuration, and helpers reside in `lib/core/`.
2. **Strict Backend Abstraction**: Never call Firebase or Firestore APIs directly inside UI files. Instead, fetch/save data using helper methods in `Backend` interface files, allowing the database backend to be swapped out without changes to the screens.
3. **App Check Verification**: In production, Cloud Functions verify App Check custom claim validity context. When building new Callable Functions, ensure `enforceAppCheck: true` is set.
4. **Console Output Rule**: Never use raw `print()` for debugging. Always use `debugPrint()` to prevent logs from spilling into release builds.
5. **No Hardcoded Copy**: Every user-facing message must use localized keys mapped via `AppLocalizations.of(context)` to maintain English/Spanish compatibility.
