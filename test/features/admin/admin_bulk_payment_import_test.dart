import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/features/admin/admin_bulk_payment_import_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

Widget _wrapWithL10n(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('es')],
    locale: const Locale('en'),
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

  group('AdminBulkPaymentImportScreen - Period Parser', () {
    test('parses English and Spanish mmm-yy period formats into YYYY-MM', () {
      expect(AdminBulkPaymentImportScreen.parsePeriodHeader('Nov-24'), '2024-11');
      expect(AdminBulkPaymentImportScreen.parsePeriodHeader('nov-24'), '2024-11');
      expect(AdminBulkPaymentImportScreen.parsePeriodHeader('NOV-24'), '2024-11');
      expect(AdminBulkPaymentImportScreen.parsePeriodHeader('Jan-25'), '2025-01');
      expect(AdminBulkPaymentImportScreen.parsePeriodHeader('Dec-2024'), '2024-12');
      expect(AdminBulkPaymentImportScreen.parsePeriodHeader('Sept-24'), '2024-09');

      // Spanish
      expect(AdminBulkPaymentImportScreen.parsePeriodHeader('Ene-25'), '2025-01');
      expect(AdminBulkPaymentImportScreen.parsePeriodHeader('ene-25'), '2025-01');
      expect(AdminBulkPaymentImportScreen.parsePeriodHeader('Abr-24'), '2024-04');
      expect(AdminBulkPaymentImportScreen.parsePeriodHeader('Ago-24'), '2024-08');
      expect(AdminBulkPaymentImportScreen.parsePeriodHeader('Dic-23'), '2023-12');

      // ISO
      expect(AdminBulkPaymentImportScreen.parsePeriodHeader('2024-11'), '2024-11');
      expect(AdminBulkPaymentImportScreen.parsePeriodHeader('2025/01'), '2025-01');

      // Invalids
      expect(AdminBulkPaymentImportScreen.parsePeriodHeader(''), isNull);
      expect(AdminBulkPaymentImportScreen.parsePeriodHeader('Street'), isNull);
      expect(AdminBulkPaymentImportScreen.parsePeriodHeader('Number'), isNull);
      expect(AdminBulkPaymentImportScreen.parsePeriodHeader('xyz-99'), isNull);
    });

    test('splits CSV lines preserving quoted values with commas and delimiters', () {
      final cells = AdminBulkPaymentImportScreen.splitCsvLine(
        '"Almendros, Privada",101,"$1,500.00","0.00"',
        ',',
      );
      expect(cells.length, 4);
      expect(cells[0], 'Almendros, Privada');
      expect(cells[1], '101');
      expect(cells[2], '\$1,500.00');
      expect(cells[3], '0.00');
    });

    test('parses full payment CSV with monetary amounts, empty cells, and case insensitivity', () {
      const csv = '\uFEFF"Street","Number","Nov-24","Dec-24","Ene-25"\n'
          '"Almendros",101,"1,500.00","\$1,500",""\n'
          '"CALLE ROBLES","12","1200","","1200"\n'
          '"Avenida Olmos",5,"0","",""\n';

      final result = AdminBulkPaymentImportScreen.parsePaymentCsv(csv);
      expect(result['error'], isNull);

      final items = List<Map<String, dynamic>>.from(result['items'] as List);
      expect(items.length, 3);

      // Row 1: Almendros #101
      expect(items[0]['streetName'], 'Almendros');
      expect(items[0]['number'], 101);
      final p1 = items[0]['periodAmounts'] as Map<String, double>;
      expect(p1['2024-11'], 1500.0);
      expect(p1['2024-12'], 1500.0);
      expect(p1.containsKey('2025-01'), isFalse);

      // Row 2: CALLE ROBLES #12
      expect(items[1]['streetName'], 'CALLE ROBLES');
      expect(items[1]['number'], 12);
      final p2 = items[1]['periodAmounts'] as Map<String, double>;
      expect(p2['2024-11'], 1200.0);
      expect(p2['2025-01'], 1200.0);
      expect(p2.containsKey('2024-12'), isFalse);

      // Row 3: Avenida Olmos #5 has only 0 / empty
      expect(items[2]['streetName'], 'Avenida Olmos');
      expect(items[2]['number'], 5);
      final p3 = items[2]['periodAmounts'] as Map<String, double>;
      expect(p3.isEmpty, isTrue);
    });

    test('returns no_periods error if CSV does not contain valid period headers', () {
      const invalidCsv = '"Street","Number","Name","Email"\n"Almendros",101,"John","john@test.com"\n';
      final result = AdminBulkPaymentImportScreen.parsePaymentCsv(invalidCsv);
      expect(result['error'], 'no_periods');
    });

    test('generateResultCsvString generates valid RFC compliant CSV output', () {
      final results = [
        {
          'street': 'Almendros',
          'number': 101,
          'status': 'ok',
          'importedPeriods': ['Nov-24', 'Dec-24'],
          'skippedPeriods': <String>[],
          'message': 'Imported 2 period(s).',
        },
        {
          'street': 'Robles',
          'number': 12,
          'status': 'skipped',
          'importedPeriods': <String>[],
          'skippedPeriods': ['Nov-24 (Already Paid)'],
          'message': 'All periods already paid.',
        },
        {
          'street': 'Fake "Street"',
          'number': 999,
          'status': 'error',
          'importedPeriods': <String>[],
          'skippedPeriods': <String>[],
          'message': 'Address not found.',
        },
      ];

      final csvStr = AdminBulkPaymentImportScreen.generateResultCsvString(results);
      expect(csvStr.contains('"Street","Number","Status","ImportedPeriods","SkippedPeriods","Message"'), isTrue);
      expect(csvStr.contains('"Almendros","101","ok","Nov-24; Dec-24","","Imported 2 period(s)."'), isTrue);
      expect(csvStr.contains('"Fake ""Street""","999","error","","","Address not found."'), isTrue);
    });
  });

  group('AdminBulkPaymentImportScreen - Widget UI', () {
    testWidgets('renders starting period selector and copies template to clipboard', (tester) async {
      await tester.pumpWidget(_wrapWithL10n(const AdminBulkPaymentImportScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Bulk Previous Payments Import'), findsNWidgets(2)); // AppBar + Header title
      expect(find.text('Starting Period'), findsOneWidget);
      expect(find.text('End Period (Current)'), findsOneWidget);
      expect(find.text('Download Sample Template'), findsOneWidget);
      expect(find.text('Download All Addresses Template'), findsOneWidget);
      expect(find.text('Copy Template'), findsOneWidget);

      // Tap Copy Template
      await tester.tap(find.text('Copy Template'));
      await tester.pumpAndSettle();

      expect(copiedClipboardText, isNotNull);
      expect(copiedClipboardText!.contains('"Street","Number"'), isTrue);
      expect(find.text('CSV Template copied to clipboard'), findsOneWidget);
    });
  });
}
