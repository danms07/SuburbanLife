import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import 'package:intl/intl.dart';
import '../../core/config/app_config.dart';
import 'booking_service.dart';
import '../../l10n/app_localizations.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({Key? key}) : super(key: key);

  @override
  _BookingScreenState createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final BookingService _bookingService = BookingService();
  String _selectedFacility = 'multipurpose_room';
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startTime = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 12, minute: 0);

  void _submitBooking() async {
    try {
      final startDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _startTime.hour,
        _startTime.minute,
      );
      final endDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _endTime.hour,
        _endTime.minute,
      );

      await _bookingService.createBooking(_selectedFacility, startDateTime, endDateTime);

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.bookingCreatedSuccess),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorPrefix(e.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(l10n.facilityBooking, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: user == null
          ? Center(child: Text(l10n.userNotLoggedIn))
          : StreamBuilder<Map<String, dynamic>?>(
              stream: DatabaseService().streamDocument('users', user.uid),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final userData = userSnapshot.data;
                final addressRef = userData?['addressRef'] as DbReference?;

                if (addressRef == null) {
                  return Center(child: Text(l10n.noActiveAddressLinked));
                }

                return StreamBuilder<Map<String, dynamic>?>(
                  stream: DatabaseService().streamDocument('addresses', addressRef.id),
                  builder: (context, addressSnapshot) {
                    if (addressSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final addressData = addressSnapshot.data;
                    final rawStatus = addressData?['paymentStatus'] as String?;
                    final paymentStatus = (rawStatus == null || rawStatus.trim().isEmpty) ? 'restricted' : rawStatus;
                    final isRestricted = paymentStatus == 'restricted';

                    if (isRestricted) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.block, color: Colors.redAccent, size: 60),
                              const SizedBox(height: 16),
                              Text(
                                l10n.accessRestricted,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.accountRestrictedMsg,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context),
                                style: ElevatedButton.styleFrom(backgroundColor: AppConfig.primaryColor, foregroundColor: Colors.white),
                                child: Text(l10n.cancel),
                              )
                            ],
                          ),
                        ),
                      );
                    }

                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: DatabaseService().streamCollection('facilities'),
                  builder: (context, facSnapshot) {
                    if (facSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final facDocs = facSnapshot.data ?? [];

                    // User specified rule: If empty, show an empty list / clear notification
                    if (facDocs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.event_busy, size: 60, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'No amenities currently available for booking.',
                                style: TextStyle(fontSize: 16, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    // Ensure _selectedFacility maps to an active item
                    if (!facDocs.any((d) => d['id'] == _selectedFacility)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _selectedFacility = facDocs.first['id'] as String;
                          });
                        }
                      });
                    }

                    final activeFacId = facDocs.any((d) => d['id'] == _selectedFacility) ? _selectedFacility : facDocs.first['id'] as String;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 0),
                          DropdownButtonFormField<String>(
                            initialValue: activeFacId,
                            decoration: InputDecoration(
                              labelText: l10n.selectFacility,
                              border: const OutlineInputBorder(),
                            ),
                            items: facDocs.map((doc) {
                              final name = doc['name'] ?? doc['id'];
                              return DropdownMenuItem<String>(
                                value: doc['id'] as String,
                                child: Text(name),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedFacility = value;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 20),
                          ListTile(
                            title: Text('${l10n.date}: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}'),
                            trailing: const Icon(Icons.calendar_today, color: AppConfig.primaryColor),
                            shape: RoundedRectangleBorder(
                              side: const BorderSide(color: Colors.grey),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 30)),
                              );
                              if (picked != null) {
                                setState(() {
                                  _selectedDate = picked;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: ListTile(
                                  title: Text('${l10n.from}: ${_startTime.format(context)}'),
                                  trailing: const Icon(Icons.access_time, color: AppConfig.primaryColor),
                                  shape: RoundedRectangleBorder(
                                    side: const BorderSide(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  onTap: () async {
                                    final picked = await showTimePicker(
                                      context: context,
                                      initialTime: _startTime,
                                    );
                                    if (picked != null) {
                                      setState(() {
                                        _startTime = picked;
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: ListTile(
                                  title: Text('${l10n.to}: ${_endTime.format(context)}'),
                                  trailing: const Icon(Icons.access_time, color: AppConfig.primaryColor),
                                  shape: RoundedRectangleBorder(
                                    side: const BorderSide(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  onTap: () async {
                                    final picked = await showTimePicker(
                                      context: context,
                                      initialTime: _endTime,
                                    );
                                    if (picked != null) {
                                      setState(() {
                                        _endTime = picked;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppConfig.primaryColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _submitBooking,
                              child: Text(
                                l10n.confirmBooking,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontFamily: AppConfig.fontFamily,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                          Text(
                            l10n.upcomingBookings,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: AppConfig.fontFamily,
                              color: AppConfig.primaryColor,
                            ),
                          ),
                          const SizedBox(height: 10),
                          StreamBuilder<List<Map<String, dynamic>>>(
                            stream: _bookingService.getBookings(activeFacId),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: CircularProgressIndicator());
                              }
                              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                                return Text(l10n.noBookings);
                              }
                              return ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: snapshot.data!.length,
                                itemBuilder: (context, index) {
                                  final b = snapshot.data![index];
                                  final start = DateTime.fromMillisecondsSinceEpoch(b['startTime']);
                                  final end = DateTime.fromMillisecondsSinceEpoch(b['endTime']);
                                  return Card(
                                    margin: const EdgeInsets.symmetric(vertical: 8),
                                    child: ListTile(
                                      title: Text('${DateFormat('MMM dd, yyyy').format(start)} from ${DateFormat('hh:mm a').format(start)} to ${DateFormat('hh:mm a').format(end)}'),
                                      subtitle: Text(l10n.bookingStatusLabel(b['status']?.toString() ?? '')),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.cancel, color: Colors.redAccent),
                                        onPressed: () async {
                                          await _bookingService.cancelBooking(b['id']);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text(l10n.bookingCancelledSuccess)),
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          )
                        ],
                      ),
                    );
                  },
                );
                  },
                );
              },
            ),
    );
  }
}
