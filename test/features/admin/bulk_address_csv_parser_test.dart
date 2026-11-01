import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/features/admin/admin_bulk_address_import_screen.dart';
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

  group('AdminBulkAddressImportScreen - CSV Parser & Counter', () {
    test('parses address ranges with exclusions and standard headers', () {
      const csv = 'streetName,initialNumber,finalNumber,exclusions\n'
          '"Avenida Olmos",1,50,"12,14"\n'
          '"Calle Robles",10,30,""\n';

      final items = AdminBulkAddressImportScreen.parseAddressCsvContent(csv);

      expect(items.length, equals(2));
      expect(items[0]['streetName'], equals('Avenida Olmos'));
      expect(items[0]['initialNumber'], equals(1));
      expect(items[0]['finalNumber'], equals(50));
      expect(items[0]['exclusions'], equals('12,14'));

      expect(items[1]['streetName'], equals('Calle Robles'));
      expect(items[1]['initialNumber'], equals(10));
      expect(items[1]['finalNumber'], equals(30));
    });

    test('strips UTF-8 BOM character from the beginning of file content', () {
      const csvWithBom = '\uFEFFstreetName,initialNumber,finalNumber,exclusions\n'
          'Paseo del Valle,100,105,""\n';

      final items = AdminBulkAddressImportScreen.parseAddressCsvContent(csvWithBom);
      expect(items.length, equals(1));
      expect(items[0]['streetName'], equals('Paseo del Valle'));
    });

    test('auto-detects semicolon and tab delimiters and single-number columns', () {
      const csvSemicolon = 'calle;desde;hasta;exclusiones\n'
          'Calle Real;1;10;5\n';

      final items = AdminBulkAddressImportScreen.parseAddressCsvContent(csvSemicolon);
      expect(items.length, equals(1));
      expect(items[0]['streetName'], equals('Calle Real'));
      expect(items[0]['initialNumber'], equals(1));
      expect(items[0]['finalNumber'], equals(10));
      expect(items[0]['exclusions'], equals('5'));

      const singleColCsv = 'street\tnumber\nRoble\t42\n';
      final singleItems = AdminBulkAddressImportScreen.parseAddressCsvContent(singleColCsv);
      expect(singleItems.length, equals(1));
      expect(singleItems[0]['initialNumber'], equals(42));
      expect(singleItems[0]['finalNumber'], equals(42));
    });

    test('calculateTotalAddressCount excludes only numbers within range', () {
      final items = [
        {
          'streetName': 'Avenida Olmos',
          'initialNumber': 1,
          'finalNumber': 10,
          'exclusions': '2, 4, 99', // 99 is outside 1-10 range and ignored
        },
        {
          'streetName': 'Calle Roble',
          'initialNumber': 20,
          'finalNumber': 25,
          'exclusions': '',
        },
      ];

      final total = AdminBulkAddressImportScreen.calculateTotalAddressCount(items);
      expect(total, equals(14));
    });
  });

  group('AdminBulkAddressImportScreen - Widget Flows', () {
    testWidgets('copies CSV template to clipboard and shows snackbar', (tester) async {
      await tester.pumpWidget(_wrapWithL10n(const AdminBulkAddressImportScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();

      expect(copiedClipboardText, contains('streetName,initialNumber,finalNumber,exclusions'));
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('renders parsed preview, invokes adminBulkImportAddresses, and resets', (tester) async {
      FakeBackendHelper.functions.registerHandler('adminBulkImportAddresses', (params) {
        final items = params?['items'] as List?;
        expect(items?.length, equals(1));
        return {'createdCount': 8, 'skippedCount': 2};
      });

      final parsed = AdminBulkAddressImportScreen.parseAddressCsvContent(
        'streetName,initialNumber,finalNumber,exclusions\n"Avenida Olmos",1,10,"2,4"\n',
      );

      await tester.pumpWidget(
        _wrapWithL10n(
          AdminBulkAddressImportScreen(
            initialParsedItems: parsed,
            initialFileName: 'addresses.csv',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Avenida Olmos (Range 1 - 10)'), findsOneWidget);
      expect(find.textContaining('8 addresses to create'), findsOneWidget);

      final importBtn = find.byIcon(Icons.check_circle);
      await tester.ensureVisible(importBtn);
      await tester.tap(importBtn);
      await tester.pumpAndSettle();

      expect(FakeBackendHelper.functions.callHistory.last['name'], equals('adminBulkImportAddresses'));
      expect(find.byIcon(Icons.task_alt), findsOneWidget);

      // Dismiss SnackBar before tapping reset button
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      final resetBtn = find.byIcon(Icons.refresh);
      await tester.ensureVisible(resetBtn);
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.task_alt), findsNothing);
    });
  });
}
