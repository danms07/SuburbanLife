import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/features/payments/payment_service.dart';
import '../../helpers/fake_backend.dart';

void main() {
  late PaymentService paymentService;

  setUp(() {
    FakeBackendHelper.setUp();
    paymentService = PaymentService();
  });

  group('PaymentService - recalculatePaymentStatusForAddress', () {
    test('returns "restricted" when address document is not found', () async {
      final status = await paymentService.recalculatePaymentStatusForAddress('non_existent_addr');
      expect(status, equals('restricted'));
    });

    test('returns "paid" and updates status when address has no deliveryDate', () async {
      FakeBackendHelper.db.seedDocument('addresses', 'addr_1', {
        'id': 'addr_1',
        'streetName': 'Oak Street',
        'number': 10,
        'paymentStatus': 'restricted',
        'deliveryDate': null,
      });

      final status = await paymentService.recalculatePaymentStatusForAddress('addr_1');
      expect(status, equals('paid'));

      final updatedDoc = await FakeBackendHelper.db.getDocument('addresses', 'addr_1');
      expect(updatedDoc?['paymentStatus'], equals('paid'));
    });

    test('handles StringDbReference and DbReference parameter types correctly', () async {
      FakeBackendHelper.db.seedDocument('addresses', 'addr_ref_test', {
        'id': 'addr_ref_test',
        'streetName': 'Pine St',
        'number': 5,
        'deliveryDate': null,
      });

      final ref = StringDbReference('addr_ref_test', path: 'addresses/addr_ref_test');
      final status = await paymentService.recalculatePaymentStatusForAddress(ref);
      expect(status, equals('paid'));
    });

    test('returns "paid" when all required periods from delivery date are approved', () async {
      final now = DateTime.now();
      // Delivery date set to 2 months ago
      final deliveryDate = DateTime(now.year, now.month - 1, 1);

      FakeBackendHelper.db.seedDocument('addresses', 'addr_paid', {
        'id': 'addr_paid',
        'streetName': 'Avenue 1',
        'number': 101,
        'deliveryDate': deliveryDate,
        'paymentStatus': 'pending',
      });

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_paid');

      // Seed approved payments for both periods
      final p1 = "${deliveryDate.year}-${deliveryDate.month.toString().padLeft(2, '0')}";
      final p2 = "${now.year}-${now.month.toString().padLeft(2, '0')}";

      FakeBackendHelper.db.seedDocument('payments', 'pay_1', {
        'addressRef': addrRef,
        'period': p1,
        'status': 'approved',
      });
      FakeBackendHelper.db.seedDocument('payments', 'pay_2', {
        'addressRef': addrRef,
        'period': p2,
        'status': 'approved',
      });

      final status = await paymentService.recalculatePaymentStatusForAddress('addr_paid');
      expect(status, equals('paid'));

      final updated = await FakeBackendHelper.db.getDocument('addresses', 'addr_paid');
      expect(updated?['paymentStatus'], equals('paid'));
    });

    test('returns "restricted" when any required period is missing payment', () async {
      final now = DateTime.now();
      final deliveryDate = DateTime(now.year, now.month - 1, 1);

      FakeBackendHelper.db.seedDocument('addresses', 'addr_missing', {
        'id': 'addr_missing',
        'streetName': 'Avenue 2',
        'number': 102,
        'deliveryDate': deliveryDate,
        'paymentStatus': 'paid',
      });

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_missing');

      // Only pay the earlier period, current month is unpaid
      final p1 = "${deliveryDate.year}-${deliveryDate.month.toString().padLeft(2, '0')}";
      FakeBackendHelper.db.seedDocument('payments', 'pay_1', {
        'addressRef': addrRef,
        'period': p1,
        'status': 'approved',
      });

      final status = await paymentService.recalculatePaymentStatusForAddress('addr_missing');
      expect(status, equals('restricted'));

      final updated = await FakeBackendHelper.db.getDocument('addresses', 'addr_missing');
      expect(updated?['paymentStatus'], equals('restricted'));
    });

    test('returns "restricted" when a required period payment is rejected', () async {
      final now = DateTime.now();
      final deliveryDate = DateTime(now.year, now.month, 1);

      FakeBackendHelper.db.seedDocument('addresses', 'addr_rejected', {
        'id': 'addr_rejected',
        'streetName': 'Avenue 3',
        'number': 103,
        'deliveryDate': deliveryDate,
        'paymentStatus': 'paid',
      });

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_rejected');
      final p1 = "${now.year}-${now.month.toString().padLeft(2, '0')}";

      FakeBackendHelper.db.seedDocument('payments', 'pay_rejected', {
        'addressRef': addrRef,
        'period': p1,
        'status': 'rejected',
      });

      final status = await paymentService.recalculatePaymentStatusForAddress('addr_rejected');
      expect(status, equals('restricted'));
    });

    test('returns "reviewing" when all required periods are submitted and some are pending (none unpaid/rejected)', () async {
      final now = DateTime.now();
      final deliveryDate = DateTime(now.year, now.month - 1, 1);

      FakeBackendHelper.db.seedDocument('addresses', 'addr_reviewing', {
        'id': 'addr_reviewing',
        'streetName': 'Avenue 4',
        'number': 104,
        'deliveryDate': deliveryDate,
        'paymentStatus': 'restricted',
      });

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_reviewing');
      final p1 = "${deliveryDate.year}-${deliveryDate.month.toString().padLeft(2, '0')}";
      final p2 = "${now.year}-${now.month.toString().padLeft(2, '0')}";

      FakeBackendHelper.db.seedDocument('payments', 'pay_1', {
        'addressRef': addrRef,
        'period': p1,
        'status': 'approved',
      });
      FakeBackendHelper.db.seedDocument('payments', 'pay_2', {
        'addressRef': addrRef,
        'period': p2,
        'status': 'pending',
      });

      final status = await paymentService.recalculatePaymentStatusForAddress('addr_reviewing');
      expect(status, equals('reviewing'));

      final updated = await FakeBackendHelper.db.getDocument('addresses', 'addr_reviewing');
      expect(updated?['paymentStatus'], equals('reviewing'));
    });

    test('resolves multiple payments for the same period with priority (approved > pending > rejected)', () async {
      final now = DateTime.now();
      final deliveryDate = DateTime(now.year, now.month, 1);
      final period = "${now.year}-${now.month.toString().padLeft(2, '0')}";

      FakeBackendHelper.db.seedDocument('addresses', 'addr_multi', {
        'id': 'addr_multi',
        'streetName': 'Maple St',
        'number': 20,
        'deliveryDate': deliveryDate,
      });

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_multi');

      // Both a rejected and an approved receipt exist for the same period
      FakeBackendHelper.db.seedDocument('payments', 'pay_old_rejected', {
        'addressRef': addrRef,
        'period': period,
        'status': 'rejected',
      });
      FakeBackendHelper.db.seedDocument('payments', 'pay_new_approved', {
        'addressRef': addrRef,
        'period': period,
        'status': 'approved',
      });

      final status = await paymentService.recalculatePaymentStatusForAddress('addr_multi');
      expect(status, equals('paid'));
    });
  });

  group('PaymentService - getPaymentStatus stream', () {
    test('yields null if user has no addressRef linked', () async {
      FakeBackendHelper.db.seedDocument('users', 'user_no_addr', {
        'uid': 'user_no_addr',
        'name': 'No Address User',
        'addressRef': null,
      });

      final stream = paymentService.getPaymentStatus('user_no_addr');
      final result = await stream.first;
      expect(result, isNull);
    });

    test('yields address data and defaults missing paymentStatus to "restricted"', () async {
      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_stream_test');
      FakeBackendHelper.db.seedDocument('addresses', 'addr_stream_test', {
        'id': 'addr_stream_test',
        'streetName': 'Cedar Lane',
        'number': 77,
        'paymentStatus': '',
      });

      FakeBackendHelper.db.seedDocument('users', 'user_with_addr', {
        'uid': 'user_with_addr',
        'name': 'Resident',
        'addressRef': addrRef,
      });

      final stream = paymentService.getPaymentStatus('user_with_addr');
      final result = await stream.first;
      expect(result, isNotNull);
      expect(result?['paymentStatus'], equals('restricted'));
      expect(result?['streetName'], equals('Cedar Lane'));
    });
  });
}
