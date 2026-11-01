import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:suburban_life/core/services/temp_image_cleanup_service.dart';
import 'package:suburban_life/features/qr_access/qr_scanner_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

void main() {
  late Directory testTempDir;

  setUp(() {
    FakeBackendHelper.setUp();
    TempImageCleanupService.resetHelperForTesting();
    testTempDir = Directory.systemTemp.createTempSync('catania_temp_img_test_');
  });

  tearDown(() {
    if (testTempDir.existsSync()) {
      testTempDir.deleteSync(recursive: true);
    }
  });

  Widget wrapWithApp(Widget child) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }

  group('TempImageCleanupService unit tests', () {
    test('deletes temporary XFile and Android scaled_ raw companion capture', () async {
      final rawCompanion = File('${testTempDir.path}/capture_001.jpg')..writeAsBytesSync([1, 2, 3, 4]);
      final scaledCapture = File('${testTempDir.path}/scaled_capture_001.jpg')..writeAsBytesSync([5, 6, 7]);

      expect(rawCompanion.existsSync(), isTrue);
      expect(scaledCapture.existsSync(), isTrue);

      final deleted = await TempImageCleanupService.deleteTempXFile(XFile(scaledCapture.path));
      expect(deleted, isTrue);
      expect(scaledCapture.existsSync(), isFalse);
      expect(rawCompanion.existsSync(), isFalse);
    });

    test('never deletes files outside allowed temporary/cache directories', () async {
      final nonTempRoot = Directory('${Directory.current.path}/build/test_non_temp_guard')
        ..createSync(recursive: true);
      addTearDown(() {
        if (nonTempRoot.existsSync()) {
          nonTempRoot.deleteSync(recursive: true);
        }
      });

      final userGalleryFile = File('${nonTempRoot.path}/family_photo.jpg')..writeAsBytesSync([10, 20, 30]);

      final deleted = await TempImageCleanupService.deleteTempXFile(XFile(userGalleryFile.path));
      expect(deleted, isFalse);
      expect(userGalleryFile.existsSync(), isTrue);
    });

    test('purgeStalePickerImages removes stale top-level images while preserving fresh files and subdirectories', () async {
      final staleImg = File('${testTempDir.path}/scaled_old_plate.jpg')..writeAsBytesSync([1, 2, 3]);
      staleImg.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 2)));

      final freshImg = File('${testTempDir.path}/scaled_fresh_plate.jpg')..writeAsBytesSync([4, 5, 6]);

      final subDir = Directory('${testTempDir.path}/transparency_cache')..createSync(recursive: true);
      final cachedDocImg = File('${subDir.path}/important_cached_doc.jpg')..writeAsBytesSync([7, 8, 9]);
      cachedDocImg.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 5)));

      final purgedCount = await TempImageCleanupService.purgeStalePickerImages(
        maxAge: const Duration(minutes: 30),
        overrideCacheDirPaths: [testTempDir.path],
      );

      expect(purgedCount, equals(1));
      expect(staleImg.existsSync(), isFalse);
      expect(freshImg.existsSync(), isTrue);
      expect(cachedDocImg.existsSync(), isTrue);
    });
  });

  group('QrScannerScreen - Automatic Device Photo Cleanup', () {
    testWidgets('removes ID and plate photos from device storage immediately after Cloud Storage upload and on retake', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final firstIdFile = File('${testTempDir.path}/scaled_id_first.jpg')..writeAsBytesSync([1, 2, 3]);
      final retakeIdRawFile = File('${testTempDir.path}/id_retake.jpg')..writeAsBytesSync([4, 5, 6, 7]);
      final retakeIdScaledFile = File('${testTempDir.path}/scaled_id_retake.jpg')..writeAsBytesSync([8, 9]);
      final plateRawFile = File('${testTempDir.path}/plate_capture.jpg')..writeAsBytesSync([10, 11, 12]);
      final plateScaledFile = File('${testTempDir.path}/scaled_plate_capture.jpg')..writeAsBytesSync([13, 14]);

      final queuedPhotos = <XFile>[
        XFile(firstIdFile.path),
        XFile(retakeIdScaledFile.path),
        XFile(plateScaledFile.path),
      ];
      int pickIndex = 0;

      FakeBackendHelper.functions.registerHandler('validateAndRegisterQrAccess', (params) {
        if (params?['mode'] == 'validate_only') {
          return {
            'granted': true,
            'isExit': false,
            'qrData': {
              'id': 'qr_cleanup_1',
              'creatorUid': 'resident_1',
              'guestName': 'Cleanup Visitor',
              'vehicleType': 'car',
              'vehiclePlates': 'MEM-001',
              'passengers': 2,
              'type': 'temporary',
            },
          };
        }
        return {'granted': true, 'isExit': false, 'logId': 'log_cleanup_1'};
      });

      await tester.pumpWidget(
        wrapWithApp(
          Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                key: const ValueKey('open_scanner_btn'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QrScannerScreen(
                        photoPickerOverride: () async => queuedPhotos[pickIndex++],
                      ),
                    ),
                  );
                },
                child: const Text('Open Scanner'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open_scanner_btn')));
      await tester.pumpAndSettle();

      // Simulate scanning QR code
      final mobileScanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      mobileScanner.onDetect?.call(
        BarcodeCapture(barcodes: const [Barcode(rawValue: 'qr_cleanup_1')]),
      );
      await tester.pumpAndSettle();

      // MobileScanner should unmount when not actively scanning to free camera/GPU memory
      expect(find.byType(MobileScanner), findsNothing);

      // 1. Capture first ID photo
      final idBtn = find.byKey(const ValueKey('capture_id_photo_button'));
      await tester.ensureVisible(idBtn);
      await tester.pumpAndSettle();
      await tester.tap(idBtn);
      await tester.pumpAndSettle();
      expect(pickIndex, equals(1));
      expect(firstIdFile.existsSync(), isTrue);

      // 2. Retake ID photo -> first ID photo should be immediately removed from device
      await tester.ensureVisible(idBtn);
      await tester.pumpAndSettle();
      await tester.tap(idBtn);
      await tester.pumpAndSettle();
      expect(pickIndex, equals(2));
      expect(firstIdFile.existsSync(), isFalse);
      expect(retakeIdScaledFile.existsSync(), isTrue);
      expect(retakeIdRawFile.existsSync(), isTrue);

      // 3. Capture Plate photo
      final plateBtn = find.byKey(const ValueKey('capture_plate_photo_button'));
      await tester.ensureVisible(plateBtn);
      await tester.pumpAndSettle();
      await tester.tap(plateBtn);
      await tester.pumpAndSettle();
      expect(pickIndex, equals(3));
      expect(plateScaledFile.existsSync(), isTrue);
      expect(plateRawFile.existsSync(), isTrue);

      // 4. Tap Allow Access -> uploads to Cloud Storage and deletes all local device files
      final allowBtn = find.byKey(const ValueKey('allow_access_button'));
      await tester.ensureVisible(allowBtn);
      await tester.pumpAndSettle();
      await tester.tap(allowBtn);
      await tester.pumpAndSettle();

      expect(FakeBackendHelper.storage.uploadedFiles.length, equals(2));
      expect(retakeIdScaledFile.existsSync(), isFalse);
      expect(retakeIdRawFile.existsSync(), isFalse);
      expect(plateScaledFile.existsSync(), isFalse);
      expect(plateRawFile.existsSync(), isFalse);

      final commitParams = FakeBackendHelper.functions.callHistory.last['parameters'] as Map<String, dynamic>;
      expect(commitParams['visitorIdPhotoUrl'], startsWith('https://fake-storage.local/visitor_ids/'));
      expect(commitParams['visitorPlatePhotoUrl'], startsWith('https://fake-storage.local/visitor_plates/'));
    });

    testWidgets('removes un-uploaded photos from device when guard taps Scan Again or closes screen', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final abandonedPlateFile = File('${testTempDir.path}/scaled_abandoned_plate.jpg')..writeAsBytesSync([1, 2, 3]);
      final disposedIdFile = File('${testTempDir.path}/scaled_disposed_id.jpg')..writeAsBytesSync([4, 5, 6]);
      final files = [XFile(abandonedPlateFile.path), XFile(disposedIdFile.path)];
      int idx = 0;

      FakeBackendHelper.functions.registerHandler('validateAndRegisterQrAccess', (params) {
        return {
          'granted': true,
          'isExit': false,
          'qrData': {
            'id': 'qr_abandon_1',
            'creatorUid': 'resident_1',
            'guestName': 'Abandoned Scan Visitor',
            'vehicleType': 'car',
            'vehiclePlates': 'ABN-999',
            'type': 'temporary',
          },
        };
      });

      await tester.pumpWidget(
        wrapWithApp(
          QrScannerScreen(
            photoPickerOverride: () async => files[idx++],
          ),
        ),
      );
      await tester.pump();

      final mobileScanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      mobileScanner.onDetect?.call(
        BarcodeCapture(barcodes: const [Barcode(rawValue: 'qr_abandon_1')]),
      );
      await tester.pumpAndSettle();

      final plateBtn = find.byKey(const ValueKey('capture_plate_photo_button'));
      await tester.ensureVisible(plateBtn);
      await tester.pumpAndSettle();
      await tester.tap(plateBtn);
      await tester.pumpAndSettle();
      expect(idx, equals(1));
      expect(abandonedPlateFile.existsSync(), isTrue);

      final scanAgainBtn = find.byKey(const ValueKey('scan_again_button'));
      await tester.ensureVisible(scanAgainBtn);
      await tester.pumpAndSettle();
      await tester.tap(scanAgainBtn);
      await tester.pumpAndSettle();

      expect(abandonedPlateFile.existsSync(), isFalse);
      expect(find.byType(MobileScanner), findsOneWidget);

      // Scan again, capture ID photo, and dispose screen -> should also delete un-uploaded photo
      final mobileScanner2 = tester.widget<MobileScanner>(find.byType(MobileScanner));
      mobileScanner2.onDetect?.call(
        BarcodeCapture(barcodes: const [Barcode(rawValue: 'qr_abandon_1')]),
      );
      await tester.pumpAndSettle();

      final idBtn = find.byKey(const ValueKey('capture_id_photo_button'));
      await tester.ensureVisible(idBtn);
      await tester.pumpAndSettle();
      await tester.tap(idBtn);
      await tester.pumpAndSettle();
      expect(idx, equals(2));
      expect(disposedIdFile.existsSync(), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(disposedIdFile.existsSync(), isFalse);
    });
  });
}
