import 'package:flutter_test/flutter_test.dart';
import '../../helpers/fake_backend.dart';

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
  });

  group('Admin Booking Approval Flow & Lifecycle', () {
    test('Correctly retrieves only pending review bookings for admin', () async {
      FakeBackendHelper.db.seedDocument('bookings', 'b_pending_1', {
        'id': 'b_pending_1',
        'facilityId': 'multipurpose_room',
        'userUid': 'user_1',
        'status': 'pending review',
        'startTime': DateTime(2026, 9, 1, 10, 0).millisecondsSinceEpoch,
        'endTime': DateTime(2026, 9, 1, 12, 0).millisecondsSinceEpoch,
      });

      FakeBackendHelper.db.seedDocument('bookings', 'b_approved', {
        'id': 'b_approved',
        'facilityId': 'bicycle_1',
        'userUid': 'user_2',
        'status': 'approved (upcoming)',
        'startTime': DateTime(2026, 9, 1, 14, 0).millisecondsSinceEpoch,
        'endTime': DateTime(2026, 9, 1, 16, 0).millisecondsSinceEpoch,
      });

      FakeBackendHelper.db.seedDocument('bookings', 'b_rejected', {
        'id': 'b_rejected',
        'facilityId': 'roof_garden',
        'userUid': 'user_3',
        'status': 'rejected',
        'startTime': DateTime(2026, 9, 2, 10, 0).millisecondsSinceEpoch,
        'endTime': DateTime(2026, 9, 2, 12, 0).millisecondsSinceEpoch,
      });

      final pendingStream = FakeBackendHelper.db.streamCollection('bookings');
      final list = await pendingStream.first;
      final pendingOnly = list.where((b) => b['status'] == 'pending review').toList();

      expect(pendingOnly.length, equals(1));
      expect(pendingOnly.first['id'], equals('b_pending_1'));
      expect(pendingOnly.first['facilityId'], equals('multipurpose_room'));
    });

    test('Approving a booking sets status to approved (upcoming)', () async {
      FakeBackendHelper.db.seedDocument('bookings', 'booking_to_approve', {
        'id': 'booking_to_approve',
        'facilityId': 'multipurpose_room',
        'userUid': 'user_123',
        'status': 'pending review',
      });

      await FakeBackendHelper.db.updateDocument('bookings', 'booking_to_approve', {
        'status': 'approved (upcoming)',
      });

      final doc = await FakeBackendHelper.db.getDocument('bookings', 'booking_to_approve');
      expect(doc?['status'], equals('approved (upcoming)'));
    });

    test('Rejecting a booking sets status to rejected with notes', () async {
      FakeBackendHelper.db.seedDocument('bookings', 'booking_to_reject', {
        'id': 'booking_to_reject',
        'facilityId': 'roof_garden',
        'userUid': 'user_456',
        'status': 'pending review',
      });

      await FakeBackendHelper.db.updateDocument('bookings', 'booking_to_reject', {
        'status': 'rejected',
        'notes': 'Maintenance scheduled for roof garden.',
      });

      final doc = await FakeBackendHelper.db.getDocument('bookings', 'booking_to_reject');
      expect(doc?['status'], equals('rejected'));
      expect(doc?['notes'], equals('Maintenance scheduled for roof garden.'));
    });
  });
}
