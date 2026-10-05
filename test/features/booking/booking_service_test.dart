import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/features/booking/booking_service.dart';
import '../../helpers/fake_backend.dart';

void main() {
  late BookingService bookingService;

  setUp(() {
    FakeBackendHelper.setUp();
    bookingService = BookingService();
  });

  group('BookingService - getBookings', () {
    test('filters bookings by facilityId and excludes cancelled and rejected bookings', () async {
      FakeBackendHelper.db.seedDocument('bookings', 'b_1', {
        'id': 'b_1',
        'facilityId': 'pool',
        'status': 'approved',
      });
      FakeBackendHelper.db.seedDocument('bookings', 'b_2', {
        'id': 'b_2',
        'facilityId': 'pool',
        'status': 'cancelled',
      });
      FakeBackendHelper.db.seedDocument('bookings', 'b_3', {
        'id': 'b_3',
        'facilityId': 'pool',
        'status': 'rejected',
      });
      FakeBackendHelper.db.seedDocument('bookings', 'b_4', {
        'id': 'b_4',
        'facilityId': 'gym',
        'status': 'approved',
      });

      final stream = bookingService.getBookings('pool');
      final list = await stream.first;

      expect(list.length, equals(1));
      expect(list.first['id'], equals('b_1'));
      expect(list.first['facilityId'], equals('pool'));
    });
  });

  group('BookingService - getUserBookings', () {
    test('sorts user bookings in descending order of start time with epoch integer timestamps', () async {
      FakeBackendHelper.db.seedDocument('bookings', 'b_earlier', {
        'id': 'b_earlier',
        'userUid': 'user_123',
        'startTime': 1000000,
        'status': 'approved',
      });
      FakeBackendHelper.db.seedDocument('bookings', 'b_later', {
        'id': 'b_later',
        'userUid': 'user_123',
        'startTime': 2000000,
        'status': 'approved',
      });
      FakeBackendHelper.db.seedDocument('bookings', 'b_other_user', {
        'id': 'b_other_user',
        'userUid': 'user_999',
        'startTime': 3000000,
      });

      final stream = bookingService.getUserBookings('user_123');
      final list = await stream.first;

      expect(list.length, equals(2));
      expect(list[0]['id'], equals('b_later'));
      expect(list[1]['id'], equals('b_earlier'));
    });

    test('sorts user bookings in descending order of start time with DateTime instances', () async {
      final t1 = DateTime(2026, 1, 1);
      final t2 = DateTime(2026, 6, 1);

      FakeBackendHelper.db.seedDocument('bookings', 'b_dt_earlier', {
        'id': 'b_dt_earlier',
        'userUid': 'user_abc',
        'startTime': t1,
      });
      FakeBackendHelper.db.seedDocument('bookings', 'b_dt_later', {
        'id': 'b_dt_later',
        'userUid': 'user_abc',
        'startTime': t2,
      });

      final stream = bookingService.getUserBookings('user_abc');
      final list = await stream.first;

      expect(list.length, equals(2));
      expect(list[0]['id'], equals('b_dt_later'));
      expect(list[1]['id'], equals('b_dt_earlier'));
    });
  });

  group('BookingService - createBooking and cancelBooking', () {
    test('createBooking passes correct parameters to functions backend', () async {
      final start = DateTime(2026, 5, 10, 10, 0);
      final end = DateTime(2026, 5, 10, 12, 0);

      await bookingService.createBooking('multipurpose_room', start, end);

      expect(FakeBackendHelper.functions.callHistory.length, equals(1));
      final call = FakeBackendHelper.functions.callHistory.first;
      expect(call['name'], equals('createBooking'));
      expect(call['parameters']['facilityId'], equals('multipurpose_room'));
      expect(call['parameters']['startTime'], equals(start.millisecondsSinceEpoch));
      expect(call['parameters']['endTime'], equals(end.millisecondsSinceEpoch));
    });

    test('createBooking throws formatted exception when functions call fails', () async {
      FakeBackendHelper.functions.registerHandler('createBooking', (_) {
        throw Exception('Facility already booked');
      });

      final start = DateTime(2026, 5, 10, 10, 0);
      final end = DateTime(2026, 5, 10, 12, 0);

      expect(
        () => bookingService.createBooking('pool', start, end),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Failed to create booking'))),
      );
    });

    test('cancelBooking invokes cancelBooking function correctly', () async {
      await bookingService.cancelBooking('booking_to_cancel');

      expect(FakeBackendHelper.functions.callHistory.length, equals(1));
      final call = FakeBackendHelper.functions.callHistory.first;
      expect(call['name'], equals('cancelBooking'));
      expect(call['parameters']['bookingId'], equals('booking_to_cancel'));
    });

    test('cancelBooking throws formatted exception when function returns error', () async {
      FakeBackendHelper.functions.registerHandler('cancelBooking', (_) {
        throw Exception('Booking cannot be cancelled');
      });

      expect(
        () => bookingService.cancelBooking('invalid_id'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Failed to cancel booking'))),
      );
    });

    test('Full booking lifecycle: schedule -> reject -> re-book -> approve -> cooldown blocked -> time passes -> review', () async {
      final now = DateTime.now();
      const facilityId = 'multipurpose_room';
      const userUid = 'resident_uid_test';

      FakeBackendHelper.auth.emitUser(
        AppUser(
          uid: userUid,
          email: 'resident@test.com',
          displayName: 'Test Resident',
        ),
      );

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_test');
      FakeBackendHelper.db.seedDocument('addresses', 'addr_test', {
        'paymentStatus': 'paid',
      });
      FakeBackendHelper.db.seedDocument('users', userUid, {
        'addressRef': addrRef,
      });

      FakeBackendHelper.db.seedDocument('facilities', facilityId, {
        'id': facilityId,
        'cooldownUnit': 'days',
        'cooldownValue': 7,
        'quantity': 1,
      });

      // Emulate Cloud Function createBooking logic
      FakeBackendHelper.functions.registerHandler('createBooking', (params) async {
        final fId = params?['facilityId'] as String;
        final start = params?['startTime'] as int;
        final end = params?['endTime'] as int;

        final allBookings = await FakeBackendHelper.db.streamCollection('bookings').first;
        final confirmed = allBookings.where((b) {
          if (b['userUid'] != userUid || b['facilityId'] != fId) return false;
          final status = (b['status'] ?? '').toString().toLowerCase();
          if (!status.startsWith('approved') && status != 'confirmed') return false;
          final bStart = (b['startTime'] as num).toInt();
          final ms = 7 * 24 * 60 * 60 * 1000;
          return bStart >= (start - ms) && bStart <= (start + ms);
        }).toList();

        if (confirmed.isNotEmpty) {
          throw Exception('You are only allowed to book this facility once every 7 days.');
        }

        final bId = 'b_${allBookings.length + 1}';
        final doc = {
          'id': bId,
          'facilityId': fId,
          'userUid': userUid,
          'startTime': start,
          'endTime': end,
          'status': 'pending review',
        };
        FakeBackendHelper.db.seedDocument('bookings', bId, doc);
        return {'success': true, 'booking': doc};
      });

      // 1. The resident schedules a booking
      final slot1Start = DateTime(now.year, now.month, now.day + 2, 10, 0);
      final slot1End = DateTime(now.year, now.month, now.day + 2, 14, 0);
      await bookingService.createBooking(facilityId, slot1Start, slot1End);

      var bookings = await FakeBackendHelper.db.streamCollection('bookings').first;
      expect(bookings.length, equals(1));
      final b1Id = bookings.first['id'];
      expect(bookings.first['status'], equals('pending review'));

      // 2. The admin rejects with a rejection reason
      const reason = 'Maintenance scheduled on this date';
      await FakeBackendHelper.db.updateDocument('bookings', b1Id, {
        'status': 'rejected',
        'rejectionReason': reason,
        'notes': reason,
      });

      final rejectedDoc = await FakeBackendHelper.db.getDocument('bookings', b1Id);
      expect(rejectedDoc?['status'], equals('rejected'));

      // 3. The resident creates a new booking (possible since previous was rejected)
      final slot2Start = DateTime(now.year, now.month, now.day + 3, 10, 0);
      final slot2End = DateTime(now.year, now.month, now.day + 3, 14, 0);
      await bookingService.createBooking(facilityId, slot2Start, slot2End);

      bookings = await FakeBackendHelper.db.streamCollection('bookings').first;
      expect(bookings.length, equals(2));
      final b2Id = bookings.firstWhere((b) => b['id'] != b1Id)['id'];

      // 4. The admin approves
      await FakeBackendHelper.db.updateDocument('bookings', b2Id, {
        'status': 'approved (upcoming)',
      });

      final approvedDoc = await FakeBackendHelper.db.getDocument('bookings', b2Id);
      expect(approvedDoc?['status'], equals('approved (upcoming)'));

      // 5. The resident tries to book again (should fail due to cooldown)
      final slot3Start = DateTime(now.year, now.month, now.day + 5, 10, 0); // 2 days later, within 7-day cooldown
      final slot3End = DateTime(now.year, now.month, now.day + 5, 14, 0);

      expect(
        () => bookingService.createBooking(facilityId, slot3Start, slot3End),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('You are only allowed to book this facility once every 7 days'),
        )),
      );

      // 6. The necessary time passes (resident chooses slot 10 days later, outside 7-day cooldown)
      final slot4Start = DateTime(now.year, now.month, now.day + 13, 10, 0);
      final slot4End = DateTime(now.year, now.month, now.day + 13, 14, 0);

      // 7. The resident tries to book the same facility (it should be sent for review)
      await bookingService.createBooking(facilityId, slot4Start, slot4End);

      bookings = await FakeBackendHelper.db.streamCollection('bookings').first;
      expect(bookings.length, equals(3));
      final b3 = bookings.firstWhere((b) => b['id'] != b1Id && b['id'] != b2Id);
      expect(b3['status'], equals('pending review'));
    });
  });
}
