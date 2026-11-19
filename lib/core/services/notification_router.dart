import 'package:flutter/material.dart';
import '../../features/admin/admin_shell_screen.dart';
import '../../features/announcements/announcements_screen.dart';
import '../../features/auth/roommates_screen.dart';
import '../../features/booking/manage_bookings_screen.dart';
import '../../features/payments/payment_screen.dart';
import '../../features/qr_access/manage_qr_screen.dart';
import '../../features/sanctions/sanctions_screen.dart';
import '../../features/transparency/transparency_screen.dart';
import '../backend/backend.dart';

/// Callback to switch the active section inside an open admin shell or enter admin mode.
typedef AdminSectionCallback = void Function(AdminSection section);

/// Strictly allow-listed navigation dispatcher for push notifications and
/// in-app notification inbox items.
class NotificationRouter {
  const NotificationRouter._();

  /// Maps an allow-listed admin target route string to its [AdminSection], or null.
  static AdminSection? adminSectionForRoute(String rawRoute) {
    switch (sanitizeNotificationRoute(rawRoute)) {
      case 'admin_claims':
        return AdminSection.approveResidents;
      case 'admin_payments':
        return AdminSection.reviewPayments;
      case 'admin_bookings':
        return AdminSection.reviewBookings;
      default:
        return null;
    }
  }

  /// Navigates safely within allow-listed routes based on the user's current role
  /// and active workspace.
  static Future<void> navigate({
    required BuildContext context,
    required String uid,
    required String rawRoute,
    required bool isAdmin,
    required bool isResident,
    required bool isAdminWorkspace,
    AdminSectionCallback? onOpenAdminSection,
    VoidCallback? onOpenNotificationsInbox,
  }) async {
    if (!context.mounted || uid.trim().isEmpty) return;

    final safeRoute = sanitizeNotificationRoute(rawRoute);

    // Admin review destinations require the admin claim.
    final adminSection = adminSectionForRoute(safeRoute);
    if (adminSection != null) {
      if (isAdmin && onOpenAdminSection != null) {
        onOpenAdminSection(adminSection);
      }
      return;
    }

    switch (safeRoute) {
      case 'home':
        return;

      case 'notifications':
        if (onOpenNotificationsInbox != null) {
          onOpenNotificationsInbox();
        }
        return;

      case 'payments':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PaymentScreen(currentUid: uid),
          ),
        );
        return;

      case 'sanctions':
        if (isAdminWorkspace && isAdmin && onOpenAdminSection != null) {
          onOpenAdminSection(AdminSection.sanctions);
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SanctionsScreen(currentUid: uid),
          ),
        );
        return;

      case 'bookings':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ManageBookingsScreen(),
          ),
        );
        return;

      case 'qr_codes':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ManageQrScreen(),
          ),
        );
        return;

      case 'roommates':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const RoommatesScreen(),
          ),
        );
        return;

      case 'transparency':
        if (isAdminWorkspace && isAdmin && onOpenAdminSection != null) {
          onOpenAdminSection(AdminSection.transparencyDocs);
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TransparencyScreen(isAdminView: isAdmin && isAdminWorkspace),
          ),
        );
        return;

      case 'announcements':
        if (isAdminWorkspace && isAdmin && onOpenAdminSection != null) {
          onOpenAdminSection(AdminSection.announcements);
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AnnouncementsScreen(),
          ),
        );
        return;

      default:
        return;
    }
  }
}
