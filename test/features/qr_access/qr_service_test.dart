import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/features/qr_access/qr_service.dart';
import '../../helpers/fake_backend.dart';

void main() {
  late QrService qrService;

  setUp(() {
    FakeBackendHelper.setUp();
    qrService = QrService();
  });

  group('QrService - getUserQrCodes', () {
    test('filters by creatorUid and sorts in descending order of creation timestamp', () async {
      FakeBackendHelper.db.seedDocument('qr_codes', 'qr_early', {
        'id': 'qr_early',
        'creatorUid': 'resident_1',
        'guestName': 'Alice',
        'timestamp': 100000,
        'status': 'active',
      });
      FakeBackendHelper.db.seedDocument('qr_codes', 'qr_late', {
        'id': 'qr_late',
        'creatorUid': 'resident_1',
        'guestName': 'Bob',
        'timestamp': 200000,
        'status': 'active',
      });
      FakeBackendHelper.db.seedDocument('qr_codes', 'qr_other', {
        'id': 'qr_other',
        'creatorUid': 'resident_2',
        'guestName': 'Charlie',
        'timestamp': 300000,
      });

      final stream = qrService.getUserQrCodes('resident_1');
      final list = await stream.first;

      expect(list.length, equals(2));
      expect(list[0]['id'], equals('qr_late'));
      expect(list[0]['guestName'], equals('Bob'));
      expect(list[1]['id'], equals('qr_early'));
      expect(list[1]['guestName'], equals('Alice'));
    });

    test('handles DateTime timestamp objects correctly during sorting', () async {
      final t1 = DateTime(2026, 3, 1);
      final t2 = DateTime(2026, 4, 1);

      FakeBackendHelper.db.seedDocument('qr_codes', 'qr_dt_early', {
        'id': 'qr_dt_early',
        'creatorUid': 'resident_dt',
        'timestamp': t1,
      });
      FakeBackendHelper.db.seedDocument('qr_codes', 'qr_dt_late', {
        'id': 'qr_dt_late',
        'creatorUid': 'resident_dt',
        'timestamp': t2,
      });

      final stream = qrService.getUserQrCodes('resident_dt');
      final list = await stream.first;

      expect(list.length, equals(2));
      expect(list[0]['id'], equals('qr_dt_late'));
      expect(list[1]['id'], equals('qr_dt_early'));
    });
  });

  group('QrService - invalidateQrCode', () {
    test('updates document status to "deactivated (revoked)"', () async {
      FakeBackendHelper.db.seedDocument('qr_codes', 'qr_active', {
        'id': 'qr_active',
        'creatorUid': 'user_1',
        'guestName': 'David',
        'status': 'active',
      });

      await qrService.invalidateQrCode('qr_active');

      final updated = await FakeBackendHelper.db.getDocument('qr_codes', 'qr_active');
      expect(updated?['status'], equals('deactivated (revoked)'));
    });
  });

  group('QrService - resolveEffectiveStatus', () {
    test('normalizes used, revoked, and expired status synonyms', () {
      expect(
        QrService.resolveEffectiveStatus({'status': 'used'}),
        equals('deactivated (validated)'),
      );
      expect(
        QrService.resolveEffectiveStatus({'status': 'deactivated (validated)'}),
        equals('deactivated (validated)'),
      );
      expect(
        QrService.resolveEffectiveStatus({'status': 'revoked'}),
        equals('deactivated (revoked)'),
      );
      expect(
        QrService.resolveEffectiveStatus({'status': 'expired'}),
        equals('deactivated (expired)'),
      );
      expect(
        QrService.resolveEffectiveStatus({'status': 'active', 'isValid': false}),
        equals('deactivated'),
      );
    });

    test('resolves active supplier or temporary QR code past expiryTime to deactivated (expired)', () {
      final now = DateTime(2026, 10, 12, 14, 0, 0);
      final pastExpiry = DateTime(2026, 10, 4, 23, 59, 59);
      final futureExpiry = DateTime(2026, 10, 12, 23, 59, 59);

      expect(
        QrService.resolveEffectiveStatus(
          {
            'status': 'active',
            'accessCategory': 'supplier',
            'isOneTimeUse': true,
            'expiryTime': pastExpiry,
          },
          now: now,
        ),
        equals('deactivated (expired)'),
      );

      expect(
        QrService.resolveEffectiveStatus(
          {
            'status': 'active',
            'accessCategory': 'supplier',
            'isOneTimeUse': true,
            'expiryTime': futureExpiry,
          },
          now: now,
        ),
        equals('active'),
      );
    });
  });

  group('QrService - isVisitorInside', () {
    test('returns true only when isInside is explicitly true', () {
      expect(QrService.isVisitorInside({'isInside': true}), isTrue);
      expect(QrService.isVisitorInside({'isInside': false}), isFalse);
      expect(QrService.isVisitorInside({}), isFalse);
      expect(QrService.isVisitorInside({'isInside': null}), isFalse);
    });

    test('preserves isInside flag across getUserQrCodes stream', () async {
      FakeBackendHelper.db.seedDocument('qr_codes', 'qr_inside', {
        'id': 'qr_inside',
        'creatorUid': 'res_inside',
        'guestName': 'Maria Inside',
        'timestamp': 500000,
        'status': 'active',
        'isInside': true,
        'activeAccessLogId': 'log_99',
      });

      final list = await qrService.getUserQrCodes('res_inside').first;
      expect(list.length, equals(1));
      expect(QrService.isVisitorInside(list.first), isTrue);
      expect(list.first['activeAccessLogId'], equals('log_99'));
    });
  });
}
