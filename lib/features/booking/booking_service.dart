import '../../core/backend/backend.dart';

class BookingService {
  Stream<List<Map<String, dynamic>>> getConfirmedBookings(String facilityId) {
    return Backend.db.streamCollection(
      'bookings',
      filters: [
        QueryFilter('facilityId', FilterOperator.equal, facilityId),
        QueryFilter('isConfirmed', FilterOperator.equal, true),
      ],
    );
  }

  Stream<List<Map<String, dynamic>>> getBookings(String facilityId) {
    return Backend.db.streamCollection(
      'bookings',
      filters: [
        QueryFilter('facilityId', FilterOperator.equal, facilityId),
      ],
    ).map((list) => list.where((b) {
      if (b['status'] == 'rejected' || b['status'] == 'cancelled') return false;
      if (b.containsKey('isConfirmed')) {
        return b['isConfirmed'] == true;
      }
      final status = (b['status'] ?? '').toString().toLowerCase();
      return status.startsWith('approved') || status == 'confirmed' || status == 'closed';
    }).toList());
  }

  Future<void> createBooking(String facilityId, DateTime startTime, DateTime endTime) async {
    try {
      await Backend.functions.callFunction('createBooking', {
        'facilityId': facilityId,
        'startTime': startTime.millisecondsSinceEpoch,
        'endTime': endTime.millisecondsSinceEpoch,
      });
    } catch (e, stack) {
      Backend.crashlytics.recordError(e, stack, reason: 'BookingService.createBooking');
      throw Exception('Failed to create booking: $e');
    }
  }

  Future<void> cancelBooking(String bookingId) async {
    try {
      await Backend.functions.callFunction('cancelBooking', {
        'bookingId': bookingId,
      });
    } catch (e, stack) {
      Backend.crashlytics.recordError(e, stack, reason: 'BookingService.cancelBooking');
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

