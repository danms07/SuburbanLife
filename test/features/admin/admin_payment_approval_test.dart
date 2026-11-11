import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/core/config/app_config.dart';
import 'package:suburban_life/core/widgets/storage_network_image.dart';
import 'package:suburban_life/features/admin/admin_payment_approval_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

Widget _wrapWithMaterial(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [
      Locale('en'),
      Locale('es'),
    ],
    home: child,
  );
}

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
  });

  group('AdminPaymentApprovalScreen Thumbnail & Fullscreen Viewer', () {
    testWidgets(
      'displays receipt thumbnail alongside payment details and opens full-screen viewer with 20% padding and rotate button',
      (tester) async {
        const screenWidth = 1000.0;
        const screenHeight = 800.0;
        tester.view.physicalSize = const Size(screenWidth, screenHeight);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        FakeBackendHelper.auth.emitUser(
          AppUser(
            uid: 'admin_uid',
            email: 'admin@catania.com',
            displayName: 'Admin',
          ),
        );
        FakeBackendHelper.auth.isAdminMock = true;

        final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_1');
        FakeBackendHelper.db.seedDocument('addresses', 'addr_1', {
          'id': 'addr_1',
          'streetName': '1st Avenue',
          'number': 99,
          'residentUid': 'resident_1',
        });

        FakeBackendHelper.db.seedDocument('users', 'resident_1', {
          'uid': 'resident_1',
          'name': 'Carlos Rivera',
          'email': 'carlos@catania.com',
          'role': 'resident',
          'addressRef': addrRef,
        });

        FakeBackendHelper.db.seedDocument('payments', 'pay_1', {
          'id': 'pay_1',
          'addressRef': addrRef,
          'residentUid': 'resident_1',
          'uploaderUid': 'resident_1',
          'amount': 1500.0,
          'concept': 'monthly quota',
          'folio': 'FOL-9988',
          'periods': ['2026-10'],
          'status': 'pending',
          'receiptUrl': 'https://example.com/receipt.jpg',
          'paymentDate': DateTime(2026, 10, 15).millisecondsSinceEpoch,
        });

        await tester.pumpWidget(_wrapWithMaterial(const AdminPaymentApprovalScreen()));
        await tester.pumpAndSettle();

        // 1. Verify summary card displays address and basic payment info without action buttons
        expect(find.text('1st Avenue #99'), findsOneWidget);
        expect(find.text('Carlos Rivera'), findsNothing);
        expect(find.text('\$1500.00'), findsOneWidget);
        expect(find.text('Monthly Maintenance Quota'), findsOneWidget);
        expect(find.text('Date of payment: 2026-10-15'), findsOneWidget);
        expect(find.widgetWithText(ElevatedButton, 'Approve Payment'), findsNothing);
        expect(find.byKey(const ValueKey('payment_receipt_thumbnail')), findsNothing);

        // 2. Tap the summary card to open the dedicated AdminPaymentDetailScreen
        final cardFinder = find.byKey(const ValueKey('payment_card_pay_1'));
        expect(cardFinder, findsOneWidget);
        await tester.tap(cardFinder);
        await tester.pumpAndSettle();

        // 3. Verify all payment details and address are shown on the dedicated detail screen
        expect(find.byType(AdminPaymentDetailScreen), findsOneWidget);
        expect(find.text('1st Avenue #99'), findsOneWidget);
        expect(find.text('Carlos Rivera'), findsNothing);
        expect(find.text('\$1500.00'), findsOneWidget);
        expect(find.text('Folio: FOL-9988'), findsOneWidget);
        expect(find.text('Date of payment: 2026-10-15'), findsOneWidget);
        expect(find.text('Period paid: 2026-10'), findsOneWidget);

        // Verify Approve Payment button uses AppConfig.primaryColor
        final approveBtnFinder = find.widgetWithText(ElevatedButton, 'Approve Payment');
        expect(approveBtnFinder, findsOneWidget);
        final approveBtn = tester.widget<ElevatedButton>(approveBtnFinder);
        expect(
          approveBtn.style?.backgroundColor?.resolve({}),
          equals(AppConfig.primaryColor),
        );

        // Verify thumbnail of the proof of payment expands to use the vertical space
        // and on wide screens (1000px) is positioned on the left, with payment info and buttons on the right
        final thumbFinder = find.byKey(const ValueKey('payment_receipt_thumbnail'));
        expect(thumbFinder, findsOneWidget);
        final thumbSize = tester.getSize(thumbFinder);
        expect(thumbSize.height, greaterThan(300.0));
        expect(
          tester.getTopLeft(thumbFinder).dx,
          lessThan(tester.getTopLeft(find.text('1st Avenue #99')).dx),
        );
        expect(
          tester.getTopLeft(thumbFinder).dx,
          lessThan(tester.getTopLeft(approveBtnFinder).dx),
        );

        // Verify inline rotate and full-screen buttons exist on the receipt preview
        final inlineRotatedBoxFinder = find.byKey(const ValueKey('payment_inline_rotated_box'));
        final inlineRotateBtnFinder = find.byKey(const ValueKey('payment_inline_rotate_button'));
        final fullscreenBtnFinder = find.byKey(const ValueKey('payment_fullscreen_button'));
        expect(inlineRotatedBoxFinder, findsOneWidget);
        expect(inlineRotateBtnFinder, findsOneWidget);
        expect(fullscreenBtnFinder, findsOneWidget);
        expect(tester.widget<RotatedBox>(inlineRotatedBoxFinder).quarterTurns, equals(0));

        // Rotate inline once (0 -> 1) and verify full-screen viewer inherits quarterTurns = 1
        await tester.tap(inlineRotateBtnFinder);
        await tester.pump();
        expect(tester.widget<RotatedBox>(inlineRotatedBoxFinder).quarterTurns, equals(1));

        // Click the fullscreen button to open the full-screen preview dialog
        await tester.tap(fullscreenBtnFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify full-screen dialog padding (20% of screen width and height)
        final paddingFinder = find.byKey(const ValueKey('interactive_image_padding'));
        expect(paddingFinder, findsOneWidget);
        final paddingWidget = tester.widget<Padding>(paddingFinder);
        expect(
          paddingWidget.padding,
          equals(
            const EdgeInsets.symmetric(
              horizontal: screenWidth * 0.2,
              vertical: screenHeight * 0.2,
            ),
          ),
        );

        // Verify image in full-screen dialog uses BoxFit.contain (not cropped)
        final rotatedBoxFinder = find.byKey(const ValueKey('interactive_image_rotated_box'));
        expect(rotatedBoxFinder, findsOneWidget);
        final fullScreenImageFinder = find.descendant(
          of: rotatedBoxFinder,
          matching: find.byType(StorageNetworkImage),
        );
        expect(fullScreenImageFinder, findsOneWidget);
        final fullScreenImage = tester.widget<StorageNetworkImage>(fullScreenImageFinder);
        expect(fullScreenImage.fit, equals(BoxFit.contain));

        // Verify full-screen viewer inherited 1 quarterTurn from inline preview
        expect(tester.widget<RotatedBox>(rotatedBoxFinder).quarterTurns, equals(1));

        // Verify rotate button inside dialog continues rotating through all orientations
        final rotateBtnFinder = find.byKey(const ValueKey('rotate_image_button'));
        expect(rotateBtnFinder, findsOneWidget);

        await tester.tap(rotateBtnFinder);
        await tester.pump();
        expect(tester.widget<RotatedBox>(rotatedBoxFinder).quarterTurns, equals(2));

        await tester.tap(rotateBtnFinder);
        await tester.pump();
        expect(tester.widget<RotatedBox>(rotatedBoxFinder).quarterTurns, equals(3));

        await tester.tap(rotateBtnFinder);
        await tester.pump();
        expect(tester.widget<RotatedBox>(rotatedBoxFinder).quarterTurns, equals(0));

        // Verify close button dismisses the full-screen dialog
        final closeBtnFinder = find.byKey(const ValueKey('close_image_button'));
        expect(closeBtnFinder, findsOneWidget);
        await tester.tap(closeBtnFinder);
        await tester.pumpAndSettle();
        expect(rotatedBoxFinder, findsNothing);
      },
    );

    testWidgets(
      'displays linked sanction reason, requested fine amount, and rotatable photo evidence on AdminPaymentDetailScreen for sanction payments',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        FakeBackendHelper.auth.emitUser(
          AppUser(
            uid: 'admin_uid',
            email: 'admin@catania.com',
            displayName: 'Admin',
          ),
        );
        FakeBackendHelper.auth.isAdminMock = true;

        final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_2');
        FakeBackendHelper.db.seedDocument('addresses', 'addr_2', {
          'id': 'addr_2',
          'streetName': '2nd Avenue',
          'number': 105,
          'residentUid': 'resident_2',
        });

        FakeBackendHelper.db.seedDocument('sanctions', 'sanction_1', {
          'id': 'sanction_1',
          'addressRef': addrRef,
          'residentUid': 'resident_2',
          'reason': 'Excessive noise during quiet hours after 11:00 PM.',
          'amount': 500.0,
          'evidenceUrl': 'https://example.com/infraction_evidence.jpg',
          'status': 'pending_review',
          'paymentId': 'pay_sanction_1',
        });

        FakeBackendHelper.db.seedDocument('payments', 'pay_sanction_1', {
          'id': 'pay_sanction_1',
          'addressRef': addrRef,
          'residentUid': 'resident_2',
          'uploaderUid': 'resident_2',
          'amount': 500.0,
          'concept': 'sanction',
          'sanctionId': 'sanction_1',
          'folio': 'FOL-882103',
          'periods': ['Sanction'],
          'status': 'pending',
          'receiptUrl': 'https://example.com/sanction_receipt.jpg',
          'paymentDate': DateTime(2026, 10, 22).millisecondsSinceEpoch,
        });

        await tester.pumpWidget(_wrapWithMaterial(const AdminPaymentApprovalScreen()));
        await tester.pumpAndSettle();

        final cardFinder = find.byKey(const ValueKey('payment_card_pay_sanction_1'));
        expect(cardFinder, findsOneWidget);
        await tester.tap(cardFinder);
        await tester.pumpAndSettle();

        expect(find.byType(AdminPaymentDetailScreen), findsOneWidget);
        expect(find.text('2nd Avenue #105'), findsOneWidget);
        expect(find.text('Sanction Fine'), findsOneWidget);
        expect(find.text('Fine Amount (MXN)'), findsOneWidget);
        expect(find.text('Infraction Description'), findsOneWidget);
        expect(find.text('Excessive noise during quiet hours after 11:00 PM.'), findsOneWidget);
        expect(find.text('Photo Evidence'), findsOneWidget);

        // Both receipt and sanction evidence have independent inline rotate + fullscreen buttons
        final sanctionRotateBtn = find.byKey(const ValueKey('sanction_inline_rotate_button'));
        final sanctionFullscreenBtn = find.byKey(const ValueKey('sanction_fullscreen_button'));
        final sanctionRotatedBox = find.byKey(const ValueKey('sanction_inline_rotated_box'));
        final receiptRotatedBox = find.byKey(const ValueKey('payment_inline_rotated_box'));

        expect(sanctionRotateBtn, findsOneWidget);
        expect(sanctionFullscreenBtn, findsOneWidget);
        expect(tester.widget<RotatedBox>(sanctionRotatedBox).quarterTurns, equals(0));
        expect(tester.widget<RotatedBox>(receiptRotatedBox).quarterTurns, equals(0));

        await tester.ensureVisible(sanctionRotateBtn);
        await tester.tap(sanctionRotateBtn);
        await tester.pump();
        expect(tester.widget<RotatedBox>(sanctionRotatedBox).quarterTurns, equals(1));
        expect(tester.widget<RotatedBox>(receiptRotatedBox).quarterTurns, equals(0));
      },
    );

    testWidgets(
      'invokes approvePayment callable and pops detail screen on approval',
      (tester) async {
        FakeBackendHelper.auth.emitUser(
          AppUser(uid: 'admin_1', email: 'admin@catania.com', displayName: 'Admin'),
        );
        FakeBackendHelper.auth.isAdminMock = true;

        Map<String, dynamic>? capturedApproveArgs;
        FakeBackendHelper.functions.registerHandler('approvePayment', (params) async {
          capturedApproveArgs = params;
          return {'success': true};
        });

        final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_app');
        FakeBackendHelper.db.seedDocument('addresses', 'addr_app', {
          'id': 'addr_app',
          'streetName': 'Roma',
          'number': 18,
          'residentUid': 'res_app',
        });
        FakeBackendHelper.db.seedDocument('payments', 'pay_app_1', {
          'id': 'pay_app_1',
          'addressRef': addrRef,
          'residentUid': 'res_app',
          'uploaderUid': 'res_app',
          'amount': 1200.0,
          'concept': 'monthly quota',
          'folio': 'APP-100',
          'periods': ['2026-10'],
          'status': 'pending',
          'receiptUrl': 'https://example.com/r.jpg',
          'paymentDate': DateTime(2026, 10, 5).millisecondsSinceEpoch,
        });

        await tester.pumpWidget(_wrapWithMaterial(const AdminPaymentApprovalScreen()));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('payment_card_pay_app_1')));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Approve Payment'));
        await tester.pumpAndSettle();

        expect(capturedApproveArgs, equals({'paymentId': 'pay_app_1', 'residentUid': 'res_app'}));
        expect(find.byType(AdminPaymentDetailScreen), findsNothing);
      },
    );

    testWidgets(
      'rejects sanction payment with custom Other reason, reverts sanction to active, and restricts address',
      (tester) async {
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        FakeBackendHelper.auth.emitUser(
          AppUser(uid: 'admin_rej', email: 'admin@catania.com', displayName: 'Admin'),
        );
        FakeBackendHelper.auth.isAdminMock = true;

        final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_rej_s');
        FakeBackendHelper.db.seedDocument('addresses', 'addr_rej_s', {
          'id': 'addr_rej_s',
          'streetName': 'Milan',
          'number': 77,
          'residentUid': 'res_rej',
          'paymentStatus': 'paid',
        });
        FakeBackendHelper.db.seedDocument('sanctions', 'sanc_rej_1', {
          'id': 'sanc_rej_1',
          'addressRef': addrRef,
          'residentUid': 'res_rej',
          'reason': 'Speeding inside gate',
          'amount': 700.0,
          'status': 'pending_review',
          'paymentId': 'pay_rej_s_1',
        });
        FakeBackendHelper.db.seedDocument('payments', 'pay_rej_s_1', {
          'id': 'pay_rej_s_1',
          'addressRef': addrRef,
          'residentUid': 'res_rej',
          'uploaderUid': 'res_rej',
          'amount': 700.0,
          'concept': 'sanction',
          'sanctionId': 'sanc_rej_1',
          'folio': 'REJ-500',
          'periods': ['Sanction'],
          'status': 'pending',
          'receiptUrl': 'https://example.com/s_rec.jpg',
          'paymentDate': DateTime(2026, 10, 20).millisecondsSinceEpoch,
        });

        await tester.pumpWidget(_wrapWithMaterial(const AdminPaymentApprovalScreen()));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('payment_card_pay_rej_s_1')));
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(tester.element(find.byType(AdminPaymentDetailScreen)))!;
        final rejectBtn = find.text(l10n.rejectResidentButton);
        await tester.ensureVisible(rejectBtn);
        await tester.tap(rejectBtn);
        await tester.pumpAndSettle();

        // Select "Other" reason in rejection dialog and enter custom reason
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.rejectionReasonOther).last);
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'Transfer receipt cut off at bottom');
        await tester.tap(find.widgetWithText(ElevatedButton, l10n.rejectResidentButton));
        await tester.pumpAndSettle();

        final updatedPay = await FakeBackendHelper.db.getDocument('payments', 'pay_rej_s_1');
        expect(updatedPay?['status'], equals('rejected'));
        expect(updatedPay?['rejectionReason'], equals('Transfer receipt cut off at bottom'));
        expect(updatedPay?['rejectedBy'], equals('admin_rej'));

        final updatedSanction = await FakeBackendHelper.db.getDocument('sanctions', 'sanc_rej_1');
        expect(updatedSanction?['status'], equals('active'));
        expect(updatedSanction?['rejectionReason'], equals('Transfer receipt cut off at bottom'));

        final updatedAddr = await FakeBackendHelper.db.getDocument('addresses', 'addr_rej_s');
        expect(updatedAddr?['paymentStatus'], equals('restricted'));
      },
    );
  });
}
