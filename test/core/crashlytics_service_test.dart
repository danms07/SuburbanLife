import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/core/widgets/error_fallback_screen.dart';
import 'package:suburban_life/features/payments/payment_service.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../helpers/fake_backend.dart';

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
  });

  group('CrashlyticsService BaaS Delegation & Production Error Reporting', () {
    test('CrashlyticsService() factory delegates all telemetry calls to Backend.crashlytics', () async {
      final crashlytics = CrashlyticsService();

      await crashlytics.setCrashlyticsCollectionEnabled(true);
      expect(FakeBackendHelper.crashlytics.isCollectionEnabled, isTrue);

      await crashlytics.setUserIdentifier('user-12345');
      expect(FakeBackendHelper.crashlytics.currentUserId, equals('user-12345'));

      await crashlytics.setCustomKey('role', 'admin');
      await crashlytics.log('Navigated to Admin dashboard');
      expect(FakeBackendHelper.crashlytics.customKeys['role'], equals('admin'));
      expect(FakeBackendHelper.crashlytics.logs, contains('Navigated to Admin dashboard'));

      await crashlytics.recordError(
        Exception('Non-fatal network timeout'),
        StackTrace.current,
        reason: 'DashboardSync',
        fatal: false,
      );

      final flutterDetails = FlutterErrorDetails(
        exception: Exception('RenderBox overflow'),
        stack: StackTrace.current,
        library: 'widgets library',
      );
      await crashlytics.recordFlutterError(flutterDetails, fatal: true);

      expect(FakeBackendHelper.crashlytics.recordedErrors.length, equals(2));
      expect(
        FakeBackendHelper.crashlytics.recordedErrors.first,
        contains('Non-fatal network timeout (fatal: false, reason: DashboardSync)'),
      );
      expect(
        FakeBackendHelper.crashlytics.recordedErrors.last,
        contains('RenderBox overflow (fatal: true)'),
      );
    });

    test('PaymentService.uploadPaymentReceipt reports storage failures to Crashlytics', () async {
      FakeBackendHelper.db.seedDocument('users', 'res_1', {
        'addressRef': FakeBackendHelper.db.createReference('addresses', 'addr_1'),
      });
      FakeBackendHelper.storage.uploadHandler = (path, data) async {
        throw Exception('Storage bucket unreachable');
      };

      final fakeXFile = XFile.fromData(
        Uint8List.fromList([1, 2, 3, 4]),
        name: 'receipt.jpg',
        path: '/virtual/receipt.jpg',
      );

      await expectLater(
        () => PaymentService().uploadPaymentReceipt(
          'res_1',
          ['2026-05'],
          1500.0,
          pickedFile: fakeXFile,
        ),
        throwsException,
      );

      expect(FakeBackendHelper.crashlytics.recordedErrors, isNotEmpty);
      expect(
        FakeBackendHelper.crashlytics.recordedErrors.single,
        contains('reason: PaymentService.uploadPaymentReceipt'),
      );
    });
  });

  group('ErrorFallbackScreen Widget Tests', () {
    testWidgets('renders localized fallback screen when wrapped with AppLocalizations', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('es')],
          locale: const Locale('es'),
          home: Builder(
            builder: (context) => ErrorFallbackScreen(
              details: FlutterErrorDetails(exception: Exception('Fatal UI error')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      // Should render non-empty title and message without throwing
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('renders standalone fallback text when no Localization ancestor exists', (tester) async {
      await tester.pumpWidget(const ErrorFallbackScreen());
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });
  });
}
