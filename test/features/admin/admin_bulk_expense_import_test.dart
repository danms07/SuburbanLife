import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/features/admin/admin_bulk_expense_import_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

Widget _wrapWithL10n(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: child,
  );
}

void main() {
  String? copiedClipboardText;

  setUp(() {
    FakeBackendHelper.setUp();
    copiedClipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        copiedClipboardText = args?['text']?.toString();
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('AdminBulkExpenseImportScreen - CSV Parser & Export', () {
    test('parses bilingual headers, categories, period formats, quoted fields, and derived periods/dates', () {
      const csv = '\uFEFF"Producto / Servicio";"Monto";"Periodo";"Fecha";"Categoría";"Proveedor";"Notas"\n'
          '"Poda, riego ""general""";"\$1,450.50";"Nov-26";"2026-11-15";"Jardinería";"GreenCare";"Nota\nmultilinea"\n'
          '"Reparación portón";"950";"";"10/10/2026";"Reparaciones";"ElectroGates";""\n'
          '"Pago de luz";"620.25";"Ene-25";"";"Servicios";"CFE","Sin fecha exacta"\n';

      final parsed = AdminBulkExpenseImportScreen.parseExpenseCsv(csv);
      expect(parsed.errorCode, isNull);
      expect(parsed.invalidRows, isEmpty);
      expect(parsed.validRows.length, equals(3));

      final r1 = parsed.validRows[0];
      expect(r1.rowNumber, equals(2));
      expect(r1.productOrService, equals('Poda, riego "general"'));
      expect(r1.amount, equals(1450.50));
      expect(r1.billablePeriod, equals('2026-11'));
      expect(r1.expenseDateIso, equals('2026-11-15'));
      expect(r1.category, equals('gardening'));
      expect(r1.vendorName, equals('GreenCare'));
      expect(r1.notes, equals('Nota\nmultilinea'));

      final r2 = parsed.validRows[1];
      expect(r2.billablePeriod, equals('2026-10'));
      expect(r2.expenseDateIso, equals('2026-10-10'));
      expect(r2.category, equals('repairs'));

      final r3 = parsed.validRows[2];
      expect(r3.billablePeriod, equals('2025-01'));
      expect(r3.expenseDateIso, equals('2025-01-01'));
      expect(r3.category, equals('utilities'));
    });

    test('flags invalid rows accurately without discarding valid rows', () {
      const csv = 'productOrService,amount,billablePeriod,expenseDate,category,vendorName,notes\n'
          'Valid item,250.00,2026-11,2026-11-05,supplies,Hardware Co,\n'
          ',100,2026-11,2026-11-05,other,,\n'
          'Zero amount,0,2026-11,2026-11-05,other,,\n'
          'Bad period,100,2026-13,2026-11-05,other,,\n'
          'Bad date,100,,2026-02-30,other,,\n'
          'Bad category,100,2026-11,2026-11-05,vacation,,\n';

      final parsed = AdminBulkExpenseImportScreen.parseExpenseCsv(csv);
      expect(parsed.errorCode, isNull);
      expect(parsed.validRows.length, equals(1));
      expect(parsed.invalidRows.length, equals(5));
      expect(parsed.invalidRows.map((r) => r.errorCode).toList(), equals([
        'invalid_product',
        'invalid_amount',
        'invalid_period',
        'invalid_date',
        'invalid_category',
      ]));
    });

    test('returns structural error codes for empty, missing headers, and >500 rows', () {
      expect(
        AdminBulkExpenseImportScreen.parseExpenseCsv('   \n ').errorCode,
        equals('empty'),
      );
      expect(
        AdminBulkExpenseImportScreen.parseExpenseCsv('street,number\nMain,1').errorCode,
        equals('missing_headers'),
      );

      final sb = StringBuffer('productOrService,amount,billablePeriod\n');
      for (int i = 0; i < 501; i++) {
        sb.writeln('Item $i,10,2026-11');
      }
      expect(
        AdminBulkExpenseImportScreen.parseExpenseCsv(sb.toString()).errorCode,
        equals('too_many_rows'),
      );
    });

    test('detects binary payloads disguised as CSV and sanitizes CWE-1236 cells on result CSV export', () {
      expect(
        AdminBulkExpenseImportScreen.isLikelyBinaryPayload(
          Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D]), // %PDF-
        ),
        isTrue,
      );
      expect(
        AdminBulkExpenseImportScreen.isLikelyBinaryPayload(
          Uint8List.fromList(utf8.encode('productOrService,amount,billablePeriod\n')),
        ),
        isFalse,
      );

      final csvOut = AdminBulkExpenseImportScreen.generateResultCsvString([
        {
          'rowNumber': 2,
          'productOrService': '=cmd|"/C calc"!A0',
          'amount': 500.0,
          'billablePeriod': '2026-11',
          'expenseDateIso': '2026-11-15',
          'category': 'maintenance',
          'status': 'ok',
          'expenseId': 'exp_1',
          'message': '+Imported cleanly',
        },
      ]);
      expect(csvOut.contains('"\'=cmd|""/C calc""!A0"'), isTrue);
      expect(csvOut.contains('"\'+Imported cleanly"'), isTrue);
    });
  });

  group('AdminBulkExpenseImportScreen - Widget UI & Reconciliation Flow', () {
    testWidgets('copies and exports sample CSV template', (tester) async {
      String? exportedFileName;
      String? exportedContent;

      await tester.pumpWidget(
        _wrapWithL10n(
          AdminBulkExpenseImportScreen(
            onExportCsv: (content, fileName) async {
              exportedContent = content;
              exportedFileName = fileName;
              return '/tmp/$fileName';
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('bulk_expense_copy_template_button')),
      );
      await tester.pumpAndSettle();
      expect(
        copiedClipboardText?.contains('productOrService,amount,billablePeriod'),
        isTrue,
      );
      expect(find.text('CSV Template copied to clipboard'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('bulk_expense_download_template_button')),
      );
      await tester.pumpAndSettle();
      expect(exportedFileName, equals('expenses_import_template.csv'));
      expect(exportedContent, equals(AdminBulkExpenseImportScreen.csvTemplate));
    });

    testWidgets('picks CSV, runs pre-check duplicate reconciliation (Skip & Import Anyway), and exports sanitized results CSV', (tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const csv = 'productOrService,amount,billablePeriod,expenseDate,category,vendorName,notes\n'
          'Duplicate gardening,1200.00,2026-11,2026-11-15,gardening,GreenCare,Matched\n'
          'Duplicate gate repair,800.00,2026-10,2026-10-10,repairs,ElectroGates,Matched\n'
          'New lighting bulbs,350.00,2026-11,2026-11-20,supplies,Hardware,\n'
          'Bad row,-10,2026-11,2026-11-20,other,,\n';

      FakeBackendHelper.functions.registerHandler('adminPreCheckExpenseImport', (params) {
        return {
          'validCount': 3,
          'invalidRows': [],
          'newItemsCount': 1,
          'duplicates': [
            {
              'rowIndex': 0,
              'rowNumber': 2,
              'productOrService': 'Duplicate gardening',
              'amount': 1200.0,
              'billablePeriod': '2026-11',
              'expenseDateIso': '2026-11-15',
              'category': 'gardening',
              'vendorName': 'GreenCare',
              'existingExpenseId': 'exp_old_1',
              'existingSource': 'manual',
              'existingVendorName': 'GreenCare',
            },
            {
              'rowIndex': 1,
              'rowNumber': 3,
              'productOrService': 'Duplicate gate repair',
              'amount': 800.0,
              'billablePeriod': '2026-10',
              'expenseDateIso': '2026-10-10',
              'category': 'repairs',
              'vendorName': 'ElectroGates',
              'existingExpenseId': 'exp_old_2',
              'existingSource': 'bulk_csv_import',
              'existingVendorName': 'ElectroGates',
            },
          ],
        };
      });

      Map<String, dynamic>? importPayload;
      FakeBackendHelper.functions.registerHandler('adminBulkImportExpenses', (params) {
        importPayload = params;
        return {
          'success': true,
          'totalProcessed': 3,
          'successCount': 2,
          'skippedCount': 1,
          'failureCount': 0,
          'results': [
            {
              'rowNumber': 2,
              'productOrService': 'Duplicate gardening',
              'amount': 1200.0,
              'billablePeriod': '2026-11',
              'expenseDateIso': '2026-11-15',
              'category': 'gardening',
              'status': 'skipped',
              'expenseId': 'exp_old_1',
              'message': 'Skipped matching existing active expense.',
            },
            {
              'rowNumber': 3,
              'productOrService': 'Duplicate gate repair',
              'amount': 800.0,
              'billablePeriod': '2026-10',
              'expenseDateIso': '2026-10-10',
              'category': 'repairs',
              'status': 'ok',
              'expenseId': 'exp_new_2',
              'message': 'Imported successfully.',
            },
            {
              'rowNumber': 4,
              'productOrService': 'New lighting bulbs',
              'amount': 350.0,
              'billablePeriod': '2026-11',
              'expenseDateIso': '2026-11-20',
              'category': 'supplies',
              'status': 'ok',
              'expenseId': 'exp_new_3',
              'message': 'Imported successfully.',
            },
          ],
        };
      });

      String? exportedResultsCsv;
      await tester.pumpWidget(
        _wrapWithL10n(
          AdminBulkExpenseImportScreen(
            pickCsvOverride: () async => (
              fileName: 'expenses_2026.csv',
              bytes: Uint8List.fromList(utf8.encode(csv)),
            ),
            onExportCsv: (content, fileName) async {
              exportedResultsCsv = content;
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('bulk_expense_pick_csv_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('bulk_expense_invalid_rows_card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('bulk_expense_preview_card')),
        findsOneWidget,
      );
      expect(find.text('Preview Expenses (3)'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('bulk_expense_process_button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('bulk_expense_process_button')),
      );
      await tester.pumpAndSettle();

      // Duplicate 1 of 2 -> Skip Row
      expect(find.text('Duplicate 1 of 2'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('bulk_expense_reconcile_skip_btn')),
      );
      await tester.pumpAndSettle();

      // Duplicate 2 of 2 -> Import Anyway
      expect(find.text('Duplicate 2 of 2'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('bulk_expense_reconcile_import_btn')),
      );
      await tester.pumpAndSettle();

      expect(importPayload, isNotNull);
      expect(
        importPayload!['reconciliationDecisions'],
        equals({'0': 'skip', '1': 'import'}),
      );
      expect(
        find.byKey(const ValueKey('bulk_expense_results_card')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('bulk_expense_results_card')),
          matching: find.text('2 imported, 1 skipped, 0 failed'),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('bulk_expense_download_results_btn')),
      );
      await tester.tap(
        find.byKey(const ValueKey('bulk_expense_download_results_btn')),
      );
      await tester.pumpAndSettle();
      expect(exportedResultsCsv?.contains('exp_new_2'), isTrue);
      expect(exportedResultsCsv?.contains('exp_new_3'), isTrue);
    });

    testWidgets('stacks template buttons and reconciliation dialog cleanly on narrow 360px Spanish viewports without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FakeBackendHelper.functions.registerHandler('adminPreCheckExpenseImport', (_) {
        return {
          'validCount': 1,
          'invalidRows': [],
          'newItemsCount': 0,
          'duplicates': [
            {
              'rowIndex': 0,
              'rowNumber': 2,
              'productOrService': 'Mantenimiento general',
              'amount': 950.0,
              'billablePeriod': '2026-11',
              'expenseDateIso': '2026-11-15',
              'category': 'maintenance',
              'vendorName': 'Servicios MX',
              'existingExpenseId': 'exp_1',
              'existingSource': 'manual',
              'existingVendorName': 'Servicios MX',
            },
          ],
        };
      });

      final preParsed = AdminBulkExpenseImportScreen.parseExpenseCsv(
        'productOrService,amount,billablePeriod,expenseDate,category,vendorName\n'
        'Mantenimiento general,950,2026-11,2026-11-15,maintenance,Servicios MX\n',
      );

      await tester.pumpWidget(
        _wrapWithL10n(
          AdminBulkExpenseImportScreen(
            isEmbedded: true,
            initialFileName: 'gastos.csv',
            initialParseResult: preParsed,
          ),
          locale: const Locale('es'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Importación Masiva de Gastos (CSV)'), findsOneWidget);
      expect(find.text('Seleccionar CSV de Gastos'), findsOneWidget);

      final dlRect = tester.getRect(
        find.byKey(const ValueKey('bulk_expense_download_template_button')),
      );
      final copyRect = tester.getRect(
        find.byKey(const ValueKey('bulk_expense_copy_template_button')),
      );
      expect(copyRect.top, greaterThanOrEqualTo(dlRect.bottom));

      await tester.ensureVisible(
        find.byKey(const ValueKey('bulk_expense_process_button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('bulk_expense_process_button')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Duplicado 1 de 1'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });
  });
}
