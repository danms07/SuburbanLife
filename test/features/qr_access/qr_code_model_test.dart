import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/features/qr_access/qr_code.dart';

void main() {
  group('QrCode Model', () {
    final fixedExpiry = DateTime(2026, 8, 20, 18, 0);

    test('toMap serializes QrCode fields and maps enum type correctly', () {
      final qr = QrCode(
        id: 'qr_101',
        creatorUid: 'resident_456',
        guestName: 'Carlos Visitor',
        vehicleType: 'car',
        vehiclePlates: 'XYZ-789',
        passengers: 3,
        type: QrType.temporary,
        expiryTime: fixedExpiry,
        isValid: true,
      );

      final map = qr.toMap();

      expect(map['creatorUid'], equals('resident_456'));
      expect(map['guestName'], equals('Carlos Visitor'));
      expect(map['vehicleType'], equals('car'));
      expect(map['vehiclePlates'], equals('XYZ-789'));
      expect(map['passengers'], equals(3));
      expect(map['type'], equals('temporary'));
      expect(map['expiryTime'], equals(fixedExpiry));
      expect(map['isValid'], isTrue);
    });

    test('fromMap parses temporary and permanent types correctly', () {
      final tempMap = {
        'creatorUid': 'user_1',
        'guestName': 'Guest One',
        'type': 'temporary',
        'expiryTime': fixedExpiry,
        'isValid': true,
      };
      final tempQr = QrCode.fromMap('qr_temp', tempMap);
      expect(tempQr.type, equals(QrType.temporary));
      expect(tempQr.guestName, equals('Guest One'));

      final permMap = {
        'creatorUid': 'user_1',
        'guestName': 'Family Member',
        'type': 'permanent',
        'isValid': true,
      };
      final permQr = QrCode.fromMap('qr_perm', permMap);
      expect(permQr.type, equals(QrType.permanent));
    });

    test('fromMap applies default values when optional fields are omitted', () {
      final minimalMap = {
        'creatorUid': 'user_2',
      };

      final qr = QrCode.fromMap('qr_min', minimalMap);

      expect(qr.id, equals('qr_min'));
      expect(qr.creatorUid, equals('user_2'));
      expect(qr.guestName, equals('Guest'));
      expect(qr.type, equals(QrType.temporary));
      expect(qr.isValid, isTrue);
      expect(qr.vehicleType, isNull);
      expect(qr.vehiclePlates, isNull);
      expect(qr.passengers, isNull);
      expect(qr.expiryTime, isNull);
    });
  });
}
