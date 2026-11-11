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
| **Dynamic Admin Roll-Up & Item Badges** | Admin Dashboard | [admin_shell_screen.dart](lib/features/admin/admin_shell_screen.dart) |
| **Adaptive Admin NavDrawer Workspace & Overview** | Admin Dashboard | [admin_shell_screen.dart](lib/features/admin/admin_shell_screen.dart) |
| **Dynamic Facilities Configurator** | Admin Settings | [admin_facilities_screen.dart](lib/features/admin/admin_facilities_screen.dart) |
| **Dynamic Matrix Payment Report Card**| Admin Reports | [admin_payment_report_screen.dart](lib/features/admin/admin_payment_report_screen.dart) |
| **Keyed Resident Summary Card & Detail Screen** | Resident Auth | [admin_resident_approval_screen.dart](lib/features/auth/admin_resident_approval_screen.dart) |
| **Keyed Payment Approval Card** | Admin Payments | [admin_payment_approval_screen.dart](lib/features/admin/admin_payment_approval_screen.dart) |
| **Categorized Multi-Period & Advance Payment Selector** | Payments | [payment_screen.dart](lib/features/payments/payment_screen.dart) |
| **Dynamic Shortcuts Grid & Drawer** | Core / Navigation | [main.dart](lib/main.dart) |
| **Branding Navigation Drawer Header** | Core / Navigation | [main.dart](lib/main.dart) & [admin_shell_screen.dart](lib/features/admin/admin_shell_screen.dart) |
| **Custom Branded QR Access Card** | QR Access | [qr_generator_screen.dart](lib/features/qr_access/qr_generator_screen.dart) |
| **Roommate QR Code Onboarding & Scanner** | Auth / Roommates | [main.dart](lib/main.dart) & [roommates_screen.dart](lib/features/auth/roommates_screen.dart) |
| **Bulk User Import CSV Manager** | Admin Management | [admin_bulk_user_import_screen.dart](lib/features/admin/admin_bulk_user_import_screen.dart) |
| **Bulk Address Import CSV Manager** | Admin Management | [admin_bulk_address_import_screen.dart](lib/features/admin/admin_bulk_address_import_screen.dart) |
| **General Settings & SMTP Configurator** | Admin Settings | [admin_settings_screen.dart](lib/features/admin/admin_settings_screen.dart) |
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
| **Resident QR Pass Inside Status Badge** | QR Access | [manage_qr_screen.dart](lib/features/qr_access/manage_qr_screen.dart) |
| **Facility Documentation & Resident Attachments Section** | Bookings | [facility_documents_section.dart](lib/features/booking/widgets/facility_documents_section.dart) |

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

## 7. Dynamic Admin Roll-Up & Item Badges
- **Description**: Reactive notification counters (`Badge`) inside `AdminShellScreen` backed by real-time streams on `ownership_claims`, pending `payments`, and pending `bookings`. When a sidebar/drawer category `ExpansionTile` is collapsed, child counts roll up onto the group header icon (`admin_group_badge_<id>`); when expanded, the group roll-up badge hides and individual counts display next to their specific child items (`Approve Residents`, `Review Bookings`, `Review Pending Payments`). On mobile viewports (`< 900px`), the collapsed `Pending Approvals` Overview card (`mobile_section_pending_approvals`) similarly displays a rolled-up total pending badge (`mobile_badge_pending_approvals`) that hides upon expansion.
- **Usage**: Displayed across the collapsible category groups and `Overview` pending-approval cards in `AdminShellScreen`.

## 8. Adaptive Admin NavDrawer Workspace & Overview
- **Description**: An adaptive administrative shell (`AdminShellScreen`) driven by `LayoutBuilder`. On desktop/wide viewports (`>= 900px`), it renders a persistent `290px` left navigation sidebar alongside the active module content; on mobile/narrow viewports (`< 900px`), it collapses into a modal hamburger `Drawer` with a branded `DrawerHeader`. Organizes all administrative tools into `Overview`, four collapsible `ExpansionTile` groups (`User Management`, `Residential Management`, `Finance`, and `Transparency & Community`), and a direct single-tap `General Settings` leaf tile (`admin_nav_generalSettings`, rendered without an expansion chevron since it is a single item), embedding child screens (`isEmbedded: true`) without duplicate nested `AppBar` headers, and pins a `Logout` tile (`admin_nav_logout`) to the bottom of the navigation panel. The default `Overview` landing screen renders `Pending Approvals` and `Live Community Status` as static sections on desktop (`>= 900px`) and as expandable/collapsible `ExpansionTile` cards (`mobile_section_pending_approvals` and `mobile_section_community_stats`, collapsed by default) on mobile (`< 900px`), displays the `Visitors currently inside` KPI card (`overview_stat_currently_inside`) exclusively when `config/app_settings.scanOnExitEnabled == true` (in real time alongside `Active Sanctions`), presents a responsive 6-card `Shortcuts` grid (`Create User`, `User Directory`, `Create Announcement` which directly launches the announcement creation modal, `Upload Payment on Behalf`, `Download Payment Report`, and `Settings`), and includes an Overview-exclusive `Generate Access QR` floating action button (`admin_overview_generate_qr_fab`). Its top `AppBar` is styled with `AppConfig.primaryColor` and white title/foreground icons, conditionally displaying both `Resign Admin Role` (`Icons.waving_hand`) and `Switch to Resident View` (`Icons.person`) only when the signed-in user holds dual `admin` and `resident` roles (`isAdmin && isResident`).
- **Usage**: Serves as the primary administrative workspace rendered by `MyHomePage` when in Admin View.

## 9. Dynamic Facilities Configurator & In-Place Editor
- **Description**: An administrative management interface allowing admins to configure, edit, and delete amenities. Integrates a dynamic `SwitchListTile` to switch between a "Unique Amenity" (locking capacity to 1) and a "Multi-item Amenity" (exposing quantity increment/decrement controls), daily operating hours pickers, advance notice settings, a mutually exclusive **Booking Restriction Policy** selector (`Unrestricted`, `Cooldown Period` measured in `hours | days | months | years` from a booking's end time to the next booking's start time per household, or `Booking Quota` limiting each household to `X` bookings per `daily | monthly | yearly` calendar period) with reactive `ValueListenableBuilder` human-readable rule previews, and a staged **Amenity Documentation** editor (`_buildDocumentsEditorSection`) allowing admins to attach templates/forms/rules (`pdf`, `doc`, `docx`, `xls`, `xlsx`, `jpg`, `jpeg`, `png`, `webp` up to 10 MB) with per-document requirement modes (`mandatory_return`, `optional_return`, `informative`). Staged edits inside `_EditFacilityDialog` never mutate live Storage files if dismissed via Cancel, while Save uploads new files (`Content-Disposition: attachment`) and deletes removed Storage objects cleanly.
- **Usage**: Used inside `AdminFacilitiesScreen`.

## 10. Admin Booking Approval Card & Submitted Documentation Panel
- **Description**: A pending booking review card (`_BookingApprovalCard`) in `AdminBookingApprovalScreen` displaying facility metadata, requested time slots, applicant contact details, and—whenever `hasAttachments == true` or the facility configures returnable documents—a real-time **Submitted Documentation** panel streaming `booking_attachments/{bookingId}` with requirement mode badges and one-tap **View / Download** (`approval_view_attachment_<bookingId>_<docId>`) controls before approving (with preset/custom `approvalMessage`) or rejecting (with `rejectionReason`).
- **Usage**: Exposed via `AdminBookingApprovalScreen`.

## 11. Dynamic Matrix Payment Report Card
- **Description**: An interactive reporting interface offering start and end month dropdown selectors to generate a localized CSV matrix. Evaluates monthly status blocks per address and includes automated no-data warning dialog alerts.
- **Usage**: Exposed via the `AdminPaymentReportScreen`.

## 12. Keyed Resident Summary Card & Dedicated Resident Approval Detail Screen
- **Description**: A two-stage Master-Detail administrative ownership-claim review flow matching the Payment Approval experience to prevent accidental inline approve/reject misclicks on mobile devices. In `AdminResidentApprovalScreen`, each pending `ownership_claims` entry renders as a compact, button-free, stateful `_ResidentSummaryCard` (keyed via `ValueKey(doc['id'])` to cache address and applicant lookups) displaying the physical address (`streetName #number`), `Pending Review` badge, applicant name chip, property handover date chip, and trailing chevron. Tapping a card pushes `AdminResidentDetailScreen`, which adapts via `LayoutBuilder`: on wide screens (`> 650px`), it displays the expanded rotatable ownership-proof preview (`ownership_proof_thumbnail`) on the left and the claim metadata (address header, applicant name, PII-masked email chip, handover date, submission date, privacy-by-design Storage deletion notice) with `Reject` / `Approve Resident` (`AppConfig.primaryColor`) action buttons on the right; on mobile screens (`<= 650px`), it renders a responsive vertical `Column` with constrained scrollable metadata and an `Expanded` proof preview. Administrators can rotate sideways deeds/utility bills in 90-degree increments directly inline (`inline_rotate_image_button` / `inline_proof_rotated_box`) or open the full-screen interactive zoom viewer (`showInteractiveImageDialog` with 20% screen padding, pinch-to-zoom, pan, and `rotate_image_button`, preserving `initialQuarterTurns`).
- **Usage**: Exposed via `AdminResidentApprovalScreen` and `AdminResidentDetailScreen`.

## 13. Keyed Payment Summary Card & Dedicated Payment Detail Screen
- **Description**: A two-stage address-level administrative payment review flow designed to prevent accidental approval misclicks on mobile devices. In `AdminPaymentApprovalScreen`, each pending submission renders as a compact, stateful `_PaymentSummaryCard` (keyed via `ValueKey(doc['id'])` to cache address lookups) showing basic payment info (physical address `streetName #number`, `$amount` badge, concept chip, explicitly labeled `Date of payment` chip, and trailing chevron) without inline action buttons. Tapping a card navigates to `AdminPaymentDetailScreen`, which adapts via `LayoutBuilder`: on wide screens (`> 650px`), it places the expanded clickable proof-of-payment image preview (`payment_receipt_thumbnail`) on the left and the payment details (`Folio`, `Date of payment`, `Period paid`, and for sanction payments the linked sanction's requested fine amount, infraction description, and photo evidence viewer) with the `Reject` / `Approve Payment` (`AppConfig.primaryColor`) action buttons on the right; on narrow/mobile screens, it uses a full-height vertical linear layout (`Column` with `Expanded` preview). Tapping anywhere on the receipt preview opens the full-screen interactive image viewer (`showInteractiveImageDialog` with 20% screen padding, `BoxFit.contain`, pinch-to-zoom, and 90-degree rotation button `rotate_image_button`).
- **Usage**: Exposed via `AdminPaymentApprovalScreen` and `AdminPaymentDetailScreen`.

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
- **Description**: A collapsible, card-based configuration panel (`AdminSettingsScreen`) organized into 5 expandable/collapsible `ExpansionTile` cards (`settings_card_payment`, `settings_card_access_control`, `settings_card_rejection_reasons`, `settings_card_smtp`, and `settings_card_email_template`, collapsed by default for fast navigation) with a live auto-save status banner (`settings_autosave_banner` / `settings_autosave_status`). Automatically persists all switches (`Scan on exit`, `Enable Automatic Welcome Emails`, and `Use SSL/TLS`) and general settings (payment cutoff day slider `onChangeEnd`, grace period slider `onChangeEnd`, schedule timezone dropdown, and custom payment rejection reason additions/deletions) in real time without overwriting unsaved text edits. Manual saving is required exclusively for the **SMTP Server Configuration** text fields (`save_smtp_config_button`, alongside standard port preset chips `587`, `465`, `25`, password visibility toggle, and an interactive `Test Connection` handshake tool) and the **Custom Welcome Message** template (`save_email_template_button`, featuring `%password%`, `%name%`, `%email%`, `%address%`, `%role%`, `%appName%` placeholder chips and a reset-defaults action).
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

## 25. User Directory Summary Card & Dedicated Account Detail Screen
- **Description**: A two-stage administrative user and security guard directory workflow designed to prevent accidental misclicks in the directory list (mirroring the `AdminPaymentApprovalScreen` pattern). In `AdminUserManagementScreen`, administrators browse via whole-database search and filtering (by user name, email, physical street name, and adaptive role selectors: wrapping `ChoiceChip`s `role_filter_chip_<role>` on narrow viewports `< 680px` and `SegmentedButton` on wide viewports) with a responsive `Wrap` search/batch summary bar (preventing horizontal cropping on mobile), 20-user batched query pagination (`limit: 20`, `startAfter: _lastDocId`), and a quick `Create User` shortcut (`manage_users_create_user_button` pre-selected to the active role filter). Each user renders as a compact, button-free summary card (`user_card_<uid>`) showing role-styled avatar, name, email, role badge, linked address, handover date, live payment standing (`paid`, `restricted`, `pending`, `reviewing`), and a trailing chevron. Tapping a card navigates to `AdminUserDetailScreen`, which adapts via `LayoutBuilder` (side-by-side `Row` on wide viewports `> 700px`, vertical stack on mobile) and separates standard actions (`Change User Password`, `Promote to Admin` / `Revoke Admin` hidden on guard accounts, and `Edit Delivery Date` updating `deliveryDate` without recalculating `paymentStatus`) from an isolated **Sensitive Actions** container (`Unbind Address` and `Remove Account`, which pops back to the directory upon deletion while blocking self-revocation/self-deletion).
- **Usage**: Exposed via `AdminUserManagementScreen` and `AdminUserDetailScreen`.

## 26. Admin Access Logs & History Viewer
- **Description**: A comprehensive audit and security log viewer featuring a top localized 60-day auto-removal retention notice banner (`access_logs_retention_banner`), whole-database query search & filtering (address dropdown, wrapping date range chips: Today, This Week, This Month, Custom Date Range, adaptive visitor category selectors: wrapping `ChoiceChip`s `visitor_type_chip_<type>` on narrow viewports `< 520px` and `SegmentedButton` on wide viewports, **Currently Inside** filter chip (`FilterChip` keyed `filter_currently_inside_chip`), and real-time keyword search across guest name, license plates, resident host, entry/exit guards, and entry/exit notes) with a responsive `Wrap` search/batch summary bar and 20-item batched query exploration (`limit: 20`, `startAfter: _lastDocId`) for unfiltered exploration. Features KPI summary cards (Total Events, Allowed, Denied, Providers, **Currently Inside**), log detail cards with **Inside** status badges (`log_inside_badge_<id>`), **Entry Time** and **Exit Time** metadata (including legacy same-day QR open-visit fallback), entry/exit guard names, entry/exit reason boxes, and tap-to-zoom interactive photos (`showInteractiveImageDialog`).
- **Usage**: Exposed via `AdminAccessLogsScreen`.

## 27. Security Guard QR Scanner & Decision Interface
- **Description**: A security access interface designed for gate guards to scan visitor/supplier QR passes. Features a live camera scanner overlay (`MobileScanner`, automatically unmounted while `!_isScanning` so camera/GPU buffers are released before external camera capture) with camera selector controls (back/front camera toggle in AppBar actions and floating button on scanner preview, defaulting explicitly to rear camera) and automatic **Entry vs. Fast Exit** detection powered by `validateAndRegisterQrAccess`. On **Entry**, displays guest/vehicle details, vertical ID/plate photo capture controls (`capture_id_photo_button`, `capture_plate_photo_button`, bounded to `1600px` max dimensions), optional reason notes, and balanced `Allow Access` (`allow_access_button`) / `Deny Access` (`deny_access_button`) buttons. Captured temporary device photos (and Android `scaled_` companion raw captures / Web `blob:` URLs) are automatically deleted via `TempImageCleanupService` immediately after Cloud Storage upload, as well as on photo retake, `Scan Again` (`scan_again_button`), screen disposal, and stale-capture startup sweep. On **Exit** (`isExit == true`), switches to a teal departure header showing visitor details, formatted entry time, interactive entry ID/plate photo viewers (`showInteractiveImageDialog`), an optional exit notes `TextField` (`exit_notes_field`), and a single one-tap `Register Exit` button (`register_exit_button`) without requiring new photo captures. Upon completing an entry decision or exit registration, automatically pops back (`Navigator.pop`) to the security guard main screen.
- **Usage**: Exposed via `QrScannerScreen`.

## 28. Resident Booking Card & Rejection Banner
- **Description**: A resident booking card displayed in the bookings management list (`ManageBookingsScreen`). Shows amenity code, formatted date and time slot, colored status chips, interactive `_BookingAttachmentsChips` (`ActionChip`s streaming submitted attachments from `booking_attachments/{bookingId}`), and a localized 30-day purged notice (`bookingAttachmentsPurgedNotice`) once expired attachments have been cleaned up (`attachmentsPurgedAt != null`). When a booking is rejected, it presents a prominent red callout box detailing the administrator's rejection rationale (`rejectionReason` / `notes`), gives an edit button (`_ResubmitBookingDialog`) that preloads existing submitted attachments and lets the resident replace or re-upload completed documents while routing atomically through `BookingService.uploadAndCreateBooking(..., resubmitBookingId: doc['id'])` (cleaning up superseded Storage files on the server), and provides a direct delete/cancel button allowing residents to clean up rejected or pending bookings (immediately purging any attached Storage files). On approved bookings, displays a green next-steps instructions card containing the administrator's custom or preset approval instructions (`approvalMessage`).
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

## 32. Facility Operating Hours, Household Restriction Badges & Schedule Viewer
- **Description**: An amenity reservation view providing transparent availability and fair-use policy feedback via memoized streams. Highlights the facility's daily operating window badge (`openingTime` - `closingTime`), advance notice badge (`anticipationUnit`, `anticipationValue`), and active household restriction badge: either a **Cooldown Badge** (`bookingCooldownBadge`, e.g., `Cooldown: 4 hours`) or a reactive **Household Quota Usage Badge** (`bookingQuotaBadge`, e.g., `Monthly quota: 1/2 used` for the selected calendar period, turning red when exhausted). Renders `FacilityDocumentsSection` when the selected amenity defines `facilityDocuments`, enforcing client-side mandatory-return document checks alongside operating hours, advance notice, end-after-start, and household cooldown/quota pre-validation prior to calling `uploadAndCreateBooking`, while rendering an anonymous schedule calendar streaming only confirmed bookings (`isConfirmed == true`) to protect resident privacy.
- **Usage**: Exposed via `BookingScreen`.

## 33. Explorer Document Card & Role Visibility Controls
- **Description**: A document card widget (`DocumentCard`) and upload/management dialog suite in `TransparencyScreen` supporting role-based visibility (`all` for all residents vs. `admin` for administrators only). Displays an `ADMIN ONLY` / `SOLO ADMIN` lock badge (`Icons.admin_panel_settings`) when `visibility == 'admin'`, alongside category, publication date, file size, and offline cache badges. Administrators can upload documents via an explicit document/image MIME and extension allow-list (`webUploadAcceptAttribute` / `allowedUploadExtensions`, avoiding wildcard `*/*`, `audio/*`, and `video/*` so mobile Chromium/Edge browsers on Android 13+ launch the native `ACTION_GET_CONTENT` system file picker without demanding microphone or broad media permissions) with filename traversal sanitization and a 10 MB size cap, set visibility during upload, or toggle visibility on existing documents via the `Change Visibility` popup menu item (`_showChangeDocumentVisibilityDialog`). Non-admin residents (and users opening `TransparencyScreen(isAdminView: false)` from the Resident panel or whose Firestore `users/{uid}.role` is not `admin`) automatically query and filter only `visibility == 'all'` documents and folders, strictly hiding admin-only folders (`official_manuals` and any folder with `visibility == 'admin'`) and their contents.
- **Usage**: Exposed via `TransparencyScreen` (`TransparencyScreen(isAdminView: false)` in Resident View, `TransparencyScreen(isAdminView: true)` in Admin View) and `DocumentCard`.

## 34. Resident QR Pass Retention Banner & Inside Status Badge
- **Description**: A localized 7-day inactive QR pass retention notice banner (`qr_codes_retention_banner`) rendered at the top of both empty and populated resident QR pass views, paired with a live teal status chip (`_buildInsideChip`, keyed `qr_inside_badge_<qrId>`) displayed alongside the pass status badge on resident QR pass cards when `QrService.isVisitorInside(qr)` (`qr['isInside'] == true`). Informs residents that expired, validated, and revoked passes are automatically removed after 7 days (while active permanent passes do not expire) and shows in real time when a guest or supplier is currently inside the community without requiring read access to `access_logs`.
- **Usage**: Exposed via `ManageQrScreen`.

## 35. Facility Documentation & Resident Attachments Section
- **Description**: A reusable cross-platform documentation and attachment card (`FacilityDocumentsSection`) rendered in `BookingScreen` and `_ResubmitBookingDialog`. Displays each configured `FacilityDocumentTemplate` with file-type iconography, localized requirement badge (`Required Return`, `Optional Return`, or `Informative`), file size metadata, and a cached **Download / View** button (`facility_doc_download_<docId>`). For `mandatory_return` and `optional_return` templates, renders **Attach Completed File** / **Replace** (`facility_doc_attach_<docId>`, supporting `pdf`, `doc`, `docx`, `xls`, `xlsx`, `jpg`, `jpeg`, `png`, `webp` up to 10 MB with magic-byte validation) and native **Take Photo** (`facility_doc_camera_<docId>`, bounded to `1600px` with automatic temp-file cleanup via `TempImageCleanupService`), selected file preview chips with removal controls, and a localized 30-day privacy retention notice (`bookingAttachmentsRetentionHelper`).
- **Usage**: Exposed via `lib/features/booking/widgets/facility_documents_section.dart` inside `BookingScreen` and `ManageBookingsScreen`.
















