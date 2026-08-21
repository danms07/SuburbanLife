import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';

class AdminBookingApprovalScreen extends StatefulWidget {
  const AdminBookingApprovalScreen({super.key});

  @override
  State<AdminBookingApprovalScreen> createState() => _AdminBookingApprovalScreenState();
}

class _AdminBookingApprovalScreenState extends State<AdminBookingApprovalScreen> {
  bool _isProcessing = false;

  void _approveBooking(String bookingId) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.approveBookingTitle),
        content: Text(l10n.approveBookingConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConfig.secondaryColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(l10n.confirmBooking),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      debugPrint('>>> [AdminBookingApproval] Approving booking: $bookingId');
      await DatabaseService().updateDocument('bookings', bookingId, {
        'status': 'approved (upcoming)',
        'updatedAt': DbFieldValue.serverTimestamp(),
      });

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.bookingApprovedSuccess),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('>>> [AdminBookingApproval] Error approving booking: $e\n$stack');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.errorPrefix(e.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _rejectBooking(String bookingId) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.rejectBookingTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.rejectBookingConfirm),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: InputDecoration(
                labelText: l10n.rejectionReasonOptional,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(l10n.rejected),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final reason = notesController.text.trim();
      debugPrint('>>> [AdminBookingApproval] Rejecting booking: $bookingId, reason: $reason');
      await DatabaseService().updateDocument('bookings', bookingId, {
        'status': 'rejected',
        'notes': reason,
        'updatedAt': DbFieldValue.serverTimestamp(),
      });

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.bookingRejectedSuccess),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('>>> [AdminBookingApproval] Error rejecting booking: $e\n$stack');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.errorPrefix(e.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(l10n.adminBookingApprovalTitle, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: DatabaseService().streamCollection(
          'bookings',
          filters: [
            QueryFilter('status', FilterOperator.equal, 'pending review'),
          ],
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.errorPrefix(snapshot.error.toString())));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final bookings = snapshot.data ?? [];

          if (bookings.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_available, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    l10n.noPendingBookings,
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: bookings.length,
            itemBuilder: (context, index) {
              final booking = bookings[index];
              return _BookingApprovalCard(
                key: ValueKey(booking['id'] ?? index),
                booking: booking,
                isProcessing: _isProcessing,
                onApprove: () => _approveBooking(booking['id']),
                onReject: () => _rejectBooking(booking['id']),
              );
            },
          );
        },
      ),
    );
  }
}

class _BookingApprovalCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final bool isProcessing;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _BookingApprovalCard({
    super.key,
    required this.booking,
    required this.isProcessing,
    required this.onApprove,
    required this.onReject,
  });

  String _getFacilityName(AppLocalizations l10n, String id, Map<String, dynamic>? facilityDoc) {
    if (facilityDoc != null && facilityDoc['name'] != null) {
      return facilityDoc['name'].toString();
    }
    switch (id) {
      case 'multipurpose_room':
        return l10n.multipurposeRoom;
      case 'bicycle_1':
        return l10n.bicycle1;
      case 'roof_garden':
        return l10n.roofGarden;
      default:
        return id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final facilityId = booking['facilityId']?.toString() ?? 'unknown';
    final userUid = booking['userUid']?.toString() ?? '';

    DateTime start;
    DateTime end;
    final rawStart = booking['startTime'];
    final rawEnd = booking['endTime'];

    if (rawStart is DateTime) {
      start = rawStart;
    } else if (rawStart is int) {
      start = DateTime.fromMillisecondsSinceEpoch(rawStart);
    } else {
      start = DateTime.now();
    }

    if (rawEnd is DateTime) {
      end = rawEnd;
    } else if (rawEnd is int) {
      end = DateTime.fromMillisecondsSinceEpoch(rawEnd);
    } else {
      end = DateTime.now();
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Facility & Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: StreamBuilder<Map<String, dynamic>?>(
                    stream: DatabaseService().streamDocument('facilities', facilityId),
                    builder: (context, facilitySnapshot) {
                      final name = _getFacilityName(l10n, facilityId, facilitySnapshot.data);
                      return Row(
                        children: [
                          const Icon(Icons.event_seat, color: AppConfig.primaryColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: AppConfig.fontFamily,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Text(
                    l10n.pendingReview.toUpperCase(),
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // Date & Time Slot
            Row(
              children: [
                Icon(Icons.access_time, size: 18, color: Colors.grey.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${DateFormat('EEEE, MMM dd, yyyy').format(start)} • ${DateFormat('hh:mm a').format(start)} - ${DateFormat('hh:mm a').format(end)}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Applicant Information
            StreamBuilder<Map<String, dynamic>?>(
              stream: DatabaseService().streamDocument('users', userUid),
              builder: (context, userSnapshot) {
                final userDoc = userSnapshot.data;
                final name = userDoc?['name']?.toString() ?? userUid;
                final email = userDoc?['email']?.toString() ?? '';
                final phone = userDoc?['phoneNumber']?.toString() ?? '';

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.person_outline, size: 16, color: Colors.grey.shade700),
                          const SizedBox(width: 6),
                          Text(
                            '${l10n.applicant}: $name',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.email_outlined, size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Text(email, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                          ],
                        ),
                      ],
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.phone_outlined, size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Text(phone, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Actions: Approve & Reject
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: isProcessing ? null : onReject,
                  icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
                  label: Text(l10n.reject, style: const TextStyle(color: Colors.redAccent)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: isProcessing ? null : onApprove,
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(l10n.approve),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.secondaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
