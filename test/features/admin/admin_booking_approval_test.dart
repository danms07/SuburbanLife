import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
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

  group('AdminBookingApprovalScreen - Widget & State Transitions', () {
    testWidgets('renders empty state and hides already-approved or rejected bookings', (tester) async {
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
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('approves pending booking with facility preset message and custom instructions', (tester) async {
      FakeBackendHelper.db.seedDocument('facilities', 'roof_garden', {
        'name': 'Roof Garden',
        'presetApprovalMessage': 'Pick up keys at guardhouse.',
      });
      FakeBackendHelper.db.seedDocument('users', 'res_1', {
        'name': 'Laura Resident',
        'email': 'laura@test.com',
        'phoneNumber': '555-0199',
      });
      FakeBackendHelper.db.seedDocument('bookings', 'bk_pending_1', {
        'facilityId': 'roof_garden',
        'userUid': 'res_1',
        'status': 'pending review',
        'isConfirmed': false,
        'startTime': DateTime(2026, 6, 15, 16, 0),
        'endTime': DateTime(2026, 6, 15, 20, 0),
      });

      await tester.pumpWidget(_wrapWithL10n(const AdminBookingApprovalScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Roof Garden'), findsOneWidget);
      expect(find.textContaining('Laura Resident'), findsOneWidget);
      expect(find.text('laura@test.com'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      // Verify preset message pre-populated inside dialog TextField
      expect(find.text('Pick up keys at guardhouse.'), findsOneWidget);

      final dialogField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogField, 'Pick up keys at guardhouse before 3:45 PM.');

      final confirmBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(ElevatedButton),
      );
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      final updated = await FakeBackendHelper.db.getDocument('bookings', 'bk_pending_1');
      expect(updated!['status'], equals('approved (upcoming)'));
      expect(updated['isConfirmed'], isTrue);
      expect(updated['approvalMessage'], equals('Pick up keys at guardhouse before 3:45 PM.'));
      expect(updated['updatedAt'], isA<DateTime>());
    });

    testWidgets('rejects pending booking and records rejection reason', (tester) async {
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

      await tester.tap(find.byIcon(Icons.close));
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

      final updated = await FakeBackendHelper.db.getDocument('bookings', 'bk_pending_2');
      expect(updated!['status'], equals('rejected'));
      expect(updated['isConfirmed'], isFalse);
      expect(updated['rejectionReason'], equals('Scheduled maintenance window'));
      expect(updated['notes'], equals('Scheduled maintenance window'));
    });

    testWidgets('streams submitted resident attachments from booking_attachments and opens document on View/Download', (tester) async {
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

      expect(find.text('Submitted Documentation'), findsOneWidget);
      expect(find.textContaining('Signed Event Contract'), findsOneWidget);
      expect(find.textContaining('sofia_signed_contract.pdf'), findsOneWidget);
      expect(find.text('Required Return'), findsOneWidget);

      final viewBtn = find.byKey(
        const ValueKey('approval_view_attachment_bk_with_docs_doc_contract'),
      );
      await tester.ensureVisible(viewBtn);
      await tester.tap(viewBtn);
      await tester.pumpAndSettle();

      expect(openedUrl, equals('https://fake.storage/booking_attachments/res_att/contract.pdf'));
      expect(openedFileName, equals('sofia_signed_contract.pdf'));
    });

    testWidgets('renders inline rotatable preview with rotate and fullscreen buttons for image booking attachments', (tester) async {
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

      final rotatedBoxFinder = find.byKey(
        const ValueKey('booking_att_rotated_box_bk_with_img_doc_id_photo'),
      );
      final rotateBtnFinder = find.byKey(
        const ValueKey('booking_att_rotate_btn_bk_with_img_doc_id_photo'),
      );
      final fullscreenBtnFinder = find.byKey(
        const ValueKey('booking_att_fullscreen_btn_bk_with_img_doc_id_photo'),
      );

      expect(rotatedBoxFinder, findsOneWidget);
      expect(rotateBtnFinder, findsOneWidget);
      expect(fullscreenBtnFinder, findsOneWidget);
      expect(tester.widget<RotatedBox>(rotatedBoxFinder).quarterTurns, equals(0));

      await tester.ensureVisible(rotateBtnFinder);
      await tester.tap(rotateBtnFinder);
      await tester.pump();
      expect(tester.widget<RotatedBox>(rotatedBoxFinder).quarterTurns, equals(1));

      await tester.tap(fullscreenBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final dialogRotatedBox = find.byKey(const ValueKey('interactive_image_rotated_box'));
      expect(dialogRotatedBox, findsOneWidget);
      expect(tester.widget<RotatedBox>(dialogRotatedBox).quarterTurns, equals(1));
    });
  });
}
