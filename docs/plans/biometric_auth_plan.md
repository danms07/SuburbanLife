# Biometric Authentication Implementation Plan

## Goal
Implement a secure, one-tap access gate using native Fingerprint and FaceID hardware readers. This leverages the default session persistence of Firebase Authentication, ensuring users remain logged in while protecting the application from unauthorized access on unlocked devices.

## Proposed Architecture

### 1. Dependencies
- Add the official Flutter package: `local_auth`.

### 2. Native Platform Configuration

#### Android
- **Permission**: Add `<uses-permission android:name="android.permission.USE_BIOMETRIC"/>` to `android/app/src/main/AndroidManifest.xml`.
- **Activity**: Update `MainActivity.kt` to extend `FlutterFragmentActivity` to support native biometric prompt dialogs.

#### iOS
- **Permission**: Add `NSFaceIDUsageDescription` to `ios/Runner/Info.plist` explaining why the app requires FaceID access.

### 3. Application Logic & Screens

#### `lib/features/auth/biometric_service.dart`
Create a service class wrapping `LocalAuthentication`:
```dart
class BiometricService {
  final _auth = LocalAuthentication();

  Future<bool> isBiometricAvailable() async {
    return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
  }

  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Scan your fingerprint or face to access SuburbanLife',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Falls back to device PIN/Pattern
        ),
      );
    } catch (e) {
      return false;
    }
  }
}
```

#### `lib/main.dart`
- Wrap the main resident interface in an authentication check. When the app resumes or cold-starts with an active Firebase user, present a locked splash screen invoking `BiometricService.authenticate()`. Once verified, transition smoothly to `MyHomePage`.

## Verification Plan
- Test on an Android emulator/device with configured fingerprints.
- Test on an iOS simulator/device with enrolled FaceID.
- Verify correct fallback behavior when biometrics are cancelled or unavailable.
