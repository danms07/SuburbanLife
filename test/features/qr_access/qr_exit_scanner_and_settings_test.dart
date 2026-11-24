import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/features/admin/admin_settings_screen.dart';
import 'package:suburban_life/features/qr_access/manage_qr_screen.dart';
import 'package:suburban_life/features/qr_access/qr_scanner_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
  });

  Widget wrapWithApp(Widget child, {Locale locale = const Locale('en')}) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }

  group('AdminSettingsScreen - Collapsible Cards & Real-Time Auto-Save', () {
    testWidgets(
      'starts with collapsible cards collapsed and auto-saves scanOnExitEnabled in real time when toggled',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(wrapWithApp(const AdminSettingsScreen()));
        await tester.pumpAndSettle();

        // All 5 collapsible settings cards are visible and collapsed initially
        expect(find.byKey(const ValueKey('settings_card_payment')), findsOneWidget);
        expect(find.byKey(const ValueKey('settings_card_access_control')), findsOneWidget);
        expect(find.byKey(const ValueKey('settings_card_rejection_reasons')), findsOneWidget);
        expect(find.byKey(const ValueKey('settings_card_smtp')), findsOneWidget);
        expect(find.byKey(const ValueKey('settings_card_email_template')), findsOneWidget);
        expect(find.byKey(const ValueKey('scan_on_exit_switch')), findsNothing);
        expect(find.text('Save Settings'), findsNothing);

        // Expand Access Control & QR card
        await tester.tap(find.text('Access Control & QR'));
        await tester.pumpAndSettle();

        final switchFinder = find.byKey(const ValueKey('scan_on_exit_switch'));
        expect(switchFinder, findsOneWidget);
        expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);

        // Toggle Scan on exit ON -> persists immediately in real time without manual Save button
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);

        final savedDoc = await FakeBackendHelper.db.getDocument('config', 'app_settings');
        expect(savedDoc?['scanOnExitEnabled'], isTrue);
        expect(find.byKey(const ValueKey('settings_autosave_status')), findsOneWidget);
      },
    );

    testWidgets(
      'loads existing scanOnExitEnabled = true and renders Spanish collapsible cards and auto-save hint',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        FakeBackendHelper.db.seedDocument('config', 'app_settings', {
          'paymentCutoffDay': 5,
          'gracePeriodDays': 10,
          'timeZone': 'America/Mexico_City',
          'scanOnExitEnabled': true,
        });

        await tester.pumpWidget(
          wrapWithApp(const AdminSettingsScreen(), locale: const Locale('es')),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Los interruptores y ajustes generales se guardan automáticamente'),
          findsOneWidget,
        );

        await tester.tap(find.text('Control de Acceso y QR'));
        await tester.pumpAndSettle();

        final switchFinder = find.byKey(const ValueKey('scan_on_exit_switch'));
        expect(switchFinder, findsOneWidget);
        expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
      },
    );

    testWidgets(
      'auto-saves general settings & SMTP switches in real time while requiring manual save only for SMTP server config and custom email template',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        FakeBackendHelper.db.seedDocument('config', 'smtp_settings', {
          'enabled': false,
          'secure': false,
          'host': 'smtp.initial.com',
          'port': 587,
          'user': 'admin@initial.com',
          'pass': 'InitialPass123!',
          'senderEmail': 'noreply@initial.com',
          'senderName': 'Catania Admin',
          'customSubject': 'Initial Subject',
          'customBody': 'Initial Body',
        });

        await tester.pumpWidget(wrapWithApp(const AdminSettingsScreen()));
        await tester.pumpAndSettle();

        // 1. Expand Payment & Grace Period card and change Timezone -> auto-saves immediately
        await tester.tap(find.text('Payment & Grace Period'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('timezone_dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('UTC').last);
        await tester.pumpAndSettle();

        final appDocAfterTz = await FakeBackendHelper.db.getDocument('config', 'app_settings');
        expect(appDocAfterTz?['timeZone'], 'UTC');

        // 2. Expand SMTP Email Service and type unsaved host text, then toggle SMTP Enabled switch
        await tester.tap(find.text('SMTP Email Service'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('smtp_host_field')),
          'smtp.unsaved.com',
        );
        await tester.pump();

        // Toggling smtp_enabled_switch auto-saves enabled=true immediately WITHOUT saving unsaved host text
        await tester.tap(find.byKey(const ValueKey('smtp_enabled_switch')));
        await tester.pumpAndSettle();

        final smtpAfterSwitch = await FakeBackendHelper.db.getDocument('config', 'smtp_settings');
        expect(smtpAfterSwitch?['enabled'], isTrue);
        expect(smtpAfterSwitch?['host'], 'smtp.initial.com');

        // Expand Custom Welcome Email Template card and type an unsaved subject edit
        final templateCard = find.byKey(
          const ValueKey('settings_card_email_template'),
        );
        await tester.ensureVisible(templateCard);
        await tester.pumpAndSettle();
        await tester.tap(templateCard);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('email_template_subject_field')),
          'New Custom Subject',
        );
        await tester.pump();

        // 3. Click 'Save SMTP Server' -> saves host='smtp.unsaved.com' while keeping saved template ('Initial Subject')
        final saveSmtpBtn = find.byKey(const ValueKey('save_smtp_config_button'));
        await tester.ensureVisible(saveSmtpBtn);
        await tester.pumpAndSettle();
        await tester.tap(saveSmtpBtn);
        await tester.pumpAndSettle();

        final smtpAfterServerSave = await FakeBackendHelper.db.getDocument('config', 'smtp_settings');
        expect(smtpAfterServerSave?['host'], 'smtp.unsaved.com');
        expect(smtpAfterServerSave?['customSubject'], 'Initial Subject');

        // 4. Click 'Save Email Template' -> now persists 'New Custom Subject'
        final saveTemplateBtn = find.byKey(
          const ValueKey('save_email_template_button'),
        );
        await tester.ensureVisible(saveTemplateBtn);
        await tester.pumpAndSettle();
        await tester.tap(saveTemplateBtn);
        await tester.pumpAndSettle();

        final smtpAfterTemplateSave = await FakeBackendHelper.db.getDocument('config', 'smtp_settings');
        expect(smtpAfterTemplateSave?['host'], 'smtp.unsaved.com');
        expect(smtpAfterTemplateSave?['customSubject'], 'New Custom Subject');
      },
    );
  });

  group('ManageQrScreen - Resident INSIDE status badge', () {
    testWidgets('renders INSIDE badge only for QR passes where isInside == true', (tester) async {
      FakeBackendHelper.auth.emitUser(
        AppUser(uid: 'resident_1', email: 'res@catania.mx', displayName: 'Resident One'),
      );

      FakeBackendHelper.db.seedDocument('qr_codes', 'qr_inside', {
        'id': 'qr_inside',
        'creatorUid': 'resident_1',
        'guestName': 'Carlos Inside',
        'status': 'active',
        'isInside': true,
        'timestamp': DateTime(2026, 10, 20, 14, 0).millisecondsSinceEpoch,
      });

      FakeBackendHelper.db.seedDocument('qr_codes', 'qr_outside', {
        'id': 'qr_outside',
        'creatorUid': 'resident_1',
        'guestName': 'Elena Outside',
        'status': 'active',
        'isInside': false,
        'timestamp': DateTime(2026, 10, 20, 12, 0).millisecondsSinceEpoch,
      });

      await tester.pumpWidget(wrapWithApp(const ManageQrScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Carlos Inside'), findsOneWidget);
      expect(find.text('Elena Outside'), findsOneWidget);
      expect(find.byKey(const ValueKey('qr_inside_badge_qr_inside')), findsOneWidget);
      expect(find.byKey(const ValueKey('qr_inside_badge_qr_outside')), findsNothing);
      expect(find.text('INSIDE'), findsOneWidget);
      expect(find.byKey(const Key('qr_codes_retention_banner')), findsOneWidget);
      expect(
        find.text(
          'Inactive QR passes (expired, used, or revoked) are automatically deleted after 7 days. Active permanent passes do not expire.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders Spanish 7-day retention banner even when QR list is empty', (tester) async {
      FakeBackendHelper.auth.emitUser(
        AppUser(uid: 'resident_empty', email: 'empty@catania.mx', displayName: 'Resident Empty'),
      );

      await tester.pumpWidget(wrapWithApp(const ManageQrScreen(), locale: const Locale('es')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('qr_codes_retention_banner')), findsOneWidget);
      expect(
        find.text(
          'Los pases QR inactivos (vencidos, usados o revocados) se eliminan automáticamente después de 7 días. Los pases permanentes activos no vencen.',
        ),
        findsOneWidget,
      );
    });
  });

  group('QrScannerScreen - Fast Guard Exit Scan Flow', () {
    testWidgets('renders exit scan overlay without mandatory photo capture and registers exit', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final entryEpochMs = DateTime(2026, 10, 20, 9, 45).millisecondsSinceEpoch;

      FakeBackendHelper.functions.registerHandler('validateAndRegisterQrAccess', (params) {
        if (params?['mode'] == 'validate_only') {
          return {
            'granted': true,
            'isExit': true,
            'openLog': {
              'id': 'log_open_42',
              'timestamp': entryEpochMs,
              'visitorIdPhotoUrl': 'https://fake-storage.local/id_photo.jpg',
              'visitorPlatePhotoUrl': 'https://fake-storage.local/plate_photo.jpg',
            },
            'qrData': {
              'id': 'qr_exit_test',
              'creatorUid': 'resident_1',
              'guestName': 'Supplier Exit Test',
              'addressDisplay': 'Loreto #10',
              'vehicleType': 'car',
              'vehiclePlates': 'EXIT-777',
              'passengers': 2,
              'type': 'temporary',
            },
          };
        }
        return {
          'granted': true,
          'isExit': true,
          'logId': 'log_open_42',
        };
      });

      await tester.pumpWidget(wrapWithApp(const QrScannerScreen()));
      await tester.pump();

      // Simulate scanning QR code via MobileScanner callback
      final mobileScanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      mobileScanner.onDetect?.call(
        BarcodeCapture(
          barcodes: const [Barcode(rawValue: 'qr_exit_test')],
        ),
      );
      await tester.pumpAndSettle();

      // Verify Fast Exit UI is rendered without camera capture buttons, including destination address
      expect(find.text('Visitor Exit Ready'), findsOneWidget);
      expect(find.textContaining('Supplier Exit Test'), findsOneWidget);
      expect(find.byKey(const ValueKey('qr_scanner_destination_address')), findsOneWidget);
      expect(find.text('Destination: Loreto #10'), findsOneWidget);
      expect(find.text('Visitor ID Photo'), findsOneWidget);
      expect(find.text('Vehicle Plate Photo'), findsOneWidget);
      expect(find.text('Capture ID Photo'), findsNothing);
      expect(find.text('Capture Plate Photo'), findsNothing);

      final exitNotesField = find.byKey(const ValueKey('exit_notes_field'));
      final registerExitBtn = find.byKey(const ValueKey('register_exit_button'));
      expect(exitNotesField, findsOneWidget);
      expect(registerExitBtn, findsOneWidget);

      await tester.enterText(exitNotesField, 'Exited smoothly');
      await tester.ensureVisible(registerExitBtn);
      await tester.pumpAndSettle();
      await tester.tap(registerExitBtn);
      await tester.pumpAndSettle();

      // Verify SnackBar confirmation and second Cloud Function call payload
      expect(find.text('Visitor exit registered successfully.'), findsOneWidget);
      expect(FakeBackendHelper.functions.callHistory.length, equals(2));
      final commitParams = FakeBackendHelper.functions.callHistory.last['parameters'] as Map<String, dynamic>;
      expect(commitParams['qrId'], equals('qr_exit_test'));
      expect(commitParams['mode'], equals('validate_and_register'));
      expect(commitParams['isAllowed'], isTrue);
      expect(commitParams['visitorIdPhotoUrl'], isEmpty);
      expect(commitParams['visitorPlatePhotoUrl'], isEmpty);
      expect(commitParams['reason'], equals('Exited smoothly'));
    });

    testWidgets('returns to guard main screen after granting access or registering exit', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool isExitMode = false;
      FakeBackendHelper.functions.registerHandler('validateAndRegisterQrAccess', (params) {
        if (params?['mode'] == 'validate_only') {
          return {
            'granted': true,
            'isExit': isExitMode,
            'qrData': {
              'id': 'qr_nav_test',
              'creatorUid': 'resident_1',
              'guestName': 'Guest Nav Test',
              'vehicleType': 'car',
              'vehiclePlates': 'NAV-123',
              'passengers': 1,
              'type': 'temporary',
            },
          };
        }
        return {
          'granted': true,
          'isExit': isExitMode,
          'logId': 'log_nav_1',
        };
      });

      await tester.pumpWidget(
        wrapWithApp(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('guard_main_scan_btn'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
                    );
                  },
                  child: const Text('Guard Main Scan QR'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Entry access flow: push QrScannerScreen from guard main screen
      await tester.tap(find.byKey(const ValueKey('guard_main_scan_btn')));
      await tester.pumpAndSettle();
      expect(find.byType(QrScannerScreen), findsOneWidget);

      var mobileScanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      mobileScanner.onDetect?.call(
        BarcodeCapture(barcodes: const [Barcode(rawValue: 'qr_nav_test')]),
      );
      await tester.pumpAndSettle();

      final allowBtn = find.text('Allow Access');
      expect(allowBtn, findsOneWidget);
      await tester.ensureVisible(allowBtn);
      await tester.pumpAndSettle();
      await tester.tap(allowBtn);
      await tester.pumpAndSettle();

      // Should pop back to the guard main screen
      expect(find.byType(QrScannerScreen), findsNothing);
      expect(find.byKey(const ValueKey('guard_main_scan_btn')), findsOneWidget);
      expect(find.text('Access registered successfully'), findsOneWidget);

      // 2. Exit scan flow: push QrScannerScreen again
      isExitMode = true;
      await tester.tap(find.byKey(const ValueKey('guard_main_scan_btn')));
      await tester.pumpAndSettle();
      expect(find.byType(QrScannerScreen), findsOneWidget);

      mobileScanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      mobileScanner.onDetect?.call(
        BarcodeCapture(barcodes: const [Barcode(rawValue: 'qr_nav_test')]),
      );
      await tester.pumpAndSettle();

      final registerExitBtn = find.byKey(const ValueKey('register_exit_button'));
      expect(registerExitBtn, findsOneWidget);
      await tester.ensureVisible(registerExitBtn);
      await tester.pumpAndSettle();
      await tester.tap(registerExitBtn);
      await tester.pumpAndSettle();

      // Should pop back to the guard main screen
      expect(find.byType(QrScannerScreen), findsNothing);
      expect(find.byKey(const ValueKey('guard_main_scan_btn')), findsOneWidget);
    });

    testWidgets(
      'blocks scan and action buttons and displays floating wheel overlay while validating and registering QR access',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final validationCompleter = Completer<Map<String, dynamic>>();
        final registrationCompleter = Completer<Map<String, dynamic>>();

        FakeBackendHelper.functions.registerHandler('validateAndRegisterQrAccess', (params) {
          if (params?['mode'] == 'validate_only') {
            return validationCompleter.future;
          }
          return registrationCompleter.future;
        });

        await tester.pumpWidget(wrapWithApp(const QrScannerScreen(), locale: const Locale('en')));
        await tester.pump();

        // Trigger QR detection twice in rapid succession to simulate duplicate scanner frames
        final mobileScanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
        mobileScanner.onDetect?.call(
          BarcodeCapture(barcodes: const [Barcode(rawValue: 'qr_busy_test')]),
        );
        mobileScanner.onDetect?.call(
          BarcodeCapture(barcodes: const [Barcode(rawValue: 'qr_busy_test')]),
        );
        await tester.pump();
        await tester.pump();

        // Only one validation request should be in flight; floating wheel overlay & wait hint visible
        expect(FakeBackendHelper.functions.callHistory.length, equals(1));
        final loadingOverlay = find.byKey(const ValueKey('qr_scanner_loading_overlay'));
        expect(loadingOverlay, findsOneWidget);
        expect(
          find.descendant(of: loadingOverlay, matching: find.byType(CircularProgressIndicator)),
          findsOneWidget,
        );
        expect(find.text('Validating QR Code...'), findsOneWidget);
        expect(
          find.text('Please wait while the operation completes. Do not tap any other buttons.'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.error_outline), findsNothing);

        // Scan Again button is visible in disabled state and cannot reset or trigger another scan
        final scanAgainFinder = find.byKey(const ValueKey('scan_again_button'));
        expect(scanAgainFinder, findsOneWidget);
        expect(tester.widget<OutlinedButton>(scanAgainFinder).onPressed, isNull);

        await tester.tap(scanAgainFinder, warnIfMissed: false);
        await tester.pump();
        expect(find.byType(MobileScanner), findsNothing);
        expect(FakeBackendHelper.functions.callHistory.length, equals(1));

        // Resolve visitor info lookup
        validationCompleter.complete({
          'granted': true,
          'isExit': false,
          'qrData': {
            'id': 'qr_busy_test',
            'creatorUid': 'resident_1',
            'guestName': 'Delayed Visitor',
            'vehicleType': 'car',
            'vehiclePlates': 'WAIT-101',
            'passengers': 2,
            'type': 'temporary',
          },
        });
        await tester.pumpAndSettle();

        expect(loadingOverlay, findsNothing);
        expect(find.textContaining('Delayed Visitor'), findsOneWidget);

        final allowBtnFinder = find.byKey(const ValueKey('allow_access_button'));
        final denyBtnFinder = find.byKey(const ValueKey('deny_access_button'));
        expect(tester.widget<OutlinedButton>(scanAgainFinder).onPressed, isNotNull);
        expect(tester.widget<ElevatedButton>(allowBtnFinder).onPressed, isNotNull);
        expect(tester.widget<ElevatedButton>(denyBtnFinder).onPressed, isNotNull);

        // Tap Allow Access and keep registration pending
        await tester.ensureVisible(allowBtnFinder);
        await tester.pumpAndSettle();
        await tester.tap(allowBtnFinder);
        await tester.pump();
        await tester.pump();

        expect(FakeBackendHelper.functions.callHistory.length, equals(2));
        expect(loadingOverlay, findsOneWidget);
        expect(find.text('Processing access request...'), findsOneWidget);
        expect(tester.widget<ElevatedButton>(allowBtnFinder).onPressed, isNull);
        expect(tester.widget<ElevatedButton>(denyBtnFinder).onPressed, isNull);
        expect(tester.widget<OutlinedButton>(scanAgainFinder).onPressed, isNull);

        // Additional tap during in-flight registration is blocked
        await tester.tap(allowBtnFinder, warnIfMissed: false);
        await tester.pump();
        expect(FakeBackendHelper.functions.callHistory.length, equals(2));

        registrationCompleter.complete({
          'granted': true,
          'isExit': false,
          'logId': 'log_busy_1',
        });
        await tester.pumpAndSettle();
        expect(find.text('Access registered successfully'), findsOneWidget);
      },
    );

    testWidgets(
      'displays Spanish localized floating loading overlay messages while validating QR code',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final validationCompleter = Completer<Map<String, dynamic>>();
        FakeBackendHelper.functions.registerHandler('validateAndRegisterQrAccess', (_) {
          return validationCompleter.future;
        });

        await tester.pumpWidget(wrapWithApp(const QrScannerScreen(), locale: const Locale('es')));
        await tester.pump();

        final mobileScanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
        mobileScanner.onDetect?.call(
          BarcodeCapture(barcodes: const [Barcode(rawValue: 'qr_es_busy')]),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const ValueKey('qr_scanner_loading_overlay')), findsOneWidget);
        expect(find.text('Validando código QR...'), findsOneWidget);
        expect(
          find.text('Por favor, espere mientras se completa la operación. No presione otros botones.'),
          findsOneWidget,
        );

        validationCompleter.complete({'granted': false, 'reason': 'No encontrado'});
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'displays localized destination address on entry scan in English and Spanish without overflow on narrow mobile screens',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        FakeBackendHelper.functions.registerHandler('validateAndRegisterQrAccess', (params) {
          return {
            'granted': true,
            'isExit': false,
            'qrData': {
              'id': 'qr_dest_entry',
              'creatorUid': 'resident_1',
              'guestName': 'Lucia Visitor',
              'addressDisplay': 'Boulevard Residencial de los Alamos #142',
              'vehicleType': 'car',
              'vehiclePlates': 'DEST-142',
              'passengers': 2,
              'type': 'temporary',
            },
          };
        });

        // English check on 360x780 mobile viewport
        await tester.pumpWidget(wrapWithApp(const QrScannerScreen(), locale: const Locale('en')));
        await tester.pump();

        var mobileScanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
        mobileScanner.onDetect?.call(
          BarcodeCapture(barcodes: const [Barcode(rawValue: 'qr_dest_entry')]),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('qr_scanner_destination_address')), findsOneWidget);
        expect(
          find.text('Destination: Boulevard Residencial de los Alamos #142'),
          findsOneWidget,
        );

        // Spanish check on 360x780 mobile viewport
        await tester.pumpWidget(
          wrapWithApp(
            const QrScannerScreen(key: ValueKey('es_dest_scanner')),
            locale: const Locale('es'),
          ),
        );
        await tester.pump();

        mobileScanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
        mobileScanner.onDetect?.call(
          BarcodeCapture(barcodes: const [Barcode(rawValue: 'qr_dest_entry')]),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('qr_scanner_destination_address')), findsOneWidget);
        expect(
          find.text('Destino: Boulevard Residencial de los Alamos #142'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'localizes Admin office destination address in English and Spanish and resolves Firestore fallback when addressDisplay is omitted',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1. Admin office normalization ("Admin office #0" -> localized Admin office / Oficina de administración)
        FakeBackendHelper.functions.registerHandler('validateAndRegisterQrAccess', (params) {
          return {
            'granted': true,
            'isExit': false,
            'qrData': {
              'id': 'qr_admin_dest',
              'creatorUid': 'admin_1',
              'guestName': 'Inspector Visit',
              'addressDisplay': 'Admin office #0',
              'vehicleType': 'walking',
              'type': 'temporary',
            },
          };
        });

        await tester.pumpWidget(wrapWithApp(const QrScannerScreen(), locale: const Locale('en')));
        await tester.pump();

        var mobileScanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
        mobileScanner.onDetect?.call(
          BarcodeCapture(barcodes: const [Barcode(rawValue: 'qr_admin_dest')]),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('qr_scanner_destination_address')), findsOneWidget);
        expect(find.text('Destination: Admin office'), findsOneWidget);

        await tester.pumpWidget(
          wrapWithApp(
            const QrScannerScreen(key: ValueKey('es_admin_dest_scanner')),
            locale: const Locale('es'),
          ),
        );
        await tester.pump();

        mobileScanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
        mobileScanner.onDetect?.call(
          BarcodeCapture(barcodes: const [Barcode(rawValue: 'qr_admin_dest')]),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('qr_scanner_destination_address')), findsOneWidget);
        expect(find.text('Destino: Oficina de administración'), findsOneWidget);

        // 2. Fallback lookup via users/{creatorUid}.addressRef -> addresses/{id} when addressDisplay is omitted
        final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_fallback_1');
        FakeBackendHelper.db.seedDocument('addresses', 'addr_fallback_1', {
          'id': 'addr_fallback_1',
          'streetName': 'Av. Modena',
          'number': 25,
          'paymentStatus': 'paid',
        });
        FakeBackendHelper.db.seedDocument('users', 'resident_fallback_1', {
          'uid': 'resident_fallback_1',
          'name': 'Fallback Resident',
          'role': 'resident',
          'addressRef': addrRef,
        });

        FakeBackendHelper.functions.registerHandler('validateAndRegisterQrAccess', (params) {
          return {
            'granted': true,
            'isExit': false,
            'qrData': {
              'id': 'qr_fallback_dest',
              'creatorUid': 'resident_fallback_1',
              'guestName': 'Fallback Guest',
              'vehicleType': 'car',
              'type': 'temporary',
            },
          };
        });

        await tester.pumpWidget(
          wrapWithApp(
            const QrScannerScreen(key: ValueKey('fallback_dest_scanner')),
            locale: const Locale('en'),
          ),
        );
        await tester.pump();

        mobileScanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
        mobileScanner.onDetect?.call(
          BarcodeCapture(barcodes: const [Barcode(rawValue: 'qr_fallback_dest')]),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('qr_scanner_destination_address')), findsOneWidget);
        expect(find.text('Destination: Av. Modena #25'), findsOneWidget);
      },
    );

    testWidgets('persists initialBudgetBalance inside Payment & Grace Period settings card', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(wrapWithApp(const AdminSettingsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('settings_card_payment')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('initial_budget_balance_field')),
        '15250.50',
      );
      await tester.tap(find.byKey(const ValueKey('save_opening_balance_button')));
      await tester.pumpAndSettle();

      final savedDoc = await FakeBackendHelper.db.getDocument('config', 'app_settings');
      expect(savedDoc?['initialBudgetBalance'], equals(15250.5));
    });

    testWidgets(
      'pre-fills default welcome template body when no custom body is saved and preserves custom body when present',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(wrapWithApp(const AdminSettingsScreen()));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey('settings_card_email_template')),
        );
        await tester.tap(
          find.byKey(const ValueKey('settings_card_email_template')),
        );
        await tester.pumpAndSettle();

        final ctx = tester.element(find.byType(AdminSettingsScreen));
        final l10n = AppLocalizations.of(ctx)!;
        final bodyField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('email_template_body_field')),
        );
        expect(bodyField.controller!.text, equals(l10n.defaultWelcomeBody));

        // Now verify existing custom template is preserved on fresh load
        FakeBackendHelper.setUp();
        FakeBackendHelper.db.seedDocument('config', 'smtp_settings', {
          'customSubject': 'Custom Subject',
          'customBody': 'Custom saved welcome body for %name%',
        });

        await tester.pumpWidget(
          wrapWithApp(const AdminSettingsScreen(key: ValueKey('saved_template_reload'))),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey('settings_card_email_template')),
        );
        await tester.tap(
          find.byKey(const ValueKey('settings_card_email_template')),
        );
        await tester.pumpAndSettle();

        final savedBodyField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('email_template_body_field')),
        );
        expect(
          savedBodyField.controller!.text,
          equals('Custom saved welcome body for %name%'),
        );
      },
    );

    testWidgets(
      'stacks welcome template description cleanly above restore button on mobile Spanish viewport without vertical squishing',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          wrapWithApp(const AdminSettingsScreen(), locale: const Locale('es')),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey('settings_card_email_template')),
        );
        await tester.tap(
          find.byKey(const ValueKey('settings_card_email_template')),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        final ctx = tester.element(find.byType(AdminSettingsScreen));
        final l10n = AppLocalizations.of(ctx)!;

        // First match may be the collapsed tile subtitle; the expanded body copy
        // sits directly above reset_default_template_button with full width.
        final expandedDescription = find.text(l10n.customWelcomeEmailSubtitle).last;
        final restoreBtn = find.byKey(const ValueKey('reset_default_template_button'));

        expect(expandedDescription, findsOneWidget);
        expect(restoreBtn, findsOneWidget);

        final descRect = tester.getRect(expandedDescription);
        final btnRect = tester.getRect(restoreBtn);

        expect(descRect.width, greaterThan(220));
        expect(descRect.bottom, lessThanOrEqualTo(btnRect.top));

        final bodyField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('email_template_body_field')),
        );
        expect(bodyField.controller!.text, equals(l10n.defaultWelcomeBody));
      },
    );
  });
}
