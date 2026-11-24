# Cloud Functions Reference (`functions/`)

Node.js **24** runtime (`firebase-functions` v2, `firebase-admin` v14 modular SDK). App Check (`enforceAppCheck: true, consumeAppCheckToken: true`) is active in production and disabled automatically in Firebase Emulators (`callableOptions`).

- [`index.js`](index.js): All HTTPS `onCall` callables, Firestore triggers, and daily cron jobs.
- [`notifications.js`](notifications.js): Bilingual template builders, category/route allow-listing, RTDB mirroring/pruning, and FCM multicast + stale token cleanup.
- [`brand_config.js`](brand_config.js): Shared brand palette and typography constants for HTML welcome emails (mirrors `AppConfig`).

---

## 1. HTTPS Callable Functions (`onCall`)

### Auth, Roles & Users
| Function | Access | Purpose / Key Inputs |
| :--- | :--- | :--- |
| `setRole` | Admin | Sets single role (`admin`, `resident`, `guard`, `roommate`) custom claim for `{ uid, role }`. |
| `setCustomUserClaims` | Admin | Updates claims map `{ uid, claims }`; prevents self-revoking `admin`. |
| `adminListAuthUsers` | Admin | Paginates `getAuth().listUsers()`, enriched with Firestore `users` onboarding metadata (`hasFirestoreProfile`, `hasAddress`, `onboardingCompleted`). |
| `adminUpdateEmail` | Admin | Validates `{ uid, newEmail }`, updates Firebase Auth email + syncs `users/{uid}.email`. |
| `adminUpdatePassword` | Admin | Updates Auth password for `{ uid, newPassword }`. |
| `adminCreateUser` | Admin | Creates Auth user (`name`, `email`, `password`, `role`, address fields / `deliveryDate`), sets claims, links address as `'paid'`, optionally emails credentials. |
| `adminProvisionGuard` | Admin | Creates Auth/Firestore guard account `{ name, email, password }`. |
| `adminDeleteUser` | Admin | Deletes Auth + Firestore user and cleans RTDB `/notifications/{uid}` + `/user_notification_settings/{uid}`. |
| `adminBulkImportResidents` | Admin | Batch creates residents `{ users }` matching existing addresses, generates secure/deterministic passwords, links addresses, returns per-row status. |
| `adminBulkImportAddresses` | Admin | Batch creates/validates `addresses` from `{ items }`. |
| `unbindAddress` | Self or Admin | Unlinks `{ uid }` from address/roommates cleanly (preserves `HttpsError` codes). |
| `deleteOwnAccount` | Authenticated | Deletes caller's own Auth + Firestore account cleanly. |
| `addRoommate` | Primary Resident | Links roommate by `{ email, roommateUid }`, syncs `familyMembers`/`addressRef`, dispatches bilateral notifications. |
| `removeRoommate` | Resident or Admin | Unlinks `{ roommateUid }` from family group/address. |
| `reviewOwnershipClaim` | Admin | Atomically approves/rejects `{ claimId, action, reason }`, binds address/claims, deletes private Storage proof, dispatches RTDB/FCM notification. |

### Bookings, Payments & Expenses
| Function | Access | Purpose / Key Inputs |
| :--- | :--- | :--- |
| `createBooking` | Authenticated | Enforces `!hasActiveSanctions`, clashes, operating hours, advance notice, household (`addressId` + legacy `userUid`) cooldown/quota, magic-byte + UID-path verification of attachments (`booking_attachments/{bookingId}` w/ 30d `expireAt`), `resubmitBookingId` atomic overwrite + Storage cleanup; returns JSON-safe `booking` (`toSerializableBookingResponse` omits `DocumentReference`). |
| `cancelBooking` | Creator / Household / Admin | Cancels booking and immediately deletes `booking_attachments/{bookingId}` + Storage files. |
| `approvePayment` | Admin | Approves `{ paymentId, residentUid }`, updates periods/sanctions/address standing, dispatches resident review notification. |
| `adminPreCheckPaymentImport` | Admin | Pre-validates bulk historical payment rows `{ items }` and detects existing amount mismatches. |
| `adminBulkImportPayments` | Admin | Applies `{ items, reconciliationDecisions }` idempotently and recalculates affected addresses. |
| `createExpense` | Admin | Validates fields, UID-scoped Storage ownership (`expenses/{uid}/`), and 16-byte magic bytes (deletes spoofed files) for `productEvidence` (JPG/PNG/WEBP) + `receiptEvidence` (JPG/PNG/WEBP/PDF); writes `/expenses`. |
| `voidExpense` | Admin | Transactionally transitions `'active' -> 'voided'` with mandatory `voidReason` (preserves record + Storage proof). |

### QR Access, Transparency & Settings
| Function | Access | Purpose / Key Inputs |
| :--- | :--- | :--- |
| `validateAndRegisterQrAccess` | Guard or Admin | Atomically validates QR entry or auto-detects Scan-on-Exit (`scanOnExitEnabled` + legacy same-day fallback), resolves destination `addressDisplay` (`formatAccessAddressDisplay`, `Admin office`, `openLog` fallback), invalidates single-use passes, stamps 60d `access_logs.expireAt` and 7d terminal `qr_codes.expireAt`. |
| `syncTransparencyDocument` | Admin | Publishes single or bilingual (`translations`) files to `documents/` + `documents/{docId}` (`translatedTitles`, `translatedFiles`, `folderNameKey`, `localizedNames`, default `'all'` folder visibility outside `official_manuals`) and deletes superseded Storage objects on republish. |
| `adminTestSmtpConnection` | Admin | Verifies SMTP settings `{ host, port, secure, user, pass, ... }` via `nodemailer` and optionally sends a test message. |

---

## 2. Firestore Triggers & Scheduled Jobs

| Trigger / Schedule | Event / Schedule | Behavior |
| :--- | :--- | :--- |
| `translateAnnouncement` | `announcements/{id}` create | Translates title/content ES↔EN via Vertex AI (`gemini-3.8-flash`) and dispatches announcement notifications. |
| `onPaymentWritten` | `payments/{id}` write | Recalculates address `paymentStatus` / grace period and notifies admins on new pending proofs. |
| `onSanctionWritten` | `sanctions/{id}` write | Recalculates `hasActiveSanctions` standing and notifies residents on new active sanctions. |
| `onOwnershipClaimCreated` | `ownership_claims/{id}` create | Notifies admins of new pending claim. |
| `onOwnershipClaimDeleted` | `ownership_claims/{id}` delete | Legacy fallback notification if client deletes claim directly on approval (deduplicated by deterministic RTDB key). |
| `onBookingWritten` | `bookings/{id}` write | Notifies admins on `'pending review'` and residents on decision (`approved` / `rejected`). |
| `onTransparencyDocumentWritten` | `documents/{id}` write | Notifies eligible residents/admins on creation or `'admin' -> 'all'` promotion (intersects folder visibility). |
| `notifyAccessResult` | `access_logs/{id}` write | Dispatches QR entry/exit notification and invalidates one-time passes when not `isInside`. |
| `onAccessLogDeleted` | `access_logs/{id}` delete | Deletes allow-listed `visitor_ids/**` & `visitor_plates/**` in Storage (`404`-tolerant) and heals open `qr_codes.isInside`. |
| `onBookingAttachmentDeleted` | `booking_attachments/{id}` delete | Deletes allow-listed `booking_attachments/**` in Storage and stamps `bookings/{id}.attachmentsPurgedAt`. |
| `checkMonthlyPaymentStatuses` | Cron `0 0 * * *` (`America/Mexico_City`) | Recalculates all address payment statuses; expires outdated QRs; sweeps terminal QRs (>7d), `access_logs` (>60d), `booking_attachments` (>30d), and RTDB notifications (>30d or >100 items/user). |

---

## 3. Notifications Module (`functions/notifications.js`)

- **7 Categories**: `reviews`, `sanctions`, `qr_access`, `roommates`, `transparency`, `announcements`, `admin_reviews`.
- **12 Allow-Listed `targetRoute`s**: `home`, `notifications`, `payments`, `sanctions`, `bookings`, `qr_codes`, `roommates`, `transparency`, `announcements`, `admin_claims`, `admin_payments`, `admin_bookings`.
- **Delivery & Cleanup**: Checks per-user RTDB settings (`/user_notification_settings/{uid}`), writes bilingual inbox entries to `/notifications/{uid}/{key}`, sends FCM multicast (chunks of 500) pruning `registration-token-not-registered` / `invalid-registration-token` / `mismatched-credential` from `users/{uid}.fcmTokens`, and caps RTDB inbox at **30 days / 100 items per user**.

## 4. Testing

```bash
npm --prefix functions test   # Runs helpers.test.js, notifications.test.js, handlers.test.js, security_rules.test.js
```
