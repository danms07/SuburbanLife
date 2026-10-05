import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/features/admin/admin_access_logs_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
  });

  group('Admin Access Logs In-Memory Filtering Logic', () {
    final sampleLogs = [
      {
        'id': 'log-1',
        'guestName': 'John Doe',
        'accessCategory': 'visitor',
        'addressDisplay': 'Calle Roble #101',
        'streetName': 'Calle Roble',
        'number': '101',
        'vehiclePlates': 'ABC-123',
        'status': 'allowed',
        'timestamp': DateTime(2026, 8, 18, 10, 30).millisecondsSinceEpoch,
        'reason': 'Family visit',
      },
      {
        'id': 'log-2',
        'guestName': 'Acme Delivery Services',
        'accessCategory': 'supplier',
        'addressDisplay': 'Calle Roble #101',
        'streetName': 'Calle Roble',
        'number': '101',
        'vehiclePlates': 'XYZ-999',
        'status': 'allowed',
        'timestamp': DateTime(2026, 8, 18, 14, 0).millisecondsSinceEpoch,
        'reason': 'Package delivery',
      },
      {
        'id': 'log-3',
        'guestName': 'Carlos Gomez',
        'accessCategory': 'visitor',
        'addressDisplay': 'Av. Los Pinos #50',
        'streetName': 'Av. Los Pinos',
        'number': '50',
        'vehiclePlates': 'MNO-456',
        'status': 'denied',
        'timestamp': DateTime(2026, 8, 10, 9, 0).millisecondsSinceEpoch,
        'reason': 'QR Code has expired',
      },
    ];

    test('Filters by destination address correctly', () {
      final filtered = sampleLogs.where((log) {
        return log['addressDisplay'] == 'Calle Roble #101';
      }).toList();

      expect(filtered.length, 2);
      expect(filtered.map((l) => l['id']), containsAll(['log-1', 'log-2']));
    });

    test('Filters by visitor category (guest vs supplier) correctly', () {
      final suppliers = sampleLogs.where((log) => log['accessCategory'] == 'supplier').toList();
      final guests = sampleLogs.where((log) => log['accessCategory'] == 'visitor').toList();

      expect(suppliers.length, 1);
      expect(suppliers.first['guestName'], 'Acme Delivery Services');

      expect(guests.length, 2);
      expect(guests.map((l) => l['id']), containsAll(['log-1', 'log-3']));
    });

    test('Filters by date range correctly', () {
      final start = DateTime(2026, 8, 18, 0, 0, 0);
      final end = DateTime(2026, 8, 18, 23, 59, 59);

      final filtered = sampleLogs.where((log) {
        final dt = DateTime.fromMillisecondsSinceEpoch(log['timestamp'] as int);
        return !dt.isBefore(start) && !dt.isAfter(end);
      }).toList();

      expect(filtered.length, 2);
      expect(filtered.map((l) => l['id']), containsAll(['log-1', 'log-2']));
    });

    test('Filters by search keyword across guest name, plates and reason', () {
      bool matchesSearch(Map<String, dynamic> log, String query) {
        final q = query.toLowerCase();
        return (log['guestName'] as String).toLowerCase().contains(q) ||
            (log['vehiclePlates'] as String).toLowerCase().contains(q) ||
            (log['reason'] as String).toLowerCase().contains(q);
      }

      final queryPlates = sampleLogs.where((l) => matchesSearch(l, 'XYZ')).toList();
      expect(queryPlates.length, 1);
      expect(queryPlates.first['id'], 'log-2');

      final queryReason = sampleLogs.where((l) => matchesSearch(l, 'expired')).toList();
      expect(queryReason.length, 1);
      expect(queryReason.first['id'], 'log-3');
    });
  });

  group('Batched Database Queries for Access Logs (20 Items per Batch)', () {
    test('getCollection respects limit: 20 and startAfter for pagination', () async {
      // Seed 35 access log documents
      for (int i = 1; i <= 35; i++) {
        final id = 'log_${i.toString().padLeft(3, '0')}';
        final ts = DateTime(2026, 8, 25, 0, 0).subtract(Duration(hours: i));
        FakeBackendHelper.db.seedDocument('access_logs', id, {
          'id': id,
          'guestName': 'Guest $i',
          'accessCategory': (i % 3 == 0) ? 'supplier' : 'visitor',
          'addressDisplay': 'Calle Catania #${100 + i}',
          'streetName': 'Calle Catania',
          'number': '${100 + i}',
          'vehiclePlates': 'PLT-$i',
          'status': (i % 5 == 0) ? 'denied' : 'allowed',
          'timestamp': ts.millisecondsSinceEpoch,
          'reason': 'Visit #$i',
        });
      }

      // Batch 1: First 20 items (sorted descending by timestamp)
      final batch1 = await FakeBackendHelper.db.getCollection(
        'access_logs',
        sorts: [QuerySort('timestamp', descending: true)],
        limit: 20,
      );

      expect(batch1.length, equals(20));
      expect(batch1.first['guestName'], equals('Guest 1'));
      expect(batch1.last['guestName'], equals('Guest 20'));

      // Batch 2: Next 15 items using cursor startAfter
      final lastDocId = batch1.last['id'];
      final batch2 = await FakeBackendHelper.db.getCollection(
        'access_logs',
        sorts: [QuerySort('timestamp', descending: true)],
        limit: 20,
        startAfter: lastDocId,
      );

      expect(batch2.length, equals(15));
      expect(batch2.first['guestName'], equals('Guest 21'));
      expect(batch2.last['guestName'], equals('Guest 35'));
    });
  });

  group('AdminAccessLogsScreen Widget Tests', () {
    Widget createTestWidget() {
      return const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AdminAccessLogsScreen(),
      );
    }

    testWidgets('Renders first batch of 20 logs and loads more on button press', (tester) async {
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
      });
      FakeBackendHelper.db.seedDocument('addresses', 'addr_2', {
        'id': 'addr_2',
        'streetName': 'Av. Los Pinos',
        'number': '202',
      });

      // Seed 25 access logs
      for (int i = 1; i <= 25; i++) {
        final id = 'log_${i.toString().padLeft(3, '0')}';
        final ts = DateTime(2026, 8, 25, 12, 0).subtract(Duration(minutes: i * 10));
        FakeBackendHelper.db.seedDocument('access_logs', id, {
          'id': id,
          'guestName': 'Guest ${i.toString().padLeft(2, '0')}',
          'accessCategory': (i % 2 == 0) ? 'supplier' : 'visitor',
          'addressDisplay': (i % 2 == 0) ? 'Calle Catania #101' : 'Av. Los Pinos #202',
          'streetName': (i % 2 == 0) ? 'Calle Catania' : 'Av. Los Pinos',
          'number': (i % 2 == 0) ? '101' : '202',
          'vehiclePlates': 'XYZ-$i',
          'status': 'allowed',
          'timestamp': ts.millisecondsSinceEpoch,
          'reason': 'Entry visit $i',
        });
      }

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Verify KPI metrics and first log card
      expect(find.text('Guest 01'), findsOneWidget);

      final verticalScrollable = find.byType(Scrollable).first;

      // Scroll to verify Guest 20 is present in the first batch
      await tester.scrollUntilVisible(find.text('Guest 20'), 500, scrollable: verticalScrollable);
      expect(find.text('Guest 20'), findsOneWidget);
      expect(find.text('Guest 21'), findsNothing);

      // Scroll to and tap "Load More Logs" button
      final loadMoreFinder = find.byIcon(Icons.expand_more);
      await tester.scrollUntilVisible(loadMoreFinder, 500, scrollable: verticalScrollable);
      expect(loadMoreFinder, findsOneWidget);

      await tester.tap(loadMoreFinder);
      await tester.pumpAndSettle();

      // Now Guest 21 through Guest 25 should be rendered
      await tester.scrollUntilVisible(find.text('Guest 25'), 500, scrollable: verticalScrollable);
      expect(find.text('Guest 25'), findsOneWidget);
    });

    testWidgets('Filters logs by destination address dropdown', (tester) async {
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
      });
      FakeBackendHelper.db.seedDocument('addresses', 'addr_2', {
        'id': 'addr_2',
        'streetName': 'Av. Los Pinos',
        'number': '202',
      });

      // Seed 2 access logs with different addresses
      FakeBackendHelper.db.seedDocument('access_logs', 'log_1', {
        'id': 'log_1',
        'guestName': 'Alice Resident Guest',
        'accessCategory': 'visitor',
        'addressDisplay': 'Calle Catania #101',
        'streetName': 'Calle Catania',
        'number': '101',
        'status': 'allowed',
        'timestamp': DateTime(2026, 8, 25, 10, 0).millisecondsSinceEpoch,
      });

      FakeBackendHelper.db.seedDocument('access_logs', 'log_2', {
        'id': 'log_2',
        'guestName': 'Bob Pinos Guest',
        'accessCategory': 'visitor',
        'addressDisplay': 'Av. Los Pinos #202',
        'streetName': 'Av. Los Pinos',
        'number': '202',
        'status': 'allowed',
        'timestamp': DateTime(2026, 8, 25, 9, 0).millisecondsSinceEpoch,
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Alice Resident Guest'), findsOneWidget);
      expect(find.text('Bob Pinos Guest'), findsOneWidget);

      // Select 'Calle Catania #101' from the address dropdown
      await tester.tap(find.text('All Addresses'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Calle Catania #101').last);
      await tester.pumpAndSettle();

      // Only Alice should remain visible
      expect(find.text('Alice Resident Guest'), findsOneWidget);
      expect(find.text('Bob Pinos Guest'), findsNothing);

      // Clear filter via Clear Filters button
      expect(find.text('Clear Filters'), findsOneWidget);
      await tester.tap(find.text('Clear Filters'));
      await tester.pumpAndSettle();

      expect(find.text('Alice Resident Guest'), findsOneWidget);
      expect(find.text('Bob Pinos Guest'), findsOneWidget);
    });

    testWidgets('Filters logs by search query keyword', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FakeBackendHelper.db.seedDocument('access_logs', 'log_1', {
        'id': 'log_1',
        'guestName': 'Special VIP Guest',
        'accessCategory': 'visitor',
        'addressDisplay': 'Calle Catania #101',
        'vehiclePlates': 'VIP-001',
        'status': 'allowed',
        'timestamp': DateTime(2026, 8, 25, 10, 0).millisecondsSinceEpoch,
      });

      FakeBackendHelper.db.seedDocument('access_logs', 'log_2', {
        'id': 'log_2',
        'guestName': 'Regular Visitor',
        'accessCategory': 'visitor',
        'addressDisplay': 'Calle Catania #101',
        'vehiclePlates': 'REG-999',
        'status': 'allowed',
        'timestamp': DateTime(2026, 8, 25, 9, 0).millisecondsSinceEpoch,
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Special VIP Guest'), findsOneWidget);
      expect(find.text('Regular Visitor'), findsOneWidget);

      // Enter search text 'VIP'
      await tester.enterText(find.byType(TextField), 'VIP');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.text('Special VIP Guest'), findsOneWidget);
      expect(find.text('Regular Visitor'), findsNothing);
    });

    testWidgets('Searches whole database to find access logs outside initial 20 preloaded items', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Seed 25 access logs with timestamps descending (most recent first)
      final baseTime = DateTime(2026, 8, 25, 12, 0);
      for (int i = 1; i <= 25; i++) {
        final padded = i.toString().padLeft(2, '0');
        FakeBackendHelper.db.seedDocument('access_logs', 'log_$padded', {
          'id': 'log_$padded',
          'guestName': 'Standard Visitor $padded',
          'accessCategory': 'visitor',
          'addressDisplay': 'Calle Catania #101',
          'vehiclePlates': 'STD-$padded',
          'status': 'allowed',
          'timestamp': baseTime.subtract(Duration(minutes: i)).millisecondsSinceEpoch,
        });
      }

      // Seed an older target access log that would be on batch 2 (> 20)
      FakeBackendHelper.db.seedDocument('access_logs', 'log_target', {
        'id': 'log_target',
        'guestName': 'Unique Delivery Driver',
        'accessCategory': 'supplier',
        'addressDisplay': 'Av. Los Pinos #505',
        'vehiclePlates': 'DELIV-99',
        'status': 'allowed',
        'timestamp': baseTime.subtract(const Duration(hours: 10)).millisecondsSinceEpoch,
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // On initial load (batch 1 of 20), the older target log is not present
      expect(find.text('Standard Visitor 01'), findsOneWidget);
      expect(find.text('Unique Delivery Driver'), findsNothing);

      // Now search for 'DELIV-99' -> query searches entire database
      await tester.enterText(find.byType(TextField), 'DELIV-99');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      // Unique Delivery Driver is loaded and found from the whole database
      expect(find.text('Unique Delivery Driver'), findsOneWidget);
      expect(find.text('Standard Visitor 01'), findsNothing);
    });
  });
}
