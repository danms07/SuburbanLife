# Changelog

All notable changes to the **Suburban Life** project are documented in this file.

## [Unreleased] — 2026-11-08

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
  - Added a top-level `## Prerequisites` section documenting required SDK/CLI toolchains (`Flutter`, `Node.js 22`, `firebase-tools`, `flutterfire_cli`, and Google Cloud CLI `gcloud`).
  - Documented the one-time `gcloud` authentication, native Cloud Firestore TTL policy enablement (`access_logs.expireAt`, `qr_codes.expireAt`, and `booking_attachments.expireAt`), Cloud Storage Object Lifecycle bucket update (`storage_lifecycle.json`), and verification commands, linked from Setup Step 5.

