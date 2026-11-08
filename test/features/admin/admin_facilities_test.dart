import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/core/services/document_transfer_helper.dart';
import 'package:suburban_life/features/admin/admin_facilities_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
    DocumentTransferHelper.resetOverridesForTesting();
    FakeBackendHelper.auth.emitUser(
      AppUser(
        uid: 'admin_test_uid',
        email: 'admin@example.com',
        displayName: 'Admin User',
      ),
    );
    FakeBackendHelper.auth.isAdminMock = true;
  });

  tearDown(() {
    DocumentTransferHelper.resetOverridesForTesting();
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

    testWidgets('Deletes facility and cleans up any facilityDocuments Storage URLs when delete icon is tapped', (tester) async {
      FakeBackendHelper.db.seedDocument('facilities', 'gym', {
        'id': 'gym',
        'name': 'Gym Facility',
        'isUnique': true,
        'quantity': 1,
        'cooldownUnit': 'unrestricted',
        'cooldownValue': 0,
        'facilityDocuments': [
          {
            'docId': 'doc_gym_waiver',
            'title': 'Gym Waiver',
            'requirementMode': 'mandatory_return',
            'fileName': 'waiver.pdf',
            'fileType': 'pdf',
            'fileSize': 1024,
            'url': 'https://fake.storage/facility_documents/gym/waiver.pdf',
            'storagePath': 'facility_documents/gym/waiver.pdf',
            'uploadedAt': 1700000000000,
          },
        ],
      });

      await tester.pumpWidget(wrapWithMaterial(const AdminFacilitiesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Gym Facility'), findsOneWidget);
      expect(find.textContaining('Docs: 1 (1 required)'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      final doc = await FakeBackendHelper.db.getDocument('facilities', 'gym');
      expect(doc, isNull);
      expect(
        FakeBackendHelper.storage.deletedUrls,
        contains('https://fake.storage/facility_documents/gym/waiver.pdf'),
      );
    });

    testWidgets('Edit dialog stages new documents, leaves Storage untouched on Cancel, and uploads/deletes properly on Save', (tester) async {
      FakeBackendHelper.db.seedDocument('facilities', 'event_room', {
        'id': 'event_room',
        'name': 'Event Room',
        'isUnique': true,
        'quantity': 1,
        'cooldownUnit': 'unrestricted',
        'cooldownValue': 0,
        'facilityDocuments': [
          {
            'docId': 'doc_old_rules',
            'title': 'Old Rules',
            'requirementMode': 'informative',
            'fileName': 'old_rules.pdf',
            'fileType': 'pdf',
            'fileSize': 2048,
            'url': 'https://fake.storage/facility_documents/event_room/old_rules.pdf',
            'storagePath': 'facility_documents/event_room/old_rules.pdf',
            'uploadedAt': 1700000000000,
          },
        ],
      });

      DocumentTransferHelper.setOverridesForTesting(
        pickDocument: (ctx) async => PickedDocumentData(
          sanitizedFileName: 'deposit_agreement.pdf',
          extension: 'pdf',
          contentType: 'application/pdf',
          fileSize: 16,
          bytes: Uint8List.fromList('%PDF-1.7 deposit'.codeUnits),
        ),
      );

      await tester.pumpWidget(wrapWithMaterial(const AdminFacilitiesScreen()));
      await tester.pumpAndSettle();

      // 1. Open Edit dialog, remove existing doc and stage a new doc, then tap Cancel -> NO Storage changes!
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      final removeOldBtn = find.byKey(const ValueKey('edit_remove_doc_doc_old_rules'));
      await tester.ensureVisible(removeOldBtn);
      await tester.tap(removeOldBtn);
      await tester.pumpAndSettle();

      final addDocBtn = find.byKey(const ValueKey('edit_add_facility_doc_button'));
      await tester.ensureVisible(addDocBtn);
      await tester.tap(addDocBtn);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(FakeBackendHelper.storage.deletedUrls, isEmpty);
      expect(FakeBackendHelper.storage.uploadedFiles, isEmpty);
      final unchangedDoc = await FakeBackendHelper.db.getDocument('facilities', 'event_room');
      expect((unchangedDoc?['facilityDocuments'] as List).length, equals(1));

      // 2. Re-open Edit dialog, remove old doc, add new mandatory doc, and tap Save -> uploads new & deletes removed!
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      await tester.ensureVisible(removeOldBtn);
      await tester.tap(removeOldBtn);
      await tester.pumpAndSettle();

      await tester.ensureVisible(addDocBtn);
      await tester.tap(addDocBtn);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        FakeBackendHelper.storage.deletedUrls,
        contains('https://fake.storage/facility_documents/event_room/old_rules.pdf'),
      );
      expect(FakeBackendHelper.storage.uploadedFiles.length, equals(1));
      final uploadedEntry = FakeBackendHelper.storage.uploadedOptions.entries.single;
      expect(uploadedEntry.key, startsWith('facility_documents/event_room/'));
      expect(
        uploadedEntry.value['contentDisposition'],
        equals('attachment; filename="deposit_agreement.pdf"'),
      );

      final savedDoc = await FakeBackendHelper.db.getDocument('facilities', 'event_room');
      final savedDocsList = savedDoc?['facilityDocuments'] as List;
      expect(savedDocsList.length, equals(1));
      expect(savedDocsList.first['title'], equals('deposit agreement'));
      expect(savedDocsList.first['requirementMode'], equals('mandatory_return'));
      expect(find.textContaining('Docs: 1 (1 required)'), findsOneWidget);
    });
  });
}
