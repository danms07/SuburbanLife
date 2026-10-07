# Widget Catalog

This catalog inventories the custom reusable UI elements and visual structures established across the Suburban Life application.

## Widget Directory & File Mapping

The following table maps each visual component to its feature domain and source file path:

| Component Name | Feature Domain | Source File Path |
| :--- | :--- | :--- |
| **Premium Action Header & Split Pane** | Core / UI | Multiple (`login_screen.dart`, `signup_screen.dart`, etc.) |
| **Padded Form Cards** | Core / UI | Used inline in forms |
| **Cascading Address Selection** | Auth / Onboarding | [signup_screen.dart](lib/features/auth/signup_screen.dart) & [admin_upload_payment_screen.dart](lib/features/admin/admin_upload_payment_screen.dart) |
| **Security Guard Action Panel** | Guard Dashboard | [main.dart](lib/main.dart) |
| **Multi-Address Inline Header Spinner** | Core / Home | [main.dart](lib/main.dart) |
| **Reviewing Fallback Overlay** | Resident Auth | [ownership_proof_screen.dart](lib/features/auth/ownership_proof_screen.dart) |
| **Dynamic Admin Review Badge** | Admin Dashboard | [main.dart](lib/main.dart) |
| **Admin Menu Grid & Buttons** | Admin Dashboard | [main.dart](lib/main.dart) |
| **Dynamic Facilities Configurator** | Admin Settings | [admin_facilities_screen.dart](lib/features/admin/admin_facilities_screen.dart) |
| **Active Guard Lifecycle List** | Admin Settings | [admin_guard_management_screen.dart](lib/features/admin/admin_guard_management_screen.dart) |
| **Dynamic Matrix Payment Report Card**| Admin Reports | [admin_payment_report_screen.dart](lib/features/admin/admin_payment_report_screen.dart) |
| **Keyed Resident Approval Card** | Resident Auth | [admin_resident_approval_screen.dart](lib/features/auth/admin_resident_approval_screen.dart) |
| **Keyed Payment Approval Card** | Admin Payments | [admin_payment_approval_screen.dart](lib/features/admin/admin_payment_approval_screen.dart) |
| **Categorized Multi-Period & Advance Payment Selector** | Payments | [payment_screen.dart](lib/features/payments/payment_screen.dart) |
| **Dynamic Shortcuts Grid & Drawer** | Core / Navigation | [main.dart](lib/main.dart) |
| **Branding Navigation Drawer Header** | Core / Navigation | [main.dart](lib/main.dart) |
| **Custom Branded QR Access Card** | QR Access | [qr_generator_screen.dart](lib/features/qr_access/qr_generator_screen.dart) |
| **Roommate QR Code Onboarding & Scanner** | Auth / Roommates | [main.dart](lib/main.dart) & [roommates_screen.dart](lib/features/auth/roommates_screen.dart) |
| **Bulk User Import CSV Manager** | Admin Management | [admin_bulk_user_import_screen.dart](lib/features/admin/admin_bulk_user_import_screen.dart) |
| **Bulk Address Import CSV Manager** | Admin Management | [admin_bulk_address_import_screen.dart](lib/features/admin/admin_bulk_address_import_screen.dart) |
| **Admin Settings & SMTP Configurator** | Admin Settings | [admin_settings_screen.dart](lib/features/admin/admin_settings_screen.dart) |
| **Unified User Creation Manager** | Admin Management | [admin_create_user_screen.dart](lib/features/admin/admin_create_user_screen.dart) |
| **Rich Media & Emoji Announcements Feed** | Announcements | [announcements_screen.dart](lib/features/announcements/announcements_screen.dart) |
| **Admin Access Logs & History Viewer** | Admin Reports | [admin_access_logs_screen.dart](lib/features/admin/admin_access_logs_screen.dart) |
| **Release Error Fallback Screen** | Core / UI | [error_fallback_screen.dart](lib/core/widgets/error_fallback_screen.dart) |
| **File Explorer Breadcrumb** | Transparency | [file_explorer_breadcrumb.dart](lib/features/transparency/widgets/file_explorer_breadcrumb.dart) |
| **Explorer Folder Card** | Transparency | [folder_card.dart](lib/features/transparency/widgets/folder_card.dart) |
| **Explorer Document Card** | Transparency | [document_card.dart](lib/features/transparency/widgets/document_card.dart) |
| **Native Document Viewer** | Transparency | [document_viewer_screen.dart](lib/features/transparency/document_viewer_screen.dart) |
| **Admin Booking Approval Card** | Admin Bookings | [admin_booking_approval_screen.dart](lib/features/admin/admin_booking_approval_screen.dart) |
| **User Directory & Account Management View** | Admin Management | [admin_user_management_screen.dart](lib/features/admin/admin_user_management_screen.dart) |
| **Security Guard QR Scanner & Decision Interface** | QR Access | [qr_scanner_screen.dart](lib/features/qr_access/qr_scanner_screen.dart) |
| **Resident Booking Card & Rejection Banner** | Bookings | [manage_bookings_screen.dart](lib/features/booking/manage_bookings_screen.dart) |
| **Resident Sanctions & Infractions Viewer** | Sanctions | [sanctions_screen.dart](lib/features/sanctions/sanctions_screen.dart) |
| **Admin Sanctions Manager & Issuance Sheet** | Sanctions | [admin_sanctions_screen.dart](lib/features/sanctions/admin_sanctions_screen.dart) |
| **Payment Validation & Rejection Recovery Card** | Payments | [payment_screen.dart](lib/features/payments/payment_screen.dart) |
| **Facility Operating Hours & Schedule Viewer** | Bookings | [booking_screen.dart](lib/features/booking/booking_screen.dart) |

---

## 1. Premium Action Header & Split Pane
- **Description**: A double-sized action bar featuring a rich background color (`AppConfig.primaryColor`) with beautifully rounded bottom corners (`Radius.circular(30)`). For wide screens, `LoginScreen` adapts to a premium side-by-side split layout where the left welcome pane features a linear gradient utilizing the `AppConfig.primaryColor` and `AppConfig.gradientEndColor` tokens, displaying the white logo emblem (`AppConfig.whiteLogoEmblemAsset`) with multi-resolution antialiased variants above the application title with 50px spacing (reduced by 40%). In mobile/portrait view, the premium action header displays the white logo emblem (`height: 50`) above the application title with responsive safe area top padding (`MediaQuery.paddingOf(context).top + 24`).
- **Usage**: Used as the top header in `MyHomePage`, `LoginScreen` (on mobile/narrow screens), `SignupScreen`, and `ForgotPasswordScreen` to wow the user and establish visual consistency.
- **Properties**:
  - Top padding: Responsive `MediaQuery.paddingOf(context).top + 24` on mobile login screen (or `+ 16` on standard action headers) to support notch screens while remaining compact on web/desktop.
  - Bottom left/right border radius: 30px
  - Typography: White, bold, clear titles using the app's configured font family.

## 2. Padded Form Cards
- **Description**: Elevated card containers (`elevation: 4`) wrapping input forms to provide a clean, glassmorphism-inspired layering effect on top of the scaffold background.
- **Usage**: Used in authentication and registration screens to house `TextField` and `ElevatedButton` components.
- **Properties**:
  - Border radius: 15px
  - Internal padding: 24px

## 3. Cascading Address Selection Dropdowns
- **Description**: Hierarchical dropdown inputs (`DropdownButtonFormField`) providing rapid street-level filtering and sortable numeric selection to locate addresses seamlessly.
- **Usage**: Used in `SignupScreen` during step 2 of resident onboarding and in `AdminUploadPaymentScreen` for uploading payment receipts on behalf of specific addresses.
- **Features**:
  - Dynamic dependency: Number selection automatically filters and sorts based on the selected street name.
  - Rich prefix iconography (`Icons.map` / `Icons.signpost` and `Icons.home`) matching brand colors.

## 4. Security Guard Action Panel
- **Description**: A premium, dedicated dashboard tailored for security guard personnel, integrating a customized brand header and an elevated primary call-to-action card (`elevation: 6`) for visitor QR scanning.
- **Usage**: Displayed as the primary application surface in `MyHomePage` for users with the `guard` custom claim.
- **Properties**:
  - Header: Deep primary background with localized guard titles and direct logout access.
  - CTA Card: Large touch target with generous padding (30px) and clear iconography for immediate detection tasks.

## 5. Multi-Address Inline Header Spinner
- **Description**: An inline header control converting the default title text into a deeply stylized `DropdownButton` allowing residents who own multiple houses to switch active contexts on the fly.
- **Usage**: Displayed inside the *Premium Action Header* when querying multiple approved references.
- **Properties**: Semitransparent white overlays with contrast-heavy menu entries.

## 6. Reviewing Fallback Overlay & Direct Proof Capture
- **Description**: A full-surface lock layout presented to newly onboarded residents featuring a date picker for the property handover/delivery date and direct native camera upload interactions, accompanied by transparent data purging disclosures.
- **Features**: 
  - Displays the specific target property street and number dynamically, and provides an outlined cancellation action to let users abandon the claim if selected incorrectly.
  - Enforces capturing the property delivery date prior to camera photo proof uploads.
  - Uses the modern Flutter `withValues(alpha: ...)` API for theme color transparency overlays to avoid precision loss.

## 7. Dynamic Admin Review Badge
- **Description**: A vibrant, reactive action badge (`Badge`) listening to active `ownership_claims` and `payments` changes in real-time.
- **Usage**: Wraps the "Approve Residents" and "Review Payments" action items on the Admin dashboard to highlight pending pipeline actions automatically.

## 8. Admin Menu Grid & Buttons
- **Description**: A scrollable, structured grid menu leveraging uniform custom button widgets (`_buildAdminMenuButton`) styled with individual semantic background colors, prefix icons, and trailing reactive badges.
- **Usage**: Serves as the primary administrative interface in `MyHomePage` when under the `admin` custom claim.

## 9. Dynamic Facilities Configurator & In-Place Editor
- **Description**: An administrative management interface allowing admins to configure, edit, and delete amenities. Integrates a dynamic `SwitchListTile` to switch between a "Unique Amenity" (locking capacity to 1) and a "Multi-item Amenity" (exposing quantity increment/decrement controls), as well as a booking cooldown selector (unrestricted, days, months, years) with custom duration. Also includes an in-place **Edit Amenity Dialog** (`_editFacility`) accessible via each facility's edit action button to change or remove cooldowns on existing amenities in real time.
- **Usage**: Used inside `AdminFacilitiesScreen`.

## 10. Active Guard Lifecycle List
- **Description**: A real-time Stream-based list view rendering active security guard accounts with `role == 'guard'`. Renders circular avatar visual badges and interactive delete controls with loading spinners during the deletion cycle.
- **Usage**: Displayed in the `AdminGuardManagementScreen`.

## 11. Dynamic Matrix Payment Report Card
- **Description**: An interactive reporting interface offering start and end month dropdown selectors to generate a localized CSV matrix. Evaluates monthly status blocks per address and includes automated no-data warning dialog alerts.
- **Usage**: Exposed via the `AdminPaymentReportScreen`.

## 12. Keyed Resident Approval Card
- **Description**: An optimized, stateful card representing an individual pending ownership claim. Uses a stateful structure to cache the address query future and is keyed via `ValueKey(doc['id'])` in parent lists to preserve state, avoiding redundant image downloads and Firestore fetches. It formats and displays the property delivery/handover date.
- **Usage**: Internal sub-widget inside `AdminResidentApprovalScreen`.

## 13. Keyed Payment Approval Card
- **Description**: An optimized, stateful card representing an individual pending payment receipt review. Uses a stateful structure to cache the user query future and is keyed via `ValueKey(doc['id'])` in parent lists to preserve state, avoiding redundant image downloads and Firestore fetches. It formats and displays the verified payment amount badge (`$amount MXN`) and individual chips for all covered billing periods.
- **Usage**: Internal sub-widget inside `AdminPaymentApprovalScreen`.

## 14. Categorized Multi-Period & Advance Payment Selector
- **Description**: An interactive payment submission interface (`PaymentScreen` & `AdminUploadPaymentScreen`) that renders an amount input field and categorizes candidate billing periods into **Due / Pending Months** (missing/rejected periods from delivery date up to current month) and **Advance / Upcoming Months** (up to 12 months ahead). Enables multi-selection of periods via `FilterChip` items with visual status icons (paid checkmark, reviewing hourglass) and automatic chronological sorting. Uploading a proof of payment transitions the address status to `pending`. When the status is `pending` within the active grace period (`isWithinGracePeriod == true`), the resident is considered `paid` and retains unrestricted access to bookings and QR passes.
- **Usage**: Used inside `PaymentScreen` and `AdminUploadPaymentScreen` to support single and advance multi-month payments.

## 15. Dynamic Shortcuts Grid & Drawer Menu
- **Description**: Interactive menus displaying resident feature options. Employs StreamBuilders listening to the `facilities` collection to check for registered amenities. If the collection is empty, the "Book Facility" shortcut item on the dashboard grid and the "Manage Bookings" menu item in the navigation drawer are dynamically removed to avoid clutter and layout alignment gaps.
- **Usage**: Main screen feature navigation dashboard and navigation drawer widgets.

## 16. Branding Navigation Drawer Header
- **Description**: A customized drawer header container (`DrawerHeader`) styling the main application drawer menu. Replaces standard text name strings with a centered, high-resolution in-app branding logo image (`AppConfig.appLogoAsset` / `assets/icon/app_logo.png`) fitted inside a premium brand color header box.
- **Usage**: Displayed at the top of the app navigation drawer widget.

## 17. Custom Branded QR Access Card
- **Description**: An on-the-fly generated shareable/downloadable graphic card (`800x1200` PNG). Uses a Custom Paint canvas recorder layout combining a branded header strip (featuring the brand app logo and name), a centered QR access code, a content divider, and five custom rows detailing the guest's name, authorized address, access category, validity/expiry status, and vehicle information. Leverages `share_plus` with `ShareParams`, `XFile.fromData`, and `fileNameOverrides` for cross-platform native device sharing, with an automatic web download fallback when native sharing is unavailable on desktop browsers.
- **Usage**: Dynamically compiled when the user clicks 'Share Code' or 'Download Code' in `QrGeneratorScreen`.

## 18. Roommate QR Code Onboarding & Scanner
- **Description**: A dual-sided QR and UID account linking system for roommates and family members. On the unlinked account onboarding card (`main.dart`), an interactive `SegmentedButton` lets users toggle between "Claim Property" and "Join as Roommate". The Roommate tab presents a high-contrast `QrImageView` encoding `roommate_uid:$uid`, user credentials, a selectable plain-text UID box with an inline "Copy to Clipboard" icon button (`Clipboard.setData`), a full-width copy action button, and a live stream builder waiting indicator. In `RoommatesScreen`, primary residents can launch an inline camera QR scanner sheet powered by `MobileScanner` with camera selector controls (back/front camera toggle in sheet header and floating button on scanner preview, defaulting explicitly to rear camera) to scan roommate QR codes or manually type/paste a roommate UID or email address using the built-in `content_paste` suffix button in the input field.
- **Usage**: Used during initial onboarding in `main.dart` and inside `RoommatesScreen`.

## 19. Bulk User Import CSV Manager
- **Description**: An administrative interface allowing bulk creation of resident user accounts from an uploaded CSV file. Features a file picker, a robust CSV parser (detecting headers or positional defaults), an interactive preview list of parsed rows showing assigned or deterministic temporary passwords, a copy template action, and a full results report view with copy-all passwords functionality.
- **Usage**: Exposed via `AdminBulkUserImportScreen`.

## 20. Bulk Address Import CSV Manager
- **Description**: An administrative interface for pre-populating physical neighborhood address records into Firestore from a CSV file. Supports parsing street names, initial house numbers, final house numbers, and optional house number exclusions. Offers a CSV template copy helper, live row preview listing, and collision checks against existing database records.
- **Usage**: Exposed via `AdminBulkAddressImportScreen`.

## 21. Admin Settings & SMTP Configurator
- **Description**: A multi-section configuration panel for administrators to adjust payment cutoff days, grace period limits, schedule timezones (defaulting to Central Standard Time / Mexico City), and configure a custom SMTP mail server. Includes preset chips for standard ports (587, 465, 25), SSL/TLS switch, password visibility toggle, a rich customizable welcome message template editor with placeholder chips (`%password%`, `%name%`, `%email%`, `%address%`, `%role%`, `%appName%`) and reset defaults action, and an interactive connection testing tool that executes an SMTP handshake and sends a test email to verify credentials before saving.
- **Usage**: Exposed via `AdminSettingsScreen`.

## 22. Unified User Creation Manager
- **Description**: A centralized administrative interface for provisioning new accounts across all user tiers: Resident, Security Guard, and Administrator. Features a dynamic form switcher driven by a user type selector (defaulting to Resident), password visibility toggles, automated secure password generator, reactive cascading street-and-number selectors ensuring collision-free address assignment, and a property delivery date picker with strict future-date rejection validation for resident accounts. For Administrator accounts, automatically ensures linkage to the fixed "Admin office" address.
- **Usage**: Exposed via `AdminCreateUserScreen`.

## 23. Rich Media, Clipboard Pasting & Emoji Announcements Feed
- **Description**: A responsive feed interface rendering community notices and administrative broadcasts. Features orientation-aware client-side proportional thumbnail generation for landscape and portrait images, responsive desktop (horizontal side-by-side card) and mobile (linear vertical card) layouts, tap-to-zoom full-screen interactive image viewer (`InteractiveViewer`), audience badges (All vs. Residents), and full native emoji support across titles and message bodies. In administrative mode, an enhanced creation modal features a quick-tap horizontal emoji bar (`📢`, `🚨`, `⚠️`, `ℹ️`, `🔔`, etc.), cross-platform gallery image picker, direct clipboard image pasting button, automatic system clipboard image capture (`Ctrl+V` / `Cmd+V` & browser `onPaste` event stream), live thumbnail preview, and upload progress indicator.
- **Usage**: Exposed via `AnnouncementsScreen`.

## 24. Release Error Fallback Screen
- **Description**: A user-friendly, beautifully styled fallback error screen displayed during fatal framework rendering or widget build crashes in release builds (intercepted via `ErrorWidget.builder`). Prevents standard red/grey crash screens by presenting a clean alert card with bilingual support (`AppLocalizations`) explaining that an automatic incident report has been dispatched to Firebase Crashlytics.
- **Usage**: Configured globally in `main.dart` via `ErrorWidget.builder` and defined in `lib/core/widgets/error_fallback_screen.dart`.

## 25. User Directory & Account Management View
- **Description**: An administrative user directory interface featuring whole-database search and filtering (by user name, email, physical street name, and role chips) combined with 20-user batched query pagination (`limit: 20`, `startAfter: _lastDocId`) when browsing unfiltered. When active filters or search terms are applied, it queries and inspects the whole database with cached in-memory address resolution to ensure complete visibility. Each user card renders avatar indicators, role badges, physical address linkage status, address delivery date, and live payment standing (`paid`, `restricted`, `pending`, `reviewing`). Provides actions to set or edit address delivery dates via a date picker dialog, change passwords, toggle administrator roles, force unbind physical addresses, and permanently remove user accounts via a confirmation dialog with loading spinner indicator and self-deletion prevention for the active admin.
- **Usage**: Exposed via `AdminUserManagementScreen`.

## 26. Admin Access Logs & History Viewer
- **Description**: A comprehensive audit and security log viewer featuring whole-database query search & filtering (address dropdown, date range filtering: Today, This Week, This Month, Custom Date Range, visitor category chips: Guest vs Provider, and real-time keyword search across guest name, license plates, resident host, guard, and entry reason) combined with 20-item batched query exploration (`limit: 20`, `startAfter: _lastDocId`) for unfiltered exploration. Features KPI summary cards (Total Events, Allowed, Denied, Providers), log detail cards with visitor/driver identity, vehicle and plate metadata, reason notes, and tap-to-zoom interactive photos (`showInteractiveImageDialog`).
- **Usage**: Exposed via `AdminAccessLogsScreen`.

## 27. Security Guard QR Scanner & Decision Interface
- **Description**: A security access interface designed for gate guards to scan visitor/supplier QR passes. Features a live camera scanner overlay (`MobileScanner`) with camera selector controls (back/front camera toggle in AppBar actions and floating button on scanner preview, defaulting explicitly to rear camera), a validation status card with guest identity details and vehicle metadata, a step-by-step vertical linear layout for photographic evidence capture (ID photo and vehicle plate photo with captured indicator state), an optional reason text input, and balanced, centered allow/deny decision action buttons (`Allow Access` / `Deny Access`) with independent color coding and atomic transaction logging via `validateAndRegisterQrAccess`.
- **Usage**: Exposed via `QrScannerScreen`.

## 28. Resident Booking Card & Rejection Banner
- **Description**: A resident booking card displayed in the bookings management list (`ManageBookingsScreen`). Shows amenity code, formatted date and time slot, and colored status chips. When a booking is rejected, it presents a prominent red callout box detailing the administrator's rejection rationale (`rejectionReason` / `notes`), gives an edit button to reschedule with the previous reason displayed for context, and provides a direct delete/cancel button allowing residents to clean up rejected or pending bookings. On approved bookings, displays a green next-steps instructions card containing the administrator's custom or preset approval instructions (`approvalMessage`).
- **Usage**: Exposed via `ManageBookingsScreen`.

## 29. Resident Sanctions & Infractions Viewer
- **Description**: A resident infraction history screen querying the `sanctions` collection filtered by `authorizedUids` (array-contains current UID). Each sanction card displays the infraction reason, monetary fine amount, issuance date, status chip (`active`, `pending_review`, `paid`, `cancelled`), and photographic evidence thumbnail. Tapping the thumbnail launches a full-screen interactive pinch-to-zoom modal dialog (`showInteractiveImageDialog`). For active sanctions, a primary "Pay Sanction" button seamlessly opens `PaymentScreen` pre-configured with the fine amount, concept set to "Sanction", and target sanction pre-selected.
- **Usage**: Exposed via `SanctionsScreen`.

## 30. Admin Sanctions Manager & Issuance Sheet
- **Description**: A complete administrative dashboard for managing neighborhood infractions. Features horizontal filter chips to inspect sanctions by status (All, Active, In Review, Paid, Cancelled), reactive metrics badges, and an elevated "Issue Sanction" floating action button. The bottom-sheet issuance form offers cascading street-and-number address selection, auto-resolves resident `authorizedUids` to maintain strict Firestore security rules compliance, captures fine amount and detailed reason, and allows snapping a camera photo or picking from gallery with high-compression optimization. Also includes a waiver/cancellation confirmation dialog to dismiss infractions.
- **Usage**: Exposed via `AdminSanctionsScreen`.

## 31. Payment Validation & Rejection Recovery Card
- **Description**: An enhanced payment submission interface featuring a concept switcher segmented button (Monthly Quota vs. Sanction), dynamic Folio text input with inline prefix iconography, payment date picker with calendar picker modal, advance periods toggle switch with checkbox list view, responsive horizontal receipt photo capture button container, and an isolated `ListenableBuilder` missing-fields warning banner and submit button. Explicit `FocusNode` instances, `ValueKey` identifiers, and memoized database stream instances decouple keystroke updates from screen rebuilds, completely eliminating virtual keyboard dismisses on mobile browsers while retaining instant validation feedback. When an address has a recently rejected payment, a top red recovery banner highlights the administrator's rejection rationale and provides a one-tap button to automatically pre-fill the form with the rejected payment's details.
- **Usage**: Exposed via `PaymentScreen`.

## 32. Facility Operating Hours & Schedule Viewer
- **Description**: An amenity reservation view providing transparent availability feedback. Highlights the facility's daily operating window badge (`openingTime` - `closingTime`) and enforces client-side time-picker bounds, preventing residents from selecting slots outside operating hours. Limits calendar selection to valid future dates based on the configured advance anticipation window (`anticipationUnit`, `anticipationValue`). Renders an anonymous schedule calendar streaming only confirmed bookings (`isConfirmed == true`) to protect resident privacy while clearly displaying occupied slots.
- **Usage**: Exposed via `BookingScreen`.

## 33. Explorer Document Card & Role Visibility Controls
- **Description**: A document card widget (`DocumentCard`) and upload/management dialog suite in `TransparencyScreen` supporting role-based visibility (`all` for all residents vs. `admin` for administrators only). Displays an `ADMIN ONLY` / `SOLO ADMIN` lock badge (`Icons.admin_panel_settings`) when `visibility == 'admin'`, alongside category, publication date, file size, and offline cache badges. Administrators can set visibility during document upload or toggle visibility on existing documents via the `Change Visibility` popup menu item (`_showChangeDocumentVisibilityDialog`). Non-admin residents automatically query and filter only `visibility == 'all'` documents.
- **Usage**: Exposed via `TransparencyScreen` and `DocumentCard`.
















