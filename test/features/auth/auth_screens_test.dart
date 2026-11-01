import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/features/auth/admin_resident_approval_screen.dart';
import 'package:suburban_life/features/auth/forgot_password_screen.dart';
import 'package:suburban_life/features/auth/login_screen.dart';
import 'package:suburban_life/features/auth/ownership_proof_screen.dart';
import 'package:suburban_life/features/auth/signup_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

Widget _wrapWithApp(Widget home, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('es')],
    home: home,
  );
}

AppLocalizations _enL10n(WidgetTester tester) {
  final ctx = tester.element(find.byType(Scaffold).first);
  return AppLocalizations.of(ctx)!;
}

void main() {
  late Directory tempDir;

  setUp(() {
    FakeBackendHelper.setUp();
    tempDir = Directory.systemTemp.createTempSync('auth_screens_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('LoginScreen', () {
    testWidgets('renders split desktop layout (>900px), toggles password visibility, and handles sign-in success & failure', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      String? capturedEmail;
      String? capturedPassword;
      bool shouldSucceed = false;

      FakeBackendHelper.auth.signInHandler = (email, password) async {
        capturedEmail = email;
        capturedPassword = password;
        if (!shouldSucceed) return null;
        return AppUser(uid: 'u_login', email: email, displayName: 'Test User');
      };

      await tester.pumpWidget(_wrapWithApp(const LoginScreen()));
      await tester.pumpAndSettle();

      final l10n = _enL10n(tester);

      // Verify password field starts obscured and toggles visibility
      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));
      expect(tester.widget<TextField>(textFields.at(1)).obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();
      expect(tester.widget<TextField>(textFields.at(1)).obscureText, isFalse);

      // 1. Failed login shows loginFailed SnackBar
      await tester.enterText(textFields.at(0), 'resident@catania.com');
      await tester.enterText(textFields.at(1), 'WrongPass#1');
      await tester.tap(find.widgetWithText(ElevatedButton, l10n.login));
      await tester.pumpAndSettle();

      expect(capturedEmail, equals('resident@catania.com'));
      expect(capturedPassword, equals('WrongPass#1'));
      expect(find.text(l10n.loginFailed), findsOneWidget);

      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).clearSnackBars();
      await tester.pump();

      // 2. Successful login shows loginSuccess SnackBar
      shouldSucceed = true;
      await tester.enterText(textFields.at(1), 'ValidPass#99');
      await tester.tap(find.widgetWithText(ElevatedButton, l10n.login));
      await tester.pumpAndSettle();

      expect(find.text(l10n.loginSuccess), findsOneWidget);
    });

    testWidgets('renders mobile layout and navigates to ForgotPasswordScreen and SignupScreen', (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_wrapWithApp(const LoginScreen()));
      await tester.pumpAndSettle();

      final l10n = _enL10n(tester);

      // Navigate to ForgotPasswordScreen and back
      final forgotBtn = find.widgetWithText(TextButton, l10n.forgotPasswordOption);
      await tester.ensureVisible(forgotBtn);
      await tester.tap(forgotBtn);
      await tester.pumpAndSettle();
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      // Navigate to SignupScreen
      final signUpBtn = find.widgetWithText(TextButton, l10n.signUpOption);
      await tester.ensureVisible(signUpBtn);
      await tester.tap(signUpBtn);
      await tester.pumpAndSettle();
      expect(find.byType(SignupScreen), findsOneWidget);
    });
  });

  group('ForgotPasswordScreen', () {
    testWidgets('ignores empty email, reports failure, and pops on successful reset link dispatch', (tester) async {
      int resetCalls = 0;
      bool nextResult = false;
      String? resetTargetEmail;

      FakeBackendHelper.auth.sendPasswordResetHandler = (email) async {
        resetCalls++;
        resetTargetEmail = email;
        return nextResult;
      };

      await tester.pumpWidget(
        _wrapWithApp(
          Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).push(
                    MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                  ),
                  child: const Text('Open Reset'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Reset'));
      await tester.pumpAndSettle();
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);

      final l10n = AppLocalizations.of(tester.element(find.byType(ForgotPasswordScreen)))!;

      // Empty email is ignored
      await tester.tap(find.widgetWithText(ElevatedButton, l10n.sendResetLinkButton));
      await tester.pump();
      expect(resetCalls, equals(0));

      // Failure shows resetLinkFailed and stays on screen
      await tester.enterText(find.byType(TextField), 'unknown@catania.com');
      await tester.tap(find.widgetWithText(ElevatedButton, l10n.sendResetLinkButton));
      await tester.pumpAndSettle();
      expect(resetCalls, equals(1));
      expect(resetTargetEmail, equals('unknown@catania.com'));
      expect(find.text(l10n.resetLinkFailed), findsOneWidget);
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);

      // Success pops back to launcher screen
      nextResult = true;
      await tester.enterText(find.byType(TextField), 'valid@catania.com');
      await tester.tap(find.widgetWithText(ElevatedButton, l10n.sendResetLinkButton));
      await tester.pumpAndSettle();
      expect(resetCalls, equals(2));
      expect(find.byType(ForgotPasswordScreen), findsNothing);
      expect(find.text('Open Reset'), findsOneWidget);
    });
  });

  group('SignupScreen', () {
    testWidgets('Step 1 enforces password complexity and invokes signUp on compliant credentials', (tester) async {
      int signUpCalls = 0;
      String? registeredName;
      FakeBackendHelper.auth.signUpHandler = (email, password, {name}) async {
        signUpCalls++;
        registeredName = name;
        return AppUser(uid: 'new_u_1', email: email, displayName: name);
      };

      await tester.pumpWidget(
        _wrapWithApp(
          Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute(builder: (_) => const SignupScreen()),
                ),
                child: const Text('Go Signup'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Go Signup'));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(tester.element(find.byType(SignupScreen)))!;
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));

      // Weak password rejected locally
      await tester.enterText(fields.at(0), 'Elena Gomez');
      await tester.enterText(fields.at(1), 'elena@catania.com');
      await tester.enterText(fields.at(2), 'weakpass');
      await tester.tap(find.widgetWithText(ElevatedButton, l10n.signUpButton));
      await tester.pumpAndSettle();

      expect(signUpCalls, equals(0));
      expect(find.text(l10n.passwordComplexityRequirements), findsOneWidget);

      // Strong password invokes signUp and pops back
      await tester.enterText(fields.at(2), 'Strong#Pass2026');
      await tester.tap(find.widgetWithText(ElevatedButton, l10n.signUpButton));
      await tester.pumpAndSettle();

      expect(signUpCalls, equals(1));
      expect(registeredName, equals('Elena Gomez'));
      expect(find.byType(SignupScreen), findsNothing);
    });

    testWidgets('Step 2 (isAdditionalClaim: true) filters out claimed addresses and navigates to OwnershipProofScreen', (tester) async {
      FakeBackendHelper.db.seedDocument('addresses', 'addr_claimed', {
        'id': 'addr_claimed',
        'streetName': 'Claimed Blvd',
        'number': 10,
        'residentUid': 'existing_owner',
      });
      FakeBackendHelper.db.seedDocument('addresses', 'addr_free', {
        'id': 'addr_free',
        'streetName': 'Loreto',
        'number': 204,
        'residentUid': null,
      });

      await tester.pumpWidget(_wrapWithApp(const SignupScreen(isAdditionalClaim: true)));
      await tester.pumpAndSettle();

      final l10n = _enL10n(tester);

      // Claimed Blvd should not be selectable; Loreto should be present
      final dropdowns = find.byType(DropdownButtonFormField<String>);
      expect(dropdowns, findsNWidgets(2));

      await tester.tap(dropdowns.at(0));
      await tester.pumpAndSettle();
      expect(find.text('Claimed Blvd'), findsNothing);
      await tester.tap(find.text('Loreto').last);
      await tester.pumpAndSettle();

      await tester.tap(dropdowns.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('204').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, l10n.confirmAddressButton));
      await tester.pumpAndSettle();

      expect(find.byType(OwnershipProofScreen), findsOneWidget);
    });
  });

  group('OwnershipProofScreen', () {
    testWidgets('requires delivery date before capture, uploads proof, cleans up temp file, and creates ownership_claims doc', (tester) async {
      FakeBackendHelper.auth.emitUser(
        AppUser(uid: 'claimant_1', email: 'claimant@catania.com', displayName: 'Claimant'),
      );

      final tempPhoto = File('${tempDir.path}/image_picker_proof.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_claim_1');

      await tester.pumpWidget(
        _wrapWithApp(
          Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute(
                    builder: (_) => OwnershipProofScreen(
                      addressRef: addrRef,
                      pickImageOverride: () async => XFile(tempPhoto.path),
                    ),
                  ),
                ),
                child: const Text('Start Claim'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Start Claim'));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(tester.element(find.byType(OwnershipProofScreen)))!;

      // 1. Attempting photo capture without selecting handover date shows SnackBar
      await tester.tap(find.text(l10n.captureProofPhoto));
      await tester.pump();
      expect(find.text(l10n.selectDeliveryDate), findsAtLeastNWidgets(1));

      final claimsBefore = await FakeBackendHelper.db.getCollection('ownership_claims');
      expect(claimsBefore, isEmpty);

      // 2. Select handover date from DatePicker
      await tester.tap(find.byIcon(Icons.calendar_month));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // 3. Capture photo -> uploads to Storage, deletes temp file, creates claim, pops to root
      await tester.tap(find.text(l10n.captureProofPhoto));
      await tester.pumpAndSettle();

      expect(find.byType(OwnershipProofScreen), findsNothing);
      expect(tempPhoto.existsSync(), isFalse);
      expect(
        FakeBackendHelper.storage.uploadedFiles.keys.any(
          (k) => k.startsWith('ownership_proofs/claimant_1/'),
        ),
        isTrue,
      );

      final claimsAfter = await FakeBackendHelper.db.getCollection('ownership_claims');
      expect(claimsAfter, hasLength(1));
      expect(claimsAfter.first['userUid'], equals('claimant_1'));
      expect((claimsAfter.first['addressRef'] as DbReference).id, equals('addr_claim_1'));
      expect(claimsAfter.first['status'], equals('pending'));
      expect(claimsAfter.first['deliveryDate'], isA<DateTime>());
    });

    testWidgets('records Crashlytics error and cleans up temp file when Storage upload fails', (tester) async {
      FakeBackendHelper.auth.emitUser(
        AppUser(uid: 'claimant_err', email: 'err@catania.com', displayName: 'Err'),
      );
      FakeBackendHelper.storage.uploadHandler = (_, _) async {
        throw Exception('storage/unauthorized');
      };

      final tempPhoto = File('${tempDir.path}/image_picker_fail.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_err');

      await tester.pumpWidget(
        _wrapWithApp(
          OwnershipProofScreen(
            addressRef: addrRef,
            pickImageOverride: () async => XFile(tempPhoto.path),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = _enL10n(tester);

      await tester.tap(find.byIcon(Icons.calendar_month));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.captureProofPhoto));
      await tester.pumpAndSettle();

      expect(tempPhoto.existsSync(), isFalse);
      expect(FakeBackendHelper.crashlytics.recordedErrors, hasLength(1));
      expect(
        FakeBackendHelper.crashlytics.recordedErrors.first,
        contains('OwnershipProofScreen.uploadProof'),
      );
      expect(await FakeBackendHelper.db.getCollection('ownership_claims'), isEmpty);
    });
  });

  group('AdminResidentApprovalScreen', () {
    testWidgets('renders empty state when no pending claims exist', (tester) async {
      await tester.pumpWidget(_wrapWithApp(const AdminResidentApprovalScreen()));
      await tester.pumpAndSettle();

      final l10n = _enL10n(tester);
      expect(find.text(l10n.noResidentsToApprove), findsOneWidget);
    });

    testWidgets('approves pending claim: invokes setRole, binds address & user, deletes Storage proof and claim doc', (tester) async {
      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_approve');
      final deliveryDate = DateTime(2026, 5, 10);
      const proofUrl = 'https://fake-storage.local/ownership_proofs/res_new/proof.jpg';

      FakeBackendHelper.db.seedDocument('addresses', 'addr_approve', {
        'id': 'addr_approve',
        'streetName': 'Catania Norte',
        'number': 12,
        'residentUid': null,
        'paymentStatus': 'restricted',
      });
      FakeBackendHelper.db.seedDocument('users', 'res_new', {
        'uid': 'res_new',
        'name': 'Marco Polo',
        'role': 'resident',
        'addressRef': null,
      });
      FakeBackendHelper.db.seedDocument('ownership_claims', 'claim_1', {
        'id': 'claim_1',
        'userUid': 'res_new',
        'addressRef': addrRef,
        'proofUrl': proofUrl,
        'status': 'pending',
        'deliveryDate': deliveryDate,
      });

      Map<String, dynamic>? setRoleParams;
      FakeBackendHelper.functions.registerHandler('setRole', (params) async {
        setRoleParams = params;
        return {'success': true};
      });

      await tester.pumpWidget(_wrapWithApp(const AdminResidentApprovalScreen()));
      await tester.pumpAndSettle();

      final l10n = _enL10n(tester);
      expect(find.text('Catania Norte 12'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, l10n.approveResidentButton));
      await tester.pumpAndSettle();

      expect(setRoleParams, equals({'uid': 'res_new', 'role': 'resident'}));

      final updatedAddr = await FakeBackendHelper.db.getDocument('addresses', 'addr_approve');
      expect(updatedAddr?['residentUid'], equals('res_new'));
      expect(updatedAddr?['paymentStatus'], equals('paid'));
      expect(updatedAddr?['deliveryDate'], equals(deliveryDate));

      final updatedUser = await FakeBackendHelper.db.getDocument('users', 'res_new');
      expect((updatedUser?['addressRef'] as DbReference).id, equals('addr_approve'));

      expect(FakeBackendHelper.storage.deletedUrls, contains(proofUrl));
      expect(await FakeBackendHelper.db.getDocument('ownership_claims', 'claim_1'), isNull);
    });

    testWidgets('rejects pending claim: deletes Storage proof and claim doc without calling setRole', (tester) async {
      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_reject');
      const proofUrl = 'https://fake-storage.local/ownership_proofs/res_rej/proof.jpg';

      FakeBackendHelper.db.seedDocument('addresses', 'addr_reject', {
        'id': 'addr_reject',
        'streetName': 'Catania Sur',
        'number': 88,
        'residentUid': null,
      });
      FakeBackendHelper.db.seedDocument('ownership_claims', 'claim_rej', {
        'id': 'claim_rej',
        'userUid': 'res_rej',
        'addressRef': addrRef,
        'proofUrl': proofUrl,
        'status': 'pending',
      });

      bool setRoleCalled = false;
      FakeBackendHelper.functions.registerHandler('setRole', (_) async {
        setRoleCalled = true;
        return {'success': true};
      });

      await tester.pumpWidget(_wrapWithApp(const AdminResidentApprovalScreen()));
      await tester.pumpAndSettle();

      final l10n = _enL10n(tester);
      expect(find.text('Catania Sur 88'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, l10n.rejectResidentButton));
      await tester.pumpAndSettle();

      expect(setRoleCalled, isFalse);
      expect(FakeBackendHelper.storage.deletedUrls, contains(proofUrl));
      expect(await FakeBackendHelper.db.getDocument('ownership_claims', 'claim_rej'), isNull);
    });
  });
}
