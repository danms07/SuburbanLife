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
}
