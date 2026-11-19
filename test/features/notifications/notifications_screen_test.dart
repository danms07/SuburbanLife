import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/core/services/notification_router.dart';
import 'package:suburban_life/features/admin/admin_booking_approval_screen.dart';
import 'package:suburban_life/features/admin/admin_shell_screen.dart';
import 'package:suburban_life/features/notifications/notifications_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import 'package:suburban_life/main.dart' show MyHomePage;
import '../../helpers/fake_backend.dart';

Widget _wrapWithApp(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('es')],
    home: child,
  );
}

AppNotification _makeNotification({
  required String id,
  NotificationCategory category = NotificationCategory.reviews,
  String targetRoute = 'home',
  bool isRead = false,
  int minutesAgo = 5,
  String titleEn = 'Title EN',
  String titleEs = 'Título ES',
  String bodyEn = 'Body EN',
  String bodyEs = 'Cuerpo ES',
}) {
  final createdAt = DateTime.now().subtract(Duration(minutes: minutesAgo));
  return AppNotification(
    id: id,
    type: 'test_event',
    categoryKey: category.key,
    category: category,
    titles: {'en': titleEn, 'es': titleEs},
    bodies: {'en': bodyEn, 'es': bodyEs},
    targetRoute: targetRoute,
    entityId: 'entity_$id',
    createdAt: createdAt,
    isRead: isRead,
  );
}

void _seedApprovedResident({required String uid}) {
  FakeBackendHelper.auth.isAdminMock = false;
  FakeBackendHelper.auth.isGuardMock = false;
  FakeBackendHelper.auth.isResidentMock = true;
  FakeBackendHelper.auth.emitUser(
    AppUser(
      uid: uid,
      email: '$uid@test.com',
      displayName: 'Resident Tester',
    ),
  );
  final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_$uid');
  FakeBackendHelper.db.seedDocument('addresses', 'addr_$uid', {
    'id': 'addr_$uid',
    'streetName': 'Av. Modena',
    'number': 42,
    'residentUid': uid,
    'paymentStatus': 'paid',
  });
  FakeBackendHelper.db.seedDocument('users', uid, {
    'uid': uid,
    'name': 'Resident Tester',
    'email': '$uid@test.com',
    'role': 'resident',
    'addressRef': addrRef,
  });
}

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
  });

  group('Notification Models & Routing Sanitization', () {
    test('sanitizeNotificationRoute permits allow-listed routes and rejects untrusted paths', () {
      expect(sanitizeNotificationRoute('sanctions'), equals('sanctions'));
      expect(sanitizeNotificationRoute('admin_payments'), equals('admin_payments'));
      expect(sanitizeNotificationRoute('admin_bookings'), equals('admin_bookings'));
      expect(sanitizeNotificationRoute('https://evil.example/phish'), equals('home'));
      expect(sanitizeNotificationRoute('../../admin/root'), equals('home'));
      expect(sanitizeNotificationRoute('unknown_route'), equals('home'));
      expect(sanitizeNotificationRoute(null), equals('home'));
    });

    test('AppNotification.fromRtdbMap parses fields and sanitizes untrusted targetRoute', () {
      final notif = AppNotification.fromRtdbMap('n_1', {
        'type': 'sanction_issued',
        'category': 'sanctions',
        'titles': {'en': 'Sanction applied', 'es': 'Sanción aplicada'},
        'bodies': {'en': 'Fine \$500', 'es': 'Multa \$500'},
        'targetRoute': 'https://evil.example',
        'entityId': 'sanction_9',
        'createdAt': 1700000000000,
        'isRead': false,
        'metadata': {'amount': 500},
      });

      expect(notif.id, equals('n_1'));
      expect(notif.category, equals(NotificationCategory.sanctions));
      expect(notif.localizedTitle('en'), equals('Sanction applied'));
      expect(notif.localizedTitle('es'), equals('Sanción aplicada'));
      expect(notif.localizedBody('en'), equals('Fine \$500'));
      expect(notif.targetRoute, equals('home'));
      expect(notif.entityId, equals('sanction_9'));
      expect(notif.isRead, isFalse);
      expect(notif.metadata['amount'], equals(500));
    });

    test('AppNotification.fromRemoteData parses FCM data payload safely', () {
      final notif = AppNotification.fromRemoteData(
        {
          'notificationId': 'fcm_42',
          'type': 'booking_review',
          'category': 'admin_reviews',
          'targetRoute': 'admin_bookings',
          'entityId': 'bk_7',
          'title': 'New booking pending',
          'body': 'Clubhouse reservation awaits approval',
        },
        preferredLanguage: 'en',
      );

      expect(notif.id, equals('fcm_42'));
      expect(notif.category, equals(NotificationCategory.adminReviews));
      expect(notif.localizedTitle('en'), equals('New booking pending'));
      expect(notif.targetRoute, equals('admin_bookings'));
      expect(notif.entityId, equals('bk_7'));
    });

    test('NotificationRouter.adminSectionForRoute maps admin routes strictly', () {
      expect(
        NotificationRouter.adminSectionForRoute('admin_claims'),
        equals(AdminSection.approveResidents),
      );
      expect(
        NotificationRouter.adminSectionForRoute('admin_payments'),
        equals(AdminSection.reviewPayments),
      );
      expect(
        NotificationRouter.adminSectionForRoute('admin_bookings'),
        equals(AdminSection.reviewBookings),
      );
      expect(NotificationRouter.adminSectionForRoute('sanctions'), isNull);
      expect(NotificationRouter.adminSectionForRoute('evil://route'), isNull);
    });
  });

  group('NotificationBellButton', () {
    testWidgets('displays live unread count badge and caps at 99+', (tester) async {
      FakeBackendHelper.notifications.seedNotifications('u1', [
        _makeNotification(id: 'n1', isRead: false),
        _makeNotification(id: 'n2', isRead: true),
        _makeNotification(id: 'n3', isRead: false),
      ]);

      await tester.pumpWidget(
        _wrapWithApp(
          Scaffold(
            appBar: AppBar(
              actions: [
                NotificationBellButton(uid: 'u1', onPressed: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_bell_button')), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      // Seed 105 unread items -> should cap at 99+
      final manyUnread = List.generate(
        105,
        (i) => _makeNotification(id: 'bulk_$i', isRead: false),
      );
      FakeBackendHelper.notifications.seedNotifications('u1', manyUnread);
      await tester.pumpAndSettle();

      expect(find.text('99+'), findsOneWidget);
    });
  });

  group('NotificationsScreen Inbox', () {
    testWidgets(
      'supports bilingual rendering, All/Unread filters, tap-to-read routing, mark all read, single delete, clear all, and opt-in banner',
      (tester) async {
        FakeBackendHelper.notifications.permissionStatus =
            PushPermissionStatus.notDetermined;
        FakeBackendHelper.notifications.seedNotifications('admin_1', [
          _makeNotification(
            id: 'n_admin',
            category: NotificationCategory.adminReviews,
            targetRoute: 'admin_payments',
            isRead: false,
            titleEn: 'Payment awaiting review',
            titleEs: 'Pago pendiente de revisión',
            bodyEn: 'Transfer receipt uploaded',
            bodyEs: 'Comprobante subido',
          ),
          _makeNotification(
            id: 'n_read',
            category: NotificationCategory.announcements,
            targetRoute: 'announcements',
            isRead: true,
            titleEn: 'Pool maintenance',
            titleEs: 'Mantenimiento de alberca',
            bodyEn: 'Closed Friday',
            bodyEs: 'Cerrada el viernes',
          ),
        ]);

        AdminSection? openedAdminSection;

        await tester.pumpWidget(
          _wrapWithApp(
            NotificationsScreen(
              uid: 'admin_1',
              isAdmin: true,
              onOpenAdminSection: (section) => openedAdminSection = section,
            ),
            locale: const Locale('es'),
          ),
        );
        await tester.pumpAndSettle();

        final esL10n = AppLocalizations.of(
          tester.element(find.byType(NotificationsScreen)),
        )!;

        // Retention notice & opt-in banner on notDetermined
        expect(find.text(esL10n.notificationsRetentionNotice), findsOneWidget);
        expect(find.byKey(const Key('inbox_push_opt_in_banner')), findsOneWidget);
        expect(find.text('Pago pendiente de revisión'), findsOneWidget);
        expect(find.text('Mantenimiento de alberca'), findsOneWidget);

        // Opt-in permission from inbox banner
        await tester.tap(find.byKey(const Key('inbox_enable_push_button')));
        await tester.pumpAndSettle();
        expect(
          FakeBackendHelper.notifications.permissionStatus,
          equals(PushPermissionStatus.authorized),
        );
        expect(find.byKey(const Key('inbox_push_opt_in_banner')), findsNothing);

        // Switch to Unread filter -> hides n_read
        await tester.tap(find.byKey(const Key('filter_unread_notifications')));
        await tester.pumpAndSettle();
        expect(find.text('Pago pendiente de revisión'), findsOneWidget);
        expect(find.text('Mantenimiento de alberca'), findsNothing);

        // Tap unread admin notification -> marks read and forwards admin section callback
        await tester.tap(find.byKey(const Key('notification_card_n_admin')));
        await tester.pumpAndSettle();
        expect(openedAdminSection, equals(AdminSection.reviewPayments));
        expect(find.text(esL10n.notificationsNoUnreadTitle), findsOneWidget);

        // Switch back to All -> both items exist and can be deleted individually
        await tester.tap(find.byKey(const Key('filter_all_notifications')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('notification_card_n_read')), findsOneWidget);

        await tester.tap(find.byKey(const Key('delete_notification_n_read')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('notification_card_n_read')), findsNothing);

        // Re-seed two items and verify Mark All Read + Clear All dialog flow
        FakeBackendHelper.notifications.seedNotifications('admin_1', [
          _makeNotification(id: 'u_a', isRead: false, titleEs: 'Nueva 1'),
          _makeNotification(id: 'u_b', isRead: false, titleEs: 'Nueva 2'),
        ]);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('mark_all_read_button')));
        await tester.pumpAndSettle();
        final currentAfterMark =
            FakeBackendHelper.notifications.currentNotifications('admin_1');
        expect(currentAfterMark.every((n) => n.isRead), isTrue);

        // Clear all -> cancel keeps items -> confirm deletes all
        await tester.tap(find.byKey(const Key('clear_all_notifications_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(esL10n.cancel));
        await tester.pumpAndSettle();
        expect(find.text('Nueva 1'), findsOneWidget);

        await tester.tap(find.byKey(const Key('clear_all_notifications_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm_clear_notifications_button')));
        await tester.pumpAndSettle();
        expect(find.text(esL10n.notificationsEmptyTitle), findsOneWidget);
      },
    );
  });

  group('NotificationPreferencesSheet', () {
    testWidgets(
      'handles permission lifecycle states, push/in-app banner toggles, and hides admin_reviews for residents',
      (tester) async {
        FakeBackendHelper.notifications.permissionStatus =
            PushPermissionStatus.notDetermined;
        FakeBackendHelper.notifications.nextRequestPermissionResult =
            PushPermissionStatus.authorized;
        FakeBackendHelper.notifications.seedSettings(
          'res_pref_1',
          const UserNotificationSettings(
            locale: 'en',
            pushEnabled: true,
            inAppBannerEnabled: true,
          ),
        );

        await tester.pumpWidget(
          _wrapWithApp(
            const Scaffold(
              body: NotificationPreferencesSheet(
                uid: 'res_pref_1',
                isAdmin: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('permission_status_card_notDetermined')),
          findsOneWidget,
        );

        // Grant OS push permission via explicit button
        await tester.tap(find.byKey(const Key('enable_push_permission_button')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('permission_status_card_authorized')),
          findsOneWidget,
        );

        // Scroll to category switches while pushEnabled == true and verify role gating + category toggle
        await tester.scrollUntilVisible(
          find.byKey(const Key('switch_category_sanctions')),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.byKey(const Key('switch_category_sanctions')), findsOneWidget);
        await tester.tap(find.byKey(const Key('switch_category_sanctions')));
        await tester.pumpAndSettle();

        // Scroll to bottom to verify non-admin does NOT see admin_reviews toggle
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('switch_category_admin_reviews')), findsNothing);

        // Scroll back up to toggle push master switch & in-app banner switch (bell-only mode)
        await tester.scrollUntilVisible(
          find.byKey(const Key('switch_push_enabled')),
          -200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.byKey(const Key('switch_push_enabled')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('switch_in_app_banner')));
        await tester.pumpAndSettle();

        final updated = FakeBackendHelper.notifications.currentSettings('res_pref_1');
        expect(updated.pushEnabled, isFalse);
        expect(updated.inAppBannerEnabled, isFalse);
        expect(updated.categories['sanctions'], isFalse);
      },
    );

    testWidgets(
      'displays denied system hint, unsupported card, and shows admin_reviews category for admins',
      (tester) async {
        FakeBackendHelper.notifications.permissionStatus =
            PushPermissionStatus.denied;

        await tester.pumpWidget(
          _wrapWithApp(
            const Scaffold(
              body: NotificationPreferencesSheet(
                uid: 'admin_pref_1',
                isAdmin: true,
              ),
            ),
            locale: const Locale('es'),
          ),
        );
        await tester.pumpAndSettle();

        final esL10n = AppLocalizations.of(
          tester.element(find.byType(NotificationPreferencesSheet)),
        )!;
        expect(
          find.byKey(const Key('permission_status_card_denied')),
          findsOneWidget,
        );
        expect(find.text(esL10n.notificationSystemSettingsHint), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('switch_category_admin_reviews')),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.byKey(const Key('switch_category_admin_reviews')), findsOneWidget);

        // Unsupported status test
        FakeBackendHelper.notifications.permissionStatus =
            PushPermissionStatus.unsupported;
        await tester.pumpWidget(
          _wrapWithApp(
            const Scaffold(
              body: NotificationPreferencesSheet(
                key: ValueKey('prefs_unsupported'),
                uid: 'admin_pref_2',
                isAdmin: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('permission_status_card_unsupported')),
          findsOneWidget,
        );
      },
    );
  });

  group('Home & Admin Shell Notification Integration', () {
    testWidgets(
      'displays foreground banner when enabled, suppresses banner when bell-only mode is active, syncs locale, handles opt-in card, and unregisters token on signOut',
      (tester) async {
        _seedApprovedResident(uid: 'res_home_1');
        FakeBackendHelper.notifications.permissionStatus =
            PushPermissionStatus.notDetermined;
        FakeBackendHelper.notifications.seedSettings(
          'res_home_1',
          const UserNotificationSettings(
            locale: 'en',
            pushEnabled: true,
            inAppBannerEnabled: true,
          ),
        );

        await tester.pumpWidget(
          _wrapWithApp(const MyHomePage(title: 'Suburban Life')),
        );
        await tester.pumpAndSettle();

        expect(FakeBackendHelper.notifications.syncedLocales, contains('en'));
        expect(find.byKey(const Key('push_permission_opt_in_card')), findsOneWidget);

        // Tap inline Enable Push button on home card
        await tester.tap(find.byKey(const Key('home_enable_push_button')));
        await tester.pumpAndSettle();
        expect(
          FakeBackendHelper.notifications.permissionStatus,
          equals(PushPermissionStatus.authorized),
        );
        expect(find.byKey(const Key('push_permission_opt_in_card')), findsNothing);

        // Foreground notification arrives -> shows interactive banner
        FakeBackendHelper.notifications.emitForegroundMessage(
          _makeNotification(
            id: 'fg_1',
            category: NotificationCategory.sanctions,
            targetRoute: 'sanctions',
            titleEn: 'New sanction notice',
            bodyEn: 'Check details',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('in_app_notification_banner')), findsOneWidget);
        expect(find.text('New sanction notice'), findsOneWidget);

        // Dismiss banner
        await tester.tap(find.byKey(const Key('in_app_banner_dismiss_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('in_app_notification_banner')), findsNothing);

        // Enable bell-only mode (disable in-app foreground banner) and emit another message
        await FakeBackendHelper.notifications.setInAppBannerEnabled('res_home_1', false);
        FakeBackendHelper.notifications.seedNotifications('res_home_1', [
          _makeNotification(id: 'fg_2', isRead: false, titleEn: 'Silent bell alert'),
        ]);
        FakeBackendHelper.notifications.emitForegroundMessage(
          _makeNotification(
            id: 'fg_2',
            category: NotificationCategory.announcements,
            targetRoute: 'announcements',
            titleEn: 'Silent bell alert',
            bodyEn: 'Bell only',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('in_app_notification_banner')), findsNothing);
        expect(find.byKey(const Key('notification_bell_button')), findsOneWidget);
        expect(find.text('1'), findsOneWidget);

        // Sign out via resident drawer triggers unregisterCurrentDeviceToken()
        final l10n = AppLocalizations.of(
          tester.element(find.byType(MyHomePage)),
        )!;
        final scaffoldState = tester.firstState<ScaffoldState>(
          find.byType(Scaffold),
        );
        scaffoldState.openDrawer();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(l10n.logout));
        await tester.tap(find.text(l10n.logout));
        await tester.pumpAndSettle();
        expect(FakeBackendHelper.notifications.unregisterCallCount, equals(1));
      },
    );

    testWidgets(
      'AdminShellScreen renders NotificationBellButton and opens deep-linked AdminSection',
      (tester) async {
        FakeBackendHelper.auth.isAdminMock = true;
        FakeBackendHelper.auth.isResidentMock = false;
        FakeBackendHelper.auth.emitUser(
          AppUser(uid: 'admin_shell_1', email: 'admin@test.com'),
        );
        FakeBackendHelper.notifications.seedNotifications('admin_shell_1', [
          _makeNotification(
            id: 'adm_1',
            category: NotificationCategory.adminReviews,
            targetRoute: 'admin_bookings',
            isRead: false,
          ),
        ]);

        await tester.pumpWidget(
          _wrapWithApp(
            AdminShellScreen(
              appTitle: 'Suburban Life',
              isAdmin: true,
              isResident: false,
              onSwitchToResidentView: () {},
              onResignAdminRole: () async {},
              onLogout: () {},
              requestedSection: AdminSection.reviewBookings,
              requestedSectionToken: 1,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('notification_bell_button')), findsOneWidget);
        expect(find.text('1'), findsOneWidget);
        expect(find.byType(AdminBookingApprovalScreen), findsOneWidget);
      },
    );
  });
}
