import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/core/services/document_transfer_helper.dart';
import 'package:suburban_life/features/admin/admin_expenses_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

Widget _wrapWithApp(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
    FakeBackendHelper.auth.emitUser(
      AppUser(uid: 'admin_1', email: 'admin@test.mx', displayName: 'Admin'),
    );
    FakeBackendHelper.auth.isAdminMock = true;
    DocumentTransferHelper.resetOverridesForTesting();
  });

  tearDown(() {
    DocumentTransferHelper.resetOverridesForTesting();
  });

  group('AdminExpensesScreen - Budget KPIs, Recording, Inspection & Voiding', () {
    testWidgets('displays live KPI strip (income, active expenses, accumulated budget) and filters expenses', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FakeBackendHelper.db.seedDocument('config', 'app_settings', {
        'initialBudgetBalance': 1000.0,
      });
      FakeBackendHelper.db.seedDocument('payments', 'pay_1', {
        'id': 'pay_1',
        'concept': 'monthly quota',
        'status': 'approved',
        'amount': 500.0,
        'periods': ['2026-11'],
      });
      FakeBackendHelper.db.seedDocument('expenses', 'exp_active', {
        'id': 'exp_active',
        'productOrService': 'Gardening service',
        'amount': 300.0,
        'billablePeriod': '2026-11',
        'expenseDate': DateTime(2026, 11, 10).millisecondsSinceEpoch,
        'category': 'gardening',
        'status': 'active',
        'createdBy': 'admin_1',
        'createdByName': 'Admin',
        'productEvidence': {'fileName': 'g.jpg', 'fileType': 'jpg', 'fileSize': 100, 'url': 'https://fake/g.jpg', 'storagePath': 'expenses/admin_1/g.jpg'},
        'receiptEvidence': {'fileName': 'r.pdf', 'fileType': 'pdf', 'fileSize': 200, 'url': 'https://fake/r.pdf', 'storagePath': 'expenses/admin_1/r.pdf'},
      });
      FakeBackendHelper.db.seedDocument('expenses', 'exp_void', {
        'id': 'exp_void',
        'productOrService': 'Cancelled test expense',
        'amount': 999.0,
        'billablePeriod': '2026-11',
        'expenseDate': DateTime(2026, 11, 11).millisecondsSinceEpoch,
        'category': 'other',
        'status': 'voided',
        'voidReason': 'Entered twice',
        'createdBy': 'admin_1',
        'createdByName': 'Admin',
        'productEvidence': {'fileName': 'g.jpg', 'fileType': 'jpg', 'fileSize': 100, 'url': 'https://fake/g.jpg', 'storagePath': 'expenses/admin_1/g.jpg'},
        'receiptEvidence': {'fileName': 'r.pdf', 'fileType': 'pdf', 'fileSize': 200, 'url': 'https://fake/r.pdf', 'storagePath': 'expenses/admin_1/r.pdf'},
      });

      await tester.pumpWidget(_wrapWithApp(const AdminExpensesScreen()));
      await tester.pumpAndSettle();

      // Income = 1000 opening + 500 quota = 1500.00; Active expenses = 300.00; Budget = 1200.00
      expect(find.text('\$1500.00'), findsOneWidget);
      expect(find.text('\$300.00'), findsOneWidget);
      expect(find.text('\$1200.00'), findsOneWidget);

      // Default status filter is Active
      expect(find.text('Gardening service'), findsOneWidget);
      expect(find.text('Cancelled test expense'), findsNothing);

      // Switch filter to Voided
      await tester.tap(find.text('Voided'));
      await tester.pumpAndSettle();
      expect(find.text('Cancelled test expense'), findsOneWidget);
      expect(find.text('Gardening service'), findsNothing);
    });

    testWidgets('records new expense with required product photo and receipt PDF via modal', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Minimal valid 1x1 PNG bytes for Image.memory preview rendering
      final validPngBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82,
      ]);

      DocumentTransferHelper.setOverridesForTesting(
        pickImage: (_) async => PickedDocumentData(
          sanitizedFileName: 'garden_after.png',
          extension: 'png',
          contentType: 'image/png',
          fileSize: validPngBytes.length,
          bytes: validPngBytes,
        ),
        pickDocument: (_) async => PickedDocumentData(
          sanitizedFileName: 'invoice_101.pdf',
          extension: 'pdf',
          contentType: 'application/pdf',
          fileSize: 5,
          bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D]),
        ),
      );

      Map<String, dynamic>? recordedPayload;
      FakeBackendHelper.functions.registerHandler('createExpense', (params) {
        recordedPayload = params;
        FakeBackendHelper.db.seedDocument('expenses', 'exp_new', {
          'id': 'exp_new',
          ...params!,
          'status': 'active',
          'createdBy': 'admin_1',
          'createdByName': 'Admin',
        });
        return {'success': true, 'expenseId': 'exp_new'};
      });

      await tester.pumpWidget(_wrapWithApp(const AdminExpensesScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('add_expense_fab')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('expense_product_field')),
        'Lawn mowing and pruning',
      );
      await tester.enterText(
        find.byKey(const ValueKey('expense_amount_field')),
        '850.00',
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('expense_product_pick_button')),
      );
      await tester.tap(find.byKey(const ValueKey('expense_product_pick_button')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('expense_receipt_pick_button')),
      );
      await tester.tap(find.byKey(const ValueKey('expense_receipt_pick_button')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('submit_expense_button')),
      );
      await tester.tap(find.byKey(const ValueKey('submit_expense_button')));
      await tester.pumpAndSettle();

      expect(recordedPayload, isNotNull);
      expect(recordedPayload!['productOrService'], equals('Lawn mowing and pruning'));
      expect(recordedPayload!['amount'], equals(850.0));
      expect(recordedPayload!['productEvidence']['fileName'], equals('garden_after.png'));
      expect(recordedPayload!['receiptEvidence']['fileName'], equals('invoice_101.pdf'));
      expect(find.text('Lawn mowing and pruning'), findsOneWidget);
    });

    testWidgets('opens detail screen, delegates PDF download, and soft-voids active expense with reason', (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      String? openedFileName;
      DocumentTransferHelper.setOverridesForTesting(
        openOrDownload: ({
          required BuildContext context,
          required String cacheId,
          required String url,
          required String fileName,
          required String title,
        }) async {
          openedFileName = fileName;
        },
      );

      Map<String, dynamic>? voidCallParams;
      FakeBackendHelper.functions.registerHandler('voidExpense', (params) {
        voidCallParams = params;
        FakeBackendHelper.db.updateDocumentSync('expenses', 'exp_1', {
          'status': 'voided',
          'voidReason': params?['voidReason'],
        });
        return {'success': true, 'status': 'voided'};
      });

      FakeBackendHelper.db.seedDocument('expenses', 'exp_1', {
        'id': 'exp_1',
        'productOrService': 'Security camera repair',
        'amount': 1200.0,
        'billablePeriod': '2026-11',
        'expenseDate': DateTime(2026, 11, 8).millisecondsSinceEpoch,
        'category': 'security',
        'status': 'active',
        'createdBy': 'admin_1',
        'createdByName': 'Admin',
        'productEvidence': {
          'fileName': 'cam.jpg',
          'fileType': 'jpg',
          'fileSize': 1234,
          'url': 'https://fake/cam.jpg',
          'storagePath': 'expenses/admin_1/cam.jpg',
        },
        'receiptEvidence': {
          'fileName': 'cam_invoice.pdf',
          'fileType': 'pdf',
          'fileSize': 2048,
          'url': 'https://fake/cam_invoice.pdf',
          'storagePath': 'expenses/admin_1/cam_invoice.pdf',
        },
      });

      await tester.pumpWidget(_wrapWithApp(const AdminExpensesScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('expense_card_exp_1')));
      await tester.pumpAndSettle();

      expect(find.byType(AdminExpenseDetailScreen), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('expense_receipt_download_btn')),
      );
      await tester.tap(find.byKey(const ValueKey('expense_receipt_download_btn')));
      await tester.pumpAndSettle();
      expect(openedFileName, equals('cam_invoice.pdf'));

      await tester.ensureVisible(
        find.byKey(const ValueKey('void_expense_button')),
      );
      await tester.tap(find.byKey(const ValueKey('void_expense_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('void_expense_reason_field')),
        'Entered wrong invoice',
      );
      await tester.tap(find.byKey(const ValueKey('confirm_void_expense_button')));
      await tester.pumpAndSettle();

      expect(voidCallParams?['expenseId'], equals('exp_1'));
      expect(voidCallParams?['voidReason'], equals('Entered wrong invoice'));
    });

    testWidgets('renders Spanish localization cleanly on AdminExpensesScreen', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(const AdminExpensesScreen(), locale: const Locale('es')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gastos de la Comunidad'), findsOneWidget);
      expect(find.text('Registrar Gasto'), findsOneWidget);
      expect(find.text('Presupuesto Acumulado'), findsOneWidget);
    });
  });
}
