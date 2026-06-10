import '../../core/backend/backend.dart';

class QrService {
  Stream<List<Map<String, dynamic>>> getUserQrCodes(String userUid) {
    return Backend.db.streamCollection(
      'qr_codes',
      filters: [QueryFilter('creatorUid', FilterOperator.equal, userUid)],
    ).map((list) {
      // Sort by timestamp if available, or fallback
      list.sort((a, b) {
        final aTime = a['timestamp'] ?? 0;
        final bTime = b['timestamp'] ?? 0;
        final aVal = aTime is DateTime ? aTime.millisecondsSinceEpoch : (aTime as int);
        final bVal = bTime is DateTime ? bTime.millisecondsSinceEpoch : (bTime as int);
        return bVal.compareTo(aVal);
      });
      return list;
    });
  }

  Future<void> invalidateQrCode(String qrId) async {
    await Backend.db.updateDocument('qr_codes', qrId, {
      'status': 'deactivated (revoked)',
    });
  }
}

