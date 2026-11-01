import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import 'package:suburban_life/main.dart';
import 'helpers/fake_backend.dart';

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
  });

  Widget createWidgetUnderTest() {
    return const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale('en'),
      home: MyHomePage(title: 'Suburban Life'),
    );
  }

  testWidgets(
    'Admin-only user hides both Resign Admin Role and Switch to Resident View buttons',
    (WidgetTester tester) async {
      FakeBackendHelper.auth.currentUserMock = AppUser(
        uid: 'admin_only_1',
        email: 'admin@test.com',
        displayName: 'Admin Only',
      );
      FakeBackendHelper.auth.isAdminMock = true;
      FakeBackendHelper.auth.isResidentMock = false;
      FakeBackendHelper.auth.isGuardMock = false;

      FakeBackendHelper.db.seedDocument('users', 'admin_only_1', {
        'uid': 'admin_only_1',
        'name': 'Admin Only',
        'email': 'admin@test.com',
        'role': 'admin',
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Suburban Life (Admin)'), findsOneWidget);
      expect(find.byIcon(Icons.waving_hand), findsNothing);
      expect(find.byIcon(Icons.person), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.logout),
        ),
        findsNothing,
      );

      final ScaffoldState scaffoldState = tester.firstState(
        find.byType(Scaffold),
      );
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('admin_nav_logout')), findsOneWidget);
    },
  );

  testWidgets(
    'Dual-role admin + resident user displays both Resign Admin Role and Switch to Resident View buttons in Admin View',
    (WidgetTester tester) async {
      FakeBackendHelper.auth.currentUserMock = AppUser(
        uid: 'dual_user_1',
        email: 'dual@test.com',
        displayName: 'Dual User',
      );
      FakeBackendHelper.auth.isAdminMock = true;
      FakeBackendHelper.auth.isResidentMock = true;
      FakeBackendHelper.auth.isGuardMock = false;

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_1');
      FakeBackendHelper.db.seedDocument('addresses', 'addr_1', {
        'id': 'addr_1',
        'streetName': 'Av. Catania',
        'number': 10,
        'residentUid': 'dual_user_1',
        'paymentStatus': 'paid',
      });
      FakeBackendHelper.db.seedDocument('users', 'dual_user_1', {
        'uid': 'dual_user_1',
        'name': 'Dual User',
        'email': 'dual@test.com',
        'role': 'admin',
        'addressRef': addrRef,
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Starts in Resident View; switch to Admin View
      await tester.tap(find.byIcon(Icons.admin_panel_settings));
      await tester.pumpAndSettle();

      expect(find.text('Suburban Life (Admin)'), findsOneWidget);
      expect(find.byIcon(Icons.waving_hand), findsOneWidget);
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.logout),
        ),
        findsNothing,
      );

      final ScaffoldState scaffoldState = tester.firstState(
        find.byType(Scaffold),
      );
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('admin_nav_logout')), findsOneWidget);
    },
  );
}
