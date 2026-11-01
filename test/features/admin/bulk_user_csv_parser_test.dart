import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/features/admin/admin_bulk_user_import_screen.dart';
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

  group('AdminBulkUserImportScreen - CSV Parser & Formatter', () {
    test('parses standard English header CSV', () {
      const csv = 'name,email,password,street,number\n'
          'John Doe,john.doe@example.com,Pass123!,Oak St,10\n'
          'Jane Smith,jane.smith@example.com,,Pine St,20\n';

      final users = AdminBulkUserImportScreen.parseUserCsv(csv);

      expect(users.length, equals(2));
      expect(users[0]['name'], equals('John Doe'));
      expect(users[0]['email'], equals('john.doe@example.com'));
      expect(users[0]['password'], equals('Pass123!'));
      expect(users[0]['streetName'], equals('Oak St'));
      expect(users[0]['number'], equals('10'));

      expect(users[1]['name'], equals('Jane Smith'));
      expect(users[1]['password'], isEmpty);
    });

    test('parses Spanish header aliases (nombre, correo, contraseña, calle, número)', () {
      const csv = 'Nombre,Correo,Contraseña,Calle,Número\n'
          'Carlos Santana,carlos@musica.com,Guitar#1,Avenida Sol,100\n';

      final users = AdminBulkUserImportScreen.parseUserCsv(csv);

      expect(users.length, equals(1));
      expect(users[0]['name'], equals('Carlos Santana'));
      expect(users[0]['email'], equals('carlos@musica.com'));
      expect(users[0]['password'], equals('Guitar#1'));
      expect(users[0]['streetName'], equals('Avenida Sol'));
      expect(users[0]['number'], equals('100'));
    });

    test('parses headerless CSV with default positional columns', () {
      const csv = 'Alice Resident,alice@test.com,SecPass89,Maple Ave,42\n'
          'Bob Resident,bob@test.com,,Elm St,99\n';

      final users = AdminBulkUserImportScreen.parseUserCsv(csv);

      expect(users.length, equals(2));
      expect(users[0]['name'], equals('Alice Resident'));
      expect(users[0]['email'], equals('alice@test.com'));
      expect(users[0]['password'], equals('SecPass89'));
      expect(users[0]['streetName'], equals('Maple Ave'));
      expect(users[0]['number'], equals('42'));
    });

    test('correctly handles quoted fields containing commas', () {
      const csv = 'name,email,password,street,number\n'
          '"Doe, John Jr.",john.jr@example.com,Pass123!,"1st Avenue, North",50\n';

      final users = AdminBulkUserImportScreen.parseUserCsv(csv);

      expect(users.length, equals(1));
      expect(users[0]['name'], equals('Doe, John Jr.'));
      expect(users[0]['streetName'], equals('1st Avenue, North'));
      expect(users[0]['number'], equals('50'));
    });

    test('filters out invalid rows with empty names or missing @ in email', () {
      const csv = 'name,email,password,street,number\n'
          ',missingname@test.com,Pass123!,Oak St,10\n'
          'Invalid Email,invalid-email-address,Pass123!,Oak St,10\n'
          'Valid User,valid@test.com,Pass123!,Oak St,10\n';

      final users = AdminBulkUserImportScreen.parseUserCsv(csv);

      expect(users.length, equals(1));
      expect(users[0]['name'], equals('Valid User'));
    });

    test('generateResultCsvString compiles and escapes result rows', () {
      final results = [
        {
          'name': 'John "Johnny" Doe',
          'email': 'john@test.com',
          'password': '',
          'streetName': 'Oak St',
          'number': '10',
          'status': 'ok',
          'assignedPassword': 'AutoPass987!',
          'emailSent': true,
          'error': null,
        }
      ];

      final csvOut = AdminBulkUserImportScreen.generateResultCsvString(results);

      expect(csvOut, contains('"John ""Johnny"" Doe"'));
      expect(csvOut, contains('"john@test.com"'));
      expect(csvOut, contains('"ok"'));
      expect(csvOut, contains('"AutoPass987!"'));
      expect(csvOut, contains('"yes"'));
    });
  });

  group('AdminBulkUserImportScreen - Widget Flows', () {
    testWidgets('displays active SMTP badge when configured and copies CSV template', (tester) async {
      FakeBackendHelper.db.seedDocument('config', 'smtp_settings', {
        'enabled': true,
        'host': 'smtp.catania.local',
      });

      await tester.pumpWidget(_wrapWithL10n(const AdminBulkUserImportScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.mark_email_read), findsOneWidget);

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();

      expect(copiedClipboardText, contains('name,email,password,street,number'));
    });

    testWidgets('processes parsed user preview via adminBulkImportResidents and copies results', (tester) async {
      FakeBackendHelper.functions.registerHandler('adminBulkImportResidents', (params) {
        final users = params?['users'] as List?;
        expect(users?.length, equals(1));
        return {
          'successCount': 1,
          'failureCount': 0,
          'results': [
            {
              'name': 'John Doe',
              'email': 'john@test.com',
              'password': '',
              'streetName': 'Oak St',
              'number': '10',
              'status': 'ok',
              'assignedPassword': 'TempPass!23',
              'addressLinked': 'Oak St #10',
              'emailSent': true,
            },
          ],
        };
      });

      final parsedUsers = AdminBulkUserImportScreen.parseUserCsv(
        'name,email,password,street,number\nJohn Doe,john@test.com,,Oak St,10\n',
      );

      await tester.pumpWidget(
        _wrapWithL10n(
          AdminBulkUserImportScreen(
            initialParsedUsers: parsedUsers,
            initialFileName: 'residents.csv',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('John Doe'), findsOneWidget);

      final importBtn = find.byIcon(Icons.person_add);
      await tester.ensureVisible(importBtn);
      await tester.tap(importBtn);
      await tester.pumpAndSettle();

      expect(FakeBackendHelper.functions.callHistory.last['name'], equals('adminBulkImportResidents'));
      expect(find.textContaining('TempPass!23'), findsOneWidget);

      // Dismiss SnackBar before tapping copy passwords button
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      final copyResultBtn = find.byIcon(Icons.content_copy).last;
      await tester.ensureVisible(copyResultBtn);
      await tester.tap(copyResultBtn);
      await tester.pumpAndSettle();

      expect(copiedClipboardText, contains('TempPass!23'));
    });
  });
}
