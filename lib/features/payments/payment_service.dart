import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/backend/backend.dart';

class PaymentService {
  final ImagePicker _picker = ImagePicker();

  Future<void> uploadPaymentReceipt(
    String uid,
    List<String> periods,
    double amount, {
    String folio = '',
    String concept = 'monthly quota',
    DateTime? paymentDate,
    String? sanctionId,
    XFile? pickedFile,
  }) async {
    try {
      if (concept == 'monthly quota' && periods.isEmpty) {
        throw Exception('Please select at least one period.');
      }
      if (amount <= 0) {
        throw Exception('Please enter a valid positive payment amount.');
      }

      final actualPaymentDate = paymentDate ?? DateTime.now();

      if (pickedFile == null) {
        try {
          pickedFile = await _picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 60, // High compression to reduce size
          );
        } catch (cameraError) {
          debugPrint('Camera capture fallback to gallery on web/desktop: $cameraError');
          pickedFile = await _picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 60,
          );
        }
      }

      if (pickedFile == null) {
        throw Exception('No photo was taken.');
      }

      // Get user's addressRef
      final userDoc = await Backend.db.getDocument('users', uid);
      final addressRef = userDoc?['addressRef'] as DbReference?;
      if (addressRef == null) {
        throw Exception('No address linked to your account.');
      }

      // Upload imageFile to Storage
      final storagePath = 'payments/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
      String downloadUrl;

      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        downloadUrl = await Backend.storage.uploadFile(
          storagePath,
          bytes,
          contentType: 'image/jpeg',
          metadata: {'uploaderUid': uid},
        );
      } else {
        final File imageFile = File(pickedFile.path);
        downloadUrl = await Backend.storage.uploadFile(
          storagePath,
          imageFile,
          contentType: 'image/jpeg',
          metadata: {'uploaderUid': uid},
        );
      }

      final paymentId = DateTime.now().millisecondsSinceEpoch.toString();
      final effectivePeriods = concept == 'sanction' && periods.isEmpty ? <String>['Sanction'] : periods;

      await Backend.db.setDocument('payments', paymentId, {
        'id': paymentId,
        'residentUid': uid,
        'uploaderUid': uid,
        'addressRef': addressRef,
        'receiptUrl': downloadUrl,
        'status': 'pending',
        'amount': amount,
        'periods': effectivePeriods,
        'period': effectivePeriods.join(', '),
        'folio': folio,
        'concept': concept,
        'paymentDate': actualPaymentDate.millisecondsSinceEpoch,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        if (sanctionId != null && sanctionId.isNotEmpty) 'sanctionId': sanctionId,
      });

      if (concept == 'sanction' && sanctionId != null && sanctionId.isNotEmpty) {
        try {
          await Backend.db.updateDocument('sanctions', sanctionId, {
            'status': 'pending_review',
            'paymentId': paymentId,
          });
        } catch (sanctionUpdateErr) {
          debugPrint('Error updating sanction status: $sanctionUpdateErr');
        }
      }

      // Recalculate status (Server onPaymentWritten trigger executes recalculation; client performs best-effort local sync)
      try {
        await recalculatePaymentStatusForAddress(addressRef);
      } catch (clientRecalcError) {
        debugPrint('Note: Address status recalculation handled by backend trigger ($clientRecalcError)');
      }
    } catch (e, stack) {
      Backend.crashlytics.recordError(e, stack, reason: 'PaymentService.uploadPaymentReceipt');
      throw Exception('Failed to upload receipt: $e');
    }
  }

  Future<String> recalculatePaymentStatusForAddress(dynamic addressRef) async {
    final String addressId = addressRef is DbReference 
        ? addressRef.id 
        : (addressRef is StringDbReference ? addressRef.id : addressRef.toString().split('/').last);

    final addressData = await Backend.db.getDocument('addresses', addressId);
    if (addressData == null) return 'restricted';
    
    final addressFilterVal = Backend.db.createReference('addresses', addressId);

    // Active sanctions check: Any active or pending_review sanction restricts the address immediately
    int activeSanctionsCount = 0;
    try {
      final sanctionsQuery = await Backend.db.getCollection(
        'sanctions',
        filters: [QueryFilter('addressRef', FilterOperator.equal, addressFilterVal)],
      );
      for (var sData in sanctionsQuery) {
        final sStatus = sData['status'] as String? ?? 'active';
        if (sStatus == 'active' || sStatus == 'pending_review') {
          activeSanctionsCount++;
        }
      }
    } catch (err) {
      debugPrint('Error checking active sanctions in recalculatePaymentStatusForAddress: $err');
    }

    final bool hasActiveSanctions = activeSanctionsCount > 0;

    final deliveryDate = addressData['deliveryDate'] as DateTime?;
    if (deliveryDate == null) {
      final newStatus = hasActiveSanctions ? 'restricted' : 'paid';
      await Backend.db.updateDocument('addresses', addressId, {
        'paymentStatus': newStatus,
        'isWithinGracePeriod': !hasActiveSanctions,
        'hasActiveSanctions': hasActiveSanctions,
        'activeSanctionsCount': activeSanctionsCount,
      });
      return newStatus;
    }
    
    final now = DateTime.now();
    final requiredPeriods = _generateRequiredPeriods(deliveryDate, now);
    
    // Fetch global config settings for cutoff and grace periods
    int cutoffDay = 1;
    int graceDays = 10;
    try {
      final appSettings = await Backend.db.getDocument('config', 'app_settings');
      if (appSettings != null) {
        cutoffDay = appSettings['paymentCutoffDay'] as int? ?? 1;
        graceDays = appSettings['gracePeriodDays'] as int? ?? 10;
      }
    } catch (configErr) {
      debugPrint('Note: Using default cutoff/grace settings ($configErr)');
    }
    
    final paymentsQuery = await Backend.db.getCollection(
      'payments',
      filters: [QueryFilter('addressRef', FilterOperator.equal, addressFilterVal)],
    );
        
    final paymentsMap = <String, String>{};
    for (var pData in paymentsQuery) {
      final concept = pData['concept'] as String? ?? 'monthly quota';
      if (concept != 'monthly quota') {
        continue;
      }

      final periods = <String>[];
      if (pData['periods'] is List) {
        for (var p in (pData['periods'] as List)) {
          if (p != null && p.toString().trim().isNotEmpty) {
            periods.add(p.toString().trim());
          }
        }
      } else if (pData['period'] != null) {
        final periodStr = pData['period'].toString();
        for (var p in periodStr.split(',')) {
          if (p.trim().isNotEmpty) {
            periods.add(p.trim());
          }
        }
      }

      final status = pData['status'] as String?;
      if (status != null) {
        for (var period in periods) {
          final existing = paymentsMap[period];
          if (existing == null || 
              status == 'approved' || 
              (status == 'pending' && existing == 'rejected')) {
            paymentsMap[period] = status;
          }
        }
      }
    }
    
    final currentPeriodStr = "${now.year}-${now.month.toString().padLeft(2, '0')}";
    final graceThresholdDay = cutoffDay + graceDays;

    bool hasPending = false;
    bool hasPendingPast = false;
    bool hasUnpaidPast = false;
    bool hasUnpaidCurrent = false;
    bool hasPendingGrace = false;
    
    for (var period in requiredPeriods) {
      final status = paymentsMap[period];
      final isCurrentPeriod = period == currentPeriodStr;

      if (isCurrentPeriod) {
        if (status == 'approved') {
          // Current month is paid
        } else if (status == 'pending') {
          hasPending = true;
        } else {
          // status is null or rejected for current month
          if (now.day <= graceThresholdDay) {
            hasPendingGrace = true;
          } else {
            hasUnpaidCurrent = true;
          }
        }
      } else {
        // Past historical periods
        if (status == null || status == 'rejected') {
          hasUnpaidPast = true;
        } else if (status == 'pending') {
          hasPending = true;
          hasPendingPast = true;
        }
      }
    }
    
    String newStatus = 'paid';
    if (hasActiveSanctions || hasUnpaidPast || hasUnpaidCurrent) {
      newStatus = 'restricted';
    } else if (hasPending || hasPendingGrace) {
      newStatus = 'pending';
    } else {
      newStatus = 'paid';
    }

    final bool isWithinGracePeriod = !hasActiveSanctions && !hasUnpaidPast && !hasPendingPast && (now.day <= graceThresholdDay);
    
    await Backend.db.updateDocument('addresses', addressId, {
      'paymentStatus': newStatus,
      'isWithinGracePeriod': isWithinGracePeriod,
      'hasActiveSanctions': hasActiveSanctions,
      'activeSanctionsCount': activeSanctionsCount,
    });
    return newStatus;
  }
  
  List<String> _generateRequiredPeriods(DateTime start, DateTime end) {
    final List<String> periods = [];
    var current = DateTime(start.year, start.month, 1);
    final target = DateTime(end.year, end.month, 1);
    
    while (!current.isAfter(target)) {
      final periodStr = "${current.year}-${current.month.toString().padLeft(2, '0')}";
      periods.add(periodStr);
      current = DateTime(current.year, current.month + 1, 1);
    }
    return periods;
  }

  /// Generates all candidate periods from deliveryDate (or current month) up to [advanceMonths] in the future.
  List<String> generateSelectablePeriods(DateTime? deliveryDate, DateTime now, {int advanceMonths = 12}) {
    final List<String> periods = [];
    final start = deliveryDate != null ? DateTime(deliveryDate.year, deliveryDate.month, 1) : DateTime(now.year, now.month, 1);
    var current = start;
    final target = DateTime(now.year, now.month + advanceMonths, 1);

    while (!current.isAfter(target)) {
      final periodStr = "${current.year}-${current.month.toString().padLeft(2, '0')}";
      periods.add(periodStr);
      current = DateTime(current.year, current.month + 1, 1);
    }
    return periods;
  }

  Stream<Map<String, dynamic>?> getPaymentStatus(String uid) async* {
    await for (final userDoc in Backend.db.streamDocument('users', uid)) {
      final addressRef = userDoc?['addressRef'] as DbReference?;
      if (addressRef != null) {
        yield* Backend.db.streamDocument('addresses', addressRef.id).map((data) {
          if (data != null) {
            final rawStatus = data['paymentStatus'] as String?;
            if (rawStatus == null || rawStatus.trim().isEmpty) {
              data['paymentStatus'] = 'restricted';
            }
          }
          return data;
        });
      } else {
        yield null;
      }
    }
  }
}

