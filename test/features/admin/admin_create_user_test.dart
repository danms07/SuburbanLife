import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/features/admin/admin_create_user_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
    FakeBackendHelper.auth.emitUser(
      AppUser(
        uid: 'admin_test_uid',
        email: 'admin@example.com',
        displayName: 'Admin User',
      ),
    );
    FakeBackendHelper.auth.isAdminMock = true;

    // Register adminCreateUser mock
    FakeBackendHelper.functions.registerHandler('adminCreateUser', (params) async {
      if (FakeBackendHelper.auth.isAdminMock != true) {
        throw Exception('Function must be called by an authenticated admin.');
      }
      final name = params?['name']?.toString();
      final email = params?['email']?.toString();
      final password = params?['password']?.toString();
      final role = params?['role']?.toString();
      final addressId = params?['addressId']?.toString();
      final deliveryDateStr = params?['deliveryDate']?.toString();

      if (name == null || email == null || password == null || role == null) {
        throw Exception('Missing name, email, password, or role.');
      }

      if (role == 'resident' && deliveryDateStr != null) {
        final d = DateTime.tryParse(deliveryDateStr);
        if (d == null) {
          throw Exception('Invalid delivery date format.');
        }
        if (d.isAfter(DateTime.now())) {
          throw Exception('Delivery date cannot be in the future.');
        }
      }

      if (role == 'resident') {
        if (addressId == null) {
          throw Exception('Specified address was not found in database.');
        }
        final addressDoc = await FakeBackendHelper.db.getDocument('addresses', addressId);
        if (addressDoc == null) {
          throw Exception('Specified address was not found in database.');
        }
        if (addressDoc['residentUid'] != null && addressDoc['residentUid'].toString().trim().isNotEmpty) {
          throw Exception('The address is already claimed by another resident.');
        }

        final newUid = 'created_resident_${DateTime.now().millisecondsSinceEpoch}';
        final addressUpdate = <String, dynamic>{
          'residentUid': newUid,
        };
        if (deliveryDateStr != null) {
          addressUpdate['deliveryDate'] = DateTime.parse(deliveryDateStr);
        }
        await FakeBackendHelper.db.updateDocument('addresses', addressId, addressUpdate);

        await FakeBackendHelper.db.setDocument('users', newUid, {
          'uid': newUid,
          'name': name,
          'email': email,
          'role': role,
          'addressRef': StringDbReference('addresses/$addressId'),
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });

        return {'success': true, 'uid': newUid, 'role': role, 'emailSent': true};
      }

      final newUid = 'created_user_${DateTime.now().millisecondsSinceEpoch}';
      await FakeBackendHelper.db.setDocument('users', newUid, {
        'uid': newUid,
        'name': name,
        'email': email,
        'role': role,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      return {'success': true, 'uid': newUid, 'role': role, 'emailSent': true};
    });
  });

  Widget wrapWithMaterial(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }

  group('AdminCreateUserScreen Form Validation, Role Switching & Error Handling', () {
    testWidgets('Validates weak password and missing address before invoking Cloud Function', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FakeBackendHelper.db.seedDocument('addresses', 'loreto_108', {
        'id': 'loreto_108',
        'streetName': 'loreto',
        'number': 108,
        'paymentStatus': 'paid',
        'residentUid': null,
      });

      await tester.pumpWidget(wrapWithMaterial(const AdminCreateUserScreen(initialRole: 'resident')));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Karla Islas');
      await tester.enterText(textFields.at(1), 'karip2209@gmail.com');
      await tester.enterText(textFields.at(2), 'weak');
      await tester.pumpAndSettle();

      final submitBtn = find.byType(ElevatedButton);
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Weak password blocks submission
      expect(FakeBackendHelper.functions.callHistory, isEmpty);

      // Tap random password generator button -> produces compliant password
      await tester.tap(find.byIcon(Icons.auto_fix_high));
      await tester.pumpAndSettle();

      // Submitting resident without selecting an address shows warning SnackBar and does not call backend
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();
      expect(FakeBackendHelper.functions.callHistory, isEmpty);
      expect(find.textContaining('Please select a street and house number'), findsOneWidget);
    });

    testWidgets('Switches role to Security Guard, hides address card, creates guard, and logs server errors gracefully', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(wrapWithMaterial(const AdminCreateUserScreen(initialRole: 'resident')));
      await tester.pumpAndSettle();

      // Switch role dropdown from Resident to Guard
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guard').last);
      await tester.pumpAndSettle();

      // Address street dropdown should no longer exist for Guard role
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Pedro Guard');
      await tester.enterText(textFields.at(1), 'pedro.guard@catania.com');
      await tester.enterText(textFields.at(2), 'SecurePass123!');
      await tester.pumpAndSettle();

      final submitBtn = find.byType(ElevatedButton);
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(
        FakeBackendHelper.functions.callHistory.any(
          (c) =>
              c['name'] == 'adminCreateUser' &&
              c['parameters']?['role'] == 'guard' &&
              c['parameters']?['email'] == 'pedro.guard@catania.com',
        ),
        isTrue,
      );

      // Advance SnackBar and simulate a server-side failure (e.g. duplicate email)
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      FakeBackendHelper.functions.registerHandler('adminCreateUser', (_) async {
        throw Exception('Email address is already in use.');
      });

      await tester.enterText(textFields.at(0), 'Duplicate Guard');
      await tester.enterText(textFields.at(1), 'pedro.guard@catania.com');
      await tester.enterText(textFields.at(2), 'SecurePass123!');
      await tester.pumpAndSettle();

      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('Email address is already in use.'), findsOneWidget);
      expect(FakeBackendHelper.crashlytics.recordedErrors, isNotEmpty);
    });

    testWidgets('AdminCreateUserScreen widget creates resident and shows success', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      FakeBackendHelper.db.seedDocument('addresses', 'loreto_108', {
        'id': 'loreto_108',
        'streetName': 'loreto',
        'number': 108,
        'paymentStatus': 'paid',
        'residentUid': null,
      });

      await tester.pumpWidget(wrapWithMaterial(const AdminCreateUserScreen(initialRole: 'resident')));
      await tester.pumpAndSettle();

      // Enter name, email, password
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Karla Islas');
      await tester.enterText(textFields.at(1), 'karip2209@gmail.com');
      await tester.enterText(textFields.at(2), 'Pass123!@#');
      await tester.pumpAndSettle();

      // Select Street
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('loreto').last);
      await tester.pumpAndSettle();

      // Select Number
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('#108 [Available]').last);
      await tester.pumpAndSettle();

      // Tap create user button
      final submitBtn = find.byType(ElevatedButton);
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Check success SnackBar
      expect(find.textContaining('User account created successfully!'), findsOneWidget);

      final addressDoc = await FakeBackendHelper.db.getDocument('addresses', 'loreto_108');
      expect(addressDoc?['residentUid'], isNotNull);
    });
  });
}
