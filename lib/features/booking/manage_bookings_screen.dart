import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import 'booking_service.dart';
import 'booking_screen.dart'; // To navigate for creating new booking
import '../../l10n/app_localizations.dart';

class ManageBookingsScreen extends StatefulWidget {
  const ManageBookingsScreen({Key? key}) : super(key: key);

  @override
  _ManageBookingsScreenState createState() => _ManageBookingsScreenState();
}

class _ManageBookingsScreenState extends State<ManageBookingsScreen> {
  final BookingService _bookingService = BookingService();
  final String? _uid = AuthService().currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(l10n.upcomingBookings, style: const TextStyle(fontFamily: AppConfig.fontFamily)), // Or a new string for history
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _uid == null
          ? const Center(child: Text("User not logged in"))
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: _bookingService.getUserBookings(_uid!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(child: Text(l10n.noBookings));
                }

                final bookings = snapshot.data!;

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: bookings.length,
                  itemBuilder: (context, index) {
                    final b = bookings[index];
                    final start = DateTime.fromMillisecondsSinceEpoch(b['startTime']);
                    final end = DateTime.fromMillisecondsSinceEpoch(b['endTime']);
                    final status = b['status'] ?? 'pending';
                    final facilityId = b['facilityId'] ?? 'unknown';

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        title: Text(
                          _getFacilityName(l10n, facilityId),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: AppConfig.fontFamily),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${DateFormat('MMM dd, yyyy').format(start)} from ${DateFormat('hh:mm a').format(start)} to ${DateFormat('hh:mm a').format(end)}'),
                            const SizedBox(height: 4),
                            _buildStatusChip(l10n, status),
                          ],
                        ),
                        trailing: status == 'rejected'
                            ? IconButton(
                                icon: const Icon(Icons.edit, color: AppConfig.primaryColor),
                                onPressed: () {
                                  _showEditDialog(b);
                                },
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const BookingScreen()),
          );
        },
      ),
    );
  }

  String _getFacilityName(AppLocalizations l10n, String id) {
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

  String _getTranslatedStatus(AppLocalizations l10n, String status) {
    switch (status) {
      case 'pending review':
        return l10n.pendingReview;
      case 'approved (upcoming)':
        return l10n.approvedUpcoming;
      case 'approved (in use)':
        return l10n.approvedInUse;
      case 'closed':
        return l10n.closed;
      case 'rejected':
        return l10n.rejected;
      default:
        return status;
    }
  }

  Widget _buildStatusChip(AppLocalizations l10n, String status) {
    Color color = Colors.grey;
    switch (status) {
      case 'pending review':
        color = Colors.orange;
        break;
      case 'approved (upcoming)':
        color = Colors.green;
        break;
      case 'approved (in use)':
        color = Colors.blue;
        break;
      case 'closed':
        color = Colors.grey;
        break;
      case 'rejected':
        color = Colors.red;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        _getTranslatedStatus(l10n, status).toUpperCase(),
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> booking) {
    final l10n = AppLocalizations.of(context)!;
    DateTime selectedDate = DateTime.fromMillisecondsSinceEpoch(booking['startTime']);
    TimeOfDay startTime = TimeOfDay.fromDateTime(selectedDate);
    TimeOfDay endTime = TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(booking['endTime']));

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text("Edit Rejected Booking"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text('${l10n.date}: ${DateFormat('yyyy-MM-dd').format(selectedDate)}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                    );
                    if (picked != null) {
                      setState(() {
                        selectedDate = picked;
                      });
                    }
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        title: Text('${l10n.from}: ${startTime.format(context)}'),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: startTime,
                          );
                          if (picked != null) {
                            setState(() {
                              startTime = picked;
                            });
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        title: Text('${l10n.to}: ${endTime.format(context)}'),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: endTime,
                          );
                          if (picked != null) {
                            setState(() {
                              endTime = picked;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
              ElevatedButton(
                onPressed: () async {
                  final startDateTime = DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    selectedDate.day,
                    startTime.hour,
                    startTime.minute,
                  );
                  final endDateTime = DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    selectedDate.day,
                    endTime.hour,
                    endTime.minute,
                  );

                  try {
                    await DatabaseService().updateDocument('bookings', booking['id'], {
                      'startTime': startDateTime.millisecondsSinceEpoch,
                      'endTime': endDateTime.millisecondsSinceEpoch,
                      'status': 'pending review',
                    });
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Booking resubmitted for review.')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                },
                child: const Text("Resubmit"),
              ),
            ],
          );
        },
      ),
    );
  }
}
