import '../../core/backend/backend.dart';
import '../../core/services/document_transfer_helper.dart';
import '../../core/services/temp_image_cleanup_service.dart';

/// Allowed expense category slugs matching Cloud Function validation.
class ExpenseCategory {
  static const String maintenance = 'maintenance';
  static const String gardening = 'gardening';
  static const String security = 'security';
  static const String utilities = 'utilities';
  static const String repairs = 'repairs';
  static const String supplies = 'supplies';
  static const String other = 'other';

  static const List<String> all = [
    maintenance,
    gardening,
    security,
    utilities,
    repairs,
    supplies,
    other,
  ];
}

/// Metadata and storage coordinates for an uploaded expense evidence file.
class ExpenseEvidence {
  final String fileName;
  final String fileType;
  final int fileSize;
  final String url;
  final String storagePath;
  final int uploadedAt;

  const ExpenseEvidence({
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.url,
    required this.storagePath,
    required this.uploadedAt,
  });

  bool get isImage => DocumentTransferHelper.imageExtensions.contains(
        fileType.toLowerCase(),
      );

  factory ExpenseEvidence.fromMap(Map<String, dynamic> map) {
    return ExpenseEvidence(
      fileName: map['fileName']?.toString() ?? '',
      fileType: map['fileType']?.toString().toLowerCase() ?? '',
      fileSize: (map['fileSize'] as num?)?.toInt() ?? 0,
      url: map['url']?.toString() ?? '',
      storagePath: map['storagePath']?.toString() ?? '',
      uploadedAt: (map['uploadedAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fileName': fileName,
      'fileType': fileType,
      'fileSize': fileSize,
      'url': url,
      'storagePath': storagePath,
      'uploadedAt': uploadedAt,
    };
  }
}

/// Domain model representing a recorded community expense and its audit status.
class ExpenseRecord {
  final String id;
  final String productOrService;
  final double amount;
  final String billablePeriod;
  final int expenseDateMs;
  final String category;
  final String vendorName;
  final String notes;
  final ExpenseEvidence productEvidence;
  final ExpenseEvidence receiptEvidence;
  final String status;
  final String createdBy;
  final String createdByName;
  final int createdAtMs;
  final String? voidedBy;
  final String? voidedByName;
  final int? voidedAtMs;
  final String? voidReason;

  const ExpenseRecord({
    required this.id,
    required this.productOrService,
    required this.amount,
    required this.billablePeriod,
    required this.expenseDateMs,
    required this.category,
    required this.vendorName,
    required this.notes,
    required this.productEvidence,
    required this.receiptEvidence,
    required this.status,
    required this.createdBy,
    required this.createdByName,
    required this.createdAtMs,
    this.voidedBy,
    this.voidedByName,
    this.voidedAtMs,
    this.voidReason,
  });

  bool get isActive => status == 'active';
  bool get isVoided => status == 'voided';

  DateTime get expenseDate =>
      DateTime.fromMillisecondsSinceEpoch(expenseDateMs);

  static int _parseMillis(dynamic raw, {int fallback = 0}) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is DateTime) return raw.millisecondsSinceEpoch;
    return fallback;
  }

  factory ExpenseRecord.fromMap(Map<String, dynamic> map) {
    final prodMap = map['productEvidence'] is Map
        ? Map<String, dynamic>.from(map['productEvidence'] as Map)
        : <String, dynamic>{};
    final recMap = map['receiptEvidence'] is Map
        ? Map<String, dynamic>.from(map['receiptEvidence'] as Map)
        : <String, dynamic>{};

    final createdMs = _parseMillis(map['createdAt']);
    final expenseMs = _parseMillis(map['expenseDate'], fallback: createdMs);

    return ExpenseRecord(
      id: map['id']?.toString() ?? '',
      productOrService: map['productOrService']?.toString() ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      billablePeriod: map['billablePeriod']?.toString() ?? '',
      expenseDateMs: expenseMs,
      category: (map['category']?.toString().trim().isNotEmpty ?? false)
          ? map['category'].toString().trim().toLowerCase()
          : ExpenseCategory.other,
      vendorName: map['vendorName']?.toString() ?? '',
      notes: map['notes']?.toString() ?? '',
      productEvidence: ExpenseEvidence.fromMap(prodMap),
      receiptEvidence: ExpenseEvidence.fromMap(recMap),
      status: map['status']?.toString() ?? 'active',
      createdBy: map['createdBy']?.toString() ?? '',
      createdByName: map['createdByName']?.toString() ?? '',
      createdAtMs: createdMs,
      voidedBy: map['voidedBy']?.toString(),
      voidedByName: map['voidedByName']?.toString(),
      voidedAtMs: map['voidedAt'] != null ? _parseMillis(map['voidedAt']) : null,
      voidReason: map['voidReason']?.toString(),
    );
  }
}

/// Service orchestrating Cloud Storage uploads, Cloud Function persistence,
/// rollback cleanup, and live streaming for administrative community expenses.
class ExpenseService {
  static final RegExp _periodRegex = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

  /// Streams all recorded expenses sorted chronologically (newest first).
  Stream<List<ExpenseRecord>> streamExpenses() {
    return Backend.db.streamCollection('expenses').map((docs) {
      final list = docs.map(ExpenseRecord.fromMap).toList();
      list.sort((a, b) {
        final dateCmp = b.expenseDateMs.compareTo(a.expenseDateMs);
        if (dateCmp != 0) return dateCmp;
        return b.createdAtMs.compareTo(a.createdAtMs);
      });
      return list;
    });
  }

  /// Uploads both required evidences to `expenses/<uid>/` and invokes
  /// `createExpense`, cleaning up uploaded objects on failure and removing temp
  /// local camera files after upload.
  Future<String> recordExpense({
    required String adminUid,
    required String productOrService,
    required double amount,
    required String billablePeriod,
    required DateTime expenseDate,
    required String category,
    required PickedDocumentData productEvidenceFile,
    required PickedDocumentData receiptEvidenceFile,
    String vendorName = '',
    String notes = '',
  }) async {
    final trimmedTitle = productOrService.trim();
    if (trimmedTitle.isEmpty || trimmedTitle.length > 200) {
      throw ArgumentError('Product or service description is required.');
    }
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Expense amount must be a positive number.');
    }
    final cleanPeriod = billablePeriod.trim();
    if (!_periodRegex.hasMatch(cleanPeriod)) {
      throw ArgumentError('Billable period must follow YYYY-MM format.');
    }
    if (!DocumentTransferHelper.imageExtensions
        .contains(productEvidenceFile.extension.toLowerCase())) {
      throw ArgumentError('Product/Service evidence must be an image file.');
    }
    if (!DocumentTransferHelper.expenseReceiptExtensions
        .contains(receiptEvidenceFile.extension.toLowerCase())) {
      throw ArgumentError(
        'Receipt/Invoice evidence must be an image or PDF file.',
      );
    }

    final uploadedUrls = <String>[];
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final prodStoragePath = DocumentTransferHelper.buildStoragePath(
        prefix: 'expenses',
        scopeId: adminUid,
        extension: productEvidenceFile.extension,
      );
      final prodUrl = await Backend.storage.uploadFile(
        prodStoragePath,
        productEvidenceFile.bytes,
        contentType: productEvidenceFile.contentType,
        contentDisposition: DocumentTransferHelper.buildContentDisposition(
          productEvidenceFile.sanitizedFileName,
        ),
        metadata: {'uploaderUid': adminUid},
      );
      uploadedUrls.add(prodUrl);

      final receiptStoragePath = DocumentTransferHelper.buildStoragePath(
        prefix: 'expenses',
        scopeId: adminUid,
        extension: receiptEvidenceFile.extension,
      );
      final receiptUrl = await Backend.storage.uploadFile(
        receiptStoragePath,
        receiptEvidenceFile.bytes,
        contentType: receiptEvidenceFile.contentType,
        contentDisposition: DocumentTransferHelper.buildContentDisposition(
          receiptEvidenceFile.sanitizedFileName,
        ),
        metadata: {'uploaderUid': adminUid},
      );
      uploadedUrls.add(receiptUrl);

      final payload = {
        'productOrService': trimmedTitle,
        'amount': (amount * 100).round() / 100.0,
        'billablePeriod': cleanPeriod,
        'expenseDate': expenseDate.millisecondsSinceEpoch,
        'category': ExpenseCategory.all.contains(category)
            ? category
            : ExpenseCategory.other,
        'vendorName': vendorName.trim(),
        'notes': notes.trim(),
        'productEvidence': {
          'fileName': productEvidenceFile.sanitizedFileName,
          'fileType': productEvidenceFile.extension,
          'fileSize': productEvidenceFile.fileSize,
          'url': prodUrl,
          'storagePath': prodStoragePath,
          'uploadedAt': nowMs,
        },
        'receiptEvidence': {
          'fileName': receiptEvidenceFile.sanitizedFileName,
          'fileType': receiptEvidenceFile.extension,
          'fileSize': receiptEvidenceFile.fileSize,
          'url': receiptUrl,
          'storagePath': receiptStoragePath,
          'uploadedAt': nowMs,
        },
      };

      final res = await Backend.functions.callFunction('createExpense', payload);
      if (res is Map && res['expenseId'] != null) {
        return res['expenseId'].toString();
      }
      return '';
    } catch (e, stack) {
      // Roll back uploaded Storage artifacts so failed requests never leave orphan files
      for (final url in uploadedUrls) {
        try {
          await Backend.storage.deleteFileFromUrl(url);
        } catch (_) {}
      }
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'ExpenseService.recordExpense',
      );
      rethrow;
    } finally {
      await TempImageCleanupService.deleteTempXFile(
        productEvidenceFile.tempCameraFile,
      );
      await TempImageCleanupService.deleteTempXFile(
        receiptEvidenceFile.tempCameraFile,
      );
    }
  }

  /// Soft-voids an active expense while preserving audit trail and evidences.
  Future<void> voidExpense({
    required String expenseId,
    required String voidReason,
  }) async {
    final trimmedReason = voidReason.trim();
    if (trimmedReason.length < 3) {
      throw ArgumentError('Void reason must be at least 3 characters.');
    }

    try {
      await Backend.functions.callFunction('voidExpense', {
        'expenseId': expenseId,
        'voidReason': trimmedReason,
      });
    } catch (e, stack) {
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'ExpenseService.voidExpense',
      );
      rethrow;
    }
  }
}
