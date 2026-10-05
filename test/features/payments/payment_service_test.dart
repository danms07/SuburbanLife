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

    test('returns "pending" when current month is missing payment but within grace period', () async {
      final now = DateTime.now();
      final deliveryDate = DateTime(now.year, now.month, 1);

      // Seed app_settings with generous grace period covering today
      FakeBackendHelper.db.seedDocument('config', 'app_settings', {
        'paymentCutoffDay': 1,
        'gracePeriodDays': 31,
      });

      FakeBackendHelper.db.seedDocument('addresses', 'addr_grace_pending', {
        'id': 'addr_grace_pending',
        'streetName': 'Avenue 2',
        'number': 102,
        'deliveryDate': deliveryDate,
        'paymentStatus': 'paid',
      });

      final status = await paymentService.recalculatePaymentStatusForAddress('addr_grace_pending');
      expect(status, equals('pending'));

      final updated = await FakeBackendHelper.db.getDocument('addresses', 'addr_grace_pending');
      expect(updated?['paymentStatus'], equals('pending'));
    });

    test('returns "restricted" when a past historical period is missing payment', () async {
      final now = DateTime.now();
      // Delivery date set to 2 months ago
      final deliveryDate = DateTime(now.year, now.month - 2, 1);

      FakeBackendHelper.db.seedDocument('config', 'app_settings', {
        'paymentCutoffDay': 1,
        'gracePeriodDays': 31,
      });

      FakeBackendHelper.db.seedDocument('addresses', 'addr_past_missing', {
        'id': 'addr_past_missing',
        'streetName': 'Avenue Past',
        'number': 105,
        'deliveryDate': deliveryDate,
        'paymentStatus': 'paid',
      });

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_past_missing');

      // Pay current month and 2 months ago, but leave 1 month ago missing
      final p0 = "${deliveryDate.year}-${deliveryDate.month.toString().padLeft(2, '0')}";
      final pCurrent = "${now.year}-${now.month.toString().padLeft(2, '0')}";
      FakeBackendHelper.db.seedDocument('payments', 'pay_0', {
        'addressRef': addrRef,
        'period': p0,
        'status': 'approved',
      });
      FakeBackendHelper.db.seedDocument('payments', 'pay_current', {
        'addressRef': addrRef,
        'period': pCurrent,
        'status': 'approved',
      });

      final status = await paymentService.recalculatePaymentStatusForAddress('addr_past_missing');
      expect(status, equals('restricted'));

      final updated = await FakeBackendHelper.db.getDocument('addresses', 'addr_past_missing');
      expect(updated?['paymentStatus'], equals('restricted'));
    });

    test('returns "restricted" when current month grace period has expired with zero grace days', () async {
      final now = DateTime.now();
      final deliveryDate = DateTime(now.year, now.month, 1);

      // Seed cutoff on day 1 and 0 grace days (expired immediately after day 1)
      FakeBackendHelper.db.seedDocument('config', 'app_settings', {
        'paymentCutoffDay': 0,
        'gracePeriodDays': 0,
      });

      FakeBackendHelper.db.seedDocument('addresses', 'addr_grace_expired', {
        'id': 'addr_grace_expired',
        'streetName': 'Avenue Expired',
        'number': 106,
        'deliveryDate': deliveryDate,
        'paymentStatus': 'paid',
      });

      final status = await paymentService.recalculatePaymentStatusForAddress('addr_grace_expired');
      expect(status, equals('restricted'));

      final updated = await FakeBackendHelper.db.getDocument('addresses', 'addr_grace_expired');
      expect(updated?['paymentStatus'], equals('restricted'));
    });

    test('returns "restricted" when a required past period payment is rejected', () async {
      final now = DateTime.now();
      // Past month delivery
      final deliveryDate = DateTime(now.year, now.month - 1, 1);

      FakeBackendHelper.db.seedDocument('addresses', 'addr_rejected', {
        'id': 'addr_rejected',
        'streetName': 'Avenue 3',
        'number': 103,
        'deliveryDate': deliveryDate,
        'paymentStatus': 'paid',
      });

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_rejected');
      final pastPeriod = "${deliveryDate.year}-${deliveryDate.month.toString().padLeft(2, '0')}";

      FakeBackendHelper.db.seedDocument('payments', 'pay_rejected', {
        'addressRef': addrRef,
        'period': pastPeriod,
        'status': 'rejected',
      });

      final status = await paymentService.recalculatePaymentStatusForAddress('addr_rejected');
      expect(status, equals('restricted'));
    });

    test('returns "pending" when all required periods are submitted and some are pending (none unpaid/rejected)', () async {
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
      expect(status, equals('pending'));

      final updated = await FakeBackendHelper.db.getDocument('addresses', 'addr_reviewing');
      expect(updated?['paymentStatus'], equals('pending'));
    });

    test('sets isWithinGracePeriod to true when pending within grace period', () async {
      final now = DateTime.now();
      final deliveryDate = DateTime(now.year, now.month, 1);

      // Seed generous grace period covering today
      FakeBackendHelper.db.seedDocument('config', 'app_settings', {
        'paymentCutoffDay': 1,
        'gracePeriodDays': 31,
      });

      FakeBackendHelper.db.seedDocument('addresses', 'addr_pending_grace', {
        'id': 'addr_pending_grace',
        'streetName': 'Avenue Grace',
        'number': 108,
        'deliveryDate': deliveryDate,
        'paymentStatus': 'restricted',
      });

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_pending_grace');
      final pCurrent = "${now.year}-${now.month.toString().padLeft(2, '0')}";

      FakeBackendHelper.db.seedDocument('payments', 'pay_grace_pending', {
        'addressRef': addrRef,
        'period': pCurrent,
        'status': 'pending',
      });

      final status = await paymentService.recalculatePaymentStatusForAddress('addr_pending_grace');
      expect(status, equals('pending'));

      final updated = await FakeBackendHelper.db.getDocument('addresses', 'addr_pending_grace');
      expect(updated?['paymentStatus'], equals('pending'));
      expect(updated?['isWithinGracePeriod'], isTrue);
    });

    test('sets isWithinGracePeriod to false when pending outside grace period', () async {
      final now = DateTime.now();
      final deliveryDate = DateTime(now.year, now.month, 1);

      // Expired grace period (0 grace days)
      FakeBackendHelper.db.seedDocument('config', 'app_settings', {
        'paymentCutoffDay': 0,
        'gracePeriodDays': 0,
      });

      FakeBackendHelper.db.seedDocument('addresses', 'addr_pending_no_grace', {
        'id': 'addr_pending_no_grace',
        'streetName': 'Avenue No Grace',
        'number': 109,
        'deliveryDate': deliveryDate,
        'paymentStatus': 'restricted',
      });

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_pending_no_grace');
      final pCurrent = "${now.year}-${now.month.toString().padLeft(2, '0')}";

      FakeBackendHelper.db.seedDocument('payments', 'pay_no_grace_pending', {
        'addressRef': addrRef,
        'period': pCurrent,
        'status': 'pending',
      });

      final status = await paymentService.recalculatePaymentStatusForAddress('addr_pending_no_grace');
      expect(status, equals('pending'));

      final updated = await FakeBackendHelper.db.getDocument('addresses', 'addr_pending_no_grace');
      expect(updated?['paymentStatus'], equals('pending'));
      expect(updated?['isWithinGracePeriod'], isFalse);
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

    test('correctly handles multi-period arrays in a single payment document', () async {
      final now = DateTime.now();
      final deliveryDate = DateTime(now.year, now.month - 1, 1);
      final p1 = "${deliveryDate.year}-${deliveryDate.month.toString().padLeft(2, '0')}";
      final p2 = "${now.year}-${now.month.toString().padLeft(2, '0')}";

      FakeBackendHelper.db.seedDocument('addresses', 'addr_multi_period_doc', {
        'id': 'addr_multi_period_doc',
        'streetName': 'Birch St',
        'number': 44,
        'deliveryDate': deliveryDate,
        'paymentStatus': 'restricted',
      });

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_multi_period_doc');

      // Seed a single receipt covering both periods via periods array
      FakeBackendHelper.db.seedDocument('payments', 'pay_multi_batch', {
        'addressRef': addrRef,
        'periods': [p1, p2],
        'amount': 3000.0,
        'status': 'approved',
      });

      final status = await paymentService.recalculatePaymentStatusForAddress('addr_multi_period_doc');
      expect(status, equals('paid'));

      final updated = await FakeBackendHelper.db.getDocument('addresses', 'addr_multi_period_doc');
      expect(updated?['paymentStatus'], equals('paid'));
    });

    test('generateSelectablePeriods produces missing past periods and advance future periods', () {
      final now = DateTime(2026, 9, 15);
      final deliveryDate = DateTime(2026, 7, 1);

      final periods = paymentService.generateSelectablePeriods(deliveryDate, now, advanceMonths: 3);

      expect(periods, containsAllInOrder([
        '2026-07',
        '2026-08',
        '2026-09',
        '2026-10',
        '2026-11',
        '2026-12',
      ]));
      expect(periods.length, equals(6));
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

  group('PaymentService - Sanctions enforcement in recalculatePaymentStatusForAddress', () {
    test('restricts address when there is an active sanction even if maintenance is paid', () async {
      FakeBackendHelper.db.seedDocument('addresses', 'addr_sanction_test', {
        'id': 'addr_sanction_test',
        'streetName': 'Maple Ave',
        'number': 22,
        'deliveryDate': null, // usually paid
        'paymentStatus': 'paid',
      });

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_sanction_test');
      FakeBackendHelper.db.seedDocument('sanctions', 'sanc_1', {
        'id': 'sanc_1',
        'addressRef': addrRef,
        'status': 'active',
        'reason': 'Loud noise after hours',
        'amount': 500.0,
      });

      final status = await paymentService.recalculatePaymentStatusForAddress('addr_sanction_test');
      expect(status, equals('restricted'));

      final updatedAddr = await FakeBackendHelper.db.getDocument('addresses', 'addr_sanction_test');
      expect(updatedAddr?['paymentStatus'], equals('restricted'));
      expect(updatedAddr?['hasActiveSanctions'], isTrue);
      expect(updatedAddr?['activeSanctionsCount'], equals(1));
    });

    test('restricts address when sanction status is pending_review', () async {
      FakeBackendHelper.db.seedDocument('addresses', 'addr_sanc_pending', {
        'id': 'addr_sanc_pending',
        'streetName': 'Maple Ave',
        'number': 23,
        'deliveryDate': null,
        'paymentStatus': 'paid',
      });

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_sanc_pending');
      FakeBackendHelper.db.seedDocument('sanctions', 'sanc_2', {
        'id': 'sanc_2',
        'addressRef': addrRef,
        'status': 'pending_review',
      });

      final status = await paymentService.recalculatePaymentStatusForAddress('addr_sanc_pending');
      expect(status, equals('restricted'));

      final updatedAddr = await FakeBackendHelper.db.getDocument('addresses', 'addr_sanc_pending');
      expect(updatedAddr?['hasActiveSanctions'], isTrue);
    });

    test('does not restrict address if sanctions are paid or cancelled', () async {
      FakeBackendHelper.db.seedDocument('addresses', 'addr_sanc_cleared', {
        'id': 'addr_sanc_cleared',
        'streetName': 'Maple Ave',
        'number': 24,
        'deliveryDate': null,
        'paymentStatus': 'paid',
      });

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_sanc_cleared');
      FakeBackendHelper.db.seedDocument('sanctions', 'sanc_3', {
        'id': 'sanc_3',
        'addressRef': addrRef,
        'status': 'paid',
      });
      FakeBackendHelper.db.seedDocument('sanctions', 'sanc_4', {
        'id': 'sanc_4',
        'addressRef': addrRef,
        'status': 'cancelled',
      });

      final status = await paymentService.recalculatePaymentStatusForAddress('addr_sanc_cleared');
      expect(status, equals('paid'));

      final updatedAddr = await FakeBackendHelper.db.getDocument('addresses', 'addr_sanc_cleared');
      expect(updatedAddr?['hasActiveSanctions'], isFalse);
      expect(updatedAddr?['activeSanctionsCount'], equals(0));
    });

    test('ignores sanction concept payments when checking maintenance quotas', () async {
      final now = DateTime.now();
      final deliveryDate = DateTime(now.year, now.month - 1, 1);
      final p1 = "${deliveryDate.year}-${deliveryDate.month.toString().padLeft(2, '0')}";

      FakeBackendHelper.db.seedDocument('addresses', 'addr_concept_test', {
        'id': 'addr_concept_test',
        'deliveryDate': deliveryDate,
        'paymentStatus': 'pending',
      });

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_concept_test');
      // Payment for sanction with period p1 should NOT count as paying maintenance
      FakeBackendHelper.db.seedDocument('payments', 'pay_sanc', {
        'addressRef': addrRef,
        'period': p1,
        'concept': 'sanction',
        'status': 'approved',
      });

      final status = await paymentService.recalculatePaymentStatusForAddress('addr_concept_test');
      // Should still be restricted because p1 maintenance quota was never paid!
      expect(status, equals('restricted'));
    });
  });
}
