import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/core/services/app_update_service.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import 'package:suburban_life/main.dart';
import 'helpers/fake_backend.dart';

void main() {
  final expectedVersion = AppUpdateService.parseVersionPayload(
    File('web/version.json').readAsStringSync(),
  );

  setUp(() {
    FakeBackendHelper.setUp();
  });

  Widget createWidgetUnderTest({Locale locale = const Locale('en')}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: const MyHomePage(title: 'Suburban Life'),
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
      expect(find.byKey(const ValueKey('admin_app_version_label')), findsOneWidget);
      expect(find.text('Version $expectedVersion'), findsOneWidget);
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
      expect(find.byKey(const ValueKey('admin_app_version_label')), findsOneWidget);
    },
  );

  testWidgets(
    'Approved resident navigation drawer displays localized app version label in English and Spanish',
    (WidgetTester tester) async {
      FakeBackendHelper.auth.currentUserMock = AppUser(
        uid: 'res_drawer_1',
        email: 'resident@test.com',
        displayName: 'Carlos Resident',
      );
      FakeBackendHelper.auth.isAdminMock = false;
      FakeBackendHelper.auth.isResidentMock = true;
      FakeBackendHelper.auth.isGuardMock = false;

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_res_1');
      FakeBackendHelper.db.seedDocument('addresses', 'addr_res_1', {
        'id': 'addr_res_1',
        'streetName': 'Av. Modena',
        'number': 25,
        'residentUid': 'res_drawer_1',
        'paymentStatus': 'paid',
      });
      FakeBackendHelper.db.seedDocument('users', 'res_drawer_1', {
        'uid': 'res_drawer_1',
        'name': 'Carlos Resident',
        'email': 'resident@test.com',
        'role': 'resident',
        'addressRef': addrRef,
      });

      // English check
      await tester.pumpWidget(createWidgetUnderTest(locale: const Locale('en')));
      await tester.pumpAndSettle();

      final ScaffoldState enScaffold = tester.firstState(find.byType(Scaffold));
      enScaffold.openDrawer();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('resident_app_version_label')), findsOneWidget);
      expect(find.text('Version $expectedVersion'), findsOneWidget);

      // Spanish check
      await tester.pumpWidget(createWidgetUnderTest(locale: const Locale('es')));
      await tester.pumpAndSettle();

      final ScaffoldState esScaffold = tester.firstState(find.byType(Scaffold));
      esScaffold.openDrawer();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('resident_app_version_label')), findsOneWidget);
      expect(find.text('Versión $expectedVersion'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Security guard panel displays localized app version label in bottom footer without overflow on narrow screens',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FakeBackendHelper.auth.currentUserMock = AppUser(
        uid: 'guard_footer_1',
        email: 'guard@test.com',
        displayName: 'Guard Test',
      );
      FakeBackendHelper.auth.isAdminMock = false;
      FakeBackendHelper.auth.isResidentMock = false;
      FakeBackendHelper.auth.isGuardMock = true;

      FakeBackendHelper.db.seedDocument('users', 'guard_footer_1', {
        'uid': 'guard_footer_1',
        'name': 'Guard Test',
        'email': 'guard@test.com',
        'role': 'guard',
      });

      // English check
      await tester.pumpWidget(createWidgetUnderTest(locale: const Locale('en')));
      await tester.pumpAndSettle();

      final scanCardBtn = find.byKey(const ValueKey('guard_scan_qr_button'));
      final guardVersionLabel = find.byKey(const ValueKey('guard_app_version_label'));
      expect(scanCardBtn, findsOneWidget);
      expect(guardVersionLabel, findsOneWidget);
      expect(find.text('Version $expectedVersion'), findsOneWidget);
      expect(
        tester.getRect(guardVersionLabel).top,
        greaterThanOrEqualTo(tester.getRect(scanCardBtn).bottom),
      );
      expect(tester.takeException(), isNull);

      // Spanish check
      await tester.pumpWidget(createWidgetUnderTest(locale: const Locale('es')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('guard_app_version_label')), findsOneWidget);
      expect(find.text('Versión $expectedVersion'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Unassigned resident onboarding screen shows Sign Out button on both claim and family group tabs and signs out when tapped',
    (WidgetTester tester) async {
      FakeBackendHelper.auth.currentUserMock = AppUser(
        uid: 'new_res_1',
        email: 'new@test.com',
        displayName: 'New Resident',
      );
      FakeBackendHelper.auth.isAdminMock = false;
      FakeBackendHelper.auth.isResidentMock = true;
      FakeBackendHelper.auth.isGuardMock = false;

      FakeBackendHelper.db.seedDocument('users', 'new_res_1', {
        'uid': 'new_res_1',
        'name': 'New Resident',
        'email': 'new@test.com',
        'role': 'resident',
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('onboarding_logout_button')),
        findsOneWidget,
      );

      // Switch to Join Family / Roommate tab and confirm logout button remains accessible
      // Use bounded pumps because the QR waiting banner contains a continuous progress spinner.
      await tester.tap(find.byIcon(Icons.qr_code));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final logoutBtn = find.byKey(const ValueKey('onboarding_logout_button'));
      expect(logoutBtn, findsOneWidget);

      await tester.ensureVisible(logoutBtn);
      await tester.tap(logoutBtn);
      await tester.pump();

      expect(FakeBackendHelper.auth.currentUserMock, isNull);
    },
  );
}
