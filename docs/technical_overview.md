# Suburban Life — Technical Overview

*Last Updated: September 2026*

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [What Suburban Life Does: Key Capabilities by User Role](#2-what-suburban-life-a67ab-does-key-capabilities-by-user-role)
   - [2.1 For Residents and Household Members](#21-for-residents-and-household-members)
   - [2.2 For Security Guards & Checkpoint Personnel](#22-for-security-guards--checkpoint-personnel)
   - [2.3 For Condominium Administrators](#23-for-condominium-administrators)
3. [Core Technology: Built with Flutter](#3-core-technology-built-with-flutter)
   - [3.1 What is Flutter?](#31-what-is-flutter)
   - [3.2 Why Flutter for Suburban Life?](#32-why-flutter-for-suburban-life-a67ab)
4. [Cloud Infrastructure: Firebase Services in Action](#4-cloud-infrastructure-firebase-services-in-action)
   - [4.1 Firebase Authentication](#41-firebase-authentication)
   - [4.2 Cloud Firestore (Real-Time Database)](#42-cloud-firestore-real-time-database)
   - [4.3 Firebase Cloud Storage (Secure File Hosting)](#43-firebase-cloud-storage-secure-file-hosting)
   - [4.4 Cloud Functions for Firebase (Serverless Logic)](#44-cloud-functions-for-firebase-serverless-logic)
   - [4.5 Firebase App Check](#45-firebase-app-check)
   - [4.6 Firebase Hosting & Automated Web Updates](#46-firebase-hosting--automated-web-updates)
   - [4.7 Firebase Crashlytics & Telemetry](#47-firebase-crashlytics--telemetry)
5. [Security Measures & Protection Architecture](#5-security-measures--protection-architecture)
   - [5.1 Firebase Authentication & Role-Based Access Control (RBAC)](#51-firebase-authentication--role-based-access-control-rbac)
   - [5.2 Declarative Security Rules (Firestore & Cloud Storage)](#52-declarative-security-rules-firestore--cloud-storage)
   - [5.3 App-Level API Key Restrictions](#53-app-level-api-key-restrictions)
   - [5.4 Replay Attack Protection for Cloud Functions](#54-replay-attack-protection-for-cloud-functions)
   - [5.5 App Check with reCAPTCHA Enterprise & Device Attestation](#55-app-check-with-recaptcha-enterprise--device-attestation)
6. [Data Collection, Processing, & Privacy Compliance](#6-data-collection-processing--privacy-compliance)
   - [6.1 What Information is Collected?](#61-what-information-is-collected)
   - [6.2 How Information is Processed & Used](#62-how-information-is-processed--used)
   - [6.3 Privacy Compliance & ARCO Rights (Mexican LFPDPPP)](#63-privacy-compliance--arco-rights-mexican-lfpdppp)
   - [6.4 Account Deletion & Data Purging](#64-account-deletion--data-purging)
7. [Summary & Operational Reliability](#7-summary--operational-reliability)

---

## 1. Executive Summary

**Suburban Life** is a modern, white-label residential management platform designed to streamline daily operations for gated communities, condominiums, and housing developments. 

By connecting **Residents**, **Security Personnel**, and **Condominium Administrators** within a single unified digital ecosystem, Suburban Life replaces outdated paper logbooks, unorganized messaging groups, and manual spreadsheets with an automated, secure, and transparent digital workflow.

This document provides a comprehensive technical overview written in accessible, non-technical language to explain how the platform functions, the technologies powering it, the multi-layered security measures protecting community data, and how resident privacy is preserved.

---

## 2. What Suburban Life Does: Key Capabilities by User Role

Suburban Life provides tailored interfaces and tools for three primary groups of users:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Suburban Life                               │
│                         Residential Platform                            │
└──────────────┬──────────────────────────┬───────────────────────────────┘
               │                          │
               ▼                          ▼
┌───────────────────────────┐ ┌───────────────────────────┐ ┌─────────────▼───────────────┐
│   Residents & Families    │ │   Security Checkpoint     │ │   Condo Administration      │
│  • QR Visitor Passes      │ │  • Fast QR Code Scanning  │ │  • User & House Directory   │
│  • Amenity Bookings       │ │  • ID & Plate Capture     │ │  • Payment Review & Matrix  │
│  • Payment Proof Uploads  │ │  • Real-Time Access Logs  │ │  • Ownership Validations    │
│  • Community Bulletins    │ │  • Instant Deny/Allow     │ │  • Amenity Rules & Limits   │
│  • Transparency Documents │ └───────────────────────────┘ │  • AI Multilingual Notices  │
│  • Family Member Invites  │                               │  • Bulk CSV Imports & SMTP  │
└───────────────────────────┘                               └─────────────────────────────┘
```

### 2.1 For Residents and Household Members

* **Digital QR Access Passes**: Residents can generate instant QR codes for expected visitors, recurring guests, or delivery suppliers. Passes can be configured as **one-time use** or **temporary (with specific expiration dates and times)**, including optional vehicle details (car, motorcycle, license plate) and passenger counts.
* **Amenity & Facility Reservations**: Residents can browse and reserve community amenities (such as event rooms, swimming pool areas, barbecue grills, or sports equipment). The system prevents scheduling conflicts in real time, enforces fair-use quotas, and manages booking approval workflows.
* **Maintenance Fee Tracking & Proof Submission**: Residents can view their current balance status (Paid, Pending, Reviewing, Restricted), review past payment history, and upload digital photos of bank deposit slips or transfer receipts (coming soon) directly from their mobile camera or photo gallery.
* **Community Bulletins & Announcements**: An interactive multimedia board delivers official administrative announcements with rich images, formatted notices, and automatic bilingual translation (English and Spanish).
* **Document Transparency Portal**: An in-app virtual file explorer allows verified residents to view official condominium documents, such as neighborhood bylaws, meeting minutes, monthly balance sheets, and maintenance schedules, with offline caching for quick access.
* **Household & Roommate Management**: Primary homeowners can invite family members or co-inhabitants to their household account via quick QR scans or email invitations, allowing all household members to generate visitor passes while keeping billing unified per address.

### 2.2 For Security Guards & Checkpoint Personnel

* **Instant Camera QR Scanner**: Security guards at entry gates can scan visitor QR codes using their smartphone or tablet camera.
* **Server-Side Identity Verification**: The system immediately verifies whether the QR code is active and within its authorized time window.
* **Visitor & Vehicle Photo Capture**: Guards can capture verification photos of visitor ID cards and vehicle license plates at the gate before granting access.
* **Audit Access Logs**: Every scan produces an immutable digital timestamp log detailing the guest name, resident address, guard on duty, entry decision (Allowed or Denied), and attached photos.

### 2.3 For Condominium Administrators

* **Resident Directory & Property Mapping**: Administrators can view and search all registered residents across the whole database by name, email, or street address, with street filters, role management, and password reset capabilities, plus 20-user batches when browsing without filters.
* **Access History & Audit Logs**: Administrators can search through the entire database history using physical address dropdown filters, date range filters, visitor category chips, and keyword search across visitor names, license plates, resident hosts, guards, and reason notes, plus 20-event batch exploration for unfiltered browsing.
* **Property Ownership Verification Queue**: Administrators review deed or handover documentation submitted by new residents to confirm genuine homeownership before assigning primary resident privileges.
* **Payment Approval & Financial Matrix**: Administrative staff can review submitted payment receipts, approve or reject them with feedback, and export complete monthly payment status matrices (CSV) for accounting records.
* **Bulk Data Import via CSV**: Administrators can provision hundreds of addresses or resident accounts in seconds using spreadsheet files (CSV), with automated welcome emails and cryptographically secure passwords.
* **Amenity & Facility Configuration**: Board members can configure available amenities, mark facilities as single-booking or multi-unit, set operating hours, and define fair-use rules.
* **Automated Bilingual Bulletins with AI**: Administrators can post news bulletins in Spanish or English; the system automatically translates titles and descriptions using server-side Google Gemini AI without exposing sensitive keys.
* **Custom SMTP Email Notifications**: Automated welcome emails with login credentials and community updates are dispatched via the administration's configured SMTP server.

---

## 3. Core Technology: Built with Flutter

Suburban Life is built with **Flutter**, Google's industry-leading, open-source multi-platform framework.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Single Flutter Codebase (Dart)                     │
└──────────────┬──────────────────────────┬───────────────────────────────┘
               │                          │
               ▼                          ▼
┌───────────────────────────┐ ┌───────────────────────────┐ ┌─────────────▼─────────────┐
│        Android App        │ │          iOS App          │ │      Web Application        │
│   (Google Play / APK)     │ │        (App Store)        │ │  (Desktop & Mobile Web CDN) │
└───────────────────────────┘ └───────────────────────────┘ └─────────────────────────────┘
```

### 3.1 What is Flutter?

Flutter allows developers to write application code once in the **Dart** programming language and compile it directly into native machine code for **Android**, **iOS**, and modern **Web browsers**.

Unlike traditional web wrappers or hybrid frameworks that rely on slow browser bridges, Flutter renders every pixel directly onto the screen using high-performance graphics engines (Skia and Impeller), delivering smooth, responsive animations and native UI behavior.

### 3.2 Why Flutter for Suburban Life?

1. **True Cross-Platform Availability**: Residents can access Suburban Life on Android smartphones, Apple iPhones, iPads, and desktop web browsers without any difference in functionality or design.
2. **Unified Feature Parity**: A single codebase means new features, security updates, and bug fixes are delivered simultaneously to all platforms, eliminating discrepancies between Android, iOS, and Web.
3. **Responsive UI Architecture**: The application layout dynamically adapts between mobile phone screens, tablet displays, and wide desktop monitors used by administration offices.
4. **Offline-First Resilience**: Critical information (such as recent announcements, governance documents, and address data) is stored in local device memory, enabling fast loading even in low-connectivity gatehouse environments.
5. **Seamless Web Updates**: The web client includes background update detection (`AppUpdateService`) that automatically checks for new software releases and refreshes the application smoothly when the user is idle.

> [!NOTE]
> **Mobile App Store Distribution Disclaimer**:
> Although native **Android** and **iOS** versions exist and are fully functional within the project codebase, their public publishing and distribution through the **Google Play Store** and **Apple App Store** require official developer accounts (which incur platform registration and recurring subscription fees). The decision to acquire these developer accounts and allocate the necessary budget must be formally presented and approved in a **Community/Condominium Assembly**. In the interim, the application is 100% operational, fully responsive, and immediately accessible to all residents, security personnel, and administrators through any modern mobile or desktop web browser.

---

## 4. Cloud Infrastructure: Firebase Services in Action

Suburban Life leverages Google's **Firebase** cloud ecosystem, providing an enterprise-grade, serverless infrastructure that ensures high availability, real-time synchronization, and zero server maintenance overhead.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Suburban Life Cloud (Firebase)                   │
├───────────────────┬───────────────────┬────────────────┬────────────────┤
│   Firebase Auth   │  Cloud Firestore  │ Cloud Storage  │ Cloud Functions│
│ (Identity & Roles)│ (Real-time NoSQL) │ (Encrypted S3) │ (Backend Logic)│
├───────────────────┼───────────────────┼────────────────┼────────────────┤
│     App Check     │ Firebase Hosting  │  Crashlytics   │ Google Gemini  │
│ (Anti-abuse Gate) │   (Global CDN)    │ (Error Alerts) │ (Vertex AI)    │
└───────────────────┴───────────────────┴────────────────┴────────────────┘
```

### 4.1 Firebase Authentication
* **Role**: Serves as the central digital identity gatekeeper.
* **Function**: Handles account registration, secure password hashing, credential recovery, session tokens, and multi-role claim issuance (`admin`, `guard`, `resident`).

### 4.2 Cloud Firestore (Real-Time Database)
* **Role**: The core cloud database storing all structured operational data.
* **Function**: Firestore is a globally distributed NoSQL database that synchronizes changes across all connected devices in milliseconds.
* **Primary Collections**:
  * `users`: Resident, guard, and administrator profiles and contact details.
  * `addresses`: Physical properties, homeowner links, delivery dates, and monthly payment statuses.
  * `qr_codes`: Access passes, guest names, vehicle plates, and validity rules.
  * `bookings`: Common amenity schedules, booking intervals, and approval statuses.
  * `announcements`: Community bulletins, banner URLs, read receipts, and bilingual translations.
  * `documents` & `document_folders`: Directory tree and metadata for community governance files.
  * `access_logs`: Checkpoint audit history, guard entries, and verification photo links.
  * `payments`: Maintenance receipts, payment periods (`YYYY-MM`), amounts, and approval states.
  * `ownership_claims`: Deed validation submissions awaiting administrative review.
  * `facilities`: Configurable list of community amenities and capacity settings.
  * `config`: Payment cutoff day parameters, grace periods, and Administrator configuration.

### 4.3 Firebase Cloud Storage (Secure File Hosting)
* **Role**: Encrypted cloud file vault for multimedia and binary documents.
* **Function**: Securely stores ownership proof files (deed scans), payment receipts, gate verification photos (visitor IDs and vehicle license plates), transparency files, and announcement media.

### 4.4 Cloud Functions for Firebase (Serverless Logic)
* **Role**: Secure server-side execution environment for business-critical operations.
* **Function**: Executes server-side code in isolated micro-containers in response to user actions or database events without running a persistent server:
  * **Atomic QR Access Validation** (`validateAndRegisterQrAccess`): Evaluates access rules and writes the access log in a single secure cloud transaction.
  * **AI Announcement Translation** (`translateAnnouncement`): Calls Google Vertex AI (Gemini) keylessly to translate community bulletins between Spanish and English.
  * **Payment Recalculation Trigger** (`onPaymentWritten`): Automatically re-evaluates house payment status whenever a payment receipt is approved.
  * **Bulk Account & Address Creation** (`adminBulkImportResidents`, `adminBulkImportAddresses`): Creates accounts, assigns custom claims, and generates complex passwords securely in bulk.
  * **Automated Welcome Emails**: Connects securely to the administrator's SMTP server to send login instructions upon account provisioning.

### 4.5 Firebase App Check
* **Role**: Defense against bot attacks, API scraping, and unauthorized client apps.
* **Function**: Attests that incoming API traffic originates exclusively from legitimate, untampered Suburban Life mobile apps or authorized web browsers.

### 4.6 Firebase Hosting & Automated Web Updates
* **Role**: Global Content Delivery Network (CDN) for the web version.
* **Function**: Delivers web assets worldwide with ultra-low latency, HTTPS encryption, cache-busting headers, and automatic reload support on version updates.

### 4.7 Firebase Crashlytics & Telemetry
* **Role**: Real-time application health monitoring.
* **Function**: Automatically captures and aggregates technical crash logs, unhandled errors, and performance metrics so technical maintainers can diagnose and fix software bugs before they impact users.

---

## 5. Security Measures & Protection Architecture

Security and privacy are engineered directly into the foundation of Suburban Life. The platform implements a **defense-in-depth** strategy, ensuring that security is enforced across multiple independent layers.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     5-Layer Security Architecture                       │
├─────────────────────────────────────────────────────────────────────────┤
│ 1. Client Attestation   │ App Check with reCAPTCHA Enterprise           │
├─────────────────────────┼───────────────────────────────────────────────┤
│ 2. API Scope Lockdown   │ App-Level Platform API Key Restrictions       │
├─────────────────────────┼───────────────────────────────────────────────┤
│ 3. Identity & Claims    │ Firebase Auth + Custom Role Claims (RBAC)     │
├─────────────────────────┼───────────────────────────────────────────────┤
│ 4. Request Replay Guard │ Cloud Functions One-Time Token Consumption    │
├─────────────────────────┼───────────────────────────────────────────────┤
│ 5. Data Access Firewall │ Server-Enforced Firestore & Storage Rules     │
└─────────────────────────┴───────────────────────────────────────────────┘
```

### 5.1 Firebase Authentication & Role-Based Access Control (RBAC)

* **Cryptographic Passwords & Policy Enforcement**: The application strictly enforces strong password complexity (minimum 8 characters, requiring at least one uppercase letter, one lowercase letter, one numeric digit, and one special symbol). In bulk import workflows, cryptographically secure 12-character random passwords are generated server-side.
* **Custom Security Claims**: User roles are not simple fields in a database that a malicious client could modify. Instead, roles are issued as cryptographically signed **Custom Auth Claims** (`{ admin: true }`, `{ guard: true }`, `{ resident: true }`). These claims are verified on every single database read, write, and Cloud Function invocation.

### 5.2 Declarative Security Rules (Firestore & Cloud Storage)

Security in Suburban Life is enforced **in the cloud**, not on the user's device. Even if someone inspects or modifies the app's client-side code, Cloud Firestore and Cloud Storage enforce strict declarative security rules:

* **Principle of Least Privilege**:
  * **Residents** can only read their own user profiles, their household's QR codes, their own payment proofs, and approved community announcements.
  * **Residents cannot** alter their own account role, modify their home's payment status, view other neighbors' payment proofs, or delete access audit logs.
  * **Security Guards** can read necessary QR validity information and write access logs, but cannot access financial records, modify resident passwords, or alter administrative settings.
  * **Administrators** have authenticated governance access to validate claims, review receipts, and manage configuration.
* **Storage Protection**: Uploaded files (deeds, payment receipts, visitor ID photos) are stored in private Cloud Storage directories guarded by matching security rules, preventing public indexing or unauthorized direct link access.
* **Sensitive Configuration Isolation**: System settings such as SMTP passwords and payment cutoff parameters are locked exclusively to verified administrators.

### 5.3 App-Level API Key Restrictions

Every modern mobile and web app uses Google Cloud API keys to identify the project. To prevent attackers from copying these keys from app bundles and using them elsewhere, **API keys for Suburban Life are strictly restricted in Google Cloud**:

* **Android Restriction**: The Android API key is locked exclusively to the application's unique package name (`com.example.suburban_life`) and the developer's SHA-1 signing certificate fingerprint. Requests originating from any other app or device are rejected immediately.
* **iOS Restriction**: The iOS API key is restricted exclusively to the registered iOS Bundle Identifier (`com.example.suburban_life`).
* **Web Client Restriction**: The Web API key is locked to authorized HTTP referrers and verified domain origins (e.g., `suburban-life-a67ab.web.app` and custom condominium domains). Requests sent from unauthorized websites or third-party tools (like Postman or curl) are blocked.

### 5.4 Replay Attack Protection for Cloud Functions

A **replay attack** occurs when an unauthorized user intercepts a legitimate network request and resends it repeatedly (for example, trying to validate an expired pass twice or repeat a transaction).

To eliminate this vulnerability:
* Suburban Life utilizes Cloud Functions (2nd Generation) configured with **`consumeAppCheckToken: true`** on the server.
* The Flutter application invokes callable functions with **`limitedUseAppCheckToken: true`**.
* **How it works**: Every time a user initiates a critical server request (such as checking a QR pass or approving a payment), a single-use App Check token is issued. Upon execution, the server **immediately consumes and invalidates** the token. If an attacker intercepts the network packet and attempts to replay it, the server rejects the duplicate request outright by lacking a valid token.

### 5.5 App Check with reCAPTCHA Enterprise & Device Attestation

**Firebase App Check** prevents unauthorized clients, automated scripts, and malicious bots from accessing cloud resources. It verifies that incoming traffic comes from an authentic, unaltered app installation:

* **Web Platform (reCAPTCHA Enterprise)**: Analyzes behavioral interactions and browser signals transparently without forcing residents to solve annoying image puzzles, verifying that the web traffic originates from genuine human users on the authorized domain.
* **Android Devices (reCAPTCHA Enterprise)**: Evaluates risk signals and client authenticity using the dedicated reCAPTCHA Enterprise provider for Android, blocking unauthorized access and automated scripts.
* **iOS Devices (DeviceCheck & Apple App Attest)**: Cryptographically asserts that the app is authentic, unmodified, and running on a genuine Apple device.

---

## 6. Data Collection, Processing, & Privacy Compliance

### 6.1 What Information is Collected?

To provide community access control, fee management, and safety services, the app collects:

| Category | Specific Data Collected | Purpose |
| :--- | :--- | :--- |
| **Account Data** | Full name, email address, password hash, assigned role. | User authentication and role-based permissions. |
| **Property Info** | Street name, house number, linked physical property. | Associating resident accounts with their physical residence. |
| **Ownership Proof** | Photos of property deeds, delivery certificates, handover dates. | Confirming legitimate property ownership before granting resident privileges. |
| **Financial Records** | Maintenance fee receipts (images), payment amounts, payment dates. | Reconciling monthly community dues and updating account standing. |
| **Visitor Access** | Guest names, vehicle types, license plate numbers, authorized time slots. | Generating QR access passes and pre-authorizing gate entry. |
| **Gate Checkpoint Logs** | Check-in timestamps, validation status (Allowed/Denied), verification photos of visitor IDs or license plates. | Preserving community safety and creating a verifiable gate access audit trail. |
| **Technical Telemetry** | Anonymous crash logs, performance diagnostics (via Crashlytics/Analytics). | Identifying bugs, preventing application crashes, and optimizing performance. |

### 6.2 How Information is Processed & Used

* **Strict Purpose Limitation**: Personal data is processed exclusively for residential community governance, safety verification at gate checkpoints, and financial accounting.
* **Zero Commercial Data Selling**: Suburban Life **never** sells, rents, or monetizes personal resident data to third parties, advertisers, or data brokers.
* **Keyless Server-Side AI Processing**: Community announcements translated by Google Vertex AI (Gemini) are processed purely as public bulletin text. **No personal user profile data, financial records, or private documents are ever transmitted to AI models.**

### 6.3 Privacy Compliance & ARCO Rights (Mexican LFPDPPP)

In compliance with Mexican personal data protection laws (**LFPDPPP**), every user retains full legal ownership of their personal information through their **ARCO Rights**:

* **Access (Acceso)**: The right to know what personal data is held about you and how it is processed.
* **Rectification (Rectificación)**: The right to request the immediate correction of inaccurate, incomplete, or outdated information.
* **Cancellation (Cancelación)**: The right to request that your personal information and documents be removed from active databases.
* **Opposition (Oposición)**: The right to object to specific data processing activities.

Users can exercise their ARCO rights directly through their Condominium Administration or via the in-app account portal.

### 6.4 Account Deletion & Data Purging

* **Self-Service & Admin Deletion**: Users can delete their account directly within the app via the **"Delete Account"** button or by requesting deletion from an administrator.
* **Permanent & Irreversible Purge**: When an account is deleted, the user's credentials in Firebase Authentication, user document in Cloud Firestore, and ownership proof files in Cloud Storage are **permanently and irreversibly destroyed**.

---

## 7. Summary & Operational Reliability

| Objective | Architectural Solution in Suburban Life |
| :--- | :--- |
| **Accessibility** | Single responsive Flutter codebase running across Android, iOS, and Web. |
| **Speed & Availability** | Serverless Google Cloud Firestore with real-time sync and offline caching. |
| **User Identity** | Firebase Authentication with hardened password policies and role-based custom claims. |
| **Data Protection** | Cloud-enforced Firestore & Storage security rules ensuring least-privilege data access. |
| **API Lockdown** | Google Cloud API key restrictions for Android (SHA-1/Package), iOS (Bundle ID), and Web (HTTP referrers). |
| **Anti-Abuse & Bot Defense** | Firebase App Check with reCAPTCHA Enterprise and device attestation (reCAPTCHA Enterprise / App Attest). |
| **Replay Protection** | Single-use token consumption (`consumeAppCheckToken`) for all Cloud Functions. |
| **Privacy & Compliance** | Full ARCO rights compliance (LFPDPPP) and irreversible account deletion. |

Suburban Life combines modern mobile technology, serverless cloud scalability, and bank-grade security practices to deliver an easy-to-use, reliable, and secure community management experience.
