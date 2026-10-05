import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/features/auth/roommates_screen.dart';
import 'package:suburban_life/features/qr_access/qr_scanner_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
  });

  Widget wrapWithMaterial(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: child,
    );
  }

  testWidgets('RoommatesScreen QR scanner sheet displays camera switch button', (tester) async {
    final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_1');
    FakeBackendHelper.db.seedDocument('addresses', 'addr_1', {
      'id': 'addr_1',
      'streetName': 'Calle Roble',
      'number': 101,
      'residentUid': 'test_resident',
    });

    FakeBackendHelper.db.seedDocument('users', 'test_resident', {
      'uid': 'test_resident',
      'name': 'Resident User',
      'email': 'resident@example.com',
      'addressRef': addrRef,
    });

    FakeBackendHelper.auth.emitUser(
      AppUser(
        uid: 'test_resident',
        email: 'resident@example.com',
        displayName: 'Resident User',
      ),
    );

    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrapWithMaterial(const RoommatesScreen()));
    await tester.pumpAndSettle();

    final scanQrBtn = find.text('Scan QR Code');
    expect(scanQrBtn, findsOneWidget);
    await tester.tap(scanQrBtn);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Switch Camera'), findsAtLeastNWidgets(1));
  });

  testWidgets('QrScannerScreen displays camera switch button in AppBar and floating button', (tester) async {
    await tester.pumpWidget(wrapWithMaterial(const QrScannerScreen()));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Switch Camera'), findsAtLeastNWidgets(1));
  });
}
