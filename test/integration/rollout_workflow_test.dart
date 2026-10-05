import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/features/admin/admin_booking_approval_screen.dart';
import 'package:suburban_life/features/admin/admin_payment_approval_screen.dart';
import 'package:suburban_life/features/announcements/announcements_screen.dart';
import 'package:suburban_life/features/booking/booking_screen.dart';
import 'package:suburban_life/features/booking/booking_service.dart';
import 'package:suburban_life/features/payments/payment_service.dart';
import 'package:suburban_life/features/qr_access/qr_generator_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../helpers/fake_backend.dart';

void main() {
  late PaymentService paymentService;

  setUp(() {
    FakeBackendHelper.setUp();
    paymentService = PaymentService();

    // Register Cloud Function mock for approvePayment
    FakeBackendHelper.functions.registerHandler('approvePayment', (params) async {
      final paymentId = params?['paymentId'] as String?;
      if (paymentId != null) {
        await FakeBackendHelper.db.updateDocument('payments', paymentId, {
          'status': 'approved',
          'approvalDate': DateTime.now().millisecondsSinceEpoch,
        });
        final payDoc = await FakeBackendHelper.db.getDocument('payments', paymentId);
        if (payDoc != null) {
          if (payDoc['sanctionId'] != null) {
            await FakeBackendHelper.db.updateDocument('sanctions', payDoc['sanctionId'], {
              'status': 'paid',
              'resolvedAt': DateTime.now().millisecondsSinceEpoch,
            });
          }
          if (payDoc['addressRef'] != null) {
            await paymentService.recalculatePaymentStatusForAddress(payDoc['addressRef']);
          }
        }
      }
      return {'success': true};
    });

    // Register Cloud Function mock for createBooking with dynamic cooldown & clash checks
    FakeBackendHelper.functions.registerHandler('createBooking', (params) async {
      final facilityId = params?['facilityId'] as String?;
      final startTime = params?['startTime'] as int?;
      final endTime = params?['endTime'] as int?;
      if (facilityId == null || startTime == null || endTime == null) {
        throw Exception('Missing facilityId, startTime, or endTime.');
      }

      final uid = FakeBackendHelper.auth.currentUser?.uid;
      if (uid == null) {
        throw Exception('User must be logged in.');
      }

      // Check payment status
      final userDoc = await FakeBackendHelper.db.getDocument('users', uid);
      if (userDoc != null && userDoc['addressRef'] != null) {
        final addressRef = userDoc['addressRef'];
        final addrId = addressRef is StringDbReference ? addressRef.id : addressRef.toString();
        final addressDoc = await FakeBackendHelper.db.getDocument('addresses', addrId);
        final status = addressDoc?['paymentStatus'];
        final isWithinGrace = addressDoc?['isWithinGracePeriod'] as bool? ?? false;
        final isConsideredPaid = status == 'paid' ||
            ((status == 'pending' || status == 'reviewing') && isWithinGrace);
        if (!isConsideredPaid) {
          throw Exception('Your account is restricted due to missing payment.');
        }
      }

      final facilityDoc = await FakeBackendHelper.db.getDocument('facilities', facilityId);

      // Anticipation validation
      final anticipationUnit = facilityDoc?['anticipationUnit'] ?? 'unrestricted';
      final anticipationValue = (facilityDoc?['anticipationValue'] as num?)?.toInt() ?? 0;
      if (anticipationUnit != 'unrestricted' && anticipationValue > 0) {
        int anticipationMs = 0;
        if (anticipationUnit == 'hours') {
          anticipationMs = anticipationValue * 60 * 60 * 1000;
        } else if (anticipationUnit == 'days') {
          anticipationMs = anticipationValue * 24 * 60 * 60 * 1000;
        } else if (anticipationUnit == 'weeks') {
          anticipationMs = anticipationValue * 7 * 24 * 60 * 60 * 1000;
        }
        if (startTime < DateTime.now().millisecondsSinceEpoch + anticipationMs) {
          throw Exception('This facility requires advance notice of at least $anticipationValue $anticipationUnit.');
        }
      }

      // Daily operating hours validation
      final openingTime = facilityDoc?['openingTime'] as String? ?? '00:00';
      final closingTime = facilityDoc?['closingTime'] as String? ?? '23:59';
      if (openingTime != '00:00' || closingTime != '23:59') {
        final openParts = openingTime.split(':').map(int.parse).toList();
        final closeParts = closingTime.split(':').map(int.parse).toList();
        final openMinutes = openParts[0] * 60 + openParts[1];
        final closeMinutes = closeParts[0] * 60 + closeParts[1];

        final sDt = DateTime.fromMillisecondsSinceEpoch(startTime);
        final eDt = DateTime.fromMillisecondsSinceEpoch(endTime);
        final startMin = sDt.hour * 60 + sDt.minute;
        final endMin = eDt.hour * 60 + eDt.minute;

        if (startMin < openMinutes || endMin > closeMinutes || sDt.day != eDt.day) {
          throw Exception('Reservation must be within operating hours ($openingTime - $closingTime).');
        }
      }

      // Dynamic cooldown validation
      final cooldownUnit = facilityDoc?['cooldownUnit'] ?? 'unrestricted';
      final cooldownValue = (facilityDoc?['cooldownValue'] as num?)?.toInt() ?? 0;

      if (cooldownUnit != 'unrestricted') {
        int startTimeBoundary = 0;
        int endTimeBoundary = 0x7FFFFFFFFFFFFFFF;
        if (cooldownUnit == 'days') {
          final ms = cooldownValue * 24 * 60 * 60 * 1000;
          startTimeBoundary = startTime - ms;
          endTimeBoundary = startTime + ms;
        } else if (cooldownUnit == 'months') {
          final dt = DateTime.fromMillisecondsSinceEpoch(startTime);
          final dateBefore = DateTime(dt.year, dt.month - cooldownValue, dt.day, dt.hour, dt.minute);
          final dateAfter = DateTime(dt.year, dt.month + cooldownValue, dt.day, dt.hour, dt.minute);
          startTimeBoundary = dateBefore.millisecondsSinceEpoch;
          endTimeBoundary = dateAfter.millisecondsSinceEpoch;
        }

        final allBookings = await FakeBackendHelper.db.streamCollection('bookings').first;
        final confirmedBookings = allBookings.where((b) {
          if (b['userUid'] != uid || b['facilityId'] != facilityId) return false;
          final status = (b['status'] ?? '').toString().toLowerCase();
          final isConfirmed = status.startsWith('approved') || status == 'confirmed' || status == 'closed';
          if (!isConfirmed) return false;
          final bStart = (b['startTime'] as num).toInt();
          return bStart >= startTimeBoundary && bStart <= endTimeBoundary;
        }).toList();

        if (confirmedBookings.isNotEmpty) {
          throw Exception('You are only allowed to book this facility once every $cooldownValue $cooldownUnit.');
        }
      }

      // Clashes & Capacity validation
      final quantity = (facilityDoc?['quantity'] as num?)?.toInt() ?? 1;
      final allBookings = await FakeBackendHelper.db.streamCollection('bookings').first;
      final activeClashes = allBookings.where((b) {
        if (b['facilityId'] != facilityId) return false;
        final bStatus = b['status'];
        if (bStatus == 'cancelled' || bStatus == 'rejected') return false;
        final bStart = (b['startTime'] as num).toInt();
        final bEnd = (b['endTime'] as num).toInt();
        return !(bEnd <= startTime || bStart >= endTime);
      }).toList();

      if (activeClashes.length >= quantity) {
        throw Exception('This facility has reached its maximum booking capacity for the requested time slot.');
      }

      // Create booking document
      final bookingId = 'booking_${allBookings.length + 1}';
      final bookingData = {
        'id': bookingId,
        'facilityId': facilityId,
        'userUid': uid,
        'startTime': startTime,
        'endTime': endTime,
        'status': 'pending review',
        'isConfirmed': false,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      FakeBackendHelper.db.seedDocument('bookings', bookingId, bookingData);
      return {'success': true, 'booking': bookingData};
    });

    // Register Cloud Function mock for adminCreateUser
    FakeBackendHelper.functions.registerHandler('adminCreateUser', (params) async {
      if (FakeBackendHelper.auth.isAdminMock != true) {
        throw Exception('Function must be called by an authenticated admin.');
      }
      final name = params?['name']?.toString();
      final email = params?['email']?.toString();
      final password = params?['password']?.toString();
      final role = params?['role']?.toString();
      final addressId = params?['addressId']?.toString();
      final deliveryDateStr = params?['deliveryDate']?.toString();

      if (name == null || email == null || password == null || role == null) {
        throw Exception('Missing name, email, password, or role.');
      }

      if (role == 'resident' && deliveryDateStr != null) {
        final d = DateTime.tryParse(deliveryDateStr);
        if (d == null) {
          throw Exception('Invalid delivery date format.');
        }
        if (d.isAfter(DateTime.now())) {
          throw Exception('Delivery date cannot be in the future.');
        }
      }

      if (role == 'resident') {
        if (addressId == null) {
          throw Exception('Specified address was not found in database.');
        }
        final addressDoc = await FakeBackendHelper.db.getDocument('addresses', addressId);
        if (addressDoc == null) {
          throw Exception('Specified address was not found in database.');
        }
        if (addressDoc['residentUid'] != null && addressDoc['residentUid'].toString().trim().isNotEmpty) {
          throw Exception('The address is already claimed by another resident.');
        }

        final newUid = 'created_resident_${DateTime.now().millisecondsSinceEpoch}';
        final addressUpdate = <String, dynamic>{
          'residentUid': newUid,
        };
        if (deliveryDateStr != null) {
          addressUpdate['deliveryDate'] = DateTime.parse(deliveryDateStr);
        }
        await FakeBackendHelper.db.updateDocument('addresses', addressId, addressUpdate);

        await FakeBackendHelper.db.setDocument('users', newUid, {
          'uid': newUid,
          'name': name,
          'email': email,
          'role': role,
          'addressRef': StringDbReference('addresses/$addressId'),
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });

        return {'success': true, 'uid': newUid, 'role': role, 'emailSent': true};
      }

      final newUid = 'created_user_${DateTime.now().millisecondsSinceEpoch}';
      await FakeBackendHelper.db.setDocument('users', newUid, {
        'uid': newUid,
        'name': name,
        'email': email,
        'role': role,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      return {'success': true, 'uid': newUid, 'role': role, 'emailSent': true};
    });
  });

  Widget wrapWithMaterial(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  group('Rollout Automated Test Suite', () {
    testWidgets('Suite A: Roommate Account Linking & Address Synchronization', (tester) async {
      // 1. Seed address and primary resident
      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_101');
      FakeBackendHelper.db.seedDocument('addresses', 'addr_101', {
        'id': 'addr_101',
        'streetName': 'Calle Catania',
        'number': 101,
        'residentUid': 'resident_uid_1',
        'paymentStatus': 'paid',
      });

      FakeBackendHelper.db.seedDocument('users', 'resident_uid_1', {
        'uid': 'resident_uid_1',
        'name': 'Carlos Resident',
        'email': 'resident@test.com',
        'role': 'resident',
        'addressRef': addrRef,
      });

      // 2. Seed unlinked roommate
      FakeBackendHelper.db.seedDocument('users', 'roommate_uid_2', {
        'uid': 'roommate_uid_2',
        'name': 'Ana Roommate',
        'email': 'roommate@test.com',
        'role': 'roommate',
        'addressRef': null,
      });

      // Register Cloud Function mock for linkRoommate
      FakeBackendHelper.functions.registerHandler('linkRoommate', (params) async {
        final rUid = params?['roommateUid'] as String;
        await FakeBackendHelper.db.updateDocument('users', rUid, {
          'addressRef': addrRef,
        });
        return {'success': true};
      });

      // 3. Link roommate via function call
      final res = await FakeBackendHelper.functions.callFunction('linkRoommate', {
        'roommateUid': 'roommate_uid_2',
      });
      expect(res['success'], isTrue);

      // Verify roommate document is updated with primary address reference
      final roommateDoc = await FakeBackendHelper.db.getDocument('users', 'roommate_uid_2');
      expect(roommateDoc?['addressRef'], isNotNull);
    });

    testWidgets('Suite B: Administrative Broadcasts & Community Announcement Streaming', (tester) async {
      // 1. Admin creates announcement document
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      FakeBackendHelper.db.seedDocument('announcements', 'announcement_1', {
        'id': 'announcement_1',
        'title': '📢 Scheduled Pool Maintenance',
        'content': 'The community pool will be closed on Monday for cleaning.',
        'targetAudience': 'all',
        'timestamp': timestamp,
        'creatorUid': 'admin_uid_1',
      });

      // 2. Render resident view of AnnouncementsScreen
      FakeBackendHelper.auth.emitUser(
        AppUser(
          uid: 'resident_uid_1',
          email: 'resident@test.com',
          displayName: 'Carlos Resident',
        ),
      );
      FakeBackendHelper.auth.isResidentMock = true;
      FakeBackendHelper.auth.isAdminMock = false;

      await tester.pumpWidget(wrapWithMaterial(const AnnouncementsScreen()));
      await tester.pumpAndSettle();

      // 3. Verify announcement renders properly for residents
      expect(find.text('📢 Scheduled Pool Maintenance'), findsOneWidget);
      expect(find.text('The community pool will be closed on Monday for cleaning.'), findsOneWidget);
    });

    testWidgets('Suite C: Anticipated / Advance Multi-Period Payments Flow', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      // Delivery date set to current month (no past debt)
      final deliveryDate = DateTime(now.year, now.month, 1);

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_advance');
      FakeBackendHelper.db.seedDocument('addresses', 'addr_advance', {
        'id': 'addr_advance',
        'streetName': '1st Avenue',
        'number': 99,
        'residentUid': 'resident_advance_uid',
        'deliveryDate': deliveryDate,
        'paymentStatus': 'paid',
      });

      FakeBackendHelper.db.seedDocument('users', 'resident_advance_uid', {
        'uid': 'resident_advance_uid',
        'name': 'Carlos Gomez',
        'email': 'resident@test.com',
        'role': 'resident',
        'addressRef': addrRef,
      });

      FakeBackendHelper.auth.emitUser(
        AppUser(
          uid: 'resident_advance_uid',
          email: 'resident@test.com',
          displayName: 'Carlos Gomez',
        ),
      );
      FakeBackendHelper.auth.isResidentMock = true;
      FakeBackendHelper.auth.isAdminMock = false;

      // Seed approved payment for current month
      final currentPeriod = "${now.year}-${now.month.toString().padLeft(2, '0')}";
      FakeBackendHelper.db.seedDocument('payments', 'pay_current', {
        'addressRef': addrRef,
        'residentUid': 'resident_advance_uid',
        'periods': [currentPeriod],
        'amount': 1500.0,
        'status': 'approved',
      });

      // 1. Advance periods: next month and 2 months ahead
      final nextMonthDate = DateTime(now.year, now.month + 1, 1);
      final twoMonthsDate = DateTime(now.year, now.month + 2, 1);
      final pNext1 = "${nextMonthDate.year}-${nextMonthDate.month.toString().padLeft(2, '0')}";
      final pNext2 = "${twoMonthsDate.year}-${twoMonthsDate.month.toString().padLeft(2, '0')}";

      // 2. Submit multi-period advance payment receipt
      final paymentDocId = 'pay_advance_batch_1';
      FakeBackendHelper.db.seedDocument('payments', paymentDocId, {
        'id': paymentDocId,
        'addressRef': addrRef,
        'residentUid': 'resident_advance_uid',
        'periods': [pNext1, pNext2],
        'amount': 3000.0,
        'status': 'pending',
        'receiptUrl': '',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // 3. Admin reviews and approves the advance receipt
      FakeBackendHelper.auth.emitUser(
        AppUser(
          uid: 'admin_test_uid',
          email: 'admin@example.com',
          displayName: 'Admin User',
        ),
      );
      FakeBackendHelper.auth.isAdminMock = true;
      FakeBackendHelper.auth.isResidentMock = false;

      await tester.pumpWidget(wrapWithMaterial(const AdminPaymentApprovalScreen()));
      await tester.pumpAndSettle();

      // Verify payment card displays amount and advance periods
      expect(find.textContaining('3000.00'), findsWidgets);
      expect(find.text(pNext1), findsOneWidget);
      expect(find.text(pNext2), findsOneWidget);

      // Tap Approve button
      final approveBtn = find.byType(ElevatedButton);
      expect(approveBtn, findsOneWidget);
      await tester.tap(approveBtn);
      await tester.pumpAndSettle();

      // 4. Verify payment becomes approved and address remains paid
      final updatedPayDoc = await FakeBackendHelper.db.getDocument('payments', paymentDocId);
      expect(updatedPayDoc?['status'], equals('approved'));

      final updatedAddrDoc = await FakeBackendHelper.db.getDocument('addresses', 'addr_advance');
      expect(updatedAddrDoc?['paymentStatus'], equals('paid'));
    });

    testWidgets('Suite D: Past Due Debt, Feature Gating, and Multi-Period Recovery Flow', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      // Delivery date set to 2 months ago without approved payments
      final deliveryDate = DateTime(now.year, now.month - 2, 1);

      FakeBackendHelper.db.seedDocument('config', 'app_settings', {
        'paymentCutoffDay': 1,
        'gracePeriodDays': 5,
      });

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_debt');
      FakeBackendHelper.db.seedDocument('addresses', 'addr_debt', {
        'id': 'addr_debt',
        'streetName': 'Pine Road',
        'number': 100,
        'residentUid': 'resident_debt_uid',
        'deliveryDate': deliveryDate,
        'paymentStatus': 'paid', // Will recalculate to restricted
      });

      FakeBackendHelper.db.seedDocument('users', 'resident_debt_uid', {
        'uid': 'resident_debt_uid',
        'name': 'Overdue Resident',
        'email': 'overdue@test.com',
        'role': 'resident',
        'addressRef': addrRef,
      });

      FakeBackendHelper.auth.emitUser(
        AppUser(
          uid: 'resident_debt_uid',
          email: 'overdue@test.com',
          displayName: 'Overdue Resident',
        ),
      );
      FakeBackendHelper.auth.isResidentMock = true;
      FakeBackendHelper.auth.isAdminMock = false;

      // 1. Trigger recalculation -> Status evaluates to restricted
      final status = await paymentService.recalculatePaymentStatusForAddress('addr_debt');
      expect(status, equals('restricted'));

      // 2. Verify Feature Gating on QR Generator and Booking screens
      await tester.pumpWidget(wrapWithMaterial(const QrGeneratorScreen()));
      await tester.pumpAndSettle();
      // QR generator should show restriction notice
      expect(find.byIcon(Icons.block), findsOneWidget);

      await tester.pumpWidget(wrapWithMaterial(const BookingScreen()));
      await tester.pumpAndSettle();
      // Booking screen should show restriction notice
      expect(find.byIcon(Icons.block), findsOneWidget);

      // 3. Resident submits payment covering all past overdue months + current month
      final pMinus2 = "${deliveryDate.year}-${deliveryDate.month.toString().padLeft(2, '0')}";
      final monthMinus1 = DateTime(now.year, now.month - 1, 1);
      final pMinus1 = "${monthMinus1.year}-${monthMinus1.month.toString().padLeft(2, '0')}";
      final pCurrent = "${now.year}-${now.month.toString().padLeft(2, '0')}";

      final debtPaymentDocId = 'pay_debt_settlement';
      FakeBackendHelper.db.seedDocument('payments', debtPaymentDocId, {
        'id': debtPaymentDocId,
        'addressRef': addrRef,
        'residentUid': 'resident_debt_uid',
        'periods': [pMinus2, pMinus1, pCurrent],
        'amount': 4500.0,
        'status': 'pending',
        'receiptUrl': '',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Recalculate status while pending -> becomes pending
      final pendingStatus = await paymentService.recalculatePaymentStatusForAddress('addr_debt');
      expect(pendingStatus, equals('pending'));

      // 4. Admin approves the debt recovery payment receipt
      FakeBackendHelper.auth.emitUser(
        AppUser(
          uid: 'admin_test_uid',
          email: 'admin@example.com',
          displayName: 'Admin User',
        ),
      );
      FakeBackendHelper.auth.isAdminMock = true;
      FakeBackendHelper.auth.isResidentMock = false;

      await tester.pumpWidget(wrapWithMaterial(const AdminPaymentApprovalScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('4500.00'), findsWidgets);
      expect(find.text(pMinus2), findsOneWidget);
      expect(find.text(pMinus1), findsOneWidget);
      expect(find.text(pCurrent), findsOneWidget);

      final approveBtn = find.byType(ElevatedButton);
      expect(approveBtn, findsOneWidget);
      await tester.tap(approveBtn);
      await tester.pumpAndSettle();

      // 5. Verify status returns to paid and restrictions unlock
      final finalAddrDoc = await FakeBackendHelper.db.getDocument('addresses', 'addr_debt');
      expect(finalAddrDoc?['paymentStatus'], equals('paid'));
    });

    testWidgets('Suite E: Partial Debt Settlement Leaves Address Restricted', (tester) async {
      final now = DateTime.now();
      // Delivery date set to 3 months ago
      final deliveryDate = DateTime(now.year, now.month - 3, 1);

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_partial');
      FakeBackendHelper.db.seedDocument('addresses', 'addr_partial', {
        'id': 'addr_partial',
        'streetName': 'Maple Blvd',
        'number': 20,
        'residentUid': 'resident_partial_uid',
        'deliveryDate': deliveryDate,
        'paymentStatus': 'restricted',
      });

      final pMinus3 = "${deliveryDate.year}-${deliveryDate.month.toString().padLeft(2, '0')}";
      
      // Resident only pays 1 of 3 overdue months
      FakeBackendHelper.db.seedDocument('payments', 'pay_partial_only', {
        'addressRef': addrRef,
        'periods': [pMinus3],
        'amount': 1500.0,
        'status': 'approved',
      });

      // Recalculate status
      final partialStatus = await paymentService.recalculatePaymentStatusForAddress('addr_partial');
      // Must remain restricted because later historical months are still missing!
      expect(partialStatus, equals('restricted'));
    });

    testWidgets('Suite E: Resident with pending status within grace period is considered paid and unrestricted', (tester) async {
      final now = DateTime.now();
      final deliveryDate = DateTime(now.year, now.month, 1);

      // Seed app_settings with generous grace period covering today
      FakeBackendHelper.db.seedDocument('config', 'app_settings', {
        'paymentCutoffDay': 1,
        'gracePeriodDays': 31,
      });

      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_grace_resident');
      FakeBackendHelper.db.seedDocument('addresses', 'addr_grace_resident', {
        'id': 'addr_grace_resident',
        'streetName': 'Grace Avenue',
        'number': 10,
        'residentUid': 'resident_grace_uid',
        'deliveryDate': deliveryDate,
        'paymentStatus': 'paid',
      });

      FakeBackendHelper.db.seedDocument('users', 'resident_grace_uid', {
        'uid': 'resident_grace_uid',
        'name': 'Grace Resident',
        'email': 'grace@test.com',
        'role': 'resident',
        'addressRef': addrRef,
      });

      FakeBackendHelper.auth.emitUser(
        AppUser(
          uid: 'resident_grace_uid',
          email: 'grace@test.com',
          displayName: 'Grace Resident',
        ),
      );
      FakeBackendHelper.auth.isResidentMock = true;
      FakeBackendHelper.auth.isAdminMock = false;

      // 1. Recalculate status -> becomes pending (within grace period)
      final status = await paymentService.recalculatePaymentStatusForAddress('addr_grace_resident');
      expect(status, equals('pending'));

      final addrDoc = await FakeBackendHelper.db.getDocument('addresses', 'addr_grace_resident');
      expect(addrDoc?['isWithinGracePeriod'], isTrue);

      // 2. Verify QR Generator allows access (no restriction screen)
      await tester.pumpWidget(wrapWithMaterial(const QrGeneratorScreen()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.block), findsNothing);
      expect(find.byType(QrGeneratorScreen), findsOneWidget);

      // 3. Verify Booking screen allows access (no restriction screen)
      await tester.pumpWidget(wrapWithMaterial(const BookingScreen()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.block), findsNothing);
      expect(find.byType(BookingScreen), findsOneWidget);

      // 4. Resident uploads proof of payment for the current month
      final pCurrent = "${now.year}-${now.month.toString().padLeft(2, '0')}";
      FakeBackendHelper.db.seedDocument('payments', 'pay_grace_uploaded', {
        'id': 'pay_grace_uploaded',
        'addressRef': addrRef,
        'residentUid': 'resident_grace_uid',
        'periods': [pCurrent],
        'amount': 1500.0,
        'status': 'pending',
        'receiptUrl': 'https://example.com/receipt.jpg',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Status remains pending, isWithinGracePeriod remains true
      final updatedStatus = await paymentService.recalculatePaymentStatusForAddress('addr_grace_resident');
      expect(updatedStatus, equals('pending'));

      final updatedAddrDoc = await FakeBackendHelper.db.getDocument('addresses', 'addr_grace_resident');
      expect(updatedAddrDoc?['paymentStatus'], equals('pending'));
      expect(updatedAddrDoc?['isWithinGracePeriod'], isTrue);

      // Still unrestricted
      await tester.pumpWidget(wrapWithMaterial(const QrGeneratorScreen()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.block), findsNothing);
    });

    testWidgets('Suite F: Facility Booking Lifecycle (Rejection, Approval, Cooldown Restriction & Expiration)', (tester) async {
      final now = DateTime.now();

      // Seed resident user with paid address
      final addrRef = FakeBackendHelper.db.createReference('addresses', 'addr_booking_resident');
      FakeBackendHelper.db.seedDocument('addresses', 'addr_booking_resident', {
        'id': 'addr_booking_resident',
        'streetName': 'Oak Lane',
        'number': 42,
        'residentUid': 'resident_booking_uid',
        'deliveryDate': DateTime(now.year, now.month - 1, 1),
        'paymentStatus': 'paid',
      });

      FakeBackendHelper.db.seedDocument('users', 'resident_booking_uid', {
        'uid': 'resident_booking_uid',
        'name': 'Booking Resident',
        'email': 'booking_resident@test.com',
        'role': 'resident',
        'addressRef': addrRef,
      });

      FakeBackendHelper.db.seedDocument('facilities', 'multipurpose_room', {
        'id': 'multipurpose_room',
        'name': 'Multipurpose Room',
        'cooldownUnit': 'days',
        'cooldownValue': 7,
        'quantity': 1,
      });

      final bookingService = BookingService();

      // -------------------------------------------------------------
      // 1. The resident schedules a booking
      // -------------------------------------------------------------
      FakeBackendHelper.auth.emitUser(
        AppUser(
          uid: 'resident_booking_uid',
          email: 'booking_resident@test.com',
          displayName: 'Booking Resident',
        ),
      );
      FakeBackendHelper.auth.isResidentMock = true;
      FakeBackendHelper.auth.isAdminMock = false;

      final slot1Start = DateTime(now.year, now.month, now.day + 2, 10, 0);
      final slot1End = DateTime(now.year, now.month, now.day + 2, 14, 0);

      await bookingService.createBooking('multipurpose_room', slot1Start, slot1End);

      var bookings = await FakeBackendHelper.db.streamCollection('bookings').first;
      expect(bookings.length, equals(1));
      final booking1 = bookings.first;
      expect(booking1['status'], equals('pending review'));
      expect(booking1['facilityId'], equals('multipurpose_room'));

      // -------------------------------------------------------------
      // 2. The admin rejects with a rejection reason
      // -------------------------------------------------------------
      FakeBackendHelper.auth.emitUser(
        AppUser(
          uid: 'admin_test_uid',
          email: 'admin@example.com',
          displayName: 'Admin User',
        ),
      );
      FakeBackendHelper.auth.isAdminMock = true;
      FakeBackendHelper.auth.isResidentMock = false;

      await tester.pumpWidget(wrapWithMaterial(const AdminBookingApprovalScreen()));
      await tester.pumpAndSettle();

      // Tap Reject button (OutlinedButton with Icons.close)
      final rejectIconFinder = find.byIcon(Icons.close);
      expect(rejectIconFinder, findsOneWidget);
      await tester.tap(rejectIconFinder);
      await tester.pumpAndSettle();

      // Enter rejection reason in the dialog's TextField
      final reasonField = find.byType(TextField);
      expect(reasonField, findsOneWidget);
      const rejectionReason = 'Maintenance scheduled on this date';
      await tester.enterText(reasonField, rejectionReason);
      await tester.pumpAndSettle();

      // Tap Confirm Reject button in dialog
      final confirmRejectBtn = find.widgetWithText(ElevatedButton, 'Reject');
      expect(confirmRejectBtn, findsOneWidget);
      await tester.tap(confirmRejectBtn);
      await tester.pumpAndSettle();

      final rejectedDoc = await FakeBackendHelper.db.getDocument('bookings', booking1['id']);
      expect(rejectedDoc?['status'], equals('rejected'));
      expect(rejectedDoc?['rejectionReason'], equals(rejectionReason));

      // -------------------------------------------------------------
      // 3. The resident creates a new booking (possible since previous was rejected)
      // -------------------------------------------------------------
      FakeBackendHelper.auth.emitUser(
        AppUser(
          uid: 'resident_booking_uid',
          email: 'booking_resident@test.com',
          displayName: 'Booking Resident',
        ),
      );
      FakeBackendHelper.auth.isResidentMock = true;
      FakeBackendHelper.auth.isAdminMock = false;

      final slot2Start = DateTime(now.year, now.month, now.day + 3, 10, 0);
      final slot2End = DateTime(now.year, now.month, now.day + 3, 14, 0);

      await bookingService.createBooking('multipurpose_room', slot2Start, slot2End);

      bookings = await FakeBackendHelper.db.streamCollection('bookings').first;
      expect(bookings.length, equals(2));
      final booking2 = bookings.firstWhere((b) => b['id'] != booking1['id']);
      expect(booking2['status'], equals('pending review'));

      // -------------------------------------------------------------
      // 4. The admin approves
      // -------------------------------------------------------------
      FakeBackendHelper.auth.emitUser(
        AppUser(
          uid: 'admin_test_uid',
          email: 'admin@example.com',
          displayName: 'Admin User',
        ),
      );
      FakeBackendHelper.auth.isAdminMock = true;
      FakeBackendHelper.auth.isResidentMock = false;

      await tester.pumpWidget(wrapWithMaterial(const AdminBookingApprovalScreen()));
      await tester.pumpAndSettle();

      // Tap Approve button (ElevatedButton.icon with Icons.check)
      final approveIconFinder = find.byIcon(Icons.check);
      expect(approveIconFinder, findsOneWidget);
      await tester.tap(approveIconFinder);
      await tester.pumpAndSettle();

      // Tap Confirm Booking button in dialog
      final confirmApproveBtn = find.widgetWithText(ElevatedButton, 'Confirm Booking');
      expect(confirmApproveBtn, findsOneWidget);
      await tester.tap(confirmApproveBtn);
      await tester.pumpAndSettle();

      final approvedDoc = await FakeBackendHelper.db.getDocument('bookings', booking2['id']);
      expect(approvedDoc?['status'], equals('approved (upcoming)'));

      // -------------------------------------------------------------
      // 5. The resident tries to book again (should fail due to 7-day cooldown)
      // -------------------------------------------------------------
      FakeBackendHelper.auth.emitUser(
        AppUser(
          uid: 'resident_booking_uid',
          email: 'booking_resident@test.com',
          displayName: 'Booking Resident',
        ),
      );
      FakeBackendHelper.auth.isResidentMock = true;
      FakeBackendHelper.auth.isAdminMock = false;

      final slot3Start = DateTime(now.year, now.month, now.day + 5, 10, 0); // 2 days after approved booking -> within 7-day cooldown
      final slot3End = DateTime(now.year, now.month, now.day + 5, 14, 0);

      expect(
        () => bookingService.createBooking('multipurpose_room', slot3Start, slot3End),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('You are only allowed to book this facility once every 7 days'),
          ),
        ),
      );

      // Verify no 3rd booking was created
      bookings = await FakeBackendHelper.db.streamCollection('bookings').first;
      expect(bookings.length, equals(2));

      // -------------------------------------------------------------
      // 6. The necessary time passes (resident selects slot beyond 7-day cooldown)
      // -------------------------------------------------------------
      final slot4Start = DateTime(now.year, now.month, now.day + 12, 10, 0); // 9 days after approved booking -> cooldown cleared
      final slot4End = DateTime(now.year, now.month, now.day + 12, 14, 0);

      // -------------------------------------------------------------
      // 7. The resident tries to book the same facility (it should be sent for review)
      // -------------------------------------------------------------
      await bookingService.createBooking('multipurpose_room', slot4Start, slot4End);

      bookings = await FakeBackendHelper.db.streamCollection('bookings').first;
      expect(bookings.length, equals(3));
      final booking3 = bookings.firstWhere((b) => b['id'] != booking1['id'] && b['id'] != booking2['id']);
      expect(booking3['status'], equals('pending review'));
      expect(booking3['facilityId'], equals('multipurpose_room'));
    });

    testWidgets('Suite G: Admin Resident Creation & Delivery Date Validation', (tester) async {
      // 1. Authenticate as Admin
      FakeBackendHelper.auth.emitUser(
        AppUser(uid: 'admin_rollout_uid', email: 'admin@catania.com', displayName: 'Admin Catania'),
      );
      FakeBackendHelper.auth.isAdminMock = true;
      FakeBackendHelper.auth.isResidentMock = false;

      // 2. Seed an unclaimed address
      FakeBackendHelper.db.seedDocument('addresses', 'loreto_108', {
        'id': 'loreto_108',
        'streetName': 'loreto',
        'number': 108,
        'paymentStatus': 'paid',
        'residentUid': null,
      });

      // -------------------------------------------------------------
      // Scenario 1: Delivery date in the future (January 1st 2100) -> MUST FAIL
      // -------------------------------------------------------------
      final futureDate = DateTime(2100, 1, 1).toIso8601String();

      expect(
        () => FunctionsService().callFunction('adminCreateUser', {
          'name': 'Karla Islas',
          'email': 'karip2209@gmail.com',
          'password': 'Password123!',
          'role': 'resident',
          'addressId': 'loreto_108',
          'streetName': 'loreto',
          'number': 108,
          'deliveryDate': futureDate,
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Delivery date cannot be in the future.'),
          ),
        ),
      );

      // Verify no user was created and address remains unclaimed
      var addressDoc = await FakeBackendHelper.db.getDocument('addresses', 'loreto_108');
      expect(addressDoc?['residentUid'], isNull);

      // -------------------------------------------------------------
      // Scenario 2: Delivery date in the past (January 1st 2025) -> SHOULD SUCCEED
      // -------------------------------------------------------------
      final validDate = DateTime(2025, 1, 1).toIso8601String();

      final result = await FunctionsService().callFunction('adminCreateUser', {
        'name': 'Karla Islas',
        'email': 'karip2209@gmail.com',
        'password': 'Password123!',
        'role': 'resident',
        'addressId': 'loreto_108',
        'streetName': 'loreto',
        'number': 108,
        'deliveryDate': validDate,
      });

      expect(result['success'], equals(true));
      final newUid = result['uid'];

      // Verify user document was created with resident role
      final userDoc = await FakeBackendHelper.db.getDocument('users', newUid);
      expect(userDoc?['email'], equals('karip2209@gmail.com'));
      expect(userDoc?['name'], equals('Karla Islas'));
      expect(userDoc?['role'], equals('resident'));

      // Verify address was claimed with delivery date
      addressDoc = await FakeBackendHelper.db.getDocument('addresses', 'loreto_108');
      expect(addressDoc?['residentUid'], equals(newUid));
      expect(addressDoc?['deliveryDate'], equals(DateTime(2025, 1, 1)));
    });

    testWidgets('Suite H: Ticket-01 Sanctions Enforcement, Payment Redirection, and Operating Hours Window', (tester) async {
      // 1. Setup resident and an address with 'paid' status
      final residentUid = 'resident_suite_h';
      final addressId = 'loreto_109';
      final addressRef = FakeBackendHelper.db.createReference('addresses', addressId);

      FakeBackendHelper.db.seedDocument('addresses', addressId, {
        'id': addressId,
        'streetName': 'loreto',
        'number': 109,
        'residentUid': residentUid,
        'paymentStatus': 'paid',
        'hasActiveSanctions': false,
        'activeSanctionsCount': 0,
        'deliveryDate': null,
      });

      FakeBackendHelper.db.seedDocument('users', residentUid, {
        'uid': residentUid,
        'email': 'resident_h@catania.com',
        'name': 'Resident H',
        'role': 'resident',
        'addressRef': addressRef,
      });

      // 2. Setup a facility with operating hours (08:00 - 20:00) and anticipation (1 day)
      FakeBackendHelper.db.seedDocument('facilities', 'pool', {
        'id': 'pool',
        'name': 'Swimming Pool',
        'cooldownUnit': 'unrestricted',
        'cooldownValue': 0,
        'quantity': 1,
        'openingTime': '08:00',
        'closingTime': '20:00',
        'anticipationUnit': 'days',
        'anticipationValue': 1,
      });

      // Verify resident can initially access and has 'paid' standing
      var addrDoc = await FakeBackendHelper.db.getDocument('addresses', addressId);
      expect(addrDoc?['paymentStatus'], equals('paid'));

      // 3. Admin issues a sanction to the address
      final sanctionId = 'sanction_h_1';
      FakeBackendHelper.db.seedDocument('sanctions', sanctionId, {
        'id': sanctionId,
        'addressRef': addressRef,
        'addressId': addressId,
        'amount': 250.0,
        'reason': 'Loud music past 11 PM',
        'status': 'active',
        'issuedAt': DateTime.now().millisecondsSinceEpoch,
        'authorizedUids': [residentUid],
      });

      // Recalculate address payment status (as Cloud Function trigger onSanctionWritten does)
      await paymentService.recalculatePaymentStatusForAddress(addressRef);

      // Verify address standing is now RESTRICTED due to sanction
      addrDoc = await FakeBackendHelper.db.getDocument('addresses', addressId);
      expect(addrDoc?['paymentStatus'], equals('restricted'));
      expect(addrDoc?['hasActiveSanctions'], equals(true));
      expect(addrDoc?['activeSanctionsCount'], equals(1));

      // 4. Authenticate as Resident
      FakeBackendHelper.auth.emitUser(
        AppUser(uid: residentUid, email: 'resident_h@catania.com', displayName: 'Resident H'),
      );
      FakeBackendHelper.auth.isAdminMock = false;
      FakeBackendHelper.auth.isResidentMock = true;

      final bookingService = BookingService();

      // Resident tries to book facility while restricted by sanction -> fails
      final now = DateTime.now();
      final futureStart = DateTime(now.year, now.month, now.day + 2, 10, 0);
      final futureEnd = DateTime(now.year, now.month, now.day + 2, 12, 0);

      expect(
        () => bookingService.createBooking('pool', futureStart, futureEnd),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('restricted'),
          ),
        ),
      );

      // 5. Resident pays the sanction
      final dummyFile = XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'receipt.jpg');
      await paymentService.uploadPaymentReceipt(
        residentUid,
        [],
        250.0,
        folio: 'SANC-0099',
        concept: 'sanction',
        sanctionId: sanctionId,
        paymentDate: DateTime.now(),
        pickedFile: dummyFile,
      );

      // Verify sanction is now 'pending_review'
      var sanctionDoc = await FakeBackendHelper.db.getDocument('sanctions', sanctionId);
      expect(sanctionDoc?['status'], equals('pending_review'));

      // Verify payment doc was created with correct fields
      final allPayments = await FakeBackendHelper.db.streamCollection('payments').first;
      final payDoc = allPayments.firstWhere((p) => p['sanctionId'] == sanctionId);
      expect(payDoc['concept'], equals('sanction'));
      expect(payDoc['sanctionId'], equals(sanctionId));
      expect(payDoc['folio'], equals('SANC-0099'));
      expect(payDoc['status'], equals('pending'));
      final paymentId = payDoc['id'] as String;

      // 6. Admin approves the payment
      FakeBackendHelper.auth.emitUser(
        AppUser(uid: 'admin_uid', email: 'admin@catania.com', displayName: 'Admin'),
      );
      FakeBackendHelper.auth.isAdminMock = true;
      FakeBackendHelper.auth.isResidentMock = false;

      await FunctionsService().callFunction('approvePayment', {'paymentId': paymentId});

      // Verify sanction status changed to 'paid'
      sanctionDoc = await FakeBackendHelper.db.getDocument('sanctions', sanctionId);
      expect(sanctionDoc?['status'], equals('paid'));
      expect(sanctionDoc?['resolvedAt'], isNotNull);

      // Verify address standing is restored to 'paid'
      addrDoc = await FakeBackendHelper.db.getDocument('addresses', addressId);
      expect(addrDoc?['paymentStatus'], equals('paid'));
      expect(addrDoc?['hasActiveSanctions'], equals(false));
      expect(addrDoc?['activeSanctionsCount'], equals(0));

      // 7. Test Anticipation and Operating Hours Windows for Facility Booking
      FakeBackendHelper.auth.emitUser(
        AppUser(uid: residentUid, email: 'resident_h@catania.com', displayName: 'Resident H'),
      );
      FakeBackendHelper.auth.isAdminMock = false;
      FakeBackendHelper.auth.isResidentMock = true;

      // 7a. Violation: Anticipation window (booking 2 hours from now when 1 day is required)
      final tooSoonStart = now.add(const Duration(hours: 2));
      final tooSoonEnd = now.add(const Duration(hours: 4));
      expect(
        () => bookingService.createBooking('pool', tooSoonStart, tooSoonEnd),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('advance notice'),
          ),
        ),
      );

      // 7b. Violation: Operating hours window (booking 2 days from now at 21:00 when pool closes at 20:00)
      final afterHoursStart = DateTime(now.year, now.month, now.day + 2, 21, 0);
      final afterHoursEnd = DateTime(now.year, now.month, now.day + 2, 22, 0);
      expect(
        () => bookingService.createBooking('pool', afterHoursStart, afterHoursEnd),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('operating hours'),
          ),
        ),
      );

      // 7c. Success: Booking 2 days from now within operating hours (10:00 - 12:00)
      await bookingService.createBooking('pool', futureStart, futureEnd);

      final bookings = await FakeBackendHelper.db.streamCollection('bookings').first;
      final poolBooking = bookings.firstWhere((b) => b['facilityId'] == 'pool');
      expect(poolBooking['userUid'], equals(residentUid));
      expect(poolBooking['status'], equals('pending review'));
      expect(poolBooking['isConfirmed'], equals(false));
    });
  });
}
