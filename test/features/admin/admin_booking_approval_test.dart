import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/config/app_config.dart';
import 'package:suburban_life/core/services/document_transfer_helper.dart';
import 'package:suburban_life/features/admin/admin_booking_approval_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

Widget _wrapWithL10n(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('es')],
    locale: locale,
    home: child,
  );
}

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
    DocumentTransferHelper.resetOverridesForTesting();
  });

  tearDown(() {
    DocumentTransferHelper.resetOverridesForTesting();
  });

  group('AdminBookingApprovalScreen & AdminBookingDetailScreen', () {
    testWidgets(
      'renders empty state and hides already-approved or rejected bookings',
      (tester) async {
        FakeBackendHelper.db.seedDocument('bookings', 'bk_approved', {
          'facilityId': 'roof_garden',
          'userUid': 'res_1',
          'status': 'approved (upcoming)',
          'startTime': DateTime(2026, 6, 10, 14, 0),
          'endTime': DateTime(2026, 6, 10, 18, 0),
        });
        FakeBackendHelper.db.seedDocument('bookings', 'bk_rejected', {
          'facilityId': 'roof_garden',
          'userUid': 'res_2',
          'status': 'rejected',
          'startTime': DateTime(2026, 6, 11, 14, 0),
          'endTime': DateTime(2026, 6, 11, 18, 0),
        });

        await tester.pumpWidget(_wrapWithL10n(const AdminBookingApprovalScreen()));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.event_available), findsOneWidget);
        expect(find.byIcon(Icons.chevron_right), findsNothing);
      },
    );

    testWidgets(
      'renders compact summary card without inline action buttons, navigates to detail screen, approves booking with preset message, and pops back',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final addrRef = FakeBackendHelper.db.createReference(
          'addresses',
          'addr_rg',
        );
        FakeBackendHelper.db.seedDocument('addresses', 'addr_rg', {
          'id': 'addr_rg',
          'streetName': 'Via Roma',
          'number': 24,
        });
        FakeBackendHelper.db.seedDocument('facilities', 'roof_garden', {
          'name': 'Roof Garden',
          'presetApprovalMessage': 'Pick up keys at guardhouse.',
        });
        FakeBackendHelper.db.seedDocument('users', 'res_1', {
          'name': 'Laura Resident',
          'email': 'laura@test.com',
          'phoneNumber': '555-0199',
          'addressRef': addrRef,
        });
        FakeBackendHelper.db.seedDocument('bookings', 'bk_pending_1', {
          'facilityId': 'roof_garden',
          'userUid': 'res_1',
          'addressId': 'addr_rg',
          'addressRef': addrRef,
          'status': 'pending review',
          'isConfirmed': false,
          'startTime': DateTime(2026, 6, 15, 16, 0),
          'endTime': DateTime(2026, 6, 15, 20, 0),
        });

        await tester.pumpWidget(_wrapWithL10n(const AdminBookingApprovalScreen()));
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(AdminBookingApprovalScreen)),
        )!;

        // 1. Verify compact summary card displays key metadata without inline action buttons or PII contact fields
        expect(find.text('Roof Garden'), findsOneWidget);
        expect(find.text('Laura Resident'), findsOneWidget);
        expect(find.text('Via Roma #24'), findsOneWidget);
        expect(find.text(l10n.pendingReview), findsOneWidget);
        expect(find.byIcon(Icons.chevron_right), findsOneWidget);
        expect(find.text('laura@test.com'), findsNothing);
        expect(find.text('555-0199'), findsNothing);
        expect(
          find.widgetWithText(ElevatedButton, l10n.approveBookingButton),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('booking_detail_reject_button')),
          findsNothing,
        );

        // 2. Tap summary card to navigate to AdminBookingDetailScreen
        await tester.tap(find.byKey(const ValueKey('booking_card_bk_pending_1')));
        await tester.pumpAndSettle();

        expect(find.byType(AdminBookingDetailScreen), findsOneWidget);
        expect(find.text('Roof Garden'), findsOneWidget);
        expect(find.textContaining('Laura Resident'), findsOneWidget);
        expect(find.text('Via Roma #24'), findsOneWidget);
        expect(find.text('laura@test.com'), findsOneWidget);
        expect(find.text('555-0199'), findsOneWidget);

        // Verify Approve Booking button uses AppConfig.primaryColor
        final approveBtnFinder = find.byKey(
          const ValueKey('booking_detail_approve_button'),
        );
        expect(approveBtnFinder, findsOneWidget);
        final approveBtn = tester.widget<ElevatedButton>(approveBtnFinder);
        expect(
          approveBtn.style?.backgroundColor?.resolve({}),
          equals(AppConfig.primaryColor),
        );

        await tester.tap(approveBtnFinder);
        await tester.pumpAndSettle();

        // Verify preset message pre-populated inside dialog TextField
        expect(find.text('Pick up keys at guardhouse.'), findsOneWidget);

        final dialogField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        await tester.enterText(
          dialogField,
          'Pick up keys at guardhouse before 3:45 PM.',
        );

        final confirmBtn = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(ElevatedButton),
        );
        await tester.tap(confirmBtn);
        await tester.pumpAndSettle();

        final updated = await FakeBackendHelper.db.getDocument(
          'bookings',
          'bk_pending_1',
        );
        expect(updated!['status'], equals('approved (upcoming)'));
        expect(updated['isConfirmed'], isTrue);
        expect(
          updated['approvalMessage'],
          equals('Pick up keys at guardhouse before 3:45 PM.'),
        );
        expect(updated['updatedAt'], isA<DateTime>());
        expect(find.byType(AdminBookingDetailScreen), findsNothing);
      },
    );

    testWidgets(
      'rejects pending booking from AdminBookingDetailScreen, records rejection reason, and pops back',
      (tester) async {
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        FakeBackendHelper.db.seedDocument('facilities', 'multipurpose_room', {
          'name': 'Multipurpose Room',
        });
        FakeBackendHelper.db.seedDocument('users', 'res_2', {
          'name': 'Marco Resident',
        });
        FakeBackendHelper.db.seedDocument('bookings', 'bk_pending_2', {
          'facilityId': 'multipurpose_room',
          'userUid': 'res_2',
          'status': 'pending review',
          'isConfirmed': false,
          'startTime': DateTime(2026, 6, 20, 12, 0),
          'endTime': DateTime(2026, 6, 20, 16, 0),
        });

        await tester.pumpWidget(_wrapWithL10n(const AdminBookingApprovalScreen()));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('booking_card_bk_pending_2')));
        await tester.pumpAndSettle();

        expect(find.byType(AdminBookingDetailScreen), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('booking_detail_reject_button')),
        );
        await tester.pumpAndSettle();

        final dialogField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        await tester.enterText(dialogField, 'Scheduled maintenance window');

        final rejectConfirmBtn = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(ElevatedButton),
        );
        await tester.tap(rejectConfirmBtn);
        await tester.pumpAndSettle();

        final updated = await FakeBackendHelper.db.getDocument(
          'bookings',
          'bk_pending_2',
        );
        expect(updated!['status'], equals('rejected'));
        expect(updated['isConfirmed'], isFalse);
        expect(
          updated['rejectionReason'],
          equals('Scheduled maintenance window'),
        );
        expect(updated['notes'], equals('Scheduled maintenance window'));
        expect(find.byType(AdminBookingDetailScreen), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'shows attachment count chip on summary card and streams submitted documentation on detail screen',
      (tester) async {
        String? openedUrl;
        String? openedFileName;
        DocumentTransferHelper.setOverridesForTesting(
          openOrDownload: ({
            required context,
            required cacheId,
            required url,
            required fileName,
            required title,
          }) async {
            openedUrl = url;
            openedFileName = fileName;
          },
        );

        FakeBackendHelper.db.seedDocument('facilities', 'salon', {
          'name': 'Clubhouse Hall',
        });
        FakeBackendHelper.db.seedDocument('users', 'res_att', {
          'name': 'Sofia Resident',
        });
        FakeBackendHelper.db.seedDocument('bookings', 'bk_with_docs', {
          'facilityId': 'salon',
          'userUid': 'res_att',
          'status': 'pending review',
          'isConfirmed': false,
          'hasAttachments': true,
          'attachmentCount': 1,
          'startTime': DateTime(2026, 7, 10, 14, 0),
          'endTime': DateTime(2026, 7, 10, 18, 0),
        });
        FakeBackendHelper.db.seedDocument('booking_attachments', 'bk_with_docs', {
          'bookingId': 'bk_with_docs',
          'facilityId': 'salon',
          'userUid': 'res_att',
          'attachments': [
            {
              'facilityDocId': 'doc_contract',
              'title': 'Signed Event Contract',
              'requirementMode': 'mandatory_return',
              'fileName': 'sofia_signed_contract.pdf',
              'fileType': 'pdf',
              'fileSize': 51200,
              'url': 'https://fake.storage/booking_attachments/res_att/contract.pdf',
              'storagePath': 'booking_attachments/res_att/contract.pdf',
              'uploadedAt': 1700000000000,
            },
          ],
        });

        await tester.pumpWidget(_wrapWithL10n(const AdminBookingApprovalScreen()));
        await tester.pumpAndSettle();

        // Summary card shows attachment badge count but not full documentation panel
        expect(find.text('1 attachment(s)'), findsOneWidget);
        expect(find.text('Submitted Documentation'), findsNothing);
        expect(
          find.byKey(
            const ValueKey('approval_view_attachment_bk_with_docs_doc_contract'),
          ),
          findsNothing,
        );

        await tester.tap(find.byKey(const ValueKey('booking_card_bk_with_docs')));
        await tester.pumpAndSettle();

        expect(find.byType(AdminBookingDetailScreen), findsOneWidget);
        expect(find.text('Submitted Documentation'), findsOneWidget);
        expect(find.textContaining('Signed Event Contract'), findsOneWidget);
        expect(
          find.textContaining('sofia_signed_contract.pdf'),
          findsOneWidget,
        );
        expect(find.text('Required Return'), findsOneWidget);

        final viewBtn = find.byKey(
          const ValueKey('approval_view_attachment_bk_with_docs_doc_contract'),
        );
        await tester.ensureVisible(viewBtn);
        await tester.tap(viewBtn);
        await tester.pumpAndSettle();

        expect(
          openedUrl,
          equals('https://fake.storage/booking_attachments/res_att/contract.pdf'),
        );
        expect(openedFileName, equals('sofia_signed_contract.pdf'));
      },
    );

    testWidgets(
      'renders wide side-by-side detail screen (>650px) with rotatable image preview and fullscreen viewer',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        FakeBackendHelper.db.seedDocument('facilities', 'pool', {
          'name': 'Community Pool',
        });
        FakeBackendHelper.db.seedDocument('users', 'res_img', {
          'name': 'Diego Resident',
        });
        FakeBackendHelper.db.seedDocument('bookings', 'bk_with_img', {
          'facilityId': 'pool',
          'userUid': 'res_img',
          'status': 'pending review',
          'isConfirmed': false,
          'hasAttachments': true,
          'attachmentCount': 1,
          'startTime': DateTime(2026, 7, 12, 12, 0),
          'endTime': DateTime(2026, 7, 12, 16, 0),
        });
        FakeBackendHelper.db.seedDocument('booking_attachments', 'bk_with_img', {
          'bookingId': 'bk_with_img',
          'facilityId': 'pool',
          'userUid': 'res_img',
          'attachments': [
            {
              'facilityDocId': 'doc_id_photo',
              'title': 'Signed Rules Photo',
              'requirementMode': 'mandatory_return',
              'fileName': 'signed_rules.png',
              'fileType': 'png',
              'fileSize': 40960,
              'url': 'https://fake.storage/booking_attachments/res_img/signed_rules.png',
              'storagePath': 'booking_attachments/res_img/signed_rules.png',
              'uploadedAt': 1700000000000,
            },
          ],
        });

        await tester.pumpWidget(_wrapWithL10n(const AdminBookingApprovalScreen()));
        await tester.pumpAndSettle();

        // Thumbnail preview is NOT rendered directly on the summary list screen
        expect(
          find.byKey(
            const ValueKey('booking_att_thumbnail_bk_with_img_doc_id_photo'),
          ),
          findsNothing,
        );

        await tester.tap(find.byKey(const ValueKey('booking_card_bk_with_img')));
        await tester.pumpAndSettle();

        final thumbFinder = find.byKey(
          const ValueKey('booking_att_thumbnail_bk_with_img_doc_id_photo'),
        );
        final rotatedBoxFinder = find.byKey(
          const ValueKey('booking_att_rotated_box_bk_with_img_doc_id_photo'),
        );
        final rotateBtnFinder = find.byKey(
          const ValueKey('booking_att_rotate_btn_bk_with_img_doc_id_photo'),
        );
        final fullscreenBtnFinder = find.byKey(
          const ValueKey('booking_att_fullscreen_btn_bk_with_img_doc_id_photo'),
        );

        expect(thumbFinder, findsOneWidget);
        expect(rotatedBoxFinder, findsOneWidget);
        expect(rotateBtnFinder, findsOneWidget);
        expect(fullscreenBtnFinder, findsOneWidget);

        // Wide layout (>650px): documentation pane is on the left of booking info & buttons
        expect(
          tester.getTopLeft(thumbFinder).dx,
          lessThan(tester.getTopLeft(find.text('Community Pool')).dx),
        );
        expect(
          tester.getTopLeft(thumbFinder).dx,
          lessThan(
            tester
                .getTopLeft(
                  find.byKey(const ValueKey('booking_detail_approve_button')),
                )
                .dx,
          ),
        );

        expect(tester.widget<RotatedBox>(rotatedBoxFinder).quarterTurns, equals(0));

        await tester.ensureVisible(rotateBtnFinder);
        await tester.tap(rotateBtnFinder);
        await tester.pump();
        expect(tester.widget<RotatedBox>(rotatedBoxFinder).quarterTurns, equals(1));

        await tester.tap(fullscreenBtnFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final dialogRotatedBox = find.byKey(
          const ValueKey('interactive_image_rotated_box'),
        );
        expect(dialogRotatedBox, findsOneWidget);
        expect(tester.widget<RotatedBox>(dialogRotatedBox).quarterTurns, equals(1));
      },
    );

    testWidgets(
      'adapts to narrow portrait mobile viewport (<650px) and renders complete Spanish localization cleanly',
      (tester) async {
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        FakeBackendHelper.db.seedDocument('facilities', 'roof_garden', {
          'name': 'Terraza Principal',
        });
        FakeBackendHelper.db.seedDocument('users', 'res_es', {
          'name': 'Valeria Morales',
          'email': 'valeria@test.com',
        });
        FakeBackendHelper.db.seedDocument('bookings', 'bk_es_mobile', {
          'facilityId': 'roof_garden',
          'userUid': 'res_es',
          'status': 'pending review',
          'isConfirmed': false,
          'hasAttachments': true,
          'attachmentCount': 1,
          'startTime': DateTime(2026, 8, 5, 15, 0),
          'endTime': DateTime(2026, 8, 5, 19, 0),
        });
        FakeBackendHelper.db.seedDocument('booking_attachments', 'bk_es_mobile', {
          'bookingId': 'bk_es_mobile',
          'facilityId': 'roof_garden',
          'userUid': 'res_es',
          'attachments': [
            {
              'facilityDocId': 'doc_es_waiver',
              'title': 'Carta Responsiva Firmada',
              'requirementMode': 'mandatory_return',
              'fileName': 'responsiva.pdf',
              'fileType': 'pdf',
              'fileSize': 20480,
              'url': 'https://fake.storage/booking_attachments/res_es/responsiva.pdf',
              'storagePath': 'booking_attachments/res_es/responsiva.pdf',
              'uploadedAt': 1700000000000,
            },
          ],
        });

        await tester.pumpWidget(
          _wrapWithL10n(
            const AdminBookingApprovalScreen(),
            locale: const Locale('es'),
          ),
        );
        await tester.pumpAndSettle();

        final listL10n = AppLocalizations.of(
          tester.element(find.byType(AdminBookingApprovalScreen)),
        )!;
        expect(find.text(listL10n.adminBookingApprovalTitle), findsOneWidget);
        expect(find.text(listL10n.pendingReview), findsOneWidget);
        expect(
          find.text(listL10n.bookingAttachmentsCountBadge(1)),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('booking_card_bk_es_mobile')));
        await tester.pumpAndSettle();

        expect(find.byType(AdminBookingDetailScreen), findsOneWidget);
        final detailL10n = AppLocalizations.of(
          tester.element(find.byType(AdminBookingDetailScreen)),
        )!;

        expect(find.text(detailL10n.bookingDetails), findsOneWidget);
        expect(find.text(detailL10n.bookingAttachmentsSectionTitle), findsOneWidget);
        expect(find.text(detailL10n.viewBookingAttachmentButton), findsOneWidget);
        expect(find.text(detailL10n.approveBookingButton), findsOneWidget);
        expect(find.text(detailL10n.reject), findsOneWidget);

        // Narrow layout (<650px): booking info is stacked vertically above the documentation pane
        expect(
          tester.getTopLeft(find.text('Terraza Principal')).dy,
          lessThan(
            tester
                .getTopLeft(find.text(detailL10n.bookingAttachmentsSectionTitle))
                .dy,
          ),
        );
        expect(
          tester
              .getTopLeft(find.text(detailL10n.bookingAttachmentsSectionTitle))
              .dy,
          lessThan(
            tester
                .getTopLeft(
                  find.byKey(const ValueKey('booking_detail_approve_button')),
                )
                .dy,
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
