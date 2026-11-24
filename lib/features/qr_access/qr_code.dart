
enum QrType { temporary, permanent }

class QrCode {
  final String id;
  final String creatorUid;
  final String guestName;
  final String? destinationAddress;
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
    this.destinationAddress,
    this.vehicleType,
    this.vehiclePlates,
    this.passengers,
    required this.type,
    this.expiryTime,
    this.isValid = true,
  });

  /// Formats a street name and optional house number into a clean display address,
  /// omitting placeholder number `'0'` used by `admin_office`.
  static String formatAddressParts(dynamic streetName, dynamic number) {
    final street = streetName?.toString().trim() ?? '';
    final cleanNumber = number?.toString().trim() ?? '';
    if (street.isNotEmpty && cleanNumber.isNotEmpty && cleanNumber != '0') {
      return '$street #$cleanNumber';
    }
    if (street.isNotEmpty) {
      return street;
    }
    if (cleanNumber.isNotEmpty && cleanNumber != '0') {
      return '#$cleanNumber';
    }
    return '';
  }

  Map<String, dynamic> toMap() {
    return {
      'creatorUid': creatorUid,
      'guestName': guestName,
      'destinationAddress': destinationAddress,
      'vehicleType': vehicleType,
      'vehiclePlates': vehiclePlates,
      'passengers': passengers,
      'type': type.name,
      'expiryTime': expiryTime,
      'isValid': isValid,
    };
  }

  factory QrCode.fromMap(String id, Map<String, dynamic> map) {
    final rawDestination = (map['destinationAddress'] ?? map['addressDisplay'])?.toString().trim();
    final fallbackAddress = formatAddressParts(map['streetName'], map['number']);
    final resolvedDestination = (rawDestination != null && rawDestination.isNotEmpty)
        ? rawDestination
        : (fallbackAddress.isNotEmpty ? fallbackAddress : null);
    final rawType = map['type']?.toString().trim().toLowerCase();
    final parsedType = rawType == QrType.permanent.name ? QrType.permanent : QrType.temporary;

    return QrCode(
      id: id,
      creatorUid: map['creatorUid'] ?? '',
      guestName: map['guestName'] ?? 'Guest',
      destinationAddress: resolvedDestination,
      vehicleType: map['vehicleType'],
      vehiclePlates: map['vehiclePlates'],
      passengers: map['passengers'] as int?,
      type: parsedType,
      expiryTime: map['expiryTime'] as DateTime?,
      isValid: map['isValid'] ?? true,
    );
  }
}
