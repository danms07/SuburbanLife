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

  group('Admin User Management Lifecycle & Invocations', () {
    test('Invoking adminDeleteUser records correct payload in callHistory', () async {
      FakeBackendHelper.functions.registerHandler('adminDeleteUser', (params) {
        return {'success': true};
      });

      final result = await FakeBackendHelper.functions.callFunction('adminDeleteUser', {
        'uid': 'resident_to_delete_123',
      });

      expect(result['success'], isTrue);
      expect(FakeBackendHelper.functions.callHistory.length, equals(1));
      expect(FakeBackendHelper.functions.callHistory.first['name'], equals('adminDeleteUser'));
      expect(FakeBackendHelper.functions.callHistory.first['parameters'], equals({
        'uid': 'resident_to_delete_123',
      }));
    });

    test('Invoking unbindAddress records correct payload in callHistory', () async {
      FakeBackendHelper.functions.registerHandler('unbindAddress', (params) {
        return {'success': true, 'message': 'Address unlinked successfully.'};
      });

      final result = await FakeBackendHelper.functions.callFunction('unbindAddress', {
        'uid': 'resident_to_unbind_456',
      });

      expect(result['success'], isTrue);
      expect(FakeBackendHelper.functions.callHistory.any((c) =>
          c['name'] == 'unbindAddress' &&
          c['parameters']?['uid'] == 'resident_to_unbind_456'), isTrue);
    });

    test('Promoting and revoking admin updates users collection document', () async {
      FakeBackendHelper.db.seedDocument('users', 'user_789', {
        'id': 'user_789',
        'name': 'Test Resident',
        'email': 'resident@example.com',
        'role': 'resident',
      });

      // Promote to admin
      await FakeBackendHelper.db.updateDocument('users', 'user_789', {'role': 'admin'});
      var doc = await FakeBackendHelper.db.getDocument('users', 'user_789');
      expect(doc?['role'], equals('admin'));

      // Revoke admin
      await FakeBackendHelper.db.updateDocument('users', 'user_789', {'role': 'resident'});
      doc = await FakeBackendHelper.db.getDocument('users', 'user_789');
      expect(doc?['role'], equals('resident'));
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
  });
}
