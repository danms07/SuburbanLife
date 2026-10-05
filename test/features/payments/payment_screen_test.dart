import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/features/payments/payment_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
    final addressRef = FakeBackendHelper.db.createReference('addresses', 'addr_1');
    FakeBackendHelper.auth.emitUser(
      AppUser(
        uid: 'resident_test_uid',
        email: 'resident@example.com',
        displayName: 'Resident Test',
      ),
    );
    FakeBackendHelper.auth.isAdminMock = false;
    FakeBackendHelper.auth.isResidentMock = true;

    FakeBackendHelper.db.seedDocument('addresses', 'addr_1', {
      'id': 'addr_1',
      'streetName': 'Loreto',
      'number': 108,
      'paymentStatus': 'paid',
      'residentUid': 'resident_test_uid',
    });

    FakeBackendHelper.db.seedDocument('users', 'resident_test_uid', {
      'uid': 'resident_test_uid',
      'email': 'resident@example.com',
      'name': 'Resident Test',
      'role': 'resident',
      'addressRef': addressRef,
    });
  });

  Widget wrapWithMaterial(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('es'),
      home: child,
    );
  }

  testWidgets('PaymentScreen renders horizontal photo container on narrow mobile screens without layout squeezing', (tester) async {
    // Set a narrow mobile screen resolution (360 x 1400)
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrapWithMaterial(const PaymentScreen(currentUid: 'resident_test_uid')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // Verify main screen and inputs are rendered
    expect(find.byType(PaymentScreen), findsOneWidget);

    // Verify receipt photo container header
    expect(find.text('Foto del Comprobante de Pago'), findsOneWidget);

    // Verify the prompt text inside the receipt container
    final promptFinder = find.text('Se requiere una foto del comprobante de pago');
    expect(promptFinder, findsOneWidget);

    // Verify that the prompt text widget has adequate horizontal width (> 180px) and is not squished into a narrow vertical column
    final promptSize = tester.getSize(promptFinder);
    expect(promptSize.width, greaterThan(180));
    expect(promptSize.height, lessThanOrEqualTo(100));

    // Verify the camera button is placed with full width
    final buttonFinder = find.text('Tomar foto del recibo');
    expect(buttonFinder, findsOneWidget);
    expect(find.byIcon(Icons.camera_alt), findsOneWidget);
  });

  testWidgets('Entering characters in folio and amount maintains focus and updates validation without keyboard closure', (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrapWithMaterial(const PaymentScreen(currentUid: 'resident_test_uid')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // Verify initial missing validation messages
    expect(find.text('• El folio / número de autorización es obligatorio'), findsOneWidget);
    expect(find.text('• Se requiere un monto válido'), findsOneWidget);

    // Folio input field
    final folioField = find.byKey(const ValueKey('folio_field'));
    expect(folioField, findsOneWidget);

    // Tap and focus folio field
    await tester.tap(folioField);
    await tester.pump();

    final EditableText editableFolio = tester.widget(find.descendant(of: folioField, matching: find.byType(EditableText)));
    expect(editableFolio.focusNode.hasFocus, isTrue);

    // Enter single character into folio
    await tester.enterText(folioField, 'F');
    await tester.pump();

    // Verify focus is still held
    expect(editableFolio.focusNode.hasFocus, isTrue);

    // Finish typing folio
    await tester.enterText(folioField, 'FOLIO-1234');
    await tester.pump();

    // Missing folio warning should now be gone
    expect(find.text('• El folio / número de autorización es obligatorio'), findsNothing);
    // Missing amount warning should still be present
    expect(find.text('• Se requiere un monto válido'), findsOneWidget);

    // Amount input field
    final amountField = find.byKey(const ValueKey('amount_field'));
    expect(amountField, findsOneWidget);

    // Tap and focus amount field
    await tester.tap(amountField);
    await tester.pump();

    final EditableText editableAmount = tester.widget(find.descendant(of: amountField, matching: find.byType(EditableText)));
    expect(editableAmount.focusNode.hasFocus, isTrue);

    // Enter single character into amount
    await tester.enterText(amountField, '7');
    await tester.pump();

    // Verify focus is still held
    expect(editableAmount.focusNode.hasFocus, isTrue);

    // Enter full valid amount
    await tester.enterText(amountField, '750.00');
    await tester.pump();

    // Missing amount warning should now be gone
    expect(find.text('• Se requiere un monto válido'), findsNothing);

    // Missing receipt image should still remain
    expect(find.text('• Se requiere una foto del comprobante de pago'), findsOneWidget);
  });
}
