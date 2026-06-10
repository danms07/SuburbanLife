import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/backend/backend.dart';

class PaymentService {
  final ImagePicker _picker = ImagePicker();

  Future<void> uploadPaymentReceipt(String uid, String period) async {
    try {
      // Force camera permissions and enforce taking a photo directly
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 60, // High compression to reduce size
      );

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
      await Backend.db.setDocument('payments', paymentId, {
        'id': paymentId,
        'residentUid': uid,
        'addressRef': addressRef,
        'receiptUrl': downloadUrl,
        'status': 'pending',
        'period': period,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Recalculate status!
      await recalculatePaymentStatusForAddress(addressRef);
    } catch (e) {
      throw Exception('Failed to upload receipt: $e');
    }
  }

  Future<String> recalculatePaymentStatusForAddress(dynamic addressRef) async {
    final String addressId = addressRef is DbReference 
        ? addressRef.id 
        : (addressRef is StringDbReference ? addressRef.id : addressRef.toString().split('/').last);

    final addressData = await Backend.db.getDocument('addresses', addressId);
    if (addressData == null) return 'restricted';
    
    final deliveryDate = addressData['deliveryDate'] as DateTime?;
    if (deliveryDate == null) {
      // If no delivery date, default to paid
      await Backend.db.updateDocument('addresses', addressId, {'paymentStatus': 'paid'});
      return 'paid';
    }
    
    final requiredPeriods = _generateRequiredPeriods(deliveryDate, DateTime.now());
    
    // Format query search value. Make sure we construct it correctly depending on the implementation
    final addressFilterVal = Backend.db.createReference('addresses', addressId);
    final paymentsQuery = await Backend.db.getCollection(
      'payments',
      filters: [QueryFilter('addressRef', FilterOperator.equal, addressFilterVal)],
    );
        
    final paymentsMap = <String, String>{};
    for (var pData in paymentsQuery) {
      final period = pData['period'] as String?;
      final status = pData['status'] as String?;
      if (period != null && status != null) {
        final existing = paymentsMap[period];
        if (existing == null || 
            status == 'approved' || 
            (status == 'pending' && existing == 'rejected')) {
          paymentsMap[period] = status;
        }
      }
    }
    
    String newStatus = 'paid';
    bool hasPending = false;
    bool hasUnpaid = false;
    
    for (var period in requiredPeriods) {
      final status = paymentsMap[period];
      if (status == null || status == 'rejected') {
        hasUnpaid = true;
      } else if (status == 'pending') {
        hasPending = true;
      }
    }
    
    if (hasUnpaid) {
      newStatus = 'restricted';
    } else if (hasPending) {
      newStatus = 'reviewing';
    } else {
      newStatus = 'paid';
    }
    
    await Backend.db.updateDocument('addresses', addressId, {'paymentStatus': newStatus});
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

