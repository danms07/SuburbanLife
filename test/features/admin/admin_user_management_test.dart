import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/features/admin/admin_user_management_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
  });

  group('AdminUserManagementScreen Role, Unbind & Self-Safeguard Actions', () {
    Widget createManagementWidget() {
      return const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AdminUserManagementScreen(),
      );
    }

    testWidgets('Summary card hides inline action buttons and navigates to AdminUserDetailScreen for role, password, and unbind actions', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FakeBackendHelper.auth.emitUser(
        AppUser(
          uid: 'current_admin_uid',
          email: 'superadmin@catania.com',
          displayName: 'Super Admin',
        ),
      );
      FakeBackendHelper.auth.isAdminMock = true;

      FakeBackendHelper.functions.registerHandler('setCustomUserClaims', (params) {
        return {'success': true};
      });
      FakeBackendHelper.functions.registerHandler('unbindAddress', (params) {
        return {'success': true, 'message': 'Address unlinked successfully.'};
      });
      FakeBackendHelper.functions.registerHandler('adminUpdatePassword', (params) {
        return {'success': true};
      });

      FakeBackendHelper.db.seedDocument('addresses', 'addr_789', {
        'id': 'addr_789',
        'streetName': 'Calle Catania',
        'number': '789',
        'paymentStatus': 'paid',
      });
      FakeBackendHelper.db.seedDocument('users', 'user_789', {
        'id': 'user_789',
        'uid': 'user_789',
        'name': 'Test Resident',
        'email': 'resident@example.com',
        'role': 'resident',
        'addressRef': FakeBackendHelper.db.createReference('addresses', 'addr_789'),
      });

      await tester.pumpWidget(createManagementWidget());
      await tester.pumpAndSettle();

      expect(find.text('Test Resident'), findsOneWidget);
      expect(find.text('Calle Catania #789'), findsOneWidget);

      // Summary cards in the directory list must NOT display inline action buttons
      expect(find.text('Promote to Admin'), findsNothing);
      expect(find.text('Change User Password'), findsNothing);
      expect(find.text('Remove Account'), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      // Tap summary card to open AdminUserDetailScreen
      await tester.tap(find.byKey(const ValueKey('user_card_user_789')));
      await tester.pumpAndSettle();

      expect(find.byType(AdminUserDetailScreen), findsOneWidget);
      expect(find.text('User Account Details'), findsOneWidget);
      expect(find.text('Promote to Admin'), findsOneWidget);

      // 1. Click 'Promote to Admin' button inside AdminUserDetailScreen
      await tester.tap(find.byKey(const ValueKey('user_detail_toggle_admin_button')));
      await tester.pumpAndSettle();

      var userDoc = await FakeBackendHelper.db.getDocument('users', 'user_789');
      expect(userDoc?['role'], equals('admin'));
      expect(
        FakeBackendHelper.functions.callHistory.any(
          (c) =>
              c['name'] == 'setCustomUserClaims' &&
              c['parameters']?['uid'] == 'user_789' &&
              c['parameters']?['claims']?['admin'] == true,
        ),
        isTrue,
      );

      // Advance SnackBar before next button tap
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // 2. Click 'Revoke Admin' button
      expect(find.text('Revoke Admin'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('user_detail_toggle_admin_button')));
      await tester.pumpAndSettle();

      userDoc = await FakeBackendHelper.db.getDocument('users', 'user_789');
      expect(userDoc?['role'], equals('resident'));
      expect(
        FakeBackendHelper.functions.callHistory.any(
          (c) =>
              c['name'] == 'setCustomUserClaims' &&
              c['parameters']?['uid'] == 'user_789' &&
              c['parameters']?['claims']?['admin'] == false,
        ),
        isTrue,
      );

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // 3. Unbind address via UI button and confirmation dialog
      await tester.tap(find.byKey(const ValueKey('user_detail_unbind_address_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(
        FakeBackendHelper.functions.callHistory.any(
          (c) =>
              c['name'] == 'unbindAddress' &&
              c['parameters']?['uid'] == 'user_789',
        ),
        isTrue,
      );
      expect(find.text('No active address linked.'), findsOneWidget);
      expect(find.byKey(const ValueKey('user_detail_unbind_address_button')), findsNothing);

      // Navigate back and verify directory card also reflects unlinked state
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(AdminUserDetailScreen), findsNothing);
      expect(find.text('No active address linked.'), findsOneWidget);
    });

    testWidgets('Prevents currently signed-in admin from revoking or deleting their own account', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FakeBackendHelper.auth.emitUser(
        AppUser(
          uid: 'self_admin_uid',
          email: 'self@catania.com',
          displayName: 'Self Admin',
        ),
      );
      FakeBackendHelper.auth.isAdminMock = true;

      FakeBackendHelper.db.seedDocument('users', 'self_admin_uid', {
        'id': 'self_admin_uid',
        'uid': 'self_admin_uid',
        'name': 'Self Admin',
        'email': 'self@catania.com',
        'role': 'admin',
      });

      await tester.pumpWidget(createManagementWidget());
      await tester.pumpAndSettle();

      // Open detail screen for self admin
      await tester.tap(find.byKey(const ValueKey('user_card_self_admin_uid')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('user_detail_toggle_admin_button')));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('user_detail_delete_user_button')));
      await tester.pumpAndSettle();

      expect(FakeBackendHelper.functions.callHistory, isEmpty);
      final selfDoc = await FakeBackendHelper.db.getDocument('users', 'self_admin_uid');
      expect(selfDoc?['role'], equals('admin'));
      expect(find.byType(AdminUserDetailScreen), findsOneWidget);
    });
  });

  group('Batched Database Queries (20 Users per Batch)', () {
    test('getCollection respects limit: 20 and startAfter for pagination', () async {
      // Seed 45 users
      for (int i = 1; i <= 45; i++) {
        final id = 'user_${i.toString().padLeft(3, '0')}';
        FakeBackendHelper.db.seedDocument('users', id, {
          'id': id,
          'uid': id,
          'name': 'User ${i.toString().padLeft(3, '0')}',
          'email': 'user$i@example.com',
          'role': 'resident',
        });
      }

      // Batch 1: Limit 20
      final batch1 = await FakeBackendHelper.db.getCollection(
        'users',
        sorts: [QuerySort('name', descending: false)],
        limit: 20,
      );
      expect(batch1.length, equals(20));
      expect(batch1.first['name'], equals('User 001'));
      expect(batch1.last['name'], equals('User 020'));

      // Batch 2: Next 20 starting after last item of batch 1
      final lastBatch1Id = batch1.last['id'];
      final batch2 = await FakeBackendHelper.db.getCollection(
        'users',
        sorts: [QuerySort('name', descending: false)],
        limit: 20,
        startAfter: lastBatch1Id,
      );
      expect(batch2.length, equals(20));
      expect(batch2.first['name'], equals('User 021'));
      expect(batch2.last['name'], equals('User 040'));

      // Batch 3: Remaining 5 items
      final lastBatch2Id = batch2.last['id'];
      final batch3 = await FakeBackendHelper.db.getCollection(
        'users',
        sorts: [QuerySort('name', descending: false)],
        limit: 20,
        startAfter: lastBatch2Id,
      );
      expect(batch3.length, equals(5));
      expect(batch3.first['name'], equals('User 041'));
      expect(batch3.last['name'], equals('User 045'));
    });
  });

  group('AdminUserManagementScreen Widget Tests', () {
    Widget createTestWidget() {
      return const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AdminUserManagementScreen(),
      );
    }

    testWidgets('Renders first batch of 20 users and loads more on button press', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Seed addresses
      FakeBackendHelper.db.seedDocument('addresses', 'addr_1', {
        'id': 'addr_1',
        'streetName': 'Calle Catania',
        'number': '101',
        'paymentStatus': 'paid',
      });
      FakeBackendHelper.db.seedDocument('addresses', 'addr_2', {
        'id': 'addr_2',
        'streetName': 'Av. Los Pinos',
        'number': '202',
        'paymentStatus': 'pending',
      });

      // Seed 25 users
      for (int i = 1; i <= 25; i++) {
        final id = 'user_${i.toString().padLeft(3, '0')}';
        final addrId = (i % 2 == 0) ? 'addr_1' : 'addr_2';
        FakeBackendHelper.db.seedDocument('users', id, {
          'id': id,
          'uid': id,
          'name': 'Resident ${i.toString().padLeft(2, '0')}',
          'email': 'resident$i@example.com',
          'role': 'resident',
          'addressRef': FakeBackendHelper.db.createReference('addresses', addrId),
        });
      }

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Should initially display first batch of 20 users
      expect(find.byType(Card), findsWidgets);
      expect(find.text('Resident 01'), findsOneWidget);

      // Scroll to verify Resident 20 is present in the first batch
      final verticalScrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('Resident 20'), 500, scrollable: verticalScrollable);
      expect(find.text('Resident 20'), findsOneWidget);
      expect(find.text('Resident 21'), findsNothing);

      // Scroll to and tap the "Load More Users" button
      final loadMoreFinder = find.byIcon(Icons.expand_more);
      await tester.scrollUntilVisible(loadMoreFinder, 500, scrollable: verticalScrollable);
      expect(loadMoreFinder, findsOneWidget);

      await tester.tap(loadMoreFinder);
      await tester.pumpAndSettle();

      // Now the remaining 5 users should be loaded
      await tester.scrollUntilVisible(find.text('Resident 21'), 500, scrollable: verticalScrollable);
      expect(find.text('Resident 21'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Resident 25'), 500, scrollable: verticalScrollable);
      expect(find.text('Resident 25'), findsOneWidget);
    });

    testWidgets('Filters users by search query (name, email, or street)', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FakeBackendHelper.db.seedDocument('addresses', 'addr_catania', {
        'id': 'addr_catania',
        'streetName': 'Calle Catania',
        'number': '101',
        'paymentStatus': 'paid',
      });
      FakeBackendHelper.db.seedDocument('addresses', 'addr_pinos', {
        'id': 'addr_pinos',
        'streetName': 'Av. Los Pinos',
        'number': '50',
        'paymentStatus': 'restricted',
      });

      FakeBackendHelper.db.seedDocument('users', 'user_1', {
        'id': 'user_1',
        'name': 'Carlos Gomez',
        'email': 'carlos@example.com',
        'role': 'resident',
        'addressRef': FakeBackendHelper.db.createReference('addresses', 'addr_catania'),
      });
      FakeBackendHelper.db.seedDocument('users', 'user_2', {
        'id': 'user_2',
        'name': 'Ana Perez',
        'email': 'ana@example.com',
        'role': 'resident',
        'addressRef': FakeBackendHelper.db.createReference('addresses', 'addr_pinos'),
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Carlos Gomez'), findsOneWidget);
      expect(find.text('Ana Perez'), findsOneWidget);

      // Search by name
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'carlos');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.text('Carlos Gomez'), findsOneWidget);
      expect(find.text('Ana Perez'), findsNothing);

      // Search by email
      await tester.enterText(searchField, 'ana@');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.text('Carlos Gomez'), findsNothing);
      expect(find.text('Ana Perez'), findsOneWidget);

      // Search by street
      await tester.enterText(searchField, 'Catania');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.text('Carlos Gomez'), findsOneWidget);
      expect(find.text('Ana Perez'), findsNothing);

      // Clear search
      final clearButton = find.byIcon(Icons.clear);
      await tester.tap(clearButton);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.text('Carlos Gomez'), findsOneWidget);
      expect(find.text('Ana Perez'), findsOneWidget);
    });

    testWidgets('Filters users by street dropdown selection', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FakeBackendHelper.db.seedDocument('addresses', 'addr_catania', {
        'id': 'addr_catania',
        'streetName': 'Calle Catania',
        'number': '101',
        'paymentStatus': 'paid',
      });
      FakeBackendHelper.db.seedDocument('addresses', 'addr_pinos', {
        'id': 'addr_pinos',
        'streetName': 'Av. Los Pinos',
        'number': '50',
        'paymentStatus': 'restricted',
      });

      FakeBackendHelper.db.seedDocument('users', 'user_1', {
        'id': 'user_1',
        'name': 'Carlos Gomez',
        'email': 'carlos@example.com',
        'role': 'resident',
        'addressRef': FakeBackendHelper.db.createReference('addresses', 'addr_catania'),
      });
      FakeBackendHelper.db.seedDocument('users', 'user_2', {
        'id': 'user_2',
        'name': 'Ana Perez',
        'email': 'ana@example.com',
        'role': 'resident',
        'addressRef': FakeBackendHelper.db.createReference('addresses', 'addr_pinos'),
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Open street dropdown
      final dropdownFinder = find.byType(DropdownButton<String>);
      expect(dropdownFinder, findsOneWidget);

      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      // Tap 'Calle Catania' item
      final cataniaItem = find.text('Calle Catania').last;
      await tester.tap(cataniaItem);
      await tester.pumpAndSettle();

      expect(find.text('Carlos Gomez'), findsOneWidget);
      expect(find.text('Ana Perez'), findsNothing);

      // Tap Clear Filters
      final clearFiltersBtn = find.byIcon(Icons.filter_alt_off);
      expect(clearFiltersBtn, findsOneWidget);
      await tester.tap(clearFiltersBtn);
      await tester.pumpAndSettle();

      expect(find.text('Carlos Gomez'), findsOneWidget);
      expect(find.text('Ana Perez'), findsOneWidget);
    });

    testWidgets('Searches whole database to find users outside initial 20 preloaded items', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FakeBackendHelper.db.seedDocument('addresses', 'addr_special', {
        'id': 'addr_special',
        'streetName': 'Calle Especial',
        'number': '999',
        'paymentStatus': 'paid',
      });

      // Seed 25 users alphabetically before our target user
      for (int i = 1; i <= 25; i++) {
        final padded = i.toString().padLeft(2, '0');
        FakeBackendHelper.db.seedDocument('users', 'user_$padded', {
          'id': 'user_$padded',
          'name': 'Alpha User $padded',
          'email': 'alpha$padded@example.com',
          'role': 'resident',
        });
      }

      // Seed target user that would be on batch 2 (> 20)
      FakeBackendHelper.db.seedDocument('users', 'user_target', {
        'id': 'user_target',
        'name': 'Zoe Target',
        'email': 'zoe.target@example.com',
        'role': 'resident',
        'addressRef': FakeBackendHelper.db.createReference('addresses', 'addr_special'),
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // On initial load (batch 1 of 20), Zoe is not in the first 20 items
      expect(find.text('Alpha User 01'), findsOneWidget);
      expect(find.text('Zoe Target'), findsNothing);

      // Now search for 'Zoe' -> query searches entire database
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'Zoe');
      // Wait for debounce timer and async DB fetch
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      // Zoe Target is found from the whole database
      expect(find.text('Zoe Target'), findsOneWidget);
      expect(find.text('Alpha User 01'), findsNothing);
    });

    testWidgets('Setting or editing delivery date in AdminUserDetailScreen updates deliveryDate without recalculating paymentStatus', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final oldDeliveryDate = DateTime(2024, 1, 15);
      FakeBackendHelper.db.seedDocument('addresses', 'addr_claimed', {
        'id': 'addr_claimed',
        'streetName': 'Calle Catania',
        'number': '101',
        'residentUid': 'user_claimed',
        'paymentStatus': 'paid',
        'deliveryDate': oldDeliveryDate,
      });

      FakeBackendHelper.db.seedDocument('users', 'user_claimed', {
        'id': 'user_claimed',
        'uid': 'user_claimed',
        'name': 'Mario Rossi',
        'email': 'mario@example.com',
        'role': 'resident',
        'addressRef': FakeBackendHelper.db.createReference('addresses', 'addr_claimed'),
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Edit Delivery Date button is not shown inline on summary card
      expect(find.byIcon(Icons.edit_calendar), findsNothing);

      // Tap user summary card to open AdminUserDetailScreen
      await tester.tap(find.byKey(const ValueKey('user_card_user_claimed')));
      await tester.pumpAndSettle();

      // Tap Edit Delivery Date button inside AdminUserDetailScreen
      final editDateBtn = find.byKey(const ValueKey('user_detail_edit_delivery_date_button'));
      expect(editDateBtn, findsOneWidget);
      await tester.tap(editDateBtn);
      await tester.pumpAndSettle();

      // Pick day 20 and confirm OK
      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Verify deliveryDate was updated in DB while paymentStatus stays 'paid'
      final updatedAddr = await FakeBackendHelper.db.getDocument('addresses', 'addr_claimed');
      expect(updatedAddr?['deliveryDate'], equals(DateTime(2024, 1, 20)));
      expect(updatedAddr?['paymentStatus'], equals('paid'));
      expect(find.textContaining('20/01/2024'), findsOneWidget);

      // Navigate back and verify directory summary card also shows updated date
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining('20/01/2024'), findsOneWidget);
    });

    testWidgets('Filters and manages security guard accounts via AdminUserDetailScreen without Promote to Admin button and opens Create User preselected to guard', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FakeBackendHelper.functions.registerHandler('adminDeleteUser', (params) {
        return {'success': true};
      });

      FakeBackendHelper.db.seedDocument('users', 'res_1', {
        'id': 'res_1',
        'uid': 'res_1',
        'name': 'Laura Resident',
        'email': 'laura@example.com',
        'role': 'resident',
      });
      FakeBackendHelper.db.seedDocument('users', 'guard_1', {
        'id': 'guard_1',
        'uid': 'guard_1',
        'name': 'Pedro Guard',
        'email': 'pedro.guard@example.com',
        'role': 'guard',
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Initially both resident and guard are visible as summary cards without inline buttons
      expect(find.text('Laura Resident'), findsOneWidget);
      expect(find.text('Pedro Guard'), findsOneWidget);
      expect(find.text('Remove Account'), findsNothing);

      // Filter by Guard role segment
      await tester.tap(find.text('Guard'));
      await tester.pumpAndSettle();

      expect(find.text('Pedro Guard'), findsOneWidget);
      expect(find.text('Laura Resident'), findsNothing);

      // Tapping Create User in AppBar while filtered by Guard opens AdminCreateUserScreen preselected to guard
      await tester.tap(find.byKey(const ValueKey('manage_users_create_user_button')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.manage_accounts), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Open Pedro Guard's AdminUserDetailScreen
      await tester.tap(find.byKey(const ValueKey('user_card_guard_1')));
      await tester.pumpAndSettle();

      // Guard detail screen must not show 'Promote to Admin' button, only Change Password and Remove Account
      expect(find.byKey(const ValueKey('user_detail_toggle_admin_button')), findsNothing);
      expect(find.byKey(const ValueKey('user_detail_change_password_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('user_detail_delete_user_button')), findsOneWidget);

      // Delete the security guard account -> automatically pops back to directory
      await tester.tap(find.byKey(const ValueKey('user_detail_delete_user_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(
        FakeBackendHelper.functions.callHistory.any(
          (c) => c['name'] == 'adminDeleteUser' && c['parameters']?['uid'] == 'guard_1',
        ),
        isTrue,
      );
      expect(find.byType(AdminUserDetailScreen), findsNothing);
      expect(find.text('Pedro Guard'), findsNothing);
    });

    testWidgets('AdminUserDetailScreen renders cleanly on mobile in Spanish and updates password', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FakeBackendHelper.functions.registerHandler('adminUpdatePassword', (params) {
        return {'success': true};
      });

      FakeBackendHelper.db.seedDocument('addresses', 'addr_es', {
        'id': 'addr_es',
        'streetName': 'Etna',
        'number': '12',
        'paymentStatus': 'paid',
      });
      FakeBackendHelper.db.seedDocument('users', 'user_es', {
        'id': 'user_es',
        'uid': 'user_es',
        'name': 'Ana Gomez',
        'email': 'ana@test.com',
        'role': 'roommate',
        'addressRef': FakeBackendHelper.db.createReference('addresses', 'addr_es'),
      });

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AdminUserDetailScreen(
            userDoc: {
              'id': 'user_es',
              'uid': 'user_es',
              'name': 'Ana Gomez',
              'email': 'ana@test.com',
              'role': 'roommate',
              'addressRef': FakeBackendHelper.db.createReference('addresses', 'addr_es'),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Datos de la Cuenta'), findsOneWidget);
      expect(find.text('Acciones de Cuenta y Propiedad'), findsOneWidget);
      expect(find.text('Acciones Sensibles'), findsOneWidget);
      expect(find.text('Etna #12'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('user_detail_change_password_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'StrongPass1!');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(
        FakeBackendHelper.functions.callHistory.any(
          (c) =>
              c['name'] == 'adminUpdatePassword' &&
              c['parameters']?['uid'] == 'user_es' &&
              c['parameters']?['newPassword'] == 'StrongPass1!',
        ),
        isTrue,
      );
    });

    testWidgets('Mobile viewport (360x800, Spanish) wraps role filter chips and search summary badge without horizontal cropping', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FakeBackendHelper.db.seedDocument('users', 'res_only', {
        'id': 'res_only',
        'uid': 'res_only',
        'name': 'Laura Resident',
        'email': 'laura@example.com',
        'role': 'resident',
      });

      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AdminUserManagementScreen(isEmbedded: true),
        ),
      );
      await tester.pumpAndSettle();

      // All 5 role filter chips must be visible within the 360px screen width without horizontal cropping
      for (final roleKey in ['all', 'resident', 'roommate', 'admin', 'guard']) {
        final chipFinder = find.byKey(ValueKey('role_filter_chip_$roleKey'));
        expect(chipFinder, findsOneWidget);
        final rect = tester.getRect(chipFinder);
        expect(rect.left, greaterThanOrEqualTo(0.0));
        expect(rect.right, lessThanOrEqualTo(360.0));
      }

      // Tap Guard chip when zero guards exist -> renders zero-match summary and database search badge without cropping
      await tester.tap(find.byKey(const ValueKey('role_filter_chip_guard')));
      await tester.pumpAndSettle();

      final summaryFinder = find.text('Ningún usuario coincide en la base de datos');
      final badgeFinder = find.text('Búsqueda en base de datos activa');
      expect(summaryFinder, findsOneWidget);
      expect(badgeFinder, findsOneWidget);
      expect(tester.getRect(summaryFinder).right, lessThanOrEqualTo(360.0));
      expect(tester.getRect(badgeFinder).right, lessThanOrEqualTo(360.0));
    });
  });
}
