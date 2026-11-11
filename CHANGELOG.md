# Changelog

All notable changes to the **Suburban Life** project are documented in this file.

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

