import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/core/services/document_transfer_helper.dart';
import 'package:suburban_life/features/booking/booking_screen.dart';
import 'package:suburban_life/features/booking/facility_document_models.dart';
import 'package:suburban_life/features/booking/manage_bookings_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
    DocumentTransferHelper.resetOverridesForTesting();
    FakeBackendHelper.auth.emitUser(
      AppUser(
        uid: 'res_booking_uid',
        email: 'resident@example.com',
        displayName: 'Resident Tester',
      ),
    );
  });

  tearDown(() {
    DocumentTransferHelper.resetOverridesForTesting();
  });

  Widget wrapWithL10n(Widget child, {Locale locale = const Locale('en')}) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }

  void seedPaidResidentHousehold() {
    final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_res_1');
    FakeBackendHelper.db.seedDocument('addresses', 'addr_res_1', {
      'id': 'addr_res_1',
      'streetName': 'Palermo',
      'number': 18,
      'paymentStatus': 'paid',
      'hasActiveSanctions': false,
    });
    FakeBackendHelper.db.seedDocument('users', 'res_booking_uid', {
      'uid': 'res_booking_uid',
      'name': 'Resident Tester',
      'role': 'resident',
      'addressRef': addrRef,
    });
  }

  void seedFacilityWithDocuments() {
    FakeBackendHelper.db.seedDocument('facilities', 'clubhouse', {
      'id': 'clubhouse',
      'name': 'Clubhouse Hall',
      'quantity': 1,
      'openingTime': '00:00',
      'closingTime': '23:59',
      'anticipationUnit': 'unrestricted',
      'anticipationValue': 0,
      'facilityDocuments': [
        {
          'docId': 'doc_waiver',
          'title': 'Liability Waiver Form',
          'requirementMode': 'mandatory_return',
          'fileName': 'liability_waiver.pdf',
          'fileType': 'pdf',
          'fileSize': 24576,
          'url': 'https://fake.storage/facility_documents/clubhouse/waiver.pdf',
          'storagePath': 'facility_documents/clubhouse/waiver.pdf',
          'uploadedAt': 1700000000000,
        },
        {
          'docId': 'doc_guests',
          'title': 'Guest List Sheet',
          'requirementMode': 'optional_return',
          'fileName': 'guest_list.xlsx',
          'fileType': 'xlsx',
          'fileSize': 12288,
          'url': 'https://fake.storage/facility_documents/clubhouse/guests.xlsx',
          'storagePath': 'facility_documents/clubhouse/guests.xlsx',
          'uploadedAt': 1700000000000,
        },
        {
          'docId': 'doc_rules',
          'title': 'Noise Bylaws',
          'requirementMode': 'informative',
          'fileName': 'noise_bylaws.pdf',
          'fileType': 'pdf',
          'fileSize': 15360,
          'url': 'https://fake.storage/facility_documents/clubhouse/noise.pdf',
          'storagePath': 'facility_documents/clubhouse/noise.pdf',
          'uploadedAt': 1700000000000,
        },
      ],
    });
  }

  group('DocumentTransferHelper & FacilityDocumentModels Unit Tests', () {
    test('sanitizeFileName strips traversal segments and unsafe characters', () {
      expect(
        DocumentTransferHelper.sanitizeFileName('../../etc/passwd/../Signed Form (Final).pdf'),
        equals('Signed_Form__Final_.pdf'),
      );
      expect(DocumentTransferHelper.sanitizeFileName('..'), isEmpty);
      expect(DocumentTransferHelper.sanitizeFileName(''), isEmpty);
    });

    test('validateMagicBytes verifies PDF, PNG, JPEG, WEBP, OOXML, and OLE2 headers and blocks spoofed HTML/SVG', () {
      expect(
        DocumentTransferHelper.validateMagicBytes(
          Uint8List.fromList('%PDF-1.7 test'.codeUnits),
          'pdf',
        ),
        isTrue,
      );
      expect(
        DocumentTransferHelper.validateMagicBytes(
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]),
          'png',
        ),
        isTrue,
      );
      expect(
        DocumentTransferHelper.validateMagicBytes(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
          'jpg',
        ),
        isTrue,
      );
      expect(
        DocumentTransferHelper.validateMagicBytes(
          Uint8List.fromList('RIFF\x24\x00\x00\x00WEBPVP8 '.codeUnits),
          'webp',
        ),
        isTrue,
      );
      expect(
        DocumentTransferHelper.validateMagicBytes(
          Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00]),
          'docx',
        ),
        isTrue,
      );
      expect(
        DocumentTransferHelper.validateMagicBytes(
          Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]),
          'doc',
        ),
        isTrue,
      );

      // Spoofed XSS / SVG payloads must fail
      expect(
        DocumentTransferHelper.validateMagicBytes(
          Uint8List.fromList('<html><script>alert(1)</script></html>'.codeUnits),
          'pdf',
        ),
        isFalse,
      );
      expect(
        DocumentTransferHelper.validateMagicBytes(
          Uint8List.fromList('<svg onload="alert(1)"></svg>'.codeUnits),
          'svg',
        ),
        isFalse,
      );
    });

    test('buildStoragePath, buildContentDisposition, and findMissingMandatoryDocuments work accurately', () {
      final pathA = DocumentTransferHelper.buildStoragePath(
        prefix: 'booking_attachments',
        scopeId: 'res_booking_uid',
        extension: 'pdf',
      );
      final pathB = DocumentTransferHelper.buildStoragePath(
        prefix: 'booking_attachments',
        scopeId: 'res_booking_uid',
        extension: 'pdf',
      );

      expect(pathA, startsWith('booking_attachments/res_booking_uid/'));
      expect(pathA, endsWith('.pdf'));
      expect(pathA, isNot(equals(pathB)));
      expect(
        DocumentTransferHelper.buildContentDisposition('../signed_form.pdf'),
        equals('attachment; filename="signed_form.pdf"'),
      );

      final templates = [
        const FacilityDocumentTemplate(
          docId: 'req_1',
          title: 'Mandatory Waiver',
          requirementMode: FacilityDocRequirementMode.mandatoryReturn,
          fileName: 'waiver.pdf',
          fileType: 'pdf',
          fileSize: 100,
          url: 'https://fake/waiver.pdf',
          storagePath: 'facility_documents/f/waiver.pdf',
          uploadedAt: 1,
        ),
        const FacilityDocumentTemplate(
          docId: 'opt_1',
          title: 'Optional Guests',
          requirementMode: FacilityDocRequirementMode.optionalReturn,
          fileName: 'guests.xlsx',
          fileType: 'xlsx',
          fileSize: 100,
          url: 'https://fake/guests.xlsx',
          storagePath: 'facility_documents/f/guests.xlsx',
          uploadedAt: 1,
        ),
      ];
      final missing = findMissingMandatoryDocuments(templates, const {});
      expect(missing.map((t) => t.docId).toList(), equals(['req_1']));
    });
  });

  group('BookingScreen Facility Documentation & Resident Attachments Tests', () {
    testWidgets('Renders mandatory, optional, and informative facility documents in English and Spanish', (tester) async {
      seedPaidResidentHousehold();
      seedFacilityWithDocuments();

      // English
      await tester.pumpWidget(wrapWithL10n(const BookingScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Amenity Documentation'), findsOneWidget);
      expect(find.text('Liability Waiver Form'), findsOneWidget);
      expect(find.text('Required Return'), findsOneWidget);
      expect(find.text('Guest List Sheet'), findsOneWidget);
      expect(find.text('Optional Return'), findsOneWidget);
      expect(find.text('Noise Bylaws'), findsOneWidget);
      expect(find.text('Informative'), findsOneWidget);

      // Informative item has download button, NOT attach button
      expect(find.byKey(const ValueKey('facility_doc_download_doc_rules')), findsOneWidget);
      expect(find.byKey(const ValueKey('facility_doc_attach_doc_rules')), findsNothing);
      expect(find.byKey(const ValueKey('facility_doc_attach_doc_waiver')), findsOneWidget);
      expect(find.byKey(const ValueKey('facility_doc_attach_doc_guests')), findsOneWidget);

      // Spanish
      await tester.pumpWidget(wrapWithL10n(const BookingScreen(), locale: const Locale('es')));
      await tester.pumpAndSettle();

      expect(find.text('Documentación de la Amenidad'), findsOneWidget);
      expect(find.text('Devolución Obligatoria'), findsOneWidget);
      expect(find.text('Devolución Opcional'), findsOneWidget);
      expect(find.text('Informativo'), findsOneWidget);
    });

    testWidgets('Blocks submission when mandatory document is missing, uploads with attachment Content-Disposition when attached, and rolls back Storage on server failure', (tester) async {
      seedPaidResidentHousehold();
      seedFacilityWithDocuments();

      String? downloadedUrl;
      DocumentTransferHelper.setOverridesForTesting(
        openOrDownload: ({
          required context,
          required cacheId,
          required url,
          required fileName,
          required title,
        }) async {
          downloadedUrl = url;
        },
        pickDocument: (ctx) async => PickedDocumentData(
          sanitizedFileName: 'completed_waiver.pdf',
          extension: 'pdf',
          contentType: 'application/pdf',
          fileSize: 22,
          bytes: Uint8List.fromList('%PDF-1.7 signed waiver'.codeUnits),
        ),
      );

      await tester.pumpWidget(wrapWithL10n(const BookingScreen()));
      await tester.pumpAndSettle();

      // 1. Resident downloads template first
      final downloadBtn = find.byKey(const ValueKey('facility_doc_download_doc_waiver'));
      await tester.ensureVisible(downloadBtn);
      await tester.tap(downloadBtn);
      await tester.pumpAndSettle();
      expect(downloadedUrl, equals('https://fake.storage/facility_documents/clubhouse/waiver.pdf'));

      // 2. Submitting without attaching mandatory waiver -> blocked locally, 0 Cloud Function calls
      final submitBtn = find.text('Confirm Booking');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Please attach all required documents before submitting: Liability Waiver Form'),
        findsOneWidget,
      );
      expect(FakeBackendHelper.functions.callHistory, isEmpty);

      // 3. Attach completed waiver, then simulate server failure -> newly uploaded Storage file MUST roll back!
      final attachBtn = find.byKey(const ValueKey('facility_doc_attach_doc_waiver'));
      await tester.ensureVisible(attachBtn);
      await tester.tap(attachBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('completed_waiver.pdf'), findsOneWidget);

      FakeBackendHelper.functions.registerHandler('createBooking', (_) async {
        throw Exception('Slot capacity conflict');
      });

      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(FakeBackendHelper.storage.uploadedFiles.length, equals(1));
      expect(
        FakeBackendHelper.storage.deletedUrls.length,
        equals(1),
        reason: 'Uploaded Storage file must be rolled back when createBooking fails',
      );

      // 4. Now allow createBooking to succeed -> uploads cleanly with Content-Disposition: attachment
      FakeBackendHelper.storage.uploadedFiles.clear();
      FakeBackendHelper.storage.uploadedOptions.clear();
      FakeBackendHelper.storage.deletedUrls.clear();
      FakeBackendHelper.functions.callHistory.clear();
      FakeBackendHelper.functions.registerHandler(
        'createBooking',
        (_) async => {'success': true, 'bookingId': 'bk_new_1'},
      );

      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(FakeBackendHelper.functions.callHistory.length, equals(1));
      final call = FakeBackendHelper.functions.callHistory.single;
      expect(call['name'], equals('createBooking'));
      final params = call['parameters'] as Map<String, dynamic>;
      final sentAttachments = params['attachments'] as List;
      expect(sentAttachments.length, equals(1));
      expect(sentAttachments.first['facilityDocId'], equals('doc_waiver'));
      expect(sentAttachments.first['fileName'], equals('completed_waiver.pdf'));
      expect(sentAttachments.first['storagePath'], startsWith('booking_attachments/res_booking_uid/'));

      final storageOpts = FakeBackendHelper.storage.uploadedOptions.values.single;
      expect(storageOpts['contentDisposition'], equals('attachment; filename="completed_waiver.pdf"'));
      expect(FakeBackendHelper.storage.deletedUrls, isEmpty);
    });
  });

  group('ManageBookingsScreen Attachments View, 30-Day Purged Notice & Resubmit Replacement', () {
    testWidgets('Displays attachment chips, 30-day purged notice, and replaces attachment inside Resubmit dialog', (tester) async {
      seedPaidResidentHousehold();
      seedFacilityWithDocuments();

      // 1) Closed booking whose attachments were purged after 30 days
      FakeBackendHelper.db.seedDocument('bookings', 'bk_purged_old', {
        'id': 'bk_purged_old',
        'facilityId': 'clubhouse',
        'userUid': 'res_booking_uid',
        'addressId': 'addr_res_1',
        'status': 'closed',
        'isConfirmed': true,
        'hasAttachments': true,
        'attachmentCount': 1,
        'attachmentsPurgedAt': 1700500000000,
        'startTime': DateTime(2026, 3, 10, 14, 0),
        'endTime': DateTime(2026, 3, 10, 18, 0),
      });

      // 2) Rejected booking with an existing attachment ready for replacement & resubmission
      final futureStart = DateTime.now().add(const Duration(days: 5));
      final slotStart = DateTime(futureStart.year, futureStart.month, futureStart.day, 14, 0);
      final slotEnd = DateTime(futureStart.year, futureStart.month, futureStart.day, 16, 0);

      FakeBackendHelper.db.seedDocument('bookings', 'bk_rejected_1', {
        'id': 'bk_rejected_1',
        'facilityId': 'clubhouse',
        'userUid': 'res_booking_uid',
        'addressId': 'addr_res_1',
        'status': 'rejected',
        'rejectionReason': 'Please sign page 2 of waiver.',
        'isConfirmed': false,
        'hasAttachments': true,
        'attachmentCount': 1,
        'startTime': slotStart,
        'endTime': slotEnd,
      });
      FakeBackendHelper.db.seedDocument('booking_attachments', 'bk_rejected_1', {
        'bookingId': 'bk_rejected_1',
        'facilityId': 'clubhouse',
        'userUid': 'res_booking_uid',
        'addressId': 'addr_res_1',
        'attachments': [
          {
            'facilityDocId': 'doc_waiver',
            'title': 'Liability Waiver Form',
            'requirementMode': 'mandatory_return',
            'fileName': 'unsigned_waiver.pdf',
            'fileType': 'pdf',
            'fileSize': 18000,
            'url': 'https://fake.storage/booking_attachments/res_booking_uid/unsigned.pdf',
            'storagePath': 'booking_attachments/res_booking_uid/unsigned.pdf',
            'uploadedAt': 1700000000000,
          },
        ],
      });

      DocumentTransferHelper.setOverridesForTesting(
        pickDocument: (ctx) async => PickedDocumentData(
          sanitizedFileName: 'signed_page2_waiver.pdf',
          extension: 'pdf',
          contentType: 'application/pdf',
          fileSize: 25,
          bytes: Uint8List.fromList('%PDF-1.7 signed page 2'.codeUnits),
        ),
      );
      FakeBackendHelper.functions.registerHandler(
        'createBooking',
        (_) async => {'success': true, 'bookingId': 'bk_rejected_1'},
      );

      await tester.pumpWidget(wrapWithL10n(const ManageBookingsScreen()));
      await tester.pumpAndSettle();

      // Verify both the active attachment chip on bk_rejected_1 and the 30-day purged notice on bk_purged_old
      expect(find.text('Liability Waiver Form'), findsOneWidget);
      expect(
        find.text('Attachments automatically removed 30 days after booking completion per privacy policy.'),
        findsOneWidget,
      );

      // Tap Edit & Resubmit on rejected booking
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();

      expect(find.text('Edit Rejected Booking'), findsOneWidget);
      // Preloaded attachment is shown in the dialog
      expect(find.textContaining('unsigned_waiver.pdf'), findsOneWidget);

      // Replace with newly signed waiver
      final replaceBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byKey(const ValueKey('facility_doc_attach_doc_waiver')),
      );
      await tester.ensureVisible(replaceBtn);
      await tester.tap(replaceBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('signed_page2_waiver.pdf'), findsOneWidget);

      // Tap Resubmit
      final resubmitBtn = find.text('Resubmit');
      await tester.ensureVisible(resubmitBtn);
      await tester.tap(resubmitBtn);
      await tester.pumpAndSettle();

      expect(FakeBackendHelper.functions.callHistory.length, equals(1));
      final resubmitPayload =
          FakeBackendHelper.functions.callHistory.single['parameters'] as Map<String, dynamic>;
      expect(resubmitPayload['resubmitBookingId'], equals('bk_rejected_1'));
      final resubmittedAtts = resubmitPayload['attachments'] as List;
      expect(resubmittedAtts.length, equals(1));
      expect(resubmittedAtts.first['fileName'], equals('signed_page2_waiver.pdf'));
    });
  });
}
