import '../../core/backend/backend.dart';

class BookingService {
  Stream<List<Map<String, dynamic>>> getBookings(String facilityId) {
    return Backend.db.streamCollection(
      'bookings',
      filters: [
        QueryFilter('facilityId', FilterOperator.equal, facilityId),
        QueryFilter('status', FilterOperator.notEqual, 'cancelled'),
      ],
    );
  }

  Future<void> createBooking(String facilityId, DateTime startTime, DateTime endTime) async {
    try {
      await Backend.functions.callFunction('createBooking', {
        'facilityId': facilityId,
        'startTime': startTime.millisecondsSinceEpoch,
        'endTime': endTime.millisecondsSinceEpoch,
      });
    } catch (e) {
      throw Exception('Failed to create booking: $e');
    }
  }

  Future<void> cancelBooking(String bookingId) async {
    try {
      await Backend.functions.callFunction('cancelBooking', {
        'bookingId': bookingId,
      });
    } catch (e) {
      throw Exception('Failed to cancel booking: $e');
    }
  }

  Stream<List<Map<String, dynamic>>> getUserBookings(String userUid) {
    return Backend.db.streamCollection(
      'bookings',
      filters: [QueryFilter('userUid', FilterOperator.equal, userUid)],
    ).map((list) {
      list.sort((a, b) {
        final aStart = a['startTime'];
        final bStart = b['startTime'];
        final aVal = aStart is DateTime ? aStart.millisecondsSinceEpoch : (aStart as int);
        final bVal = bStart is DateTime ? bStart.millisecondsSinceEpoch : (bStart as int);
        return bVal.compareTo(aVal);
      });
      return list;
    });
  }
}

