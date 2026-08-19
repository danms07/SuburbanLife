import 'package:flutter_test/flutter_test.dart';

String formatMonthLabel(DateTime dt) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[dt.month - 1]} ${dt.year}';
}

List<DateTime> generateMonthRange(DateTime startMonth, DateTime endMonth) {
  List<DateTime> range = [];
  DateTime current = DateTime(startMonth.year, startMonth.month, 1);
  final end = DateTime(endMonth.year, endMonth.month, 1);

  while (!current.isAfter(end)) {
    range.add(current);
    current = DateTime(current.year, current.month + 1, 1);
  }
  return range;
}

String computeMatrixStatus({
  required DateTime targetMonth,
  required DateTime currentActiveMonth,
  required int currentDay,
  required int cutoffDay,
  required int graceDays,
  required List<Map<String, dynamic>> matchingPayments,
}) {
  final hasApproved = matchingPayments.any((p) => p['status'] == 'approved');
  final hasPending = matchingPayments.any((p) => p['status'] == 'pending');

  if (hasApproved) {
    return 'paid';
  } else if (hasPending) {
    return 'pending';
  } else {
    final graceThresholdDay = cutoffDay + graceDays;
    if (targetMonth.isBefore(currentActiveMonth)) {
      return 'past due';
    } else if (targetMonth.isAtSameMomentAs(currentActiveMonth)) {
      if (currentDay <= graceThresholdDay) {
        return 'pending';
      } else {
        return 'past due';
      }
    } else {
      return 'pending';
    }
  }
}

void main() {
  group('Admin Payment Report - Month Range & Matrix Status', () {
    test('generateMonthRange creates sequential list of months within boundary', () {
      final start = DateTime(2025, 11, 1);
      final end = DateTime(2026, 2, 1);

      final months = generateMonthRange(start, end);

      expect(months.length, equals(4));
      expect(months[0], equals(DateTime(2025, 11, 1)));
      expect(months[1], equals(DateTime(2025, 12, 1)));
      expect(months[2], equals(DateTime(2026, 1, 1)));
      expect(months[3], equals(DateTime(2026, 2, 1)));
    });

    test('formatMonthLabel creates clean abbreviated English string', () {
      expect(formatMonthLabel(DateTime(2026, 1, 15)), equals('Jan 2026'));
      expect(formatMonthLabel(DateTime(2026, 8, 1)), equals('Aug 2026'));
      expect(formatMonthLabel(DateTime(2026, 12, 31)), equals('Dec 2026'));
    });

    test('computeMatrixStatus returns "paid" when approved payment exists', () {
      final status = computeMatrixStatus(
        targetMonth: DateTime(2026, 5, 1),
        currentActiveMonth: DateTime(2026, 5, 1),
        currentDay: 20,
        cutoffDay: 1,
        graceDays: 10,
        matchingPayments: [{'status': 'approved'}],
      );

      expect(status, equals('paid'));
    });

    test('computeMatrixStatus returns "pending" during grace period when no payment exists', () {
      // Cutoff: 1, Grace: 10 -> Threshold: Day 11. Current day is 5.
      final status = computeMatrixStatus(
        targetMonth: DateTime(2026, 5, 1),
        currentActiveMonth: DateTime(2026, 5, 1),
        currentDay: 5,
        cutoffDay: 1,
        graceDays: 10,
        matchingPayments: [],
      );

      expect(status, equals('pending'));
    });

    test('computeMatrixStatus returns "past due" past grace period when no payment exists', () {
      // Cutoff: 1, Grace: 10 -> Threshold: Day 11. Current day is 15.
      final status = computeMatrixStatus(
        targetMonth: DateTime(2026, 5, 1),
        currentActiveMonth: DateTime(2026, 5, 1),
        currentDay: 15,
        cutoffDay: 1,
        graceDays: 10,
        matchingPayments: [],
      );

      expect(status, equals('past due'));
    });

    test('computeMatrixStatus returns "past due" for previous months with no payment', () {
      final status = computeMatrixStatus(
        targetMonth: DateTime(2026, 3, 1),
        currentActiveMonth: DateTime(2026, 5, 1),
        currentDay: 5,
        cutoffDay: 1,
        graceDays: 10,
        matchingPayments: [],
      );

      expect(status, equals('past due'));
    });
  });
}
