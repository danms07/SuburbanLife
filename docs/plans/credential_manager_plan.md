# Google Credential Manager & Passkeys Implementation Plan

## Goal
Implement state-of-the-art passwordless authentication using Passkeys integrated with Android's Credential Manager and Apple's Keychain. This approach completely replaces traditional passwords with highly secure cryptographic key pairs, providing seamless one-tap registration and sign-in across devices.

## Proposed Architecture

### 1. Dependencies
- Integrate Passkeys functionality via updated `firebase_auth` capabilities or native `credential_manager` support.

### 2. Native Platform & Web Configuration

#### Android (Digital Asset Links)
- To enable seamless passkey validation, host an `assetlinks.json` file on the application's backend/domain at `https://<your-domain>/.well-known/assetlinks.json`.
- Configure the app's `build.gradle` and `AndroidManifest.xml` to associate with the remote domain.

#### iOS (Associated Domains)
- Enable the **Associated Domains** capability in Xcode.
- Add the entry: `webcredentials:<your-domain>`.
- Host an `apple-app-site-association` (AASA) file on the server root.

### 3. Application Logic & Screens

#### `lib/features/auth/passkey_service.dart`
Implement passkey registration and signing mechanisms:
```dart
class PasskeyService {
  // Invokes platform-specific Passkey generation flow
  Future<UserCredential?> registerWithPasskey(String email) async {
    // Calls Firebase Auth WebAuthn / Passkey linking APIs
  }

  // Invokes seamless one-tap bottom sheet for authentication
  Future<UserCredential?> signInWithPasskey() async {
    // Prompts Android Credential Manager / iOS Keychain to select saved passkey
  }
}
```

#### Screens UI Updates
- **`SignupScreen`**: Add a premium "Create Passkey" primary flow, skipping custom password inputs entirely.
- **`LoginScreen`**: Automatically prompt the native Credential Manager bottom sheet upon launch, allowing the user to authenticate with a single tap.

## Verification Plan
- Verify cross-device synchronization by creating a passkey on Android and authenticating on a secondary device signed into the same Google account.
- Confirm cryptographic verification success on the Firebase console under Authentication settings.
