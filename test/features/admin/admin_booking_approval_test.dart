import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/features/admin/admin_booking_approval_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

Widget _wrapWithL10n(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('es')],
    locale: const Locale('en'),
    home: child,
  );
}

void main() {
  setUp(() {
    FakeBackendHelper.setUp();
  });

  group('AdminBookingApprovalScreen - Widget & State Transitions', () {
    testWidgets('renders empty state and hides already-approved or rejected bookings', (tester) async {
      FakeBackendHelper.db.seedDocument('bookings', 'bk_approved', {
        'facilityId': 'roof_garden',
        'userUid': 'res_1',
        'status': 'approved (upcoming)',
        'startTime': DateTime(2026, 6, 10, 14, 0),
        'endTime': DateTime(2026, 6, 10, 18, 0),
      });
      FakeBackendHelper.db.seedDocument('bookings', 'bk_rejected', {
        'facilityId': 'roof_garden',
        'userUid': 'res_2',
        'status': 'rejected',
        'startTime': DateTime(2026, 6, 11, 14, 0),
        'endTime': DateTime(2026, 6, 11, 18, 0),
      });

      await tester.pumpWidget(_wrapWithL10n(const AdminBookingApprovalScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.event_available), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('approves pending booking with facility preset message and custom instructions', (tester) async {
      FakeBackendHelper.db.seedDocument('facilities', 'roof_garden', {
        'name': 'Roof Garden',
        'presetApprovalMessage': 'Pick up keys at guardhouse.',
      });
      FakeBackendHelper.db.seedDocument('users', 'res_1', {
        'name': 'Laura Resident',
        'email': 'laura@test.com',
        'phoneNumber': '555-0199',
      });
      FakeBackendHelper.db.seedDocument('bookings', 'bk_pending_1', {
        'facilityId': 'roof_garden',
        'userUid': 'res_1',
        'status': 'pending review',
        'isConfirmed': false,
        'startTime': DateTime(2026, 6, 15, 16, 0),
        'endTime': DateTime(2026, 6, 15, 20, 0),
      });

      await tester.pumpWidget(_wrapWithL10n(const AdminBookingApprovalScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Roof Garden'), findsOneWidget);
      expect(find.textContaining('Laura Resident'), findsOneWidget);
      expect(find.text('laura@test.com'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      // Verify preset message pre-populated inside dialog TextField
      expect(find.text('Pick up keys at guardhouse.'), findsOneWidget);

      final dialogField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogField, 'Pick up keys at guardhouse before 3:45 PM.');

      final confirmBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(ElevatedButton),
      );
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      final updated = await FakeBackendHelper.db.getDocument('bookings', 'bk_pending_1');
      expect(updated!['status'], equals('approved (upcoming)'));
      expect(updated['isConfirmed'], isTrue);
      expect(updated['approvalMessage'], equals('Pick up keys at guardhouse before 3:45 PM.'));
      expect(updated['updatedAt'], isA<DateTime>());
    });

    testWidgets('rejects pending booking and records rejection reason', (tester) async {
      FakeBackendHelper.db.seedDocument('facilities', 'multipurpose_room', {
        'name': 'Multipurpose Room',
      });
      FakeBackendHelper.db.seedDocument('users', 'res_2', {
        'name': 'Marco Resident',
      });
      FakeBackendHelper.db.seedDocument('bookings', 'bk_pending_2', {
        'facilityId': 'multipurpose_room',
        'userUid': 'res_2',
        'status': 'pending review',
        'isConfirmed': false,
        'startTime': DateTime(2026, 6, 20, 12, 0),
        'endTime': DateTime(2026, 6, 20, 16, 0),
      });

      await tester.pumpWidget(_wrapWithL10n(const AdminBookingApprovalScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      final dialogField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogField, 'Scheduled maintenance window');

      final rejectConfirmBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(ElevatedButton),
      );
      await tester.tap(rejectConfirmBtn);
      await tester.pumpAndSettle();

      final updated = await FakeBackendHelper.db.getDocument('bookings', 'bk_pending_2');
      expect(updated!['status'], equals('rejected'));
      expect(updated['isConfirmed'], isFalse);
      expect(updated['rejectionReason'], equals('Scheduled maintenance window'));
      expect(updated['notes'], equals('Scheduled maintenance window'));
    });
  });
}
