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
  bool _isSubmitting = false;

  void _submitBooking(Map<String, dynamic> activeFac) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    // 1. Operating Hours validation
    final openTimeStr = (activeFac['openingTime'] ?? '00:00').toString();
    final closeTimeStr = (activeFac['closingTime'] ?? '23:59').toString();
    if (openTimeStr != '00:00' || closeTimeStr != '23:59') {
      final openParts = openTimeStr.split(':').map(int.parse).toList();
      final closeParts = closeTimeStr.split(':').map(int.parse).toList();
      final openM = openParts[0] * 60 + openParts[1];
      final closeM = closeParts[0] * 60 + closeParts[1];
      final startM = _startTime.hour * 60 + _startTime.minute;
      final endM = _endTime.hour * 60 + _endTime.minute;

      if (startM < openM || endM > closeM || endM <= startM) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.timeOutsideOperatingHours('$openTimeStr - $closeTimeStr')),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

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

    // 2. Anticipation Window validation
    final anticipationUnit = (activeFac['anticipationUnit'] ?? 'unrestricted').toString();
    final anticipationValue = (activeFac['anticipationValue'] as num?)?.toInt() ?? 0;
    if (anticipationUnit != 'unrestricted' && anticipationValue > 0) {
      Duration anticipationDur = Duration.zero;
      if (anticipationUnit == 'hours') anticipationDur = Duration(hours: anticipationValue);
      if (anticipationUnit == 'days') anticipationDur = Duration(days: anticipationValue);
      if (anticipationUnit == 'weeks') anticipationDur = Duration(days: anticipationValue * 7);

      final minAllowed = DateTime.now().add(anticipationDur);
      if (startDateTime.isBefore(minAllowed)) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.advanceNoticeRequired(anticipationValue, anticipationUnit)),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _bookingService.createBooking(_selectedFacility, startDateTime, endDateTime);

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.bookingCreatedSuccess),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
      }
    } catch (e) {
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
          _isSubmitting = false;
        });
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
                    final isWithinGrace = addressData?['isWithinGracePeriod'] as bool? ?? false;
                    final isConsideredPaid = paymentStatus == 'paid' ||
                        ((paymentStatus == 'pending' || paymentStatus == 'reviewing') && isWithinGrace);
                    final isRestricted = !isConsideredPaid;

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
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
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
                    final activeFac = facDocs.firstWhere(
                      (d) => d['id'] == activeFacId,
                      orElse: () => facDocs.first,
                    );

                    final openTimeStr = (activeFac['openingTime'] ?? '00:00').toString();
                    final closeTimeStr = (activeFac['closingTime'] ?? '23:59').toString();
                    final isHoursRestricted = openTimeStr != '00:00' || closeTimeStr != '23:59';
                    final anticipationUnit = (activeFac['anticipationUnit'] ?? 'unrestricted').toString();
                    final anticipationValue = (activeFac['anticipationValue'] as num?)?.toInt() ?? 0;

                    DateTime minDate = DateTime.now();
                    if (anticipationUnit == 'hours') {
                      minDate = minDate.add(Duration(hours: anticipationValue));
                    } else if (anticipationUnit == 'days') {
                      minDate = minDate.add(Duration(days: anticipationValue));
                    } else if (anticipationUnit == 'weeks') {
                      minDate = minDate.add(Duration(days: anticipationValue * 7));
                    }

                    if (_selectedDate.isBefore(minDate)) {
                      _selectedDate = minDate;
                    }

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                          const SizedBox(height: 12),

                          // Badges for Operating Hours and Advance Notice
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Chip(
                                avatar: const Icon(Icons.access_time, size: 16, color: AppConfig.primaryColor),
                                label: Text(
                                  isHoursRestricted
                                      ? l10n.operatingHours('$openTimeStr - $closeTimeStr')
                                      : l10n.operatingHoursUnrestricted,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                backgroundColor: isHoursRestricted
                                    ? AppConfig.primaryColor.withValues(alpha: 0.1)
                                    : Colors.grey.withValues(alpha: 0.1),
                              ),
                              if (anticipationUnit != 'unrestricted' && anticipationValue > 0)
                                Chip(
                                  avatar: const Icon(Icons.calendar_month, size: 16, color: Colors.orange),
                                  label: Text(
                                    l10n.advanceNoticeRequired(anticipationValue, anticipationUnit),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  backgroundColor: Colors.orange.withValues(alpha: 0.1),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),

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
                                initialDate: _selectedDate.isBefore(minDate) ? minDate : _selectedDate,
                                firstDate: minDate,
                                lastDate: DateTime.now().add(const Duration(days: 90)),
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
                              onPressed: _isSubmitting ? null : () => _submitBooking(activeFac),
                              child: _isSubmitting
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                    )
                                  : Text(
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
                            stream: _bookingService.getConfirmedBookings(activeFacId),
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
                                  final rawStart = b['startTime'];
                                  final rawEnd = b['endTime'];
                                  final start = rawStart is DateTime
                                      ? rawStart
                                      : (rawStart is int ? DateTime.fromMillisecondsSinceEpoch(rawStart) : DateTime.now());
                                  final end = rawEnd is DateTime
                                      ? rawEnd
                                      : (rawEnd is int ? DateTime.fromMillisecondsSinceEpoch(rawEnd) : DateTime.now());

                                  final isOwnBooking = b['userUid'] == user.uid;

                                  return Card(
                                    margin: const EdgeInsets.symmetric(vertical: 8),
                                    child: ListTile(
                                      leading: const Icon(Icons.event_available, color: AppConfig.primaryColor),
                                      title: Text('${DateFormat('MMM dd, yyyy').format(start)} from ${DateFormat('hh:mm a').format(start)} to ${DateFormat('hh:mm a').format(end)}'),
                                      subtitle: Text(l10n.bookingStatusLabel(b['status']?.toString() ?? '')),
                                      trailing: isOwnBooking
                                          ? IconButton(
                                              icon: const Icon(Icons.cancel, color: Colors.redAccent),
                                              onPressed: () async {
                                                await _bookingService.cancelBooking(b['id']);
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text(l10n.bookingCancelledSuccess)),
                                                  );
                                                }
                                              },
                                            )
                                          : null,
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
