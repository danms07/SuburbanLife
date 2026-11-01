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

  group('AdminAccessLogsScreen Category, Date & Reason Filter Widget Tests', () {
    Widget createFilterTestWidget() {
      return const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AdminAccessLogsScreen(),
      );
    }

    testWidgets('Filters logs by visitor category SegmentedButton (Guest vs Supplier) and updates KPIs', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      FakeBackendHelper.db.seedDocument('access_logs', 'log-1', {
        'id': 'log-1',
        'guestName': 'John Doe',
        'accessCategory': 'visitor',
        'addressDisplay': 'Calle Roble #101',
        'streetName': 'Calle Roble',
        'number': '101',
        'vehiclePlates': 'ABC-123',
        'status': 'allowed',
        'timestamp': now.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch,
        'reason': 'Family visit',
      });
      FakeBackendHelper.db.seedDocument('access_logs', 'log-2', {
        'id': 'log-2',
        'guestName': 'Acme Delivery Services',
        'accessCategory': 'supplier',
        'addressDisplay': 'Calle Roble #101',
        'streetName': 'Calle Roble',
        'number': '101',
        'vehiclePlates': 'XYZ-999',
        'status': 'allowed',
        'timestamp': now.subtract(const Duration(minutes: 15)).millisecondsSinceEpoch,
        'reason': 'Package delivery',
      });
      FakeBackendHelper.db.seedDocument('access_logs', 'log-3', {
        'id': 'log-3',
        'guestName': 'Carlos Gomez',
        'accessCategory': 'visitor',
        'addressDisplay': 'Av. Los Pinos #50',
        'streetName': 'Av. Los Pinos',
        'number': '50',
        'vehiclePlates': 'MNO-456',
        'status': 'denied',
        'timestamp': now.subtract(const Duration(days: 10)).millisecondsSinceEpoch,
        'reason': 'QR Code has expired',
      });

      await tester.pumpWidget(createFilterTestWidget());
      await tester.pumpAndSettle();

      // Initially all 3 logs are visible
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('Acme Delivery Services'), findsOneWidget);
      expect(find.text('Carlos Gomez'), findsOneWidget);

      final segmentedButton = find.byType(SegmentedButton<String>);

      // Select 'Supplier' segment in SegmentedButton
      await tester.tap(
        find.descendant(
          of: segmentedButton,
          matching: find.byIcon(Icons.local_shipping_outlined),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Acme Delivery Services'), findsOneWidget);
      expect(find.text('John Doe'), findsNothing);
      expect(find.text('Carlos Gomez'), findsNothing);

      // Select 'Guest' segment in SegmentedButton
      await tester.tap(
        find.descendant(
          of: segmentedButton,
          matching: find.byIcon(Icons.person_outline),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('Carlos Gomez'), findsOneWidget);
      expect(find.text('Acme Delivery Services'), findsNothing);

      // Reset to 'All Types'
      await tester.tap(
        find.descendant(
          of: segmentedButton,
          matching: find.byIcon(Icons.groups_outlined),
        ),
      );
      await tester.pumpAndSettle();

      // Filter by Today date chip -> hides Carlos Gomez from 10 days ago
      await tester.tap(find.widgetWithText(ChoiceChip, 'Today'));
      await tester.pumpAndSettle();

      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('Acme Delivery Services'), findsOneWidget);
      expect(find.text('Carlos Gomez'), findsNothing);

      // Switch back to All Dates and search by denial reason ('expired')
      await tester.tap(find.widgetWithText(ChoiceChip, 'All Dates'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'expired');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.text('Carlos Gomez'), findsOneWidget);
      expect(find.text('John Doe'), findsNothing);
      expect(find.text('Acme Delivery Services'), findsNothing);
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
      await tester.ensureVisible(loadMoreFinder);
      await tester.pumpAndSettle();
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

    testWidgets('Displays Currently Inside KPI, exit timestamps, and filters by Currently Inside chip', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FakeBackendHelper.db.seedDocument('config', 'app_settings', {
        'scanOnExitEnabled': true,
      });

      final now = DateTime.now();
      final entryIn = now.subtract(const Duration(minutes: 45));
      final entryOut = now.subtract(const Duration(hours: 2));
      final exitOut = now.subtract(const Duration(hours: 1));

      FakeBackendHelper.db.seedDocument('access_logs', 'log_inside_1', {
        'id': 'log_inside_1',
        'guestName': 'Inside Visitor Laura',
        'accessCategory': 'visitor',
        'addressDisplay': 'Calle Catania #101',
        'status': 'allowed',
        'isInside': true,
        'timestamp': entryIn.millisecondsSinceEpoch,
      });

      FakeBackendHelper.db.seedDocument('access_logs', 'log_exited_1', {
        'id': 'log_exited_1',
        'guestName': 'Exited Supplier Pedro',
        'accessCategory': 'supplier',
        'addressDisplay': 'Calle Catania #102',
        'status': 'allowed',
        'isInside': false,
        'timestamp': entryOut.millisecondsSinceEpoch,
        'exitTimestamp': exitOut.millisecondsSinceEpoch,
        'exitGuardName': 'Guardia Salida',
        'exitReason': 'Delivered water jugs',
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Both visitors are rendered initially
      expect(find.text('Inside Visitor Laura'), findsOneWidget);
      expect(find.text('Exited Supplier Pedro'), findsOneWidget);

      // Inside badge only on log_inside_1
      expect(find.byKey(const ValueKey('log_inside_badge_log_inside_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('log_inside_badge_log_exited_1')), findsNothing);

      // Exit guard & exit notes rendered on exited log
      expect(find.text('Guardia Salida'), findsOneWidget);
      expect(find.textContaining('Delivered water jugs'), findsOneWidget);

      // Tap Currently Inside filter chip
      final insideChip = find.byKey(const ValueKey('filter_currently_inside_chip'));
      expect(insideChip, findsOneWidget);
      await tester.tap(insideChip);
      await tester.pumpAndSettle();

      // Only the visitor currently inside remains displayed
      expect(find.text('Inside Visitor Laura'), findsOneWidget);
      expect(find.text('Exited Supplier Pedro'), findsNothing);
    });
  });

  group('AdminAccessLogsScreen.isLogCurrentlyInside (Explicit & Legacy Fallback)', () {
    final fixedNow = DateTime(2026, 10, 20, 16, 30);
    final earlierToday = DateTime(2026, 10, 20, 10, 15);
    final yesterday = DateTime(2026, 10, 19, 18, 0);

    test('returns true when isInside is explicitly true and exitTimestamp is null', () {
      expect(
        AdminAccessLogsScreen.isLogCurrentlyInside(
          {
            'status': 'allowed',
            'isInside': true,
            'timestamp': yesterday.millisecondsSinceEpoch,
          },
          now: fixedNow,
          scanOnExitEnabled: true,
        ),
        isTrue,
      );
    });

    test('returns false when exitTimestamp is recorded even if isInside was true', () {
      expect(
        AdminAccessLogsScreen.isLogCurrentlyInside(
          {
            'status': 'allowed',
            'isInside': true,
            'timestamp': earlierToday.millisecondsSinceEpoch,
            'exitTimestamp': fixedNow.millisecondsSinceEpoch,
          },
          now: fixedNow,
          scanOnExitEnabled: true,
        ),
        isFalse,
      );
    });

    test('returns false when isInside is explicitly false on same day', () {
      expect(
        AdminAccessLogsScreen.isLogCurrentlyInside(
          {
            'status': 'allowed',
            'isInside': false,
            'timestamp': earlierToday.millisecondsSinceEpoch,
          },
          now: fixedNow,
          scanOnExitEnabled: true,
        ),
        isFalse,
      );
    });

    test('legacy fallback defaults to true for allowed log earlier on the same day when scanOnExitEnabled is true', () {
      expect(
        AdminAccessLogsScreen.isLogCurrentlyInside(
          {
            'status': 'allowed',
            'timestamp': earlierToday.millisecondsSinceEpoch,
          },
          now: fixedNow,
          scanOnExitEnabled: true,
        ),
        isTrue,
      );
    });

    test('legacy fallback returns false for logs from previous calendar days or denied logs', () {
      expect(
        AdminAccessLogsScreen.isLogCurrentlyInside(
          {
            'status': 'allowed',
            'timestamp': yesterday.millisecondsSinceEpoch,
          },
          now: fixedNow,
          scanOnExitEnabled: true,
        ),
        isFalse,
      );

      expect(
        AdminAccessLogsScreen.isLogCurrentlyInside(
          {
            'status': 'denied',
            'timestamp': earlierToday.millisecondsSinceEpoch,
          },
          now: fixedNow,
          scanOnExitEnabled: true,
        ),
        isFalse,
      );

      expect(
        AdminAccessLogsScreen.isLogCurrentlyInside(
          {
            'status': 'allowed',
            'timestamp': earlierToday.millisecondsSinceEpoch,
          },
          now: fixedNow,
          scanOnExitEnabled: false,
        ),
        isFalse,
      );
    });
  });

  group('AdminAccessLogsScreen Mobile Layout Tests', () {
    testWidgets('Mobile viewport (360x800, Spanish) wraps visitor type chips, date chips, and search summary badge without horizontal cropping', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AdminAccessLogsScreen(isEmbedded: true),
        ),
      );
      await tester.pumpAndSettle();

      for (final typeKey in ['all', 'visitor', 'supplier']) {
        final chipFinder = find.byKey(ValueKey('visitor_type_chip_$typeKey'));
        expect(chipFinder, findsOneWidget);
        final rect = tester.getRect(chipFinder);
        expect(rect.left, greaterThanOrEqualTo(0.0));
        expect(rect.right, lessThanOrEqualTo(360.0));
      }

      await tester.tap(find.byKey(const ValueKey('visitor_type_chip_supplier')));
      await tester.pumpAndSettle();

      final badgeFinder = find.text('Búsqueda en base de datos activa');
      expect(badgeFinder, findsOneWidget);
      expect(tester.getRect(badgeFinder).right, lessThanOrEqualTo(360.0));
    });
  });
}
