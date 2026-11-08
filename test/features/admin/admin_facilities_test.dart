import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/features/admin/admin_facilities_screen.dart';
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
  });

  Widget wrapWithMaterial(Widget child, {Locale? locale}) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }

  group('AdminFacilitiesScreen Cooldown & Quota Configuration Tests', () {
    testWidgets('Renders existing facilities with legacy cooldown, hours cooldown, and quota subtitles', (tester) async {
      FakeBackendHelper.db.seedDocument('facilities', 'pool', {
        'id': 'pool',
        'name': 'Swimming Pool',
        'isUnique': true,
        'quantity': 1,
        'cooldownUnit': 'days',
        'cooldownValue': 7,
      });
      FakeBackendHelper.db.seedDocument('facilities', 'bbq', {
        'id': 'bbq',
        'name': 'BBQ Grill',
        'isUnique': true,
        'quantity': 1,
        'restrictionType': 'cooldown',
        'cooldownUnit': 'hours',
        'cooldownValue': 4,
      });
      FakeBackendHelper.db.seedDocument('facilities', 'paddle', {
        'id': 'paddle',
        'name': 'Paddle Court',
        'isUnique': true,
        'quantity': 1,
        'restrictionType': 'quota',
        'quotaPeriod': 'monthly',
        'quotaLimit': 2,
      });

      await tester.pumpWidget(wrapWithMaterial(const AdminFacilitiesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Swimming Pool'), findsOneWidget);
      expect(find.textContaining('Limit: Wait 7 days'), findsOneWidget);
      expect(find.text('BBQ Grill'), findsOneWidget);
      expect(find.textContaining('Limit: Wait 4 hours'), findsOneWidget);
      expect(find.text('Paddle Court'), findsOneWidget);
      expect(find.textContaining('Limit: 2 (monthly)'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsNWidgets(3));
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(3));
    });

    testWidgets('Renders Spanish translations for cooldown and quota subtitles', (tester) async {
      FakeBackendHelper.db.seedDocument('facilities', 'bbq', {
        'id': 'bbq',
        'name': 'Asador',
        'isUnique': true,
        'quantity': 1,
        'restrictionType': 'cooldown',
        'cooldownUnit': 'hours',
        'cooldownValue': 4,
      });
      FakeBackendHelper.db.seedDocument('facilities', 'paddle', {
        'id': 'paddle',
        'name': 'Cancha de Pádel',
        'isUnique': true,
        'quantity': 1,
        'restrictionType': 'quota',
        'quotaPeriod': 'monthly',
        'quotaLimit': 2,
      });

      await tester.pumpWidget(
        wrapWithMaterial(const AdminFacilitiesScreen(), locale: const Locale('es')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Límite: Esperar 4 horas'), findsOneWidget);
      expect(find.textContaining('Límite: 2 (mensual)'), findsOneWidget);
    });

    testWidgets('Opens Edit dialog and updates cooldown to unrestricted', (tester) async {
      FakeBackendHelper.db.seedDocument('facilities', 'pool', {
        'id': 'pool',
        'name': 'Swimming Pool',
        'isUnique': true,
        'quantity': 1,
        'cooldownUnit': 'days',
        'cooldownValue': 7,
      });

      await tester.pumpWidget(wrapWithMaterial(const AdminFacilitiesScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Edit Amenity'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('edit_restriction_type_cooldown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unrestricted (No Limit)').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final updatedDoc = await FakeBackendHelper.db.getDocument('facilities', 'pool');
      expect(updatedDoc?['restrictionType'], equals('unrestricted'));
      expect(updatedDoc?['cooldownUnit'], equals('unrestricted'));
      expect(updatedDoc?['cooldownValue'], equals(0));
      expect(updatedDoc?['quotaPeriod'], equals('unrestricted'));
      expect(updatedDoc?['quotaLimit'], equals(0));

      expect(find.textContaining('Limit: Unrestricted'), findsOneWidget);
    });

    testWidgets('Opens Edit dialog and updates cooldown unit to Hours and value to 6', (tester) async {
      FakeBackendHelper.db.seedDocument('facilities', 'grill', {
        'id': 'grill',
        'name': 'BBQ Grill',
        'isUnique': true,
        'quantity': 1,
        'cooldownUnit': 'days',
        'cooldownValue': 3,
      });

      await tester.pumpWidget(wrapWithMaterial(const AdminFacilitiesScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('edit_cooldown_unit_days')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hours').last);
      await tester.pumpAndSettle();

      final durationField = find.byKey(const ValueKey('edit_cooldown_value_field'));
      await tester.enterText(durationField, '6');
      await tester.pumpAndSettle();

      expect(
        find.text('After finishing a booking, each household must wait 6 hours before starting another.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final updatedDoc = await FakeBackendHelper.db.getDocument('facilities', 'grill');
      expect(updatedDoc?['restrictionType'], equals('cooldown'));
      expect(updatedDoc?['cooldownUnit'], equals('hours'));
      expect(updatedDoc?['cooldownValue'], equals(6));
      expect(find.textContaining('Limit: Wait 6 hours'), findsOneWidget);
    });

    testWidgets('Opens Edit dialog and switches facility from cooldown to daily quota', (tester) async {
      FakeBackendHelper.db.seedDocument('facilities', 'court', {
        'id': 'court',
        'name': 'Tennis Court',
        'isUnique': true,
        'quantity': 1,
        'restrictionType': 'cooldown',
        'cooldownUnit': 'days',
        'cooldownValue': 2,
      });

      await tester.pumpWidget(wrapWithMaterial(const AdminFacilitiesScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('edit_restriction_type_cooldown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Booking Quota (Max bookings per period)').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('edit_quota_period_monthly')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('edit_quota_limit_field')), '3');
      await tester.pumpAndSettle();

      expect(find.text('Each household can book up to 3 time(s) (daily).'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final updatedDoc = await FakeBackendHelper.db.getDocument('facilities', 'court');
      expect(updatedDoc?['restrictionType'], equals('quota'));
      expect(updatedDoc?['quotaPeriod'], equals('daily'));
      expect(updatedDoc?['quotaLimit'], equals(3));
      expect(updatedDoc?['cooldownUnit'], equals('unrestricted'));
      expect(updatedDoc?['cooldownValue'], equals(0));
      expect(find.textContaining('Limit: 3 (daily)'), findsOneWidget);
    });

    testWidgets('Deletes facility when delete icon is tapped', (tester) async {
      FakeBackendHelper.db.seedDocument('facilities', 'gym', {
        'id': 'gym',
        'name': 'Gym Facility',
        'isUnique': true,
        'quantity': 1,
        'cooldownUnit': 'unrestricted',
        'cooldownValue': 0,
      });

      await tester.pumpWidget(wrapWithMaterial(const AdminFacilitiesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Gym Facility'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      final doc = await FakeBackendHelper.db.getDocument('facilities', 'gym');
      expect(doc, isNull);
    });
  });
}
