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

  group('Admin Resident Creation & Delivery Date Validation', () {
    test('Cloud Function validation rejects resident creation with future delivery date (January 1st 2100)', () async {
      FakeBackendHelper.db.seedDocument('addresses', 'loreto_108', {
        'id': 'loreto_108',
        'streetName': 'loreto',
        'number': 108,
        'paymentStatus': 'paid',
        'residentUid': null,
      });

      final futureDate = DateTime(2100, 1, 1).toIso8601String();

      expect(
        () => FunctionsService().callFunction('adminCreateUser', {
          'name': 'Karla Islas',
          'email': 'karip2209@gmail.com',
          'password': 'Password123!',
          'role': 'resident',
          'addressId': 'loreto_108',
          'streetName': 'loreto',
          'number': 108,
          'deliveryDate': futureDate,
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Delivery date cannot be in the future.'),
          ),
        ),
      );

      // Verify no user was created and address remains unclaimed
      final addressDoc = await FakeBackendHelper.db.getDocument('addresses', 'loreto_108');
      expect(addressDoc?['residentUid'], isNull);
    });

    test('Cloud Function validation creates resident with past delivery date (January 1st 2025)', () async {
      FakeBackendHelper.db.seedDocument('addresses', 'loreto_108', {
        'id': 'loreto_108',
        'streetName': 'loreto',
        'number': 108,
        'paymentStatus': 'paid',
        'residentUid': null,
      });

      final validDate = DateTime(2025, 1, 1).toIso8601String();

      final result = await FunctionsService().callFunction('adminCreateUser', {
        'name': 'Karla Islas',
        'email': 'karip2209@gmail.com',
        'password': 'Password123!',
        'role': 'resident',
        'addressId': 'loreto_108',
        'streetName': 'loreto',
        'number': 108,
        'deliveryDate': validDate,
      });

      expect(result['success'], equals(true));
      final uid = result['uid'];

      // Verify user document
      final userDoc = await FakeBackendHelper.db.getDocument('users', uid);
      expect(userDoc?['email'], equals('karip2209@gmail.com'));
      expect(userDoc?['name'], equals('Karla Islas'));
      expect(userDoc?['role'], equals('resident'));

      // Verify address was claimed with delivery date
      final addressDoc = await FakeBackendHelper.db.getDocument('addresses', 'loreto_108');
      expect(addressDoc?['residentUid'], equals(uid));
      expect(addressDoc?['deliveryDate'], equals(DateTime(2025, 1, 1)));
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
