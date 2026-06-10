
enum QrType { temporary, permanent }

class QrCode {
  final String id;
  final String creatorUid;
  final String guestName;
  final String? vehicleType;
  final String? vehiclePlates;
  final int? passengers;
  final QrType type;
  final DateTime? expiryTime;
  final bool isValid;

  QrCode({
    required this.id,
    required this.creatorUid,
    required this.guestName,
    this.vehicleType,
    this.vehiclePlates,
    this.passengers,
    required this.type,
    this.expiryTime,
    this.isValid = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'creatorUid': creatorUid,
      'guestName': guestName,
      'vehicleType': vehicleType,
      'vehiclePlates': vehiclePlates,
      'passengers': passengers,
      'type': type.name,
      'expiryTime': expiryTime,
      'isValid': isValid,
    };
  }

  factory QrCode.fromMap(String id, Map<String, dynamic> map) {
    return QrCode(
      id: id,
      creatorUid: map['creatorUid'] ?? '',
      guestName: map['guestName'] ?? 'Guest',
      vehicleType: map['vehicleType'],
      vehiclePlates: map['vehiclePlates'],
      passengers: map['passengers'] as int?,
      type: QrType.values.byName(map['type'] ?? 'temporary'),
      expiryTime: map['expiryTime'] as DateTime?,
      isValid: map['isValid'] ?? true,
    );
  }
}
