import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/core/config/app_config.dart';
import 'package:suburban_life/features/admin/admin_settings_screen.dart';
import 'package:suburban_life/features/admin/admin_shell_screen.dart';
import 'package:suburban_life/features/auth/admin_resident_approval_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
    FakeBackendHelper.auth.emitUser(
      AppUser(
        uid: 'admin_1',
        email: 'admin@catania.mx',
        displayName: 'System Admin',
      ),
    );
    FakeBackendHelper.auth.isAdminMock = true;
    FakeBackendHelper.auth.isResidentMock = false;
  });

  Widget buildShell({
    Locale locale = const Locale('en'),
    bool isResident = false,
    VoidCallback? onSwitchToResidentView,
    Future<void> Function()? onResignAdminRole,
    VoidCallback? onLogout,
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AdminShellScreen(
        appTitle: 'Suburban Life',
        isAdmin: true,
        isResident: isResident,
        onSwitchToResidentView: onSwitchToResidentView ?? () {},
        onResignAdminRole: onResignAdminRole ?? () async {},
        onLogout: onLogout ?? () {},
      ),
    );
  }

  group('AdminShellScreen - Adaptive NavDrawer & Overview', () {
    testWidgets(
      'renders persistent desktop sidebar, Overview dashboard, and Overview-only QR FAB on wide viewports',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('admin_desktop_sidebar')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('admin_mobile_drawer')), findsNothing);

        // Admin Panel title and Overview subtitle are removed from Overview body
        expect(find.text('Admin Panel'), findsNothing);
        expect(
          find.text('Pending approvals and live community status'),
          findsNothing,
        );

        // Overview dashboard sections & QR FAB (desktop sections are static, not mobile collapsible cards)
        expect(find.text('Overview'), findsOneWidget);
        expect(find.text('Pending Approvals'), findsOneWidget);
        expect(find.text('Live Community Status'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('mobile_section_pending_approvals')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('mobile_section_community_stats')),
          findsNothing,
        );
        // Visitors currently inside is hidden by default when scanOnExitEnabled is false/unset
        expect(find.text('Visitors currently inside'), findsNothing);
        expect(
          find.byKey(const ValueKey('overview_stat_currently_inside')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('overview_stat_active_sanctions')),
          findsOneWidget,
        );
        expect(find.text('Shortcuts'), findsOneWidget);
        expect(find.text('Management Categories'), findsNothing);
        expect(
          find.byKey(const ValueKey('admin_overview_generate_qr_fab')),
          findsOneWidget,
        );

        // Verify all 6 Overview shortcut cards
        expect(
          find.byKey(const ValueKey('overview_shortcut_create_user')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('overview_shortcut_user_directory')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('overview_shortcut_create_announcement')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('overview_shortcut_upload_payment')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('overview_shortcut_download_report')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('overview_shortcut_settings')),
          findsOneWidget,
        );

        // Verify 4 collapsible category groups + direct General Settings leaf tile appear in the sidebar
        expect(find.text('User Management'), findsOneWidget);
        expect(find.text('Residential Management'), findsOneWidget);
        expect(find.text('Finance'), findsOneWidget);
        expect(find.text('Transparency & Community'), findsOneWidget);
        expect(find.text('General Settings'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('admin_nav_generalSettings')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('admin_group_general_settings_0')),
          findsNothing,
        );

        // Verify TBD placeholder items are strictly hidden from UI
        expect(find.textContaining('Import payment'), findsNothing);
        expect(find.text('Polls'), findsNothing);
      },
    );

    testWidgets(
      'renders mobile hamburger Drawer on narrow viewports, navigates directly to General Settings without expansion arrow, and hides QR FAB off Overview',
      (tester) async {
        tester.view.physicalSize = const Size(430, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('admin_desktop_sidebar')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('admin_overview_generate_qr_fab')),
          findsOneWidget,
        );

        // Open mobile hamburger Drawer
        final ScaffoldState scaffoldState = tester.firstState(
          find.byType(Scaffold),
        );
        scaffoldState.openDrawer();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('admin_mobile_drawer')),
          findsOneWidget,
        );

        // General Settings is a direct single-tap leaf item (no ExpansionTile arrow)
        expect(
          find.byKey(const ValueKey('admin_group_general_settings_0')),
          findsNothing,
        );
        final generalSettingsLeaf = find.byKey(
          const ValueKey('admin_nav_generalSettings'),
        );
        expect(generalSettingsLeaf, findsOneWidget);
        await tester.tap(generalSettingsLeaf);
        await tester.pumpAndSettle();

        // Drawer closed, AdminSettingsScreen embedded, QR FAB hidden
        expect(find.byKey(const ValueKey('admin_mobile_drawer')), findsNothing);
        expect(find.byType(AdminSettingsScreen), findsOneWidget);
        expect(
          find.byKey(const ValueKey('admin_overview_generate_qr_fab')),
          findsNothing,
        );
        // Only the shell AppBar exists (no duplicate nested AppBar)
        expect(find.byType(AppBar), findsOneWidget);
      },
    );

    testWidgets(
      'rolls up pending badges onto collapsed groups, moves badges to child items when expanded, and switches views cleanly',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Seed pending claims, pending payments, pending bookings, inside logs, and active sanctions
        FakeBackendHelper.db.seedDocument('ownership_claims', 'claim_1', {
          'id': 'claim_1',
          'userUid': 'u1',
          'userEmail': 'u1@catania.mx',
        });
        FakeBackendHelper.db.seedDocument('ownership_claims', 'claim_2', {
          'id': 'claim_2',
          'userUid': 'u2',
          'userEmail': 'u2@catania.mx',
        });

        FakeBackendHelper.db.seedDocument('payments', 'pay_1', {
          'id': 'pay_1',
          'status': 'pending',
          'amount': 850,
        });
        FakeBackendHelper.db.seedDocument('payments', 'pay_2', {
          'id': 'pay_2',
          'status': 'pending',
          'amount': 850,
        });
        FakeBackendHelper.db.seedDocument('payments', 'pay_3', {
          'id': 'pay_3',
          'status': 'pending',
          'amount': 850,
        });

        FakeBackendHelper.db.seedDocument('bookings', 'book_1', {
          'id': 'book_1',
          'status': 'pending review',
          'facilityId': 'pool_1',
        });

        FakeBackendHelper.db.seedDocument('access_logs', 'log_1', {
          'id': 'log_1',
          'isInside': true,
        });
        FakeBackendHelper.db.seedDocument('sanctions', 'sanc_1', {
          'id': 'sanc_1',
          'status': 'active',
        });

        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        // Overview displays seeded counts
        expect(find.text('2 pending'), findsOneWidget);
        expect(find.text('3 pending'), findsOneWidget);
        expect(find.text('1 pending'), findsOneWidget);

        // Collapsed User Management group shows roll-up badge (2)
        final userGroupBadgeFinder = find.byKey(
          const ValueKey('admin_group_badge_user_management'),
        );
        expect(userGroupBadgeFinder, findsOneWidget);
        expect(tester.widget<Badge>(userGroupBadgeFinder).isLabelVisible, isTrue);

        // Collapsed Finance group shows roll-up badge (3)
        final financeGroupBadgeFinder = find.byKey(
          const ValueKey('admin_group_badge_finance'),
        );
        expect(
          tester.widget<Badge>(financeGroupBadgeFinder).isLabelVisible,
          isTrue,
        );

        // Expand User Management in desktop sidebar
        final sidebarUserGroup = find.descendant(
          of: find.byKey(const ValueKey('admin_desktop_sidebar')),
          matching: find.text('User Management'),
        );
        await tester.tap(sidebarUserGroup);
        await tester.pumpAndSettle();

        // Group roll-up badge hides when expanded; child item badge is visible
        expect(
          tester.widget<Badge>(userGroupBadgeFinder).isLabelVisible,
          isFalse,
        );
        expect(
          find.byKey(const ValueKey('admin_item_badge_approveResidents')),
          findsOneWidget,
        );

        // Tap Approve Residents leaf item
        await tester.tap(
          find.byKey(const ValueKey('admin_nav_approveResidents')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AdminResidentApprovalScreen), findsOneWidget);
        expect(find.byType(AppBar), findsOneWidget);
        expect(
          find.byKey(const ValueKey('admin_overview_generate_qr_fab')),
          findsNothing,
        );

        // Tap Overview in sidebar to return to home dashboard and restore QR FAB
        await tester.tap(find.byKey(const ValueKey('admin_nav_overview')));
        await tester.pumpAndSettle();

        expect(find.text('Pending Approvals'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('admin_overview_generate_qr_fab')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'tapping Overview pending or shortcut cards switches view, auto-expands parent group, and opens Create Announcement dialog when requested',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        // Initially Finance is collapsed, so child nav item is not built/visible
        expect(
          find.byKey(const ValueKey('admin_nav_reviewPayments')),
          findsNothing,
        );

        // Tap Review Pending Payments card on Overview
        await tester.tap(
          find.byKey(const ValueKey('overview_card_review_payments')),
        );
        await tester.pumpAndSettle();

        // Parent group 'Finance' auto-expanded in sidebar and QR FAB hidden
        expect(
          find.byKey(const ValueKey('admin_nav_reviewPayments')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('admin_overview_generate_qr_fab')),
          findsNothing,
        );

        // Return to Overview and tap 'Create Announcement' shortcut card
        await tester.tap(find.byKey(const ValueKey('admin_nav_overview')));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('overview_shortcut_create_announcement')),
        );
        await tester.pumpAndSettle();

        // Transparency & Community group expanded and Create Announcement modal opened directly
        expect(
          find.byKey(const ValueKey('admin_nav_announcements')),
          findsOneWidget,
        );
        expect(find.byType(AlertDialog), findsOneWidget);
      },
    );

    testWidgets(
      'renders Spanish translations accurately across sidebar groups and Overview',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildShell(locale: const Locale('es')));
        await tester.pumpAndSettle();

        expect(find.text('Panel de Administración'), findsNothing);
        expect(find.text('Resumen General'), findsOneWidget);
        expect(find.text('Aprobaciones Pendientes'), findsOneWidget);
        expect(find.text('Estado de la Comunidad en Vivo'), findsOneWidget);
        expect(find.text('Visitantes actualmente dentro'), findsNothing);

        // Enable scanOnExitEnabled and verify Spanish label appears
        FakeBackendHelper.db.seedDocument('config', 'app_settings', {
          'scanOnExitEnabled': true,
        });
        await tester.pumpAndSettle();
        expect(find.text('Visitantes actualmente dentro'), findsOneWidget);

        expect(find.text('Accesos Rápidos'), findsOneWidget);
        expect(find.text('Sanciones Activas'), findsOneWidget);

        expect(find.text('Crear Usuario'), findsOneWidget);
        expect(find.text('Directorio de Usuarios'), findsOneWidget);
        expect(find.text('Crear Anuncio'), findsOneWidget);
        expect(find.text('Subir Pago a Nombre de Usuario'), findsOneWidget);
        expect(find.text('Descargar Reporte de Pagos'), findsOneWidget);
        expect(find.text('Configuración'), findsOneWidget);

        expect(find.text('Gestión de Usuarios'), findsOneWidget);
        expect(find.text('Gestión Residencial'), findsOneWidget);
        expect(find.text('Finanzas'), findsOneWidget);
        expect(find.text('Transparencia y Comunidad'), findsOneWidget);
        expect(find.text('Configuración General'), findsOneWidget);
        expect(find.text('Encuestas'), findsNothing);
      },
    );

    testWidgets(
      'collapses Pending Approvals and Live Community Status on mobile viewports only, and shows Visitors currently inside only when scanOnExitEnabled is true',
      (tester) async {
        tester.view.physicalSize = const Size(430, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        FakeBackendHelper.db.seedDocument('ownership_claims', 'claim_1', {
          'id': 'claim_1',
          'userUid': 'u1',
          'userEmail': 'u1@catania.mx',
        });
        FakeBackendHelper.db.seedDocument('ownership_claims', 'claim_2', {
          'id': 'claim_2',
          'userUid': 'u2',
          'userEmail': 'u2@catania.mx',
        });
        FakeBackendHelper.db.seedDocument('payments', 'pay_1', {
          'id': 'pay_1',
          'status': 'pending',
          'amount': 850,
        });
        FakeBackendHelper.db.seedDocument('access_logs', 'log_1', {
          'id': 'log_1',
          'isInside': true,
        });
        FakeBackendHelper.db.seedDocument('sanctions', 'sanc_1', {
          'id': 'sanc_1',
          'status': 'active',
        });

        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        final mobilePendingSection = find.byKey(
          const ValueKey('mobile_section_pending_approvals'),
        );
        final mobileStatsSection = find.byKey(
          const ValueKey('mobile_section_community_stats'),
        );
        final mobilePendingBadge = find.byKey(
          const ValueKey('mobile_badge_pending_approvals'),
        );

        expect(mobilePendingSection, findsOneWidget);
        expect(mobileStatsSection, findsOneWidget);

        // Both collapsible sections start collapsed on mobile so Shortcuts stay visible
        expect(
          find.byKey(const ValueKey('overview_card_approve_residents')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('overview_stat_active_sanctions')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('overview_shortcut_create_user')),
          findsOneWidget,
        );

        // Collapsed Pending Approvals header shows rolled-up badge count (2 + 1 = 3)
        expect(mobilePendingBadge, findsOneWidget);
        expect(tester.widget<Badge>(mobilePendingBadge).isLabelVisible, isTrue);
        expect(
          find.descendant(of: mobilePendingBadge, matching: find.text('3')),
          findsOneWidget,
        );

        // Expand Pending Approvals on mobile -> cards appear and header badge hides
        await tester.tap(find.text('Pending Approvals'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('overview_card_approve_residents')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('overview_card_review_payments')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('overview_card_review_bookings')),
          findsOneWidget,
        );
        expect(
          tester.widget<Badge>(mobilePendingBadge).isLabelVisible,
          isFalse,
        );

        // Collapse Pending Approvals again -> cards hide and roll-up badge returns
        await tester.tap(find.text('Pending Approvals'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('overview_card_approve_residents')),
          findsNothing,
        );
        expect(tester.widget<Badge>(mobilePendingBadge).isLabelVisible, isTrue);

        // Expand Live Community Status on mobile -> Active Sanctions visible, Visitors currently inside hidden (scanOnExitEnabled == false)
        await tester.tap(find.text('Live Community Status'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('overview_stat_active_sanctions')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('overview_stat_currently_inside')),
          findsNothing,
        );
        expect(find.text('Visitors currently inside'), findsNothing);

        // Dynamically enable Scan on Exit -> Visitors currently inside appears in real time
        FakeBackendHelper.db.seedDocument('config', 'app_settings', {
          'scanOnExitEnabled': true,
        });
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('overview_stat_currently_inside')),
          findsOneWidget,
        );
        expect(find.text('Visitors currently inside'), findsOneWidget);

        // Dynamically disable Scan on Exit -> Visitors currently inside hides again
        FakeBackendHelper.db.seedDocument('config', 'app_settings', {
          'scanOnExitEnabled': false,
        });
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('overview_stat_currently_inside')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('overview_stat_active_sanctions')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'styles AppBar with AppConfig.primaryColor and white title, and pins Sign Out to bottom of navigation panel',
      (tester) async {
        int logoutCalls = 0;

        // 1. Desktop viewport check
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildShell(onLogout: () => logoutCalls++),
        );
        await tester.pumpAndSettle();

        final AppBar appBar = tester.widget<AppBar>(find.byType(AppBar));
        expect(appBar.backgroundColor, AppConfig.primaryColor);
        expect(appBar.foregroundColor, Colors.white);

        final Text overviewTitle = tester.widget<Text>(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Suburban Life (Admin)'),
          ),
        );
        expect(overviewTitle.style?.color, Colors.white);

        // Sign Out is NOT in AppBar, and IS pinned inside desktop sidebar
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byIcon(Icons.logout),
          ),
          findsNothing,
        );
        final desktopLogoutTile = find.descendant(
          of: find.byKey(const ValueKey('admin_desktop_sidebar')),
          matching: find.byKey(const ValueKey('admin_nav_logout')),
        );
        expect(desktopLogoutTile, findsOneWidget);

        await tester.tap(desktopLogoutTile);
        await tester.pumpAndSettle();
        expect(logoutCalls, 1);

        // Navigate to a sub-screen and verify sub-screen AppBar title is also white
        await tester.tap(
          find.byKey(const ValueKey('overview_card_review_payments')),
        );
        await tester.pumpAndSettle();

        final Text subScreenTitle = tester.widget<Text>(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Review Payments'),
          ),
        );
        expect(subScreenTitle.style?.color, Colors.white);

        // 2. Mobile viewport check
        tester.view.physicalSize = const Size(430, 900);
        await tester.pumpAndSettle();

        final ScaffoldState scaffoldState = tester.firstState(
          find.byType(Scaffold),
        );
        scaffoldState.openDrawer();
        await tester.pumpAndSettle();

        final mobileLogoutTile = find.descendant(
          of: find.byKey(const ValueKey('admin_mobile_drawer')),
          matching: find.byKey(const ValueKey('admin_nav_logout')),
        );
        expect(mobileLogoutTile, findsOneWidget);

        await tester.tap(mobileLogoutTile);
        await tester.pumpAndSettle();
        expect(logoutCalls, 2);
        expect(find.byKey(const ValueKey('admin_mobile_drawer')), findsNothing);
      },
    );
  });
}
