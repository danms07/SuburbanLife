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

  String? _cachedUserUid;
  Stream<Map<String, dynamic>?>? _userStream;
  String? _cachedAddressId;
  Stream<Map<String, dynamic>?>? _addressStream;
  Stream<List<Map<String, dynamic>>>? _facilitiesStream;
  String? _cachedFacilityStreamKey;
  Stream<List<Map<String, dynamic>>>? _householdBookingsStream;
  Stream<List<Map<String, dynamic>>>? _confirmedBookingsStream;

  Stream<Map<String, dynamic>?> _getUserStream(String uid) {
    if (_cachedUserUid != uid || _userStream == null) {
      _cachedUserUid = uid;
      _userStream = DatabaseService().streamDocument('users', uid);
    }
    return _userStream!;
  }

  Stream<Map<String, dynamic>?> _getAddressStream(String addressId) {
    if (_cachedAddressId != addressId || _addressStream == null) {
      _cachedAddressId = addressId;
      _addressStream = DatabaseService().streamDocument('addresses', addressId);
    }
    return _addressStream!;
  }

  Stream<List<Map<String, dynamic>>> _getFacilitiesStream() {
    return _facilitiesStream ??= DatabaseService().streamCollection('facilities');
  }

  void _ensureFacilityBookingStreams({
    required String facilityId,
    required String userUid,
    required String addressId,
  }) {
    final key = '$facilityId|$userUid|$addressId';
    if (_cachedFacilityStreamKey != key ||
        _householdBookingsStream == null ||
        _confirmedBookingsStream == null) {
      _cachedFacilityStreamKey = key;
      _householdBookingsStream = _bookingService.getHouseholdFacilityBookings(
        facilityId: facilityId,
        userUid: userUid,
        addressId: addressId,
      );
      _confirmedBookingsStream = _bookingService.getConfirmedBookings(facilityId);
    }
  }

  String _localizedCooldownUnit(AppLocalizations l10n, String unit) {
    switch (unit) {
      case 'hours':
        return l10n.cooldownHours.toLowerCase();
      case 'days':
        return l10n.cooldownDays.toLowerCase();
      case 'months':
        return l10n.cooldownMonths.toLowerCase();
      case 'years':
        return l10n.cooldownYears.toLowerCase();
      default:
        return unit;
    }
  }

  String _localizedAnticipationUnit(AppLocalizations l10n, String unit) {
    switch (unit) {
      case 'hours':
        return l10n.anticipationHours.toLowerCase();
      case 'days':
        return l10n.anticipationDays.toLowerCase();
      case 'weeks':
        return l10n.anticipationWeeks.toLowerCase();
      default:
        return unit;
    }
  }

  String _localizedQuotaPeriod(AppLocalizations l10n, String period) {
    switch (period) {
      case 'daily':
        return l10n.quotaDaily;
      case 'monthly':
        return l10n.quotaMonthly;
      case 'yearly':
        return l10n.quotaYearly;
      default:
        return period;
    }
  }

  void _submitBooking(
    Map<String, dynamic> activeFac,
    List<Map<String, dynamic>> householdBookings,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

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

    if (!endDateTime.isAfter(startDateTime)) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.bookingEndTimeAfterStartError),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

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

      if (startM < openM || endM > closeM) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.timeOutsideOperatingHours('$openTimeStr - $closeTimeStr')),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

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
            content: Text(
              l10n.advanceNoticeRequired(
                anticipationValue,
                _localizedAnticipationUnit(l10n, anticipationUnit),
              ),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    // 3. Household Cooldown / Quota validation
    final eval = BookingService.evaluateRestriction(
      facilityDoc: activeFac,
      requestedStart: startDateTime,
      requestedEnd: endDateTime,
      householdBookings: householdBookings,
    );
    if (!eval.isAllowed) {
      final errorMsg = eval.config.isQuota
          ? l10n.bookingQuotaExceededError(
              _localizedQuotaPeriod(l10n, eval.config.quotaPeriod).toLowerCase(),
              eval.config.quotaLimit,
            )
          : l10n.bookingCooldownBlockedError(
              eval.config.cooldownValue,
              _localizedCooldownUnit(l10n, eval.config.cooldownUnit),
            );
      messenger.showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final targetFacilityId = (activeFac['id'] ?? _selectedFacility).toString();
      await _bookingService.createBooking(targetFacilityId, startDateTime, endDateTime);

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
              stream: _getUserStream(user.uid),
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
                  stream: _getAddressStream(addressRef.id),
                  builder: (context, addressSnapshot) {
                    if (addressSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final addressData = addressSnapshot.data;
                    final rawStatus = addressData?['paymentStatus'] as String?;
                    final paymentStatus = (rawStatus == null || rawStatus.trim().isEmpty) ? 'restricted' : rawStatus;
                    final isWithinGrace = addressData?['isWithinGracePeriod'] as bool? ?? false;
                    final hasActiveSanctions = addressData?['hasActiveSanctions'] as bool? ?? false;
                    final isConsideredPaid = !hasActiveSanctions &&
                        (paymentStatus == 'paid' ||
                            ((paymentStatus == 'pending' || paymentStatus == 'reviewing') && isWithinGrace));
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
                      stream: _getFacilitiesStream(),
                      builder: (context, facSnapshot) {
                        if (facSnapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final facDocs = facSnapshot.data ?? [];

                        if (facDocs.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.event_busy, size: 60, color: Colors.grey),
                                  const SizedBox(height: 16),
                                  Text(
                                    l10n.noAmenitiesRegistered,
                                    style: const TextStyle(fontSize: 16, color: Colors.grey),
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

                        final activeFacId = facDocs.any((d) => d['id'] == _selectedFacility)
                            ? _selectedFacility
                            : facDocs.first['id'] as String;
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

                        final restriction = BookingService.resolveRestriction(activeFac);
                        _ensureFacilityBookingStreams(
                          facilityId: activeFacId,
                          userUid: user.uid,
                          addressId: addressRef.id,
                        );

                        return StreamBuilder<List<Map<String, dynamic>>>(
                          stream: _householdBookingsStream,
                          builder: (context, householdSnapshot) {
                            final householdBookings = householdSnapshot.data ?? const <Map<String, dynamic>>[];
                            final usedQuota = restriction.isQuota
                                ? BookingService.countQuotaUsage(
                                    householdBookings: householdBookings,
                                    referenceDate: _selectedDate,
                                    quotaPeriod: restriction.quotaPeriod,
                                  )
                                : 0;
                            final isQuotaExhausted = restriction.isQuota && usedQuota >= restriction.quotaLimit;

                            return SingleChildScrollView(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  DropdownButtonFormField<String>(
                                    key: ValueKey('booking_facility_$activeFacId'),
                                    initialValue: activeFacId,
                                    decoration: InputDecoration(
                                      labelText: l10n.selectFacility,
                                      border: const OutlineInputBorder(),
                                    ),
                                    items: facDocs.map((doc) {
                                      final name = doc['name'] ?? doc['id'];
                                      return DropdownMenuItem<String>(
                                        value: doc['id'] as String,
                                        child: Text(name.toString()),
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

                                  // Badges for Operating Hours, Advance Notice, and Cooldown / Quota
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
                                            l10n.advanceNoticeRequired(
                                              anticipationValue,
                                              _localizedAnticipationUnit(l10n, anticipationUnit),
                                            ),
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          backgroundColor: Colors.orange.withValues(alpha: 0.1),
                                        ),
                                      if (restriction.isCooldown)
                                        Chip(
                                          avatar: const Icon(Icons.timer_outlined, size: 16, color: Colors.deepPurple),
                                          label: Text(
                                            l10n.bookingCooldownBadge(
                                              restriction.cooldownValue,
                                              _localizedCooldownUnit(l10n, restriction.cooldownUnit),
                                            ),
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          backgroundColor: Colors.deepPurple.withValues(alpha: 0.1),
                                        ),
                                      if (restriction.isQuota)
                                        Chip(
                                          avatar: Icon(
                                            isQuotaExhausted ? Icons.error_outline : Icons.pie_chart_outline,
                                            size: 16,
                                            color: isQuotaExhausted ? Colors.redAccent : Colors.teal,
                                          ),
                                          label: Text(
                                            l10n.bookingQuotaBadge(
                                              _localizedQuotaPeriod(l10n, restriction.quotaPeriod),
                                              usedQuota,
                                              restriction.quotaLimit,
                                            ),
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          backgroundColor: (isQuotaExhausted ? Colors.redAccent : Colors.teal)
                                              .withValues(alpha: 0.1),
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
                                      onPressed:
                                          _isSubmitting ? null : () => _submitBooking(activeFac, householdBookings),
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
                                    stream: _confirmedBookingsStream,
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
                                              : (rawStart is int
                                                  ? DateTime.fromMillisecondsSinceEpoch(rawStart)
                                                  : DateTime.now());
                                          final end = rawEnd is DateTime
                                              ? rawEnd
                                              : (rawEnd is int
                                                  ? DateTime.fromMillisecondsSinceEpoch(rawEnd)
                                                  : DateTime.now());

                                          final isOwnBooking = b['userUid'] == user.uid;

                                          return Card(
                                            margin: const EdgeInsets.symmetric(vertical: 8),
                                            child: ListTile(
                                              leading:
                                                  const Icon(Icons.event_available, color: AppConfig.primaryColor),
                                              title: Text(
                                                '${DateFormat('MMM dd, yyyy').format(start)} from ${DateFormat('hh:mm a').format(start)} to ${DateFormat('hh:mm a').format(end)}',
                                              ),
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
                );
              },
            ),
    );
  }
}
