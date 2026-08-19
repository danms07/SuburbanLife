import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/features/booking/booking_service.dart';
import '../../helpers/fake_backend.dart';

void main() {
  late BookingService bookingService;

  setUp(() {
    FakeBackendHelper.setUp();
    bookingService = BookingService();
  });

  group('BookingService - getBookings', () {
    test('filters bookings by facilityId and excludes cancelled bookings', () async {
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
  });
}
