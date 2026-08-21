# Widget Catalog

This catalog inventories the custom reusable UI elements and visual structures established across the SuburbanLife application.

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
| **Period Selection Dropdown** | Payments | [payment_screen.dart](lib/features/payments/payment_screen.dart) |
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

---

## 1. Premium Action Header & Split Pane
- **Description**: A double-sized action bar featuring a rich background color (`AppConfig.primaryColor`) with beautifully rounded bottom corners (`Radius.circular(30)`). For wide screens, `LoginScreen` adapts to a premium side-by-side split layout where the left welcome pane features a linear gradient utilizing the `AppConfig.primaryColor` and `AppConfig.gradientEndColor` tokens.
- **Usage**: Used as the top header in `MyHomePage`, `LoginScreen` (on mobile/narrow screens), `SignupScreen`, and `ForgotPasswordScreen` to wow the user and establish visual consistency.
- **Properties**:
  - Top padding: Responsive `MediaQuery.paddingOf(context).top + 16` (instead of hardcoded `60px` to support notch screens while remaining compact on web/desktop).
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

## 9. Dynamic Facilities Configurator
- **Description**: An administrative form card allowing admins to configure dynamic amenities. Integrates a dynamic `SwitchListTile` to switch between a "Unique Amenity" (which locks capacity to 1) and a "Multi-item Amenity" (which exposes dynamic quantity increment/decrement controls).
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
- **Description**: An optimized, stateful card representing an individual pending payment receipt review. Uses a stateful structure to cache the user query future and is keyed via `ValueKey(doc['id'])` in parent lists to preserve state, avoiding redundant image downloads and Firestore fetches. It formats and displays the target billing period.
- **Usage**: Internal sub-widget inside `AdminPaymentApprovalScreen`.

## 14. Period Selection Dropdown
- **Description**: A form selector (`DropdownButtonFormField`) that dynamically compiles and lists missing/rejected billing periods from the property delivery date up to the current month. The selected period is formatted based on locale settings ('YYYY-MM' for English, 'MM-YYYY' for Spanish).
- **Usage**: Used inside `PaymentScreen` to enforce selecting a period before uploading a receipt.

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
- **Description**: A dual-sided QR and UID account linking system for roommates and family members. On the unlinked account onboarding card (`main.dart`), an interactive `SegmentedButton` lets users toggle between "Claim Property" and "Join as Roommate". The Roommate tab presents a high-contrast `QrImageView` encoding `roommate_uid:$uid`, user credentials, a selectable plain-text UID box with an inline "Copy to Clipboard" icon button (`Clipboard.setData`), a full-width copy action button, and a live stream builder waiting indicator. In `RoommatesScreen`, primary residents can launch an inline camera QR scanner sheet powered by `MobileScanner` to scan roommate QR codes or manually type/paste a roommate UID or email address using the built-in `content_paste` suffix button in the input field.
- **Usage**: Used during initial onboarding in `main.dart` and inside `RoommatesScreen`.

## 19. Bulk User Import CSV Manager
- **Description**: An administrative interface allowing bulk creation of resident user accounts from an uploaded CSV file. Features a file picker, a robust CSV parser (detecting headers or positional defaults), an interactive preview list of parsed rows showing assigned or deterministic temporary passwords, a copy template action, and a full results report view with copy-all passwords functionality.
- **Usage**: Exposed via `AdminBulkUserImportScreen`.

## 20. Bulk Address Import CSV Manager
- **Description**: An administrative interface for pre-populating physical neighborhood address records into Firestore from a CSV file. Supports parsing street names, initial house numbers, final house numbers, and optional house number exclusions. Offers a CSV template copy helper, live row preview listing, and collision checks against existing database records.
- **Usage**: Exposed via `AdminBulkAddressImportScreen`.

## 21. Admin Settings & SMTP Configurator
- **Description**: A multi-section configuration panel for administrators to adjust payment cutoff days, grace period limits, and configure a custom SMTP mail server. Includes preset chips for standard ports (587, 465, 25), SSL/TLS switch, password visibility toggle, a rich customizable welcome message template editor with placeholder chips (`%password%`, `%name%`, `%email%`, `%address%`, `%role%`, `%appName%`) and reset defaults action, and an interactive connection testing tool that executes an SMTP handshake and sends a test email to verify credentials before saving.
- **Usage**: Exposed via `AdminSettingsScreen`.

## 22. Unified User Creation Manager
- **Description**: A centralized administrative interface for provisioning new accounts across all user tiers: Resident, Security Guard, and Administrator. Features a dynamic form switcher driven by a user type selector (defaulting to Resident), password visibility toggles, automated secure password generator, and reactive cascading street-and-number selectors ensuring collision-free address assignment. For Administrator accounts, automatically ensures linkage to the fixed "Admin office" address.
- **Usage**: Exposed via `AdminCreateUserScreen`.

## 23. Rich Media, Clipboard Pasting & Emoji Announcements Feed
- **Description**: A responsive feed interface rendering community notices and administrative broadcasts. Features orientation-aware client-side proportional thumbnail generation for landscape and portrait images, responsive desktop (horizontal side-by-side card) and mobile (linear vertical card) layouts, tap-to-zoom full-screen interactive image viewer (`InteractiveViewer`), audience badges (All vs. Residents), and full native emoji support across titles and message bodies. In administrative mode, an enhanced creation modal features a quick-tap horizontal emoji bar (`📢`, `🚨`, `⚠️`, `ℹ️`, `🔔`, etc.), cross-platform gallery image picker, direct clipboard image pasting button, automatic system clipboard image capture (`Ctrl+V` / `Cmd+V` & browser `onPaste` event stream), live thumbnail preview, and upload progress indicator.
- **Usage**: Exposed via `AnnouncementsScreen`.

## 24. Release Error Fallback Screen
- **Description**: A user-friendly, beautifully styled fallback error screen displayed during fatal framework rendering or widget build crashes in release builds (intercepted via `ErrorWidget.builder`). Prevents standard red/grey crash screens by presenting a clean alert card with bilingual support (`AppLocalizations`) explaining that an automatic incident report has been dispatched to Firebase Crashlytics.
- **Usage**: Configured globally in `main.dart` via `ErrorWidget.builder` and defined in `lib/core/widgets/error_fallback_screen.dart`.













