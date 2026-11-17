import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/services/document_transfer_helper.dart';
import 'package:suburban_life/features/admin/expense_service.dart';
import '../../helpers/fake_backend.dart';

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
  });

  PickedDocumentData makeImageFile({String name = 'garden.jpg'}) {
    return PickedDocumentData(
      sanitizedFileName: name,
      extension: 'jpg',
      contentType: 'image/jpeg',
      fileSize: 4,
      bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
    );
  }

  PickedDocumentData makePdfFile({String name = 'invoice.pdf'}) {
    return PickedDocumentData(
      sanitizedFileName: name,
      extension: 'pdf',
      contentType: 'application/pdf',
      fileSize: 5,
      bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D]),
    );
  }

  group('ExpenseService', () {
    test('uploads both evidences with CSPRNG paths and invokes createExpense callable', () async {
      Map<String, dynamic>? capturedPayload;
      FakeBackendHelper.functions.registerHandler('createExpense', (params) {
        capturedPayload = params;
        return {'success': true, 'expenseId': 'exp_123'};
      });

      final service = ExpenseService();
      final id = await service.recordExpense(
        adminUid: 'admin_1',
        productOrService: 'Garden trimming',
        amount: 1250.75,
        billablePeriod: '2026-11',
        expenseDate: DateTime(2026, 11, 14),
        category: ExpenseCategory.gardening,
        productEvidenceFile: makeImageFile(),
        receiptEvidenceFile: makePdfFile(),
        vendorName: 'GreenCare',
        notes: 'Front gate hedge',
      );

      expect(id, equals('exp_123'));
      expect(FakeBackendHelper.storage.uploadedFiles.length, equals(2));
      for (final path in FakeBackendHelper.storage.uploadedFiles.keys) {
        expect(path, matches(RegExp(r'^expenses/admin_1/[a-f0-9]{32}\.(jpg|pdf)$')));
      }
      expect(capturedPayload, isNotNull);
      expect(capturedPayload!['productOrService'], equals('Garden trimming'));
      expect(capturedPayload!['amount'], equals(1250.75));
      expect(capturedPayload!['billablePeriod'], equals('2026-11'));
      expect(capturedPayload!['productEvidence']['fileType'], equals('jpg'));
      expect(capturedPayload!['receiptEvidence']['fileType'], equals('pdf'));
    });

    test('rolls back uploaded Storage objects when createExpense callable fails', () async {
      FakeBackendHelper.functions.registerHandler('createExpense', (_) {
        throw Exception('Server validation failure');
      });

      final service = ExpenseService();
      await expectLater(
        () => service.recordExpense(
          adminUid: 'admin_1',
          productOrService: 'Gate repair',
          amount: 500,
          billablePeriod: '2026-11',
          expenseDate: DateTime(2026, 11, 14),
          category: ExpenseCategory.repairs,
          productEvidenceFile: makeImageFile(),
          receiptEvidenceFile: makePdfFile(),
        ),
        throwsException,
      );

      expect(FakeBackendHelper.storage.uploadedFiles.length, equals(2));
      expect(FakeBackendHelper.storage.deletedUrls.length, equals(2));
    });

    test('rejects invalid inputs before uploading files', () async {
      final service = ExpenseService();

      await expectLater(
        () => service.recordExpense(
          adminUid: 'admin_1',
          productOrService: '   ',
          amount: 100,
          billablePeriod: '2026-11',
          expenseDate: DateTime.now(),
          category: ExpenseCategory.other,
          productEvidenceFile: makeImageFile(),
          receiptEvidenceFile: makePdfFile(),
        ),
        throwsArgumentError,
      );

      await expectLater(
        () => service.recordExpense(
          adminUid: 'admin_1',
          productOrService: 'Paint',
          amount: -10,
          billablePeriod: '2026-11',
          expenseDate: DateTime.now(),
          category: ExpenseCategory.maintenance,
          productEvidenceFile: makeImageFile(),
          receiptEvidenceFile: makePdfFile(),
        ),
        throwsArgumentError,
      );

      await expectLater(
        () => service.recordExpense(
          adminUid: 'admin_1',
          productOrService: 'Paint',
          amount: 100,
          billablePeriod: '2026-11',
          expenseDate: DateTime.now(),
          category: ExpenseCategory.maintenance,
          productEvidenceFile: makePdfFile(), // PDF disallowed for product photo
          receiptEvidenceFile: makePdfFile(),
        ),
        throwsArgumentError,
      );

      expect(FakeBackendHelper.storage.uploadedFiles, isEmpty);
    });

    test('voidExpense validates reason length and calls voidExpense callable', () async {
      final service = ExpenseService();
      await expectLater(
        () => service.voidExpense(expenseId: 'exp_1', voidReason: 'no'),
        throwsArgumentError,
      );

      Map<String, dynamic>? captured;
      FakeBackendHelper.functions.registerHandler('voidExpense', (params) {
        captured = params;
        return {'success': true, 'status': 'voided'};
      });

      await service.voidExpense(
        expenseId: 'exp_1',
        voidReason: 'Entered duplicate receipt',
      );
      expect(captured?['expenseId'], equals('exp_1'));
      expect(captured?['voidReason'], equals('Entered duplicate receipt'));
    });
  });
}
