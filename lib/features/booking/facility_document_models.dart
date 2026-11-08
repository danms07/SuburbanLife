import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../../core/services/temp_image_cleanup_service.dart';

/// Defines how an amenity document behaves during resident booking.
enum FacilityDocRequirementMode {
  /// Resident can download the template and MUST attach a completed/signed file to submit.
  mandatoryReturn,

  /// Resident can download the template and MAY optionally attach a file.
  optionalReturn,

  /// Informative reference only (download/view only; no return upload slot).
  informative;

  String toWireString() {
    switch (this) {
      case FacilityDocRequirementMode.mandatoryReturn:
        return 'mandatory_return';
      case FacilityDocRequirementMode.optionalReturn:
        return 'optional_return';
      case FacilityDocRequirementMode.informative:
        return 'informative';
    }
  }

  static FacilityDocRequirementMode fromWireString(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'mandatory_return':
        return FacilityDocRequirementMode.mandatoryReturn;
      case 'optional_return':
        return FacilityDocRequirementMode.optionalReturn;
      case 'informative':
      default:
        return FacilityDocRequirementMode.informative;
    }
  }

  bool get acceptsAttachment =>
      this == FacilityDocRequirementMode.mandatoryReturn ||
      this == FacilityDocRequirementMode.optionalReturn;

  bool get isMandatory => this == FacilityDocRequirementMode.mandatoryReturn;
}

/// Persisted template document entry inside `facilities/{facilityId}.facilityDocuments`.
class FacilityDocumentTemplate {
  final String docId;
  final String title;
  final FacilityDocRequirementMode requirementMode;
  final String fileName;
  final String fileType;
  final int fileSize;
  final String url;
  final String storagePath;
  final int uploadedAt;

  const FacilityDocumentTemplate({
    required this.docId,
    required this.title,
    required this.requirementMode,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.url,
    required this.storagePath,
    required this.uploadedAt,
  });

  factory FacilityDocumentTemplate.fromMap(Map<String, dynamic> map) {
    final rawSize = map['fileSize'];
    final rawUploadedAt = map['uploadedAt'];
    return FacilityDocumentTemplate(
      docId: (map['docId'] ?? '').toString().trim(),
      title: (map['title'] ?? map['fileName'] ?? '').toString().trim(),
      requirementMode: FacilityDocRequirementMode.fromWireString(
        map['requirementMode']?.toString(),
      ),
      fileName: (map['fileName'] ?? '').toString().trim(),
      fileType: (map['fileType'] ?? '').toString().trim().toLowerCase(),
      fileSize: rawSize is num ? rawSize.toInt() : int.tryParse(rawSize?.toString() ?? '0') ?? 0,
      url: (map['url'] ?? '').toString().trim(),
      storagePath: (map['storagePath'] ?? '').toString().trim(),
      uploadedAt: rawUploadedAt is num
          ? rawUploadedAt.toInt()
          : int.tryParse(rawUploadedAt?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'docId': docId,
      'title': title,
      'requirementMode': requirementMode.toWireString(),
      'fileName': fileName,
      'fileType': fileType,
      'fileSize': fileSize,
      'url': url,
      'storagePath': storagePath,
      'uploadedAt': uploadedAt,
    };
  }

  static List<FacilityDocumentTemplate> parseList(dynamic rawList) {
    if (rawList is! List) return const [];
    final parsed = <FacilityDocumentTemplate>[];
    for (final item in rawList) {
      if (item is Map) {
        final template = FacilityDocumentTemplate.fromMap(Map<String, dynamic>.from(item));
        if (template.docId.isNotEmpty && template.url.isNotEmpty) {
          parsed.add(template);
        }
      }
    }
    return parsed;
  }
}

/// Represents a resident's in-progress attachment selection for a specific `facilityDocId`.
/// Supports both newly picked/captured local files and previously uploaded attachments
/// (when editing and resubmitting a rejected booking).
class DraftBookingAttachment {
  final String facilityDocId;
  final String title;
  final FacilityDocRequirementMode requirementMode;
  final String fileName;
  final String fileType;
  final String contentType;
  final int fileSize;
  final Uint8List? bytes;
  final XFile? tempCameraFile;
  final String? existingUrl;
  final String? existingStoragePath;
  final int? existingUploadedAt;

  const DraftBookingAttachment({
    required this.facilityDocId,
    required this.title,
    required this.requirementMode,
    required this.fileName,
    required this.fileType,
    required this.contentType,
    required this.fileSize,
    this.bytes,
    this.tempCameraFile,
    this.existingUrl,
    this.existingStoragePath,
    this.existingUploadedAt,
  });

  bool get isAlreadyUploaded =>
      bytes == null &&
      existingUrl != null &&
      existingUrl!.isNotEmpty &&
      existingStoragePath != null &&
      existingStoragePath!.isNotEmpty;

  factory DraftBookingAttachment.fromSubmitted(SubmittedBookingAttachment submitted) {
    return DraftBookingAttachment(
      facilityDocId: submitted.facilityDocId,
      title: submitted.title,
      requirementMode: submitted.requirementMode,
      fileName: submitted.fileName,
      fileType: submitted.fileType,
      contentType: '',
      fileSize: submitted.fileSize,
      existingUrl: submitted.url,
      existingStoragePath: submitted.storagePath,
      existingUploadedAt: submitted.uploadedAt,
    );
  }

  /// Cleans up any local temporary camera capture file associated with this draft.
  Future<void> disposeTempCapture() async {
    if (tempCameraFile != null) {
      await TempImageCleanupService.deleteTempXFile(tempCameraFile);
    }
  }
}

/// Persisted resident booking attachment entry inside `booking_attachments/{bookingId}.attachments`.
class SubmittedBookingAttachment {
  final String facilityDocId;
  final String title;
  final FacilityDocRequirementMode requirementMode;
  final String fileName;
  final String fileType;
  final int fileSize;
  final String url;
  final String storagePath;
  final int uploadedAt;

  const SubmittedBookingAttachment({
    required this.facilityDocId,
    required this.title,
    required this.requirementMode,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.url,
    required this.storagePath,
    required this.uploadedAt,
  });

  factory SubmittedBookingAttachment.fromMap(Map<String, dynamic> map) {
    final rawSize = map['fileSize'];
    final rawUploadedAt = map['uploadedAt'];
    return SubmittedBookingAttachment(
      facilityDocId: (map['facilityDocId'] ?? '').toString().trim(),
      title: (map['title'] ?? map['fileName'] ?? '').toString().trim(),
      requirementMode: FacilityDocRequirementMode.fromWireString(
        map['requirementMode']?.toString(),
      ),
      fileName: (map['fileName'] ?? '').toString().trim(),
      fileType: (map['fileType'] ?? '').toString().trim().toLowerCase(),
      fileSize: rawSize is num ? rawSize.toInt() : int.tryParse(rawSize?.toString() ?? '0') ?? 0,
      url: (map['url'] ?? '').toString().trim(),
      storagePath: (map['storagePath'] ?? '').toString().trim(),
      uploadedAt: rawUploadedAt is num
          ? rawUploadedAt.toInt()
          : int.tryParse(rawUploadedAt?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'facilityDocId': facilityDocId,
      'title': title,
      'requirementMode': requirementMode.toWireString(),
      'fileName': fileName,
      'fileType': fileType,
      'fileSize': fileSize,
      'url': url,
      'storagePath': storagePath,
      'uploadedAt': uploadedAt,
    };
  }

  static List<SubmittedBookingAttachment> parseList(dynamic rawList) {
    if (rawList is! List) return const [];
    final parsed = <SubmittedBookingAttachment>[];
    for (final item in rawList) {
      if (item is Map) {
        final att = SubmittedBookingAttachment.fromMap(Map<String, dynamic>.from(item));
        if (att.facilityDocId.isNotEmpty && att.url.isNotEmpty) {
          parsed.add(att);
        }
      }
    }
    return parsed;
  }
}

/// Returns any `mandatory_return` templates that do not yet have a corresponding draft attachment.
List<FacilityDocumentTemplate> findMissingMandatoryDocuments(
  List<FacilityDocumentTemplate> templates,
  Map<String, DraftBookingAttachment> draftsByDocId,
) {
  final missing = <FacilityDocumentTemplate>[];
  for (final template in templates) {
    if (template.requirementMode.isMandatory) {
      final draft = draftsByDocId[template.docId];
      if (draft == null || ((draft.bytes == null || draft.bytes!.isEmpty) && !draft.isAlreadyUploaded)) {
        missing.add(template);
      }
    }
  }
  return missing;
}
