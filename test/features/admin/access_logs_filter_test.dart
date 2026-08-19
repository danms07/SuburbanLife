import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Admin Access Logs Filtering Logic', () {
    final sampleLogs = [
      {
        'id': 'log-1',
        'guestName': 'John Doe',
        'accessCategory': 'visitor',
        'addressDisplay': 'Calle Roble #101',
        'streetName': 'Calle Roble',
        'number': '101',
        'vehiclePlates': 'ABC-123',
        'status': 'allowed',
        'timestamp': DateTime(2026, 8, 18, 10, 30).millisecondsSinceEpoch,
        'reason': 'Family visit',
      },
      {
        'id': 'log-2',
        'guestName': 'Acme Delivery Services',
        'accessCategory': 'supplier',
        'addressDisplay': 'Calle Roble #101',
        'streetName': 'Calle Roble',
        'number': '101',
        'vehiclePlates': 'XYZ-999',
        'status': 'allowed',
        'timestamp': DateTime(2026, 8, 18, 14, 0).millisecondsSinceEpoch,
        'reason': 'Package delivery',
      },
      {
        'id': 'log-3',
        'guestName': 'Carlos Gomez',
        'accessCategory': 'visitor',
        'addressDisplay': 'Av. Los Pinos #50',
        'streetName': 'Av. Los Pinos',
        'number': '50',
        'vehiclePlates': 'MNO-456',
        'status': 'denied',
        'timestamp': DateTime(2026, 8, 10, 9, 0).millisecondsSinceEpoch,
        'reason': 'QR Code has expired',
      },
    ];

    test('Filters by destination address correctly', () {
      final filtered = sampleLogs.where((log) {
        return log['addressDisplay'] == 'Calle Roble #101';
      }).toList();

      expect(filtered.length, 2);
      expect(filtered.map((l) => l['id']), containsAll(['log-1', 'log-2']));
    });

    test('Filters by visitor category (guest vs supplier) correctly', () {
      final suppliers = sampleLogs.where((log) => log['accessCategory'] == 'supplier').toList();
      final guests = sampleLogs.where((log) => log['accessCategory'] == 'visitor').toList();

      expect(suppliers.length, 1);
      expect(suppliers.first['guestName'], 'Acme Delivery Services');

      expect(guests.length, 2);
      expect(guests.map((l) => l['id']), containsAll(['log-1', 'log-3']));
    });

    test('Filters by date range correctly', () {
      final start = DateTime(2026, 8, 18, 0, 0, 0);
      final end = DateTime(2026, 8, 18, 23, 59, 59);

      final filtered = sampleLogs.where((log) {
        final dt = DateTime.fromMillisecondsSinceEpoch(log['timestamp'] as int);
        return !dt.isBefore(start) && !dt.isAfter(end);
      }).toList();

      expect(filtered.length, 2);
      expect(filtered.map((l) => l['id']), containsAll(['log-1', 'log-2']));
    });

    test('Filters by search keyword across guest name, plates and reason', () {
      bool matchesSearch(Map<String, dynamic> log, String query) {
        final q = query.toLowerCase();
        return (log['guestName'] as String).toLowerCase().contains(q) ||
            (log['vehiclePlates'] as String).toLowerCase().contains(q) ||
            (log['reason'] as String).toLowerCase().contains(q);
      }

      final queryPlates = sampleLogs.where((l) => matchesSearch(l, 'XYZ')).toList();
      expect(queryPlates.length, 1);
      expect(queryPlates.first['id'], 'log-2');

      final queryReason = sampleLogs.where((l) => matchesSearch(l, 'expired')).toList();
      expect(queryReason.length, 1);
      expect(queryReason.first['id'], 'log-3');
    });
  });
}
