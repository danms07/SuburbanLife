import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/features/payments/payment_screen.dart';
import 'package:suburban_life/features/sanctions/admin_sanctions_screen.dart';
import 'package:suburban_life/features/sanctions/sanctions_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

Widget _wrapWithApp(Widget home, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('es')],
    home: home,
  );
}

AppLocalizations _enL10n(WidgetTester tester) {
  final ctx = tester.element(find.byType(Scaffold).first);
  return AppLocalizations.of(ctx)!;
}

void main() {
  late Directory tempDir;

  setUp(() {
    FakeBackendHelper.setUp();
    tempDir = Directory.systemTemp.createTempSync('sanctions_screens_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SanctionsScreen (Resident View)', () {
    testWidgets('renders empty state without restriction warning when resident has zero sanctions', (tester) async {
      await tester.pumpWidget(_wrapWithApp(const SanctionsScreen(currentUid: 'res_clean')));
      await tester.pumpAndSettle();

      final l10n = _enL10n(tester);
      expect(find.text(l10n.noSanctions), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('displays active sanction warning, rejection note, and navigates to PaymentScreen with prefilled fine', (tester) async {
      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_res_1');
      FakeBackendHelper.db.seedDocument('addresses', 'addr_res_1', {
        'id': 'addr_res_1',
        'streetName': 'Verona',
        'number': 45,
        'paymentStatus': 'restricted',
        'residentUid': 'res_fined',
      });
      FakeBackendHelper.db.seedDocument('users', 'res_fined', {
        'uid': 'res_fined',
        'name': 'Sofia Ruiz',
        'role': 'resident',
        'addressRef': addrRef,
      });
      FakeBackendHelper.db.seedDocument('sanctions', 'sanc_101', {
        'id': 'sanc_101',
        'addressRef': addrRef,
        'residentUid': 'res_fined',
        'authorizedUids': ['res_fined'],
        'reason': 'Blocking visitor parking overnight',
        'amount': 850.0,
        'status': 'active',
        'rejectionReason': 'Blurry transfer receipt',
        'createdAt': DateTime(2026, 10, 12).millisecondsSinceEpoch,
      });

      await tester.pumpWidget(_wrapWithApp(const SanctionsScreen(currentUid: 'res_fined')));
      await tester.pumpAndSettle();

      final l10n = _enL10n(tester);
      expect(find.text(l10n.activeSanctionsRestrictedWarning(1)), findsOneWidget);
      expect(find.text('\$850.00 MXN'), findsOneWidget);
      expect(find.text('Blocking visitor parking overnight'), findsOneWidget);
      expect(find.text(l10n.paymentRejectedBannerMsg('Blurry transfer receipt')), findsOneWidget);

      // Tap Pay Sanction button -> navigates to PaymentScreen in sanction mode with 850.00 prefilled
      await tester.tap(find.text(l10n.paySanction));
      await tester.pumpAndSettle();

      expect(find.byType(PaymentScreen), findsOneWidget);
      expect(find.text(l10n.conceptSanction), findsAtLeastNWidgets(1));
      final editableAmount = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('amount_field')),
          matching: find.byType(EditableText),
        ),
      );
      expect(editableAmount.controller.text, equals('850.00'));
    });
  });

  group('AdminSanctionsScreen', () {
    testWidgets('issues new sanction with evidence upload, temp cleanup, authorizedUids resolution, and address restriction', (tester) async {
      FakeBackendHelper.auth.emitUser(
        AppUser(uid: 'admin_1', email: 'admin@catania.com', displayName: 'Admin'),
      );
      FakeBackendHelper.auth.isAdminMock = true;

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_target');
      FakeBackendHelper.db.seedDocument('addresses', 'addr_target', {
        'id': 'addr_target',
        'streetName': 'Catania Poniente',
        'number': 302,
        'paymentStatus': 'paid',
        'deliveryDate': null,
      });
      FakeBackendHelper.db.seedDocument('users', 'owner_1', {
        'uid': 'owner_1',
        'name': 'Owner One',
        'addressRef': addrRef,
      });
      FakeBackendHelper.db.seedDocument('users', 'roommate_2', {
        'uid': 'roommate_2',
        'name': 'Roommate Two',
        'addressRef': addrRef,
      });

      final tempEvidence = File('${tempDir.path}/image_picker_sanction_ev.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);

      await tester.pumpWidget(
        _wrapWithApp(
          AdminSanctionsScreen(
            pickImageOverride: () async => XFile(tempEvidence.path),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = _enL10n(tester);
      expect(find.text(l10n.noSanctions), findsOneWidget);

      // Open Issue Sanction modal
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Select target address
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Catania Poniente 302').last);
      await tester.pumpAndSettle();

      // Enter reason and amount
      final formFields = find.byType(TextFormField);
      expect(formFields, findsNWidgets(2));
      await tester.enterText(formFields.at(0), 'Unleashed pet in common garden');
      await tester.enterText(formFields.at(1), '600');

      // Missing photo guard triggers before evidence is picked
      await tester.tap(find.widgetWithText(ElevatedButton, l10n.save));
      await tester.pump();
      expect(await FakeBackendHelper.db.getCollection('sanctions'), isEmpty);

      // Pick evidence photo and submit
      await tester.tap(find.widgetWithText(TextButton, l10n.takePhotoReceipt));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, l10n.save));
      await tester.pumpAndSettle();

      // Temp image cleaned up and uploaded to sanctions/addr_target/...
      expect(tempEvidence.existsSync(), isFalse);
      expect(
        FakeBackendHelper.storage.uploadedFiles.keys.any(
          (k) => k.startsWith('sanctions/addr_target/'),
        ),
        isTrue,
      );

      // Sanction document persisted with both household UIDs in authorizedUids
      final sanctions = await FakeBackendHelper.db.getCollection('sanctions');
      expect(sanctions, hasLength(1));
      expect(sanctions.first['reason'], equals('Unleashed pet in common garden'));
      expect(sanctions.first['amount'], equals(600.0));
      expect(sanctions.first['status'], equals('active'));
      expect(sanctions.first['authorizedUids'], containsAll(['owner_1', 'roommate_2']));

      // Address recalculated to restricted
      final updatedAddr = await FakeBackendHelper.db.getDocument('addresses', 'addr_target');
      expect(updatedAddr?['paymentStatus'], equals('restricted'));
      expect(updatedAddr?['hasActiveSanctions'], isTrue);
    });

    testWidgets('cleans up temporary evidence file on modal dismissal without saving', (tester) async {
      final tempUnsaved = File('${tempDir.path}/image_picker_unsaved.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);

      await tester.pumpWidget(
        _wrapWithApp(
          AdminSanctionsScreen(
            pickImageOverride: () async => XFile(tempUnsaved.path),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = _enL10n(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, l10n.takePhotoReceipt));
      await tester.pumpAndSettle();
      expect(tempUnsaved.existsSync(), isTrue);

      // Close modal via close IconButton -> dispose() deletes tempUnsaved
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(tempUnsaved.existsSync(), isFalse);
    });

    testWidgets('filters sanctions by status chips and waives active sanction restoring address status', (tester) async {
      FakeBackendHelper.auth.emitUser(
        AppUser(uid: 'admin_waiver', email: 'admin@catania.com', displayName: 'Admin'),
      );
      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_waive');
      FakeBackendHelper.db.seedDocument('addresses', 'addr_waive', {
        'id': 'addr_waive',
        'streetName': 'Palermo',
        'number': 15,
        'paymentStatus': 'restricted',
        'deliveryDate': null,
      });
      FakeBackendHelper.db.seedDocument('sanctions', 's_active', {
        'id': 's_active',
        'addressRef': addrRef,
        'reason': 'Active fine reason',
        'amount': 400.0,
        'status': 'active',
        'createdAt': 2000,
      });
      FakeBackendHelper.db.seedDocument('sanctions', 's_paid', {
        'id': 's_paid',
        'addressRef': addrRef,
        'reason': 'Historical paid fine',
        'amount': 300.0,
        'status': 'paid',
        'createdAt': 1000,
      });

      await tester.pumpWidget(_wrapWithApp(const AdminSanctionsScreen()));
      await tester.pumpAndSettle();

      final l10n = _enL10n(tester);
      expect(find.text('Active fine reason'), findsOneWidget);
      expect(find.text('Historical paid fine'), findsOneWidget);

      // Filter by Paid -> only Historical paid fine remains visible
      final paidChip = find.widgetWithText(FilterChip, l10n.sanctionStatusPaid);
      await tester.ensureVisible(paidChip);
      await tester.pumpAndSettle();
      await tester.tap(paidChip);
      await tester.pumpAndSettle();
      expect(find.text('Active fine reason'), findsNothing);
      expect(find.text('Historical paid fine'), findsOneWidget);

      // Switch to Active filter and waive the sanction
      final activeChip = find.widgetWithText(FilterChip, l10n.sanctionStatusActive);
      await tester.ensureVisible(activeChip);
      await tester.pumpAndSettle();
      await tester.tap(activeChip);
      await tester.pumpAndSettle();
      expect(find.text('Active fine reason'), findsOneWidget);

      await tester.tap(find.text(l10n.waiveSanction));
      await tester.pumpAndSettle();

      // Confirm waiver dialog
      await tester.tap(find.widgetWithText(ElevatedButton, l10n.confirmAction));
      await tester.pumpAndSettle();

      final waivedDoc = await FakeBackendHelper.db.getDocument('sanctions', 's_active');
      expect(waivedDoc?['status'], equals('cancelled'));
      expect(waivedDoc?['cancelledBy'], equals('admin_waiver'));

      final updatedAddr = await FakeBackendHelper.db.getDocument('addresses', 'addr_waive');
      expect(updatedAddr?['paymentStatus'], equals('paid'));
      expect(updatedAddr?['hasActiveSanctions'], isFalse);
    });
  });
}
