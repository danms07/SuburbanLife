import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/backend/backend.dart';
import '../../core/services/document_transfer_helper.dart';
import 'facility_document_models.dart';

class BookingRestrictionConfig {
  final String restrictionType; // 'unrestricted' | 'cooldown' | 'quota'
  final String cooldownUnit; // 'unrestricted' | 'hours' | 'days' | 'months' | 'years'
  final int cooldownValue;
  final String quotaPeriod; // 'unrestricted' | 'daily' | 'monthly' | 'yearly'
  final int quotaLimit;

  const BookingRestrictionConfig({
    this.restrictionType = 'unrestricted',
    this.cooldownUnit = 'unrestricted',
    this.cooldownValue = 0,
    this.quotaPeriod = 'unrestricted',
    this.quotaLimit = 0,
  });

  bool get isUnrestricted => restrictionType == 'unrestricted';
  bool get isCooldown => restrictionType == 'cooldown';
  bool get isQuota => restrictionType == 'quota';
}

class BookingRestrictionEvaluation {
  final BookingRestrictionConfig config;
  final bool isAllowed;
  final int quotaUsed;
  final DateTime? nextAvailableStart;

  const BookingRestrictionEvaluation({
    required this.config,
    required this.isAllowed,
    this.quotaUsed = 0,
    this.nextAvailableStart,
  });
}

class BookingService {
  /// Normalizes a facility document's booking limit rule, preserving backward
  /// compatibility with legacy documents that only specify cooldownUnit/cooldownValue.
  static BookingRestrictionConfig resolveRestriction(Map<String, dynamic>? facilityDoc) {
    if (facilityDoc == null) {
      return const BookingRestrictionConfig();
    }

    final explicitType = (facilityDoc['restrictionType'] ?? '').toString().trim().toLowerCase();
    final cooldownUnit = (facilityDoc['cooldownUnit'] ?? 'unrestricted').toString().trim().toLowerCase();
    final rawCooldownVal = facilityDoc['cooldownValue'];
    final cooldownValue = rawCooldownVal is num
        ? rawCooldownVal.toInt()
        : int.tryParse(rawCooldownVal?.toString() ?? '0') ?? 0;

    final quotaPeriod = (facilityDoc['quotaPeriod'] ?? 'unrestricted').toString().trim().toLowerCase();
    final rawQuotaLimit = facilityDoc['quotaLimit'];
    final quotaLimit = rawQuotaLimit is num
        ? rawQuotaLimit.toInt()
        : int.tryParse(rawQuotaLimit?.toString() ?? '0') ?? 0;

    if (explicitType == 'quota') {
      if (const ['daily', 'monthly', 'yearly'].contains(quotaPeriod) && quotaLimit > 0) {
        return BookingRestrictionConfig(
          restrictionType: 'quota',
          quotaPeriod: quotaPeriod,
          quotaLimit: quotaLimit,
        );
      }
      return const BookingRestrictionConfig();
    }

    if (explicitType == 'cooldown' ||
        (explicitType.isEmpty && cooldownUnit != 'unrestricted' && cooldownValue > 0)) {
      if (const ['hours', 'days', 'months', 'years'].contains(cooldownUnit) && cooldownValue > 0) {
        return BookingRestrictionConfig(
          restrictionType: 'cooldown',
          cooldownUnit: cooldownUnit,
          cooldownValue: cooldownValue,
        );
      }
    }

    return const BookingRestrictionConfig();
  }

  /// Both pending review and approved/confirmed/closed bookings count toward
  /// household cooldown and quota limits; rejected and cancelled bookings do not.
  static bool isCountedBookingForRestriction(Map<String, dynamic>? booking) {
    if (booking == null) return false;
    final status = (booking['status'] ?? '').toString().trim().toLowerCase();
    if (status.isEmpty || status == 'rejected' || status == 'cancelled') {
      return false;
    }
    return status == 'pending' ||
        status == 'pending review' ||
        status.startsWith('approved') ||
        status == 'confirmed' ||
        status == 'closed';
  }

  static DateTime? _extractDateTime(dynamic raw) {
    if (raw is DateTime) return raw;
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  /// Adds a cooldown duration (hours | days | months | years) to [dt], safely
  /// clamping calendar month-end rollovers for months and years.
  static DateTime addCooldownOffset(DateTime dt, String unit, int value) {
    if (value <= 0) return dt;
    if (unit == 'hours') {
      return dt.add(Duration(hours: value));
    }
    if (unit == 'days') {
      return dt.add(Duration(days: value));
    }
    if (unit == 'months') {
      final totalMonths = dt.year * 12 + (dt.month - 1) + value;
      final targetYear = totalMonths ~/ 12;
      final targetMonth = (totalMonths % 12) + 1;
      final maxDay = DateTime(targetYear, targetMonth + 1, 0).day;
      final clampedDay = dt.day <= maxDay ? dt.day : maxDay;
      return DateTime(
        targetYear,
        targetMonth,
        clampedDay,
        dt.hour,
        dt.minute,
        dt.second,
        dt.millisecond,
      );
    }
    if (unit == 'years') {
      final targetYear = dt.year + value;
      final maxDay = DateTime(targetYear, dt.month + 1, 0).day;
      final clampedDay = dt.day <= maxDay ? dt.day : maxDay;
      return DateTime(
        targetYear,
        dt.month,
        clampedDay,
        dt.hour,
        dt.minute,
        dt.second,
        dt.millisecond,
      );
    }
    return dt;
  }

  /// Counts active household bookings in the calendar period (daily | monthly | yearly)
  /// containing [referenceDate].
  static int countQuotaUsage({
    required List<Map<String, dynamic>> householdBookings,
    required DateTime referenceDate,
    required String quotaPeriod,
    String? excludeBookingId,
  }) {
    int used = 0;
    for (final b in householdBookings) {
      if (excludeBookingId != null && b['id']?.toString() == excludeBookingId) continue;
      if (!isCountedBookingForRestriction(b)) continue;
      final bStart = _extractDateTime(b['startTime']);
      if (bStart == null) continue;

      final sameYear = bStart.year == referenceDate.year;
      final sameMonth = sameYear && bStart.month == referenceDate.month;
      final sameDay = sameMonth && bStart.day == referenceDate.day;

      if ((quotaPeriod == 'daily' && sameDay) ||
          (quotaPeriod == 'monthly' && sameMonth) ||
          (quotaPeriod == 'yearly' && sameYear)) {
        used++;
      }
    }
    return used;
  }

  /// Evaluates whether [requestedStart]..[requestedEnd] satisfies the facility's
  /// household cooldown (endTime -> startTime gap) or calendar-period quota.
  static BookingRestrictionEvaluation evaluateRestriction({
    required Map<String, dynamic>? facilityDoc,
    required DateTime requestedStart,
    required DateTime requestedEnd,
    required List<Map<String, dynamic>> householdBookings,
    String? excludeBookingId,
  }) {
    final config = resolveRestriction(facilityDoc);
    if (config.isUnrestricted) {
      return BookingRestrictionEvaluation(config: config, isAllowed: true);
    }

    if (config.isCooldown) {
      DateTime? latestRequiredStart;
      bool conflict = false;

      for (final b in householdBookings) {
        if (excludeBookingId != null && b['id']?.toString() == excludeBookingId) continue;
        if (!isCountedBookingForRestriction(b)) continue;

        final bStart = _extractDateTime(b['startTime']);
        if (bStart == null) continue;
        final rawEnd = _extractDateTime(b['endTime']);
        final bEnd = (rawEnd != null && rawEnd.isAfter(bStart)) ? rawEnd : bStart;

        final earliestAfterB = addCooldownOffset(bEnd, config.cooldownUnit, config.cooldownValue);
        final earliestBStartAfterReq =
            addCooldownOffset(requestedEnd, config.cooldownUnit, config.cooldownValue);

        final okAfterExisting = !requestedStart.isBefore(earliestAfterB);
        final okBeforeExisting = !bStart.isBefore(earliestBStartAfterReq);

        if (!okAfterExisting && !okBeforeExisting) {
          conflict = true;
          if (latestRequiredStart == null || earliestAfterB.isAfter(latestRequiredStart)) {
            latestRequiredStart = earliestAfterB;
          }
        }
      }

      return BookingRestrictionEvaluation(
        config: config,
        isAllowed: !conflict,
        nextAvailableStart: latestRequiredStart,
      );
    }

    if (config.isQuota) {
      final used = countQuotaUsage(
        householdBookings: householdBookings,
        referenceDate: requestedStart,
        quotaPeriod: config.quotaPeriod,
        excludeBookingId: excludeBookingId,
      );
      return BookingRestrictionEvaluation(
        config: config,
        isAllowed: used < config.quotaLimit,
        quotaUsed: used,
      );
    }

    return BookingRestrictionEvaluation(config: config, isAllowed: true);
  }

  Stream<List<Map<String, dynamic>>> getConfirmedBookings(String facilityId) {
    return Backend.db.streamCollection(
      'bookings',
      filters: [
        QueryFilter('facilityId', FilterOperator.equal, facilityId),
        QueryFilter('isConfirmed', FilterOperator.equal, true),
      ],
    );
  }

  Stream<List<Map<String, dynamic>>> getBookings(String facilityId) {
    return Backend.db.streamCollection(
      'bookings',
      filters: [
        QueryFilter('facilityId', FilterOperator.equal, facilityId),
      ],
    ).map((list) => list.where((b) {
      if (b['status'] == 'rejected' || b['status'] == 'cancelled') return false;
      if (b.containsKey('isConfirmed')) {
        return b['isConfirmed'] == true;
      }
      final status = (b['status'] ?? '').toString().toLowerCase();
      return status.startsWith('approved') || status == 'confirmed' || status == 'closed';
    }).toList());
  }

  /// Streams bookings for [facilityId] attributed to the caller's household [addressId],
  /// merged with legacy pre-refactor bookings created by [userUid] without an addressId.
  Stream<List<Map<String, dynamic>>> getHouseholdFacilityBookings({
    required String facilityId,
    required String userUid,
    String? addressId,
  }) {
    final cleanAddressId = addressId?.trim() ?? '';
    if (cleanAddressId.isEmpty) {
      return Backend.db.streamCollection(
        'bookings',
        filters: [
          QueryFilter('facilityId', FilterOperator.equal, facilityId),
          QueryFilter('userUid', FilterOperator.equal, userUid),
        ],
      );
    }

    return Stream<List<Map<String, dynamic>>>.multi((controller) {
      final addressStream = Backend.db.streamCollection(
        'bookings',
        filters: [
          QueryFilter('facilityId', FilterOperator.equal, facilityId),
          QueryFilter('addressId', FilterOperator.equal, cleanAddressId),
        ],
      );
      final userStream = Backend.db.streamCollection(
        'bookings',
        filters: [
          QueryFilter('facilityId', FilterOperator.equal, facilityId),
          QueryFilter('userUid', FilterOperator.equal, userUid),
        ],
      );

      List<Map<String, dynamic>> latestByAddress = const [];
      List<Map<String, dynamic>> latestByUser = const [];
      bool hasAddressData = false;
      bool hasUserData = false;

      void emitMerged() {
        if (!hasAddressData || !hasUserData) return;
        if (controller.isClosed) return;
        final merged = <String, Map<String, dynamic>>{};
        for (final doc in latestByAddress) {
          final id = (doc['id'] ?? doc['bookingId'] ?? '').toString();
          if (id.isNotEmpty) merged[id] = doc;
        }
        for (final doc in latestByUser) {
          final id = (doc['id'] ?? doc['bookingId'] ?? '').toString();
          if (id.isEmpty || merged.containsKey(id)) continue;
          final docAddressId = doc['addressId']?.toString() ?? '';
          if (docAddressId.isEmpty || docAddressId == cleanAddressId) {
            merged[id] = doc;
          }
        }
        controller.add(merged.values.toList());
      }

      final subAddr = addressStream.listen(
        (data) {
          latestByAddress = data;
          hasAddressData = true;
          emitMerged();
        },
        onError: controller.addError,
      );

      final subUser = userStream.listen(
        (data) {
          latestByUser = data;
          hasUserData = true;
          emitMerged();
        },
        onError: controller.addError,
      );

      controller.onCancel = () {
        subAddr.cancel();
        subUser.cancel();
      };
    }, isBroadcast: true);
  }

  Future<void> createBooking(
    String facilityId,
    DateTime startTime,
    DateTime endTime, {
    String? resubmitBookingId,
    List<Map<String, dynamic>>? attachments,
  }) async {
    try {
      final payload = <String, dynamic>{
        'facilityId': facilityId,
        'startTime': startTime.millisecondsSinceEpoch,
        'endTime': endTime.millisecondsSinceEpoch,
      };
      if (resubmitBookingId != null && resubmitBookingId.trim().isNotEmpty) {
        payload['resubmitBookingId'] = resubmitBookingId.trim();
      }
      if (attachments != null) {
        payload['attachments'] = attachments;
      }
      await Backend.functions.callFunction('createBooking', payload);
    } catch (e, stack) {
      Backend.crashlytics.recordError(e, stack, reason: 'BookingService.createBooking');
      throw Exception('Failed to create booking: $e');
    }
  }

  /// Uploads any newly selected draft files to `booking_attachments/{userUid}/...` with
  /// `Content-Disposition: attachment`, invokes `createBooking`, and automatically deletes
  /// newly uploaded Storage objects if the server rejects or fails the booking.
  Future<void> uploadAndCreateBooking({
    required String facilityId,
    required String userUid,
    String? addressId,
    required DateTime startTime,
    required DateTime endTime,
    required List<FacilityDocumentTemplate> templates,
    required Map<String, DraftBookingAttachment> draftsByDocId,
    String? resubmitBookingId,
  }) async {
    final newlyUploadedUrls = <String>[];
    final attachmentMaps = <Map<String, dynamic>>[];

    try {
      for (final template in templates) {
        if (!template.requirementMode.acceptsAttachment) continue;
        final draft = draftsByDocId[template.docId];
        if (draft == null) continue;

        if (draft.isAlreadyUploaded) {
          attachmentMaps.add(
            SubmittedBookingAttachment(
              facilityDocId: template.docId,
              title: template.title,
              requirementMode: template.requirementMode,
              fileName: draft.fileName,
              fileType: draft.fileType,
              fileSize: draft.fileSize,
              url: draft.existingUrl!,
              storagePath: draft.existingStoragePath!,
              uploadedAt: draft.existingUploadedAt ?? DateTime.now().millisecondsSinceEpoch,
            ).toMap(),
          );
          continue;
        }

        final bytes = draft.bytes;
        if (bytes == null || bytes.isEmpty) continue;

        final storagePath = DocumentTransferHelper.buildStoragePath(
          prefix: 'booking_attachments',
          scopeId: userUid,
          extension: draft.fileType,
        );
        final contentType =
            draft.contentType.isNotEmpty ? draft.contentType : DocumentTransferHelper.resolveMimeType(draft.fileType);
        final downloadUrl = await Backend.storage.uploadFile(
          storagePath,
          bytes,
          contentType: contentType,
          contentDisposition: DocumentTransferHelper.buildContentDisposition(draft.fileName),
          metadata: {
            'uploaderUid': userUid,
            if (addressId != null && addressId.trim().isNotEmpty) 'addressId': addressId.trim(),
          },
        );
        newlyUploadedUrls.add(downloadUrl);
        await draft.disposeTempCapture();

        attachmentMaps.add(
          SubmittedBookingAttachment(
            facilityDocId: template.docId,
            title: template.title,
            requirementMode: template.requirementMode,
            fileName: draft.fileName,
            fileType: draft.fileType,
            fileSize: draft.fileSize,
            url: downloadUrl,
            storagePath: storagePath,
            uploadedAt: DateTime.now().millisecondsSinceEpoch,
          ).toMap(),
        );
      }

      await createBooking(
        facilityId,
        startTime,
        endTime,
        resubmitBookingId: resubmitBookingId,
        attachments: attachmentMaps,
      );
    } catch (e) {
      await rollbackUploadedUrls(newlyUploadedUrls);
      rethrow;
    }
  }

  /// Best-effort deletion of newly uploaded Storage files when a booking submission aborts.
  Future<void> rollbackUploadedUrls(List<String> urls) async {
    for (final url in urls) {
      if (url.trim().isEmpty) continue;
      try {
        await Backend.storage.deleteFileFromUrl(url);
      } catch (err) {
        debugPrint('>>> [BookingService] Non-fatal Storage rollback warning: ${err.runtimeType}');
      }
    }
  }

  /// Streams isolated resident booking attachments from `booking_attachments/{bookingId}`.
  Stream<List<SubmittedBookingAttachment>> streamBookingAttachments(String bookingId) {
    final cleanId = bookingId.trim();
    if (cleanId.isEmpty) {
      return Stream.value(const []);
    }
    return Backend.db
        .streamDocument('booking_attachments', cleanId)
        .map((doc) => SubmittedBookingAttachment.parseList(doc?['attachments']));
  }

  /// Fetches isolated resident booking attachments once from `booking_attachments/{bookingId}`.
  Future<List<SubmittedBookingAttachment>> getBookingAttachments(String bookingId) async {
    final cleanId = bookingId.trim();
    if (cleanId.isEmpty) return const [];
    final doc = await Backend.db.getDocument('booking_attachments', cleanId);
    return SubmittedBookingAttachment.parseList(doc?['attachments']);
  }

  Future<void> cancelBooking(String bookingId) async {
    try {
      await Backend.functions.callFunction('cancelBooking', {
        'bookingId': bookingId,
      });
    } catch (e, stack) {
      Backend.crashlytics.recordError(e, stack, reason: 'BookingService.cancelBooking');
      throw Exception('Failed to cancel booking: $e');
    }
  }

  Stream<List<Map<String, dynamic>>> getUserBookings(String userUid) {
    return Backend.db.streamCollection(
      'bookings',
      filters: [QueryFilter('userUid', FilterOperator.equal, userUid)],
    ).map((list) {
      list.sort((a, b) {
        final aStart = a['startTime'];
        final bStart = b['startTime'];
        final aVal = aStart is DateTime ? aStart.millisecondsSinceEpoch : (aStart as num?)?.toInt() ?? 0;
        final bVal = bStart is DateTime ? bStart.millisecondsSinceEpoch : (bStart as num?)?.toInt() ?? 0;
        return bVal.compareTo(aVal);
      });
      return list;
    });
  }
}
