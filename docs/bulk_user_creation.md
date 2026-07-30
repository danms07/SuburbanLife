# Bulk Resident User Account Creation Guide

This document details the architecture, CSV specification, deterministic temporary password strategy, and Cloud Function implementation for bulk resident creation in **Suburban Life**.

---

## 1. Feature Overview

The **Bulk Resident User Creation** feature allows community administrators to onboard multiple residents simultaneously by uploading a single CSV file. 

### Key Characteristics:
* **Instant Resident Access**: Users created via bulk import are immediately granted the **`resident`** custom Auth claim (`{ resident: true }`) and assigned `role: 'resident'` in Firestore. No manual property ownership claim review is needed.
* **Optional Password Field**: Administrators can provide custom passwords or leave the password field empty. If omitted or shorter than 6 characters, the system deterministically derives a temporary password.
* **Automatic Address Linking**: If `street` and `number` columns are specified in the CSV and match an existing address document in the `addresses` collection, the user is automatically linked (`addressRef`) and the address status is updated to `paid`.
* **Zero Client Disruption**: Account creation is executed server-side via a Firebase Admin SDK Cloud Function (`adminBulkImportResidents`), preserving the administrator's active session.

---

## 2. CSV Specification & Template

A template file is available at the project root: [`resident_import_template.csv`](../resident_import_template.csv).

### Header Columns:

| Column Name | Required? | Description & Examples |
| :--- | :--- | :--- |
| `name` | **Required** | Full name of the resident (e.g. `John Doe`, `Maria Garcia`). |
| `email` | **Required** | Resident's email address (e.g. `john.doe@example.com`). |
| `password` | *Optional* | Custom password (minimum 6 characters). If left blank, a deterministic password is generated. |
| `street` | *Optional* | Street name matching an existing address document (e.g. `1st Avenue`, `Oak Street`). |
| `number` | *Optional* | House or unit number (e.g. `101`, `12`). |

### Example CSV Format:
```csv
name,email,password,street,number
John Doe,john.doe@example.com,,1st Avenue,101
Jane Smith,jane.smith@example.com,SecretPass123!,Oak Street,12
Carlos Rodriguez,carlos.rodriguez@example.com,,Pine Road,105
Maria Garcia,maria.garcia@example.com,,Maple Boulevard,20
```

---

## 3. Deterministic Temporary Password Strategy

When the `password` column is omitted or empty, the system generates a predictable, deterministic password using the user's email address:

$$\text{Password} = \text{"Suburban\#"} + \text{sanitized(localPart)} + \text{"2026"}$$

### Formula Details:
1. Extract the local part of the email (text prior to `@`).
2. Strip non-alphanumeric characters except `.`, `_`, and `-`.
3. Prepend `Suburban#` and append `2026`.

### Examples:
* `john.doe@example.com` $\rightarrow$ `Suburban#john.doe2026`
* `carlos_r@domain.org` $\rightarrow$ `Suburban#carlos_r2026`
* `a@b.com` $\rightarrow$ `Suburban#a2026`

### Security & UX Considerations:
* Fulfills all Firebase Auth password policy requirements (minimum 6 characters, uppercase, lowercase, numbers, and symbols).
* 100% deterministic and repeatable: given an email address, both administrators and residents can predict the default temporary password without exposing secret database stores.
* Admins can copy all created passwords directly to the clipboard from the import summary UI.

---

## 4. Backend Cloud Function Architecture

The bulk import process is executed via the `adminBulkImportResidents` callable Cloud Function in [`functions/index.js`](../functions/index.js).

### Request Payload:
```json
{
  "users": [
    {
      "name": "John Doe",
      "email": "john.doe@example.com",
      "password": "",
      "streetName": "1st Avenue",
      "number": "101"
    }
  ]
}
```

### Process Flow:
1. **Admin Verification**: Asserts `request.auth.token.admin === true`.
2. **Strict Address Verification**: Resolves the address by `streetName` and `number` (handling numeric/string and case-insensitive matches). If an address is specified but does NOT exist in the database, the row is rejected with `status: "error"` and `error: 'Address "..." not found in database.'` (no new address documents are created!).
3. **User Account Creation**: If the address exists (or no address was specified), creates the Auth account via `admin.auth().createUser({ email, password, displayName })`.
4. **Custom Claim Grant**: Executes `admin.auth().setCustomUserClaims(uid, { resident: true })`.
5. **Address Claiming**: Updates the existing address document setting `residentUid = uid` and `paymentStatus = 'paid'` (marking the address as claimed).
6. **Firestore Record Creation**: Writes user document to `users/{uid}` with `role: 'resident'` and `addressRef`.
7. **Result Reporting**: Returns row-level status (`ok` / `error`), `assignedPassword`, and specific `error` message string.

### Response Payload:
```json
{
  "success": true,
  "totalProcessed": 1,
  "successCount": 1,
  "failureCount": 0,
  "results": [
    {
      "name": "John Doe",
      "email": "john.doe@example.com",
      "password": "",
      "streetName": "1st Avenue",
      "number": "101",
      "status": "ok",
      "assignedPassword": "Suburban#john.doe2026",
      "isDeterministicPassword": true,
      "addressLinked": "1st Avenue #101",
      "uid": "abc12345xyz",
      "error": ""
    }
  ]
}
```

---

## 5. UI Implementation

The admin UI is implemented in [`lib/features/admin/admin_bulk_user_import_screen.dart`](../lib/features/admin/admin_bulk_user_import_screen.dart).

### UI Features:
1. **CSV Upload & Parsing**: Pick `.csv` files using `FilePicker`. Flexible parser handles header variants (`name`/`nombre`, `email`/`correo`, `street`/`calle`, `number`/`numero`).
2. **Interactive Preview Table**: Displays parsed rows, highlighting whether passwords are user-defined or deterministic temporary passwords before execution.
3. **Template Copy Button**: Quick action to copy the CSV header structure directly to the device clipboard.
4. **Result CSV Export & Download**: Generates and downloads or copies a complete CSV file (`name,email,password,street,number,status,assigned_password,error`) containing row status (`ok`/`error`), assigned passwords, and detailed error messages for any failed rows.

---

## 6. Accessing the Feature

From the Admin Dashboard:
1. Tap **Bulk User Creation (CSV)** on the main admin dashboard grid.
2. Alternatively, open **Direct Registration** and tap the upload icon ($\uparrow$) in the app bar.
