import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/features/booking/booking_screen.dart';
import 'package:suburban_life/features/booking/booking_service.dart';
import 'package:suburban_life/features/booking/manage_bookings_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

void main() {
  late BookingService bookingService;

  setUp(() {
    FakeBackendHelper.setUp();
    bookingService = BookingService();
  });

  Widget wrapWithMaterial(Widget child, {Locale? locale}) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }

  group('BookingService - Cooldown & Quota Evaluation Helpers', () {
    test('resolveRestriction supports legacy cooldown, explicit cooldown (hours..years), and quota (daily..yearly)', () {
      expect(BookingService.resolveRestriction(null).isUnrestricted, isTrue);

      final legacy = BookingService.resolveRestriction({
        'cooldownUnit': 'days',
        'cooldownValue': 7,
      });
      expect(legacy.isCooldown, isTrue);
      expect(legacy.cooldownUnit, equals('days'));
      expect(legacy.cooldownValue, equals(7));

      final hoursCooldown = BookingService.resolveRestriction({
        'restrictionType': 'cooldown',
        'cooldownUnit': 'hours',
        'cooldownValue': 4,
      });
      expect(hoursCooldown.isCooldown, isTrue);
      expect(hoursCooldown.cooldownUnit, equals('hours'));
      expect(hoursCooldown.cooldownValue, equals(4));

      final monthlyQuota = BookingService.resolveRestriction({
        'restrictionType': 'quota',
        'quotaPeriod': 'monthly',
        'quotaLimit': 2,
      });
      expect(monthlyQuota.isQuota, isTrue);
      expect(monthlyQuota.quotaPeriod, equals('monthly'));
      expect(monthlyQuota.quotaLimit, equals(2));
    });

    test('addCooldownOffset clamps month-end and leap-year rollovers accurately', () {
      final jan31 = DateTime(2026, 1, 31, 14, 0);
      expect(BookingService.addCooldownOffset(jan31, 'hours', 5), equals(DateTime(2026, 1, 31, 19, 0)));
      expect(BookingService.addCooldownOffset(jan31, 'months', 1), equals(DateTime(2026, 2, 28, 14, 0)));

      final feb29Leap = DateTime(2024, 2, 29, 10, 30);
      expect(BookingService.addCooldownOffset(feb29Leap, 'years', 1), equals(DateTime(2025, 2, 28, 10, 30)));
    });

    test('evaluateRestriction enforces symmetric endTime->startTime cooldown and excludes rejected/cancelled bookings', () {
      final facility = {
        'restrictionType': 'cooldown',
        'cooldownUnit': 'hours',
        'cooldownValue': 3,
      };
      final bookings = [
        {
          'id': 'b_active',
          'status': 'pending review',
          'startTime': DateTime(2026, 6, 10, 10, 0).millisecondsSinceEpoch,
          'endTime': DateTime(2026, 6, 10, 12, 0).millisecondsSinceEpoch,
        },
        {
          'id': 'b_rejected',
          'status': 'rejected',
          'startTime': DateTime(2026, 6, 10, 15, 0).millisecondsSinceEpoch,
          'endTime': DateTime(2026, 6, 10, 17, 0).millisecondsSinceEpoch,
        },
      ];

      // 14:00 is only 2h after 12:00 end -> blocked
      final blockedAfter = BookingService.evaluateRestriction(
        facilityDoc: facility,
        requestedStart: DateTime(2026, 6, 10, 14, 0),
        requestedEnd: DateTime(2026, 6, 10, 16, 0),
        householdBookings: bookings,
      );
      expect(blockedAfter.isAllowed, isFalse);
      expect(blockedAfter.nextAvailableStart, equals(DateTime(2026, 6, 10, 15, 0)));

      // 15:00 is 3h after 12:00 end (and b_rejected at 15:00 is ignored) -> allowed
      final allowedAfter = BookingService.evaluateRestriction(
        facilityDoc: facility,
        requestedStart: DateTime(2026, 6, 10, 15, 0),
        requestedEnd: DateTime(2026, 6, 10, 17, 0),
        householdBookings: bookings,
      );
      expect(allowedAfter.isAllowed, isTrue);

      // 06:00 - 07:00 ends 3h before 10:00 start -> allowed symmetrically
      final allowedBefore = BookingService.evaluateRestriction(
        facilityDoc: facility,
        requestedStart: DateTime(2026, 6, 10, 6, 0),
        requestedEnd: DateTime(2026, 6, 10, 7, 0),
        householdBookings: bookings,
      );
      expect(allowedBefore.isAllowed, isTrue);
    });

    test('evaluateRestriction counts pending + approved bookings per daily/monthly/yearly calendar period', () {
      final facility = {
        'restrictionType': 'quota',
        'quotaPeriod': 'monthly',
        'quotaLimit': 2,
      };
      final bookings = [
        {
          'id': 'b1',
          'status': 'approved (upcoming)',
          'startTime': DateTime(2026, 8, 3, 10, 0).millisecondsSinceEpoch,
          'endTime': DateTime(2026, 8, 3, 12, 0).millisecondsSinceEpoch,
        },
        {
          'id': 'b2',
          'status': 'pending review',
          'startTime': DateTime(2026, 8, 15, 10, 0).millisecondsSinceEpoch,
          'endTime': DateTime(2026, 8, 15, 12, 0).millisecondsSinceEpoch,
        },
        {
          'id': 'b3_cancelled',
          'status': 'cancelled',
          'startTime': DateTime(2026, 8, 20, 10, 0).millisecondsSinceEpoch,
          'endTime': DateTime(2026, 8, 20, 12, 0).millisecondsSinceEpoch,
        },
      ];

      final evalAug = BookingService.evaluateRestriction(
        facilityDoc: facility,
        requestedStart: DateTime(2026, 8, 25, 10, 0),
        requestedEnd: DateTime(2026, 8, 25, 12, 0),
        householdBookings: bookings,
      );
      expect(evalAug.isAllowed, isFalse);
      expect(evalAug.quotaUsed, equals(2));

      final evalSep = BookingService.evaluateRestriction(
        facilityDoc: facility,
        requestedStart: DateTime(2026, 9, 1, 10, 0),
        requestedEnd: DateTime(2026, 9, 1, 12, 0),
        householdBookings: bookings,
      );
      expect(evalSep.isAllowed, isTrue);
      expect(evalSep.quotaUsed, equals(0));
    });

    test('getHouseholdFacilityBookings merges household addressId bookings with legacy userUid bookings', () async {
      // Roommate booking with addressId
      FakeBackendHelper.db.seedDocument('bookings', 'b_roommate', {
        'id': 'b_roommate',
        'facilityId': 'grill',
        'userUid': 'roommate_1',
        'addressId': 'addr_99',
        'status': 'pending review',
      });
      // Legacy booking by caller without addressId
      FakeBackendHelper.db.seedDocument('bookings', 'b_legacy_self', {
        'id': 'b_legacy_self',
        'facilityId': 'grill',
        'userUid': 'primary_1',
        'status': 'approved (upcoming)',
      });
      // Neighbor booking at another address
      FakeBackendHelper.db.seedDocument('bookings', 'b_neighbor', {
        'id': 'b_neighbor',
        'facilityId': 'grill',
        'userUid': 'neighbor_1',
        'addressId': 'addr_100',
        'status': 'approved (upcoming)',
      });

      final merged = await bookingService
          .getHouseholdFacilityBookings(
            facilityId: 'grill',
            userUid: 'primary_1',
            addressId: 'addr_99',
          )
          .first;

      final ids = merged.map((b) => b['id']).toSet();
      expect(ids, equals({'b_roommate', 'b_legacy_self'}));
    });
  });

  group('BookingService - getBookings', () {
    test('filters bookings by facilityId and excludes cancelled and rejected bookings', () async {
      FakeBackendHelper.db.seedDocument('bookings', 'b_1', {
        'id': 'b_1',
        'facilityId': 'pool',
        'status': 'approved',
      });
      FakeBackendHelper.db.seedDocument('bookings', 'b_2', {
        'id': 'b_2',
        'facilityId': 'pool',
        'status': 'cancelled',
      });
      FakeBackendHelper.db.seedDocument('bookings', 'b_3', {
        'id': 'b_3',
        'facilityId': 'pool',
        'status': 'rejected',
      });
      FakeBackendHelper.db.seedDocument('bookings', 'b_4', {
        'id': 'b_4',
        'facilityId': 'gym',
        'status': 'approved',
      });

      final stream = bookingService.getBookings('pool');
      final list = await stream.first;

      expect(list.length, equals(1));
      expect(list.first['id'], equals('b_1'));
      expect(list.first['facilityId'], equals('pool'));
    });
  });

  group('BookingService - getUserBookings', () {
    test('sorts user bookings in descending order of start time with epoch integer timestamps', () async {
      FakeBackendHelper.db.seedDocument('bookings', 'b_earlier', {
        'id': 'b_earlier',
        'userUid': 'user_123',
        'startTime': 1000000,
        'status': 'approved',
      });
      FakeBackendHelper.db.seedDocument('bookings', 'b_later', {
        'id': 'b_later',
        'userUid': 'user_123',
        'startTime': 2000000,
        'status': 'approved',
      });
      FakeBackendHelper.db.seedDocument('bookings', 'b_other_user', {
        'id': 'b_other_user',
        'userUid': 'user_999',
        'startTime': 3000000,
      });

      final stream = bookingService.getUserBookings('user_123');
      final list = await stream.first;

      expect(list.length, equals(2));
      expect(list[0]['id'], equals('b_later'));
      expect(list[1]['id'], equals('b_earlier'));
    });

    test('sorts user bookings in descending order of start time with DateTime instances', () async {
      final t1 = DateTime(2026, 1, 1);
      final t2 = DateTime(2026, 6, 1);

      FakeBackendHelper.db.seedDocument('bookings', 'b_dt_earlier', {
        'id': 'b_dt_earlier',
        'userUid': 'user_abc',
        'startTime': t1,
      });
      FakeBackendHelper.db.seedDocument('bookings', 'b_dt_later', {
        'id': 'b_dt_later',
        'userUid': 'user_abc',
        'startTime': t2,
      });

      final stream = bookingService.getUserBookings('user_abc');
      final list = await stream.first;

      expect(list.length, equals(2));
      expect(list[0]['id'], equals('b_dt_later'));
      expect(list[1]['id'], equals('b_dt_earlier'));
    });
  });

  group('BookingService - createBooking and cancelBooking', () {
    test('createBooking passes correct parameters and optional resubmitBookingId to functions backend', () async {
      final start = DateTime(2026, 5, 10, 10, 0);
      final end = DateTime(2026, 5, 10, 12, 0);

      await bookingService.createBooking('multipurpose_room', start, end, resubmitBookingId: 'rej_99');

      expect(FakeBackendHelper.functions.callHistory.length, equals(1));
      final call = FakeBackendHelper.functions.callHistory.first;
      expect(call['name'], equals('createBooking'));
      expect(call['parameters']['facilityId'], equals('multipurpose_room'));
      expect(call['parameters']['startTime'], equals(start.millisecondsSinceEpoch));
      expect(call['parameters']['endTime'], equals(end.millisecondsSinceEpoch));
      expect(call['parameters']['resubmitBookingId'], equals('rej_99'));
    });

    test('createBooking throws formatted exception when functions call fails', () async {
      FakeBackendHelper.functions.registerHandler('createBooking', (_) {
        throw Exception('Facility already booked');
      });

      final start = DateTime(2026, 5, 10, 10, 0);
      final end = DateTime(2026, 5, 10, 12, 0);

      expect(
        () => bookingService.createBooking('pool', start, end),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Failed to create booking'))),
      );
    });

    test('cancelBooking invokes cancelBooking function correctly', () async {
      await bookingService.cancelBooking('booking_to_cancel');

      expect(FakeBackendHelper.functions.callHistory.length, equals(1));
      final call = FakeBackendHelper.functions.callHistory.first;
      expect(call['name'], equals('cancelBooking'));
      expect(call['parameters']['bookingId'], equals('booking_to_cancel'));
    });

    test('cancelBooking throws formatted exception when function returns error', () async {
      FakeBackendHelper.functions.registerHandler('cancelBooking', (_) {
        throw Exception('Booking cannot be cancelled');
      });

      expect(
        () => bookingService.cancelBooking('invalid_id'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Failed to cancel booking'))),
      );
    });

    test('Full booking lifecycle: schedule -> reject -> re-book -> approve -> cooldown blocked -> time passes -> review', () async {
      final now = DateTime.now();
      const facilityId = 'multipurpose_room';
      const userUid = 'resident_uid_test';

      FakeBackendHelper.auth.emitUser(
        AppUser(
          uid: userUid,
          email: 'resident@test.com',
          displayName: 'Test Resident',
        ),
      );

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_test');
      FakeBackendHelper.db.seedDocument('addresses', 'addr_test', {
        'paymentStatus': 'paid',
      });
      FakeBackendHelper.db.seedDocument('users', userUid, {
        'addressRef': addrRef,
      });

      FakeBackendHelper.db.seedDocument('facilities', facilityId, {
        'id': facilityId,
        'restrictionType': 'cooldown',
        'cooldownUnit': 'days',
        'cooldownValue': 7,
        'quantity': 1,
      });

      FakeBackendHelper.functions.registerHandler('createBooking', (params) async {
        final fId = params?['facilityId'] as String;
        final start = params?['startTime'] as int;
        final end = params?['endTime'] as int;

        final facDoc = await FakeBackendHelper.db.getDocument('facilities', fId);
        final allBookings = await FakeBackendHelper.db.streamCollection('bookings').first;
        final householdBookings = allBookings
            .where((b) => b['facilityId'] == fId && (b['addressId'] == 'addr_test' || b['userUid'] == userUid))
            .toList();

        final eval = BookingService.evaluateRestriction(
          facilityDoc: facDoc,
          requestedStart: DateTime.fromMillisecondsSinceEpoch(start),
          requestedEnd: DateTime.fromMillisecondsSinceEpoch(end),
          householdBookings: householdBookings,
        );
        if (!eval.isAllowed) {
          throw Exception('You are only allowed to book this facility once every 7 days.');
        }

        final bId = 'b_${allBookings.length + 1}';
        final doc = {
          'id': bId,
          'facilityId': fId,
          'userUid': userUid,
          'addressId': 'addr_test',
          'startTime': start,
          'endTime': end,
          'status': 'pending review',
        };
        FakeBackendHelper.db.seedDocument('bookings', bId, doc);
        return {'success': true, 'booking': doc};
      });

      final slot1Start = DateTime(now.year, now.month, now.day + 2, 10, 0);
      final slot1End = DateTime(now.year, now.month, now.day + 2, 14, 0);
      await bookingService.createBooking(facilityId, slot1Start, slot1End);

      var bookings = await FakeBackendHelper.db.streamCollection('bookings').first;
      expect(bookings.length, equals(1));
      final b1Id = bookings.first['id'];
      expect(bookings.first['status'], equals('pending review'));

      const reason = 'Maintenance scheduled on this date';
      await FakeBackendHelper.db.updateDocument('bookings', b1Id, {
        'status': 'rejected',
        'rejectionReason': reason,
        'notes': reason,
      });

      final slot2Start = DateTime(now.year, now.month, now.day + 3, 10, 0);
      final slot2End = DateTime(now.year, now.month, now.day + 3, 14, 0);
      await bookingService.createBooking(facilityId, slot2Start, slot2End);

      bookings = await FakeBackendHelper.db.streamCollection('bookings').first;
      expect(bookings.length, equals(2));
      final b2Id = bookings.firstWhere((b) => b['id'] != b1Id)['id'];

      await FakeBackendHelper.db.updateDocument('bookings', b2Id, {
        'status': 'approved (upcoming)',
      });

      final slot3Start = DateTime(now.year, now.month, now.day + 5, 10, 0);
      final slot3End = DateTime(now.year, now.month, now.day + 5, 14, 0);

      expect(
        () => bookingService.createBooking(facilityId, slot3Start, slot3End),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('You are only allowed to book this facility once every 7 days'),
        )),
      );

      final slot4Start = DateTime(now.year, now.month, now.day + 13, 10, 0);
      final slot4End = DateTime(now.year, now.month, now.day + 13, 14, 0);

      await bookingService.createBooking(facilityId, slot4Start, slot4End);

      bookings = await FakeBackendHelper.db.streamCollection('bookings').first;
      expect(bookings.length, equals(3));
      final b3 = bookings.firstWhere((b) => b['id'] != b1Id && b['id'] != b2Id);
      expect(b3['status'], equals('pending review'));
    });
  });

  group('BookingScreen & ManageBookingsScreen Widget Tests', () {
    testWidgets('BookingScreen renders quota usage badge and blocks submission when household quota is reached', (tester) async {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_ui_1');
      FakeBackendHelper.db.seedDocument('addresses', 'addr_ui_1', {
        'id': 'addr_ui_1',
        'paymentStatus': 'paid',
        'hasActiveSanctions': false,
      });
      FakeBackendHelper.db.seedDocument('users', 'res_ui_1', {
        'uid': 'res_ui_1',
        'addressRef': addrRef,
      });
      FakeBackendHelper.auth.emitUser(
        AppUser(uid: 'res_ui_1', email: 'res@ui.test', displayName: 'UI Resident'),
      );

      FakeBackendHelper.db.seedDocument('facilities', 'paddle_court', {
        'id': 'paddle_court',
        'name': 'Paddle Court',
        'restrictionType': 'quota',
        'quotaPeriod': 'daily',
        'quotaLimit': 1,
        'openingTime': '07:00',
        'closingTime': '22:00',
      });

      // Roommate already booked Paddle Court for tomorrow (counts toward household daily quota of 1)
      FakeBackendHelper.db.seedDocument('bookings', 'b_roommate_tomorrow', {
        'id': 'b_roommate_tomorrow',
        'facilityId': 'paddle_court',
        'userUid': 'roommate_ui_1',
        'addressId': 'addr_ui_1',
        'startTime': DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 15, 0).millisecondsSinceEpoch,
        'endTime': DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 16, 0).millisecondsSinceEpoch,
        'status': 'pending review',
      });

      await tester.pumpWidget(wrapWithMaterial(const BookingScreen()));
      await tester.pumpAndSettle();

      // Badge shows 1 / 1 used
      expect(find.text('Daily Quota: 1 / 1 used'), findsOneWidget);

      // Tap Confirm Booking -> blocked client-side with quota SnackBar without invoking Cloud Function
      await tester.tap(find.text('Confirm Booking'));
      await tester.pumpAndSettle();

      expect(
        find.text('Quota reached: Your household has already used all 1 allowed (daily) bookings for this amenity.'),
        findsOneWidget,
      );
      expect(FakeBackendHelper.functions.callHistory, isEmpty);
    });

    testWidgets('ManageBookingsScreen resolves custom facility names and resubmits rejected bookings via createBooking', (tester) async {
      final tomorrow = DateTime.now().add(const Duration(days: 2));
      FakeBackendHelper.auth.emitUser(
        AppUser(uid: 'res_manage_1', email: 'm@ui.test', displayName: 'Manage Resident'),
      );
      FakeBackendHelper.db.seedDocument('facilities', 'custom_padel', {
        'id': 'custom_padel',
        'name': 'Sky Padel Court',
      });
      FakeBackendHelper.db.seedDocument('bookings', 'rej_booking_1', {
        'id': 'rej_booking_1',
        'facilityId': 'custom_padel',
        'userUid': 'res_manage_1',
        'startTime': DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10, 0).millisecondsSinceEpoch,
        'endTime': DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 12, 0).millisecondsSinceEpoch,
        'status': 'rejected',
        'rejectionReason': 'Cleaning in progress',
      });

      await tester.pumpWidget(wrapWithMaterial(const ManageBookingsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Sky Padel Court'), findsOneWidget);
      expect(find.text('Cleaning in progress'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resubmit'));
      await tester.pumpAndSettle();

      expect(FakeBackendHelper.functions.callHistory.length, equals(1));
      final call = FakeBackendHelper.functions.callHistory.first;
      expect(call['name'], equals('createBooking'));
      expect(call['parameters']['facilityId'], equals('custom_padel'));
      expect(call['parameters']['resubmitBookingId'], equals('rej_booking_1'));
    });
  });
}
