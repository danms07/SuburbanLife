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

  Widget wrapWithMaterial(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }

  group('AdminFacilitiesScreen Widget & Cooldown Edit Tests', () {
    testWidgets('Renders existing facilities with cooldown subtitle', (tester) async {
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

      expect(find.text('Swimming Pool'), findsOneWidget);
      expect(find.textContaining('Limit: 1 per 7 days'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
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

      // Tap Edit button
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      // Verify Edit dialog opened
      expect(find.text('Edit Amenity'), findsOneWidget);

      // Select 'Unrestricted (No Cooldown)' from dropdown
      await tester.tap(find.text('Days'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unrestricted (No Cooldown)').last);
      await tester.pumpAndSettle();

      // Tap Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Verify document in database updated
      final updatedDoc = await FakeBackendHelper.db.getDocument('facilities', 'pool');
      expect(updatedDoc?['cooldownUnit'], equals('unrestricted'));
      expect(updatedDoc?['cooldownValue'], equals(0));

      // Verify UI subtitle updated
      expect(find.textContaining('Limit: Unrestricted'), findsOneWidget);
    });

    testWidgets('Opens Edit dialog and changes cooldown value', (tester) async {
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

      // Tap Edit button
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      // Change cooldown duration to 14
      final durationField = find.widgetWithText(TextField, '3');
      expect(durationField, findsOneWidget);
      await tester.enterText(durationField, '14');
      await tester.pumpAndSettle();

      // Save changes
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final updatedDoc = await FakeBackendHelper.db.getDocument('facilities', 'grill');
      expect(updatedDoc?['cooldownValue'], equals(14));
      expect(updatedDoc?['cooldownUnit'], equals('days'));
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

      // Tap Delete icon
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      final doc = await FakeBackendHelper.db.getDocument('facilities', 'gym');
      expect(doc, isNull);
    });
  });
}
