# Widget Catalog

Inventory of shared UI components, responsive layout patterns, and stable widget keys in Suburban Life. *(For database fields and Cloud Functions specs, see [`database_schema.md`](database_schema.md) and [`functions/README.md`](functions/README.md).)*

## Shared Widget Index

| Component | Source File | Reused By |
| :--- | :--- | :--- |
| `RotatableImagePreview` | [`lib/core/widgets/rotatable_image_preview.dart`](lib/core/widgets/rotatable_image_preview.dart) | Resident/Payment/Booking/Expense/Sanctions detail screens |
| `showInteractiveImageDialog` | [`lib/core/widgets/interactive_image_dialog.dart`](lib/core/widgets/interactive_image_dialog.dart) | All zoomable proof, receipt, sanction & ID/plate previews |
| `StorageNetworkImage` | [`lib/core/widgets/storage_network_image.dart`](lib/core/widgets/storage_network_image.dart) | Announcements, proofs, receipts, sanctions, `RotatableImagePreview` |
| `AppVersionLabel` | [`lib/core/widgets/app_version_label.dart`](lib/core/widgets/app_version_label.dart) | Resident Drawer, Admin Sidebar/Drawer, Guard Panel |
| `ErrorFallbackScreen` | [`lib/core/widgets/error_fallback_screen.dart`](lib/core/widgets/error_fallback_screen.dart) | `main.dart` (`ErrorWidget.builder`) |
| `FacilityDocumentsSection` | [`lib/features/booking/widgets/facility_documents_section.dart`](lib/features/booking/widgets/facility_documents_section.dart) | `BookingScreen`, `_ResubmitBookingDialog` |
| `FileExplorerBreadcrumb`, `FolderCard`, `DocumentCard` | [`lib/features/transparency/widgets/`](lib/features/transparency/widgets/document_card.dart) | `TransparencyScreen` |
| `NotificationBellButton`, `InAppNotificationBanner`, `NotificationsScreen`, `NotificationPreferencesSheet` | [`lib/features/notifications/notifications_screen.dart`](lib/features/notifications/notifications_screen.dart) | `MyHomePage`, `AdminShellScreen` |

---

## 1. Core Reusable Components

### RotatableImagePreview
- **File**: `lib/core/widgets/rotatable_image_preview.dart`
- **Behavior**: Rounded bordered preview wrapping `StorageNetworkImage` inside `RotatedBox` + `InkWell`, with top-right semi-transparent dark circular buttons for inline `90°` clockwise rotation (`Icons.rotate_right`) and full-screen modal launch (`Icons.open_in_full`), forwarding `initialQuarterTurns` to `showInteractiveImageDialog`. Supports `Expanded` and fixed-height cards plus scoped `ValueKey`s.

### Full-Screen Interactive Image Dialog
- **File**: `lib/core/widgets/interactive_image_dialog.dart` (`showInteractiveImageDialog`)
- **Behavior**: Full-screen viewer with 20% screen padding, `InteractiveViewer` pinch-to-zoom/pan, optional `initialQuarterTurns`, `90°` rotate button (`rotate_image_button`), and dismiss button.

### App Version Label
- **File**: `lib/core/widgets/app_version_label.dart` (`AppVersionLabel`)
- **Behavior**: Reads & caches bundled `web/version.json` via `DefaultAssetBundle` / `AppUpdateService.parseVersionPayload`, rendering localized `appVersionLabel` (`Version X / Versión X`) with ellipsis overflow protection.
- **Mount Keys**: `resident_app_version_label`, `admin_app_version_label`, `guard_app_version_label`.

### Release Error Fallback Screen
- **File**: `lib/core/widgets/error_fallback_screen.dart` (`ErrorFallbackScreen`)
- **Behavior**: Wired via `ErrorWidget.builder` in `main.dart`; replaces Flutter's red error screen in release builds with a localized Crashlytics notice card.

---

## 2. Application Shells, Drawers & Navigation

### Premium Action Header & Split Login Pane
- **Files**: `lib/main.dart`, `lib/features/auth/login_screen.dart`, `signup_screen.dart`, `forgot_password_screen.dart`
- **Layout**: Rounded bottom header (`Radius.circular(30)`, `AppConfig.primaryColor`) with `MediaQuery.paddingOf(context).top` safe inset. Wide `LoginScreen` switches to a side-by-side gradient split layout (`AppConfig.primaryColor` -> `AppConfig.gradientEndColor`); forms use `elevation: 4` padded cards (`radius: 15`, `padding: 24`) and Enter-key submission (`TextInputAction.next` / `.done`).

### Adaptive Admin Shell & Overview
- **File**: `lib/features/admin/admin_shell_screen.dart` (`AdminShellScreen`, `AdminSection`)
- **Breakpoints**: `< 900px` modal `Drawer` + collapsible `Overview` `ExpansionTile` cards (`mobile_section_pending_approvals`, `mobile_section_community_stats`, rolled-up `mobile_badge_pending_approvals`); `>= 900px` persistent `290px` sidebar + static Overview sections.
- **Navigation**: `Overview` (6 quick shortcut cards + `admin_overview_generate_qr_fab` FAB + conditional `overview_stat_currently_inside` when `scanOnExitEnabled`), 4 collapsible `ExpansionTile` groups with roll-up badges (`admin_group_badge_<id>`), direct `admin_nav_generalSettings` leaf tile, embedded child views (`isEmbedded: true`), pinned `admin_nav_logout` + `admin_app_version_label`. Dual `admin && resident` users also see Resign Admin & Switch View AppBar actions.

### Resident Dashboard & Guard Panel
- **File**: `lib/main.dart` (`MyHomePage`)
- **Resident UI**: Branded `DrawerHeader` (`AppConfig.appLogoAsset`), multi-address inline header `DropdownButton`, conditional `facilities` StreamBuilder hiding Booking shortcuts/drawer items when empty, `resident_app_version_label` footer.
- **Guard Panel**: Overflow-safe scrollable body with `guard_scan_qr_button` (`_isOpeningQrScanner` double-tap lock) and non-interactive `SafeArea` `guard_app_version_label` footer.

---

## 3. Auth & Onboarding Flows

### Unlinked Onboarding Card & Roommate Scanner
- **Files**: `lib/main.dart`, `lib/features/auth/roommates_screen.dart`
- **Behavior**: `SegmentedButton` toggles **Claim Property** vs **Join as Roommate** (`QrImageView` encoding `roommate_uid:$uid`, clipboard copy, live waiting stream) with persistent `onboarding_logout_button`. `RoommatesScreen` includes `MobileScanner` (rear default, front/back switch) + manual UID/email paste input.

### Ownership Proof Capture Overlay
- **File**: `lib/features/auth/ownership_proof_screen.dart` (`OwnershipProofScreen`)
- **Behavior**: Property handover date picker required before proof capture; displays target street/number, cancellation button, and storage deletion disclosure.

### Master-Detail Resident Ownership Approval
- **File**: `lib/features/auth/admin_resident_approval_screen.dart` (`AdminResidentApprovalScreen`, `AdminResidentDetailScreen`)
- **Layout**: Button-free keyed `_ResidentSummaryCard` queue -> responsive detail (`> 650px` side-by-side `RotatableImagePreview` + metadata; `<= 650px` stacked). Masks applicant email, invokes `reviewOwnershipClaim`, and carries keys `ownership_proof_thumbnail`, `inline_rotate_image_button`, `inline_proof_rotated_box`, `fullscreen_proof_button`.

---

## 4. Admin Management Screens

### Unified User Creation & Directory Master-Detail
- **Files**: `lib/features/admin/admin_create_user_screen.dart`, `admin_user_management_screen.dart` (`AdminUserManagementScreen`, `AdminUserDetailScreen`)
- **Directory**: Merges `adminListAuthUsers` + Firestore `users` with `manage_users_refresh_indicator` swipe-to-refresh, `manage_users_create_user_button` FAB, whole-DB search, 20-item pagination, `onboarding_incomplete_filter_chip`, and adaptive role filter (`< 680px` wrapping `role_filter_chip_<role>` `ChoiceChip`s; `>= 680px` `SegmentedButton`).
- **Detail (`user_card_<uid>`)**: `> 700px` side-by-side, `<= 700px` stacked; separates standard actions (`adminUpdateEmail`, password reset, role promotion except guards, delivery date edit) from Sensitive Actions (Unbind / Remove Account).

### Bulk CSV Managers (Users, Addresses, Historical Payments)
- **Files**: `admin_bulk_user_import_screen.dart`, `admin_bulk_address_import_screen.dart`, `admin_bulk_payment_import_screen.dart`
- **Patterns**: `Wrap` template Download (`CsvDownloadHelper`) / Copy actions (`bulk_address_download_template_button`, `bulk_user_download_template_button`), preview tables, and result CSV export. Payment importer adapts below `600px` / `520px`, includes a scrollable starting-period Month/Year dialog and sequential Keep-Existing vs Overwrite reconciliation dialog.

### Admin Settings (5 Auto-Saving Collapsible Cards)
- **File**: `lib/features/admin/admin_settings_screen.dart` (`AdminSettingsScreen`)
- **Behavior**: Cards `settings_card_payment` (includes cutoff/grace sliders + `initialBudgetBalance` + `initialBalancePeriod`), `settings_card_access_control` (`scanOnExitEnabled`), `settings_card_rejection_reasons`, `settings_card_smtp`, and `settings_card_email_template` (`< 520px` stacked `reset_default_template_button`). Displays `settings_autosave_banner` (`settings_autosave_status`); manual Save buttons apply only to SMTP (`save_smtp_config_button`) and email template (`save_email_template_button`).

### Facilities Configurator
- **File**: `lib/features/admin/admin_facilities_screen.dart` (`AdminFacilitiesScreen`)
- **Behavior**: Unique vs multi-item capacity toggle, hours & anticipation pickers, mutually exclusive restriction selector (`Unrestricted`, `Cooldown Period` in `hours|days|months|years`, or `Booking Quota` in `daily|monthly|yearly`), and Cancel-safe staged `facilityDocuments` mode editor (`mandatory_return`, `optional_return`, `informative`).

### Community Expenses & Financial Reports
- **Files**: `lib/features/admin/admin_expenses_screen.dart` (`AdminExpensesScreen`, `AdminExpenseDetailScreen`), `admin_payment_report_screen.dart` (`AdminPaymentReportScreen`)
- **Expenses**: KPI strip (`expenses_kpi_income`, `expenses_kpi_expenses`, `expenses_kpi_budget`), keyed cards (`expense_card_<id>`), `add_expense_fab` -> `_RecordExpenseModal` (dual evidence pickers + `submit_expense_button`), `AdminExpenseDetailScreen` (`RotatableImagePreview` / `expense_receipt_download_btn` + `_VoidExpenseDialog`).
- **Financial Reports**: Places `financial_summary_preview_card` at top, `Start Month` / `End Month` dropdowns below (stacked `< 520px`), and bottom export/publish buttons (`download_report_bundle_button`, `download_status_matrix_only_button`, `download_financial_ledger_only_button`, `publish_transparency_report_button`, `open_bulk_payment_import_button`).

### Master-Detail Payment & Booking Approvals
- **Files**: `lib/features/admin/admin_payment_approval_screen.dart` (`AdminPaymentApprovalScreen`, `AdminPaymentDetailScreen`), `admin_booking_approval_screen.dart` (`AdminBookingApprovalScreen`, `AdminBookingDetailScreen`)
- **Layout (`> 650px` wide / `<= 650px` stacked)**: Button-free keyed cards (`_PaymentSummaryCard`, `booking_card_<bookingId>`).
  - `AdminPaymentDetailScreen`: Shows receipt `RotatableImagePreview` (`payment_receipt_thumbnail`, `payment_inline_rotate_button`, `payment_fullscreen_button`) + linked sanction evidence when `concept == 'sanction'`.
  - `AdminBookingDetailScreen`: Side-by-side **Submitted Documentation** pane (`booking_attachments/{bookingId}`, `approval_view_attachment_<bookingId>_<docId>`, inline `RotatableImagePreview` for images) when attachments/templates apply, otherwise centered detail card.

---

## 5. Bookings, Payments & Sanctions

- **Booking Calendar & Restriction Badges (`lib/features/booking/booking_screen.dart`)**: Memoized streams, operating window & advance notice badges, active `bookingCooldownBadge` or reactive `bookingQuotaBadge` (`used/limit`), `FacilityDocumentsSection` (download `facility_doc_download_<docId>`, attach `facility_doc_attach_<docId>`, camera `facility_doc_camera_<docId>`), anonymous confirmed-only schedule list.
- **Manage Bookings (`lib/features/booking/manage_bookings_screen.dart`)**: `_BookingAttachmentsChips`, `bookingAttachmentsPurgedNotice` after 30d purge, red rejection banner with `_ResubmitBookingDialog` (preloads & replaces attachments) and cancel/delete, green approval instructions card.
- **Payments (`lib/features/payments/payment_screen.dart`, `admin_upload_payment_screen.dart`)**: Concept switch (Monthly Quota vs Sanction), cascading street/number selector, **Due / Pending** vs **Advance** `FilterChip` period grid, rejection recovery pre-fill banner, isolated `ListenableBuilder` + explicit `FocusNode`s preventing Web virtual keyboard dismissal.
- **Sanctions (`lib/features/sanctions/sanctions_screen.dart`, `admin_sanctions_screen.dart`)**:
  - Resident view queries `authorizedUids`, shows `RotatableImagePreview` evidence, and deep-links **Pay Sanction** into pre-filled `PaymentScreen`.
  - Admin view wraps 5 `FilterChip`s (`sanction_filter_chip_<status>`) in a portrait-friendly `Wrap`, wraps card headers cleanly, and issues sanctions via bottom sheet resolving `authorizedUids`.

---

## 6. QR Access, Announcements, Transparency & Notifications

- **Admin Access Logs (`lib/features/admin/admin_access_logs_screen.dart`)**: Top `access_logs_retention_banner`, KPI cards, 20-item pagination, address/date/search filters, adaptive visitor category selector (`< 520px` `visitor_type_chip_<type>`, `>= 520px` `SegmentedButton`), `filter_currently_inside_chip`, and `log_inside_badge_<id>` chips.
- **QR Generator & Manage QR (`lib/features/qr_access/qr_generator_screen.dart`, `manage_qr_screen.dart`)**: Renders `800x1200` Canvas-painted PNG pass (`share_plus` + Web download fallback); `ManageQrScreen` displays `qr_codes_retention_banner` and live `qr_inside_badge_<qrId>` chips.
- **Guard QR Scanner (`lib/features/qr_access/qr_scanner_screen.dart`)**: Unmounts `MobileScanner` when `!_isScanning`, locks validation/submission (`_isValidating`, `_isCapturingPhoto`, `_isProcessing`, `_activeValidationToken`) with blocking `qr_scanner_loading_overlay`, displays highlighted `qr_scanner_destination_address` (EN/ES `Admin office`, `#0` suppressed) on Entry & Exit, vertical bounded photo buttons (`capture_id_photo_button`, `capture_plate_photo_button`, `allow_access_button`, `deny_access_button`), and fast departure mode (`exit_notes_field`, `register_exit_button`), auto-popping on completion.
- **Announcements (`lib/features/announcements/announcements_screen.dart`)**: Desktop horizontal vs mobile vertical cards, emoji bar, gallery + Web clipboard paste (`Ctrl/Cmd+V`), proportional thumbnails, full-screen viewer.
- **Transparency Explorer & Bilingual Reader (`lib/features/transparency/`)**: `TransparencyScreen` uses `FileExplorerBreadcrumb`, `FolderCard`, `DocumentCard` (with `ADMIN ONLY` badge + active-locale cache status), hybrid bilingual resolution, and MIME/extension-restricted uploads (no `*/*`); `DocumentViewerScreen` renders `.md`/`.txt` with font zoom, sharing, and AppBar `document_viewer_language_switcher` (`document_viewer_lang_es` / `document_viewer_lang_en`).
- **Notifications (`lib/features/notifications/notifications_screen.dart`)**: `NotificationBellButton` (`notification_bell_button`, `99+` cap), dismissible `InAppNotificationBanner` (`in_app_notification_banner`), `NotificationsScreen` (`All`/`Unread`, swipe/delete, clear all, opt-in banner), and `NotificationPreferencesSheet` (`pushEnabled`, `inAppBannerEnabled`, role-gated categories) routed via `NotificationRouter`.
