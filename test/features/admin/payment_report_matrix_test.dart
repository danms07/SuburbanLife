import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/features/admin/admin_payment_report_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

Widget _wrapWithL10n(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('es')],
    locale: locale,
    home: child,
  );
}

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
  });

  group('AdminPaymentReportScreen - Month Range, Matching & Matrix Status', () {
    test('generateMonthRange creates sequential list of months within boundary', () {
      final start = DateTime(2025, 11, 1);
      final end = DateTime(2026, 2, 1);

      final months = AdminPaymentReportScreen.generateMonthRange(start, end);

      expect(months.length, equals(4));
      expect(months[0], equals(DateTime(2025, 11, 1)));
      expect(months[1], equals(DateTime(2025, 12, 1)));
      expect(months[2], equals(DateTime(2026, 1, 1)));
      expect(months[3], equals(DateTime(2026, 2, 1)));
    });

    test('formatMonthLabel creates clean abbreviated English string', () {
      expect(AdminPaymentReportScreen.formatMonthLabel(DateTime(2026, 1, 15)), equals('Jan 2026'));
      expect(AdminPaymentReportScreen.formatMonthLabel(DateTime(2026, 8, 1)), equals('Aug 2026'));
      expect(AdminPaymentReportScreen.formatMonthLabel(DateTime(2026, 12, 31)), equals('Dec 2026'));
    });

    test('doesPaymentMatchAddressAndMonth matches multi-period advance receipts via addressRef and ignores sanctions', () {
      final addr1 = {
        'id': 'addr_101',
        'streetName': 'Avenida Olmos',
        'number': 101,
        'residentUid': 'res_1',
      };
      final addr2 = {
        'id': 'addr_102',
        'streetName': 'Avenida Olmos',
        'number': 102,
        'residentUid': 'res_1', // Multi-property owner
      };

      // Advance payment uploaded in March covering April & May for addr_101 only
      final advancePayment = {
        'addressRef': StringDbReference('addr_101', path: 'addresses/addr_101'),
        'residentUid': 'res_1',
        'concept': 'monthly quota',
        'periods': ['2026-04', '2026-05'],
        'timestamp': DateTime(2026, 3, 28).millisecondsSinceEpoch,
        'status': 'approved',
      };

      final sanctionPayment = {
        'addressRef': StringDbReference('addr_101', path: 'addresses/addr_101'),
        'residentUid': 'res_1',
        'concept': 'sanction',
        'periods': ['2026-04'],
        'timestamp': DateTime(2026, 4, 5).millisecondsSinceEpoch,
        'status': 'approved',
      };

      expect(
        AdminPaymentReportScreen.doesPaymentMatchAddressAndMonth(
          payment: advancePayment,
          addressData: addr1,
          targetMonth: DateTime(2026, 4, 1),
        ),
        isTrue,
      );
      expect(
        AdminPaymentReportScreen.doesPaymentMatchAddressAndMonth(
          payment: advancePayment,
          addressData: addr1,
          targetMonth: DateTime(2026, 5, 1),
        ),
        isTrue,
      );
      // Should NOT bleed into addr_102 even though same residentUid
      expect(
        AdminPaymentReportScreen.doesPaymentMatchAddressAndMonth(
          payment: advancePayment,
          addressData: addr2,
          targetMonth: DateTime(2026, 4, 1),
        ),
        isFalse,
      );
      // Should NOT count sanction receipts as monthly maintenance payments
      expect(
        AdminPaymentReportScreen.doesPaymentMatchAddressAndMonth(
          payment: sanctionPayment,
          addressData: addr1,
          targetMonth: DateTime(2026, 4, 1),
        ),
        isFalse,
      );
    });

    test('computeMatrixStatus evaluates paid, pending grace, and past due boundaries', () {
      expect(
        AdminPaymentReportScreen.computeMatrixStatus(
          targetMonth: DateTime(2026, 5, 1),
          currentActiveMonth: DateTime(2026, 5, 1),
          currentDay: 20,
          cutoffDay: 1,
          graceDays: 10,
          matchingPayments: [
            {'status': 'approved'},
          ],
        ),
        equals('paid'),
      );

      // Day 11 == cutoff(1) + grace(10) -> still within grace ('pending')
      expect(
        AdminPaymentReportScreen.computeMatrixStatus(
          targetMonth: DateTime(2026, 5, 1),
          currentActiveMonth: DateTime(2026, 5, 1),
          currentDay: 11,
          cutoffDay: 1,
          graceDays: 10,
          matchingPayments: [],
        ),
        equals('pending'),
      );

      // Day 12 > threshold 11 -> 'past due'
      expect(
        AdminPaymentReportScreen.computeMatrixStatus(
          targetMonth: DateTime(2026, 5, 1),
          currentActiveMonth: DateTime(2026, 5, 1),
          currentDay: 12,
          cutoffDay: 1,
          graceDays: 10,
          matchingPayments: [],
        ),
        equals('past due'),
      );

      // Previous unpaid month -> 'past due'
      expect(
        AdminPaymentReportScreen.computeMatrixStatus(
          targetMonth: DateTime(2026, 3, 1),
          currentActiveMonth: DateTime(2026, 5, 1),
          currentDay: 5,
          cutoffDay: 1,
          graceDays: 10,
          matchingPayments: [],
        ),
        equals('past due'),
      );
    });
  });

  group('AdminPaymentReportScreen - Widget Flows', () {
    testWidgets('shows alert dialog when no payment data exists for selected range', (tester) async {
      await tester.pumpWidget(_wrapWithL10n(const AdminPaymentReportScreen()));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byIcon(Icons.download));
      await tester.tap(find.byIcon(Icons.download));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('compiles CSV matrix from seeded addresses and multi-period payments', (tester) async {
      final now = DateTime.now();
      final currentPeriod = AdminPaymentReportScreen.formatPeriodKey(now);
      final prevMonth = DateTime(now.year, now.month - 1, 1);
      final prevPeriod = AdminPaymentReportScreen.formatPeriodKey(prevMonth);

      FakeBackendHelper.db.seedDocument('addresses', 'addr_1', {
        'streetName': 'Calle Robles',
        'number': 10,
        'residentUid': 'res_1',
      });
      FakeBackendHelper.db.seedDocument('payments', 'pay_1', {
        'addressRef': FakeBackendHelper.db.createReference('addresses', 'addr_1'),
        'residentUid': 'res_1',
        'concept': 'monthly quota',
        'periods': [prevPeriod, currentPeriod],
        'status': 'approved',
        'timestamp': DateTime(now.year, now.month - 2, 20).millisecondsSinceEpoch,
      });

      String? generatedCsv;
      await tester.pumpWidget(
        _wrapWithL10n(
          AdminPaymentReportScreen(
            onSaveCsv: (csv) async {
              generatedCsv = csv;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byIcon(Icons.download));
      await tester.tap(find.byIcon(Icons.download));
      await tester.pumpAndSettle();

      expect(generatedCsv, isNotNull);
      expect(generatedCsv, contains('"Calle Robles","10"'));
      expect(generatedCsv, contains('"paid"'));
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('exports Multi-Report Bundle with opening balance, quotas, sanctions, expenses, and accumulated budget, and publishes privacy-safe summary without address status matrix', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final currentPeriod = AdminPaymentReportScreen.formatPeriodKey(now);

      FakeBackendHelper.db.seedDocument('config', 'app_settings', {
        'initialBudgetBalance': 2000.0,
      });
      FakeBackendHelper.db.seedDocument('addresses', 'addr_1', {
        'streetName': 'Calle Privada',
        'number': 42,
        'residentUid': 'res_1',
      });
      FakeBackendHelper.db.seedDocument('payments', 'pay_quota', {
        'addressRef': FakeBackendHelper.db.createReference('addresses', 'addr_1'),
        'residentUid': 'res_1',
        'concept': 'monthly quota',
        'amount': 800.0,
        'periods': [currentPeriod],
        'status': 'approved',
        'timestamp': now.millisecondsSinceEpoch,
      });
      FakeBackendHelper.db.seedDocument('payments', 'pay_sanction', {
        'addressRef': FakeBackendHelper.db.createReference('addresses', 'addr_1'),
        'residentUid': 'res_1',
        'concept': 'sanction',
        'amount': 200.0,
        'periods': ['Sanction'],
        'paymentDate': now.millisecondsSinceEpoch,
        'status': 'approved',
        'timestamp': now.millisecondsSinceEpoch,
      });
      FakeBackendHelper.db.seedDocument('expenses', 'exp_1', {
        'id': 'exp_1',
        'productOrService': 'Pool filter maintenance',
        'amount': 350.0,
        'billablePeriod': currentPeriod,
        'expenseDate': now.millisecondsSinceEpoch,
        'category': 'maintenance',
        'status': 'active',
        'createdByName': 'Admin',
        'productEvidence': {'fileName': 'pool.jpg'},
        'receiptEvidence': {'fileName': 'inv.pdf'},
      });

      Map<String, dynamic>? syncedDocPayload;
      FakeBackendHelper.functions.registerHandler('syncTransparencyDocument', (params) {
        syncedDocPayload = params;
        return {'success': true, 'docId': 'doc_fin_1'};
      });

      String? matrixCsv;
      String? ledgerCsv;
      await tester.pumpWidget(
        _wrapWithL10n(
          AdminPaymentReportScreen(
            onSaveCsv: (csv) async => matrixCsv = csv,
            onSaveLedgerCsv: (csv) async => ledgerCsv = csv,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Live preview displays Ending Accumulated Budget = 2000 + 800 + 200 - 350 = 2650.00
      expect(find.byKey(const ValueKey('financial_summary_preview_card')), findsOneWidget);
      expect(find.text('\$2650.00'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('download_report_bundle_button')),
      );
      await tester.tap(find.byKey(const ValueKey('download_report_bundle_button')));
      await tester.pumpAndSettle();

      expect(matrixCsv, contains('"Calle Privada","42"'));
      expect(ledgerCsv, contains('Pool filter maintenance'));
      expect(ledgerCsv, contains('"Ending Accumulated Budget","2650.00"'));

      // Publish aggregated summary to Transparency -> must NEVER disclose address payment status matrix
      await tester.ensureVisible(
        find.byKey(const ValueKey('publish_transparency_report_button')),
      );
      await tester.tap(find.byKey(const ValueKey('publish_transparency_report_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('confirm_publish_transparency_button')));
      await tester.pumpAndSettle();

      expect(syncedDocPayload, isNotNull);
      expect(syncedDocPayload!['fileType'], equals('md'));
      final decodedMd = utf8.decode(base64Decode(syncedDocPayload!['fileBase64'] as String));
      expect(decodedMd, contains('\$2650.00'));
      expect(decodedMd, contains('Pool filter maintenance'));
      expect(decodedMd, isNot(contains('Calle Privada')));
      expect(decodedMd, isNot(contains('past due')));
    });

    testWidgets(
      'renders cleanly on narrow mobile Spanish viewport with preview at top, date pickers middle, and downloads at bottom',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          _wrapWithL10n(
            const AdminPaymentReportScreen(),
            locale: const Locale('es'),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Reportes Financieros'), findsWidgets);
        expect(find.text('Vista Previa del Resumen Financiero'), findsOneWidget);

        final previewTop = tester.getTopLeft(
          find.byKey(const ValueKey('financial_summary_preview_card')),
        ).dy;
        final startMonthTop = tester.getTopLeft(find.text('Mes de Inicio')).dy;
        final endMonthTop = tester.getTopLeft(find.text('Mes de Fin')).dy;
        final bundleButtonTop = tester.getTopLeft(
          find.byKey(const ValueKey('download_report_bundle_button')),
        ).dy;
        final matrixButtonTop = tester.getTopLeft(
          find.byKey(const ValueKey('download_status_matrix_only_button')),
        ).dy;

        expect(previewTop, lessThan(startMonthTop));
        expect(startMonthTop, lessThan(endMonthTop));
        expect(endMonthTop, lessThan(bundleButtonTop));
        expect(bundleButtonTop, lessThan(matrixButtonTop));
      },
    );
  });
}
