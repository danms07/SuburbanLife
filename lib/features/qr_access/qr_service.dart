import '../../core/backend/backend.dart';

class QrService {
  /// Returns true when the visitor associated with this QR pass is currently inside the community.
  static bool isVisitorInside(Map<String, dynamic> qr) {
    return qr['isInside'] == true;
  }

  /// Resolves the effective status of a QR code document, normalizing legacy statuses
  /// ('used', 'revoked', 'expired') and marking active passes as 'deactivated (expired)'
  /// once their expiryTime has passed.
  static String resolveEffectiveStatus(Map<String, dynamic> qr, {DateTime? now}) {
    final rawStatus = (qr['status'] as String?)?.trim() ?? 'active';
    final normalized = rawStatus.toLowerCase();

    if (normalized == 'used' || normalized == 'deactivated (validated)') {
      return 'deactivated (validated)';
    }
    if (normalized == 'revoked' || normalized == 'deactivated (revoked)') {
      return 'deactivated (revoked)';
    }
    if (normalized == 'expired' || normalized == 'deactivated (expired)') {
      return 'deactivated (expired)';
    }
    if (qr['isValid'] == false && (normalized == 'active' || normalized == 'valid')) {
      return 'deactivated';
    }

    if (normalized == 'active' || normalized == 'valid') {
      final rawExpiry = qr['expiryTime'] ?? qr['expiresAt'] ?? qr['expiry'];
      DateTime? expiryDate;
      if (rawExpiry is DateTime) {
        expiryDate = rawExpiry;
      } else if (rawExpiry is int) {
        expiryDate = DateTime.fromMillisecondsSinceEpoch(rawExpiry);
      } else if (rawExpiry is String) {
        expiryDate = DateTime.tryParse(rawExpiry);
      }

      if (expiryDate != null && (now ?? DateTime.now()).isAfter(expiryDate)) {
        return 'deactivated (expired)';
      }
      return 'active';
    }

    return rawStatus;
  }

  Stream<List<Map<String, dynamic>>> getUserQrCodes(String userUid) {
    return Backend.db.streamCollection(
      'qr_codes',
      filters: [QueryFilter('creatorUid', FilterOperator.equal, userUid)],
    ).map((list) {
      final resolved = list.map((qr) {
        final copy = Map<String, dynamic>.from(qr);
        copy['status'] = resolveEffectiveStatus(copy);
        return copy;
      }).toList();

      // Sort by timestamp if available, or fallback
      resolved.sort((a, b) {
        final aTime = a['timestamp'] ?? 0;
        final bTime = b['timestamp'] ?? 0;
        final aVal = aTime is DateTime ? aTime.millisecondsSinceEpoch : (aTime as int);
        final bVal = bTime is DateTime ? bTime.millisecondsSinceEpoch : (bTime as int);
        return bVal.compareTo(aVal);
      });
      return resolved;
    });
  }

  Future<void> invalidateQrCode(String qrId) async {
    await Backend.db.updateDocument('qr_codes', qrId, {
      'status': 'deactivated (revoked)',
    });
  }
}

