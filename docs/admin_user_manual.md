# Suburban Life — Administrator User Manual

Welcome to the **Suburban Life Administrator User Manual**. This document provides a complete operational guide for residential administrators, property managers, and board members to manage community infrastructure, resident onboarding, financial approvals, access control, and amenity bookings.

---

## Table of Contents

1. [System Access & Admin Dashboard](#1-system-access--admin-dashboard)
2. [Property & Address Management](#2-property--address-management)
   - [2.1 Bulk Address Import via CSV](#21-bulk-address-import-via-csv)
   - [2.2 Address Directory & Status Tracking](#22-address-directory--status-tracking)
3. [Resident Onboarding & User Management](#3-resident-onboarding--user-management)
   - [3.1 Bulk Resident Creation via CSV](#31-bulk-resident-creation-via-csv)
   - [3.2 Single Resident & Roommate Registration](#32-single-resident--roommate-registration)
   - [3.3 Property Ownership Claim Approvals](#33-property-ownership-claim-approvals)
   - [3.4 User Directory & Role Management](#34-user-directory--role-management)
4. [Financial & Payment Approvals](#4-financial--payment-approvals)
   - [4.1 Payment Proof Review & Status Recalculation](#41-payment-proof-review--status-recalculation)
   - [4.2 Uploading Payments on Behalf of Residents](#42-uploading-payments-on-behalf-of-residents)
   - [4.3 Payment Matrix CSV Reports](#43-payment-matrix-csv-reports)
5. [Security & Access Control](#5-security--access-control)
   - [5.1 Security Guard Account Provisioning](#51-security-guard-account-provisioning)
   - [5.2 Administrative QR Pass Generator](#52-administrative-qr-pass-generator)
6. [Facilities & Amenity Management](#6-facilities--amenity-management)
   - [6.1 Dynamic Amenities Configurator](#61-dynamic-amenities-configurator)
   - [6.2 Booking Cooldown & Capacity Rules](#62-booking-cooldown--capacity-rules)
7. [System Configuration & Rules](#7-system-configuration--rules)
   - [7.1 Maintenance Fee Cutoff & Grace Period](#71-maintenance-fee-cutoff--grace-period)
8. [Community Announcements & AI Translations](#8-community-announcements--ai-translations)

---

## 1. System Access & Admin Dashboard

Administrators log in using credentials provisioned with the **`admin`** custom claim (`{ admin: true }`). 

### Admin Dashboard Overview
Upon logging in, administrators land on the **Admin Dashboard**, which features:
* **Real-time Pipeline Badges**: Dynamic notification badges over action buttons ("Approve Residents", "Review Payments") displaying pending approval counts in real time.
* **Navigation Grid**: Direct access to all administrative modules.
* **Quick Access Drawer**: Fast navigation menu for switching screens or accessing personal settings.

---

## 2. Property & Address Management

Before residents can link their accounts to physical homes, physical addresses must exist in the database.

### 2.1 Bulk Address Import via CSV
To initialize or expand the residential directory, administrators can import streets and house numbers in bulk using a CSV file.

* **Navigation**: Dashboard $\rightarrow$ **Bulk Address Import (CSV)** (`AdminBulkAddressImportScreen`).
* **CSV Format & Headers**:
  ```csv
  streetName,initialNumber,finalNumber,exclusions
  "Avenida Olmos",1,50,"12,14"
  "Calle Robles",10,30,""
  "Paseo del Valle",101,120,"105,115"
  ```

#### Field Description:
* **`streetName`**: The full name of the street or avenue.
* **`initialNumber`**: Starting house number in the range (e.g., `1`).
* **`finalNumber`**: Ending house number in the range (e.g., `50`).
* **`exclusions`**: Comma-separated list of house numbers to skip (e.g., `"12,14"`).

#### Steps to Import:
1. Tap **Copy CSV Template** to copy a sample CSV structure to the clipboard, or prepare a `.csv` file.
2. Tap **Upload CSV File** and select your document.
3. Review the **Parsed Address Ranges Preview** showing generated house numbers and excluded units.
4. Tap **Import Addresses**. The system generates address records in batch transactions and displays a summary of created and existing addresses.

---

## 3. Resident Onboarding & User Management

### 3.1 Bulk Resident Creation via CSV
Administrators can create resident accounts in bulk without requiring residents to submit ownership proof documents manually.

* **Navigation**: Dashboard $\rightarrow$ **Bulk User Creation (CSV)** (`AdminBulkUserImportScreen`).
* **CSV Format**:
  ```csv
  name,email,password,street,number
  "John Doe",john.doe@example.com,,1st Avenue,101
  "Jane Smith",jane.smith@example.com,SecretPass123!,Oak Street,12
  ```

#### Features:
* **Instant Claims**: Users are immediately granted `{ resident: true }` claims and `role: 'resident'`.
* **Deterministic Temporary Passwords**: If the `password` column is omitted or left empty, the system generates a secure temporary password: `Suburban#<emailLocalPart>2026` (e.g., `john.doe@example.com` $\rightarrow$ `Suburban#john.doe2026`).
* **Address Linking & Verification**: If `street` and `number` are provided, the system verifies the address in the database, sets `residentUid`, and marks `paymentStatus: 'paid'`. If the address is not found in the DB, the row is rejected with a clear error message.
* **Result CSV Export**: After execution, administrators can tap **Download Result CSV** or **Copy Result CSV** to retrieve a complete spreadsheet containing execution status (`ok`/`error`), assigned passwords, and detailed error messages.

### 3.2 Single Resident & Roommate Registration
* **Navigation**: Dashboard $\rightarrow$ **Register Resident** (`AdminResidentRegistrationScreen`).
* Allows manual registration of individual primary residents or roommates.
* Features cascading street and house number selectors with address collision warnings if the property is already claimed.

### 3.3 Property Ownership Claim Approvals
When residents self-register via the mobile app, they submit property proof photos and handover dates.

* **Navigation**: Dashboard $\rightarrow$ **Approve Residents** (`AdminResidentApprovalScreen`).
* **Review Process**:
  1. Inspect the resident's submitted proof document (e.g. deed or utility bill).
  2. Verify the property handover date.
  3. Tap **Approve**: Sets `{ resident: true }` claim, links the address document, sets `paymentStatus: 'paid'`, and updates `deliveryDate`.
  4. Tap **Reject**: Notifies the resident to resubmit valid proof.

### 3.4 User Directory & Role Management
* **Navigation**: Dashboard $\rightarrow$ **User Management** (`AdminUserManagementScreen`).
* **Directory Table**: Lists all registered accounts, user UIDs, assigned roles, and current claims.
* **Role Modifications**: Upgrade or downgrade accounts between **Resident**, **Security Guard**, and **Administrator**.
* **Force Unbind Address**: Unlinks a resident from an address if they move out or transfer ownership.

---

## 4. Financial & Payment Approvals

### 4.1 Payment Proof Review & Status Recalculation
Residents upload monthly maintenance fee receipts to remain in good standing.

* **Navigation**: Dashboard $\rightarrow$ **Review Payments** (`AdminPaymentApprovalScreen`).
* **Review Process**:
  1. View submitted payment receipts and target billing period (e.g. `2026-07`).
  2. Tap **Approve**: Sets receipt status to approved, updates `lastPaymentApproval`, and automatically recalculates the address's overall `paymentStatus` (`paid`, `pending`, or `restricted`).
  3. Tap **Reject**: Prompts for rejection reason to alert the resident.

### 4.2 Uploading Payments on Behalf of Residents
Administrators can manually record maintenance payments for residents who pay in cash or bank transfer.

* **Navigation**: Dashboard $\rightarrow$ **Upload Payment on Behalf** (`AdminUploadPaymentScreen`).
* Select target street and house number using cascading dropdowns.
* Upload receipt image and specify billing period to update the property's standing immediately.

### 4.3 Payment Matrix CSV Reports
* **Navigation**: Dashboard $\rightarrow$ **Payment Reports** (`AdminPaymentReportScreen`).
* Select start and end billing periods.
* Tap **Export Payment Matrix CSV**: Downloads a complete matrix showing payment standing (`paid`, `pending`, `past due`) for every address in the community across selected months.

---

## 5. Security & Access Control

### 5.1 Security Guard Account Provisioning
Security personnel use dedicated scanning interfaces to validate visitor QR codes.

* **Navigation**: Dashboard $\rightarrow$ **Manage Guards** (`AdminGuardManagementScreen`).
* **Provision Guard**: Create guard accounts with `{ guard: true }` claims.
* **Deactivate Guard**: Instant account revocation and deletion to prevent unauthorized security access.

### 5.2 Administrative QR Pass Generator
* **Navigation**: Dashboard $\rightarrow$ **Generate QR Access** (`QrGeneratorScreen`).
* When logged in as an administrator, QR pass generation automatically assigns the default location **"Admin office" / "Oficina de administración"**, allowing administrators to issue guest entry passes without linking personal residential addresses.

---

## 6. Facilities & Amenity Management

### 6.1 Dynamic Amenities Configurator
Administrators can define community facilities (e.g. Clubhouse, Tennis Court, Pool, BBQ Area).

* **Navigation**: Dashboard $\rightarrow$ **Manage Facilities** (`AdminFacilitiesScreen`).
* **Amenity Types**:
  * **Unique Amenity**: Single-booking capacity (e.g. Clubhouse).
  * **Multi-item Amenity**: Multiple item inventory capacity (e.g. 4 Tennis Courts or 10 BBQ Grills).

### 6.2 Booking Cooldown & Capacity Rules
Administrators can enforce booking cooldown periods to ensure fair facility access:
* **Cooldown Units**: Specify restriction durations in **Days**, **Months**, **Years**, or **Unrestricted**.
* **Rule Enforcement**: Prevents a resident from booking the same facility again until their cooldown period expires.

---

## 7. System Configuration & Rules

### 7.1 Maintenance Fee Cutoff & Grace Period
* **Navigation**: Dashboard $\rightarrow$ **System Settings** (`AdminSettingsScreen`).
* **Cutoff Day**: Defines the monthly day of the month (e.g., `5th` of each month) when maintenance fees are due.
* **Grace Period Days**: Defines grace period duration (e.g., `5 days`) before an address status shifts from `pending` to `restricted`.

---

## 8. Community Announcements & AI Translations

Administrators can broadcast official notices to all residents.

* **Navigation**: Drawer Menu $\rightarrow$ **Announcements** (`AnnouncementsScreen`).
* **Bilingual Translation**: Powered by serverless **Gemini AI**. Announcements posted in Spanish are automatically translated into English (and vice versa) for non-native residents.

---

*End of Administrator User Manual.*
