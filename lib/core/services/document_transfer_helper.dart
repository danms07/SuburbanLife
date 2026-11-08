import 'dart:math';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:universal_html/html.dart' as html;
import '../config/app_config.dart';
import '../widgets/interactive_image_dialog.dart';
import '../../l10n/app_localizations.dart';
import 'document_cache_service.dart';
import 'temp_image_cleanup_service.dart';

/// Represents a validated local file selected or captured by the user prior to upload.
class PickedDocumentData {
  final String sanitizedFileName;
  final String extension;
  final String contentType;
  final int fileSize;
  final Uint8List bytes;
  final XFile? tempCameraFile;

  const PickedDocumentData({
    required this.sanitizedFileName,
    required this.extension,
    required this.contentType,
    required this.fileSize,
    required this.bytes,
    this.tempCameraFile,
  });
}

/// Centralized cross-platform file picker, validator, and downloader/viewer
/// for Amenity Documentation templates and Resident Booking Attachments.
class DocumentTransferHelper {
  /// Maximum allowed upload size (10 MB), aligned with Cloud Storage & Functions limits.
  static const int maxUploadSizeBytes = 10 * 1024 * 1024;

  /// Strict allow-list of file extensions (SVG, HTML, and executable scripts are excluded).
  static const List<String> allowedExtensions = [
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  /// Image extensions eligible for in-app interactive zoom/rotate preview.
  static const List<String> imageExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  /// Explicit `<input type="file" accept="...">` value for Web uploads.
  /// Avoids `*/*`, `audio/*`, and `video/*` so mobile Chromium/Edge browsers on
  /// Android 13+ launch the document picker without requesting audio/media permissions.
  static const String webAcceptAttribute =
      '.pdf,.doc,.docx,.xls,.xlsx,.jpg,.jpeg,.png,.webp,'
      'application/pdf,'
      'application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document,'
      'application/vnd.ms-excel,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,'
      'image/jpeg,image/png,image/webp';

  static Future<PickedDocumentData?> Function(BuildContext context)? _pickOverride;
  static Future<PickedDocumentData?> Function(BuildContext context)? _captureOverride;
  static Future<void> Function({
    required BuildContext context,
    required String cacheId,
    required String url,
    required String fileName,
    required String title,
  })? _openOverride;

  @visibleForTesting
  static void setOverridesForTesting({
    Future<PickedDocumentData?> Function(BuildContext context)? pickDocument,
    Future<PickedDocumentData?> Function(BuildContext context)? capturePhoto,
    Future<void> Function({
      required BuildContext context,
      required String cacheId,
      required String url,
      required String fileName,
      required String title,
    })? openOrDownload,
  }) {
    _pickOverride = pickDocument;
    _captureOverride = capturePhoto;
    _openOverride = openOrDownload;
  }

  @visibleForTesting
  static void resetOverridesForTesting() {
    _pickOverride = null;
    _captureOverride = null;
    _openOverride = null;
  }

  /// Strips directory traversal segments and unsafe characters from uploaded filenames.
  static String sanitizeFileName(String rawFileName) {
    final normalized = rawFileName.trim().replaceAll('\\', '/');
    final baseName = normalized.split('/').last.trim();
    if (baseName.isEmpty || baseName == '.' || baseName == '..') {
      return '';
    }
    var sanitized = baseName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    sanitized = sanitized.replaceAll(RegExp(r'\.{2,}'), '_');
    if (sanitized.isEmpty || RegExp(r'^[_.-]+$').hasMatch(sanitized)) {
      return '';
    }
    if (sanitized.length > 120) {
      final ext = extractExtension(sanitized);
      final maxStem = ext.isNotEmpty ? 120 - ext.length - 1 : 120;
      final stem = sanitized.substring(0, maxStem);
      sanitized = ext.isNotEmpty ? '$stem.$ext' : stem;
    }
    return sanitized;
  }

  /// Extracts the lowercase file extension without leading dot, or empty string if missing.
  static String extractExtension(String fileName) {
    final sanitized = sanitizeFileName(fileName);
    final dotIndex = sanitized.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == sanitized.length - 1) {
      return '';
    }
    return sanitized.substring(dotIndex + 1).toLowerCase();
  }

  /// Derives a default human-readable document title from a filename (stripping extension).
  static String defaultTitleFromFileName(String fileName) {
    final sanitized = sanitizeFileName(fileName);
    if (sanitized.isEmpty) return 'Document';
    final dotIndex = sanitized.lastIndexOf('.');
    final stem = dotIndex > 0 ? sanitized.substring(0, dotIndex) : sanitized;
    final cleaned = stem.replaceAll('_', ' ').trim();
    return cleaned.isEmpty ? sanitized : cleaned;
  }

  /// Validates that [fileName] has an extension in [allowedExtensions].
  static bool isAllowedExtension(String fileName) {
    final ext = extractExtension(fileName);
    return ext.isNotEmpty && allowedExtensions.contains(ext);
  }

  /// Resolves the canonical MIME type for an allow-listed [extension].
  static String? resolveMimeType(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return null;
    }
  }

  /// Builds a safe `Content-Disposition: attachment` header to force file download
  /// and prevent inline browser execution.
  static String buildContentDisposition(String rawFileName) {
    final safeName = sanitizeFileName(rawFileName);
    final fallback = safeName.isEmpty ? 'document.bin' : safeName;
    return 'attachment; filename="$fallback"';
  }

  /// Generates a cryptographically strong hex identifier using OS CSPRNG.
  static String generateSecureRandomHex([int byteLength = 16]) {
    final rng = Random.secure();
    final buffer = StringBuffer();
    for (int i = 0; i < byteLength; i++) {
      buffer.write(rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Constructs an unpredictable Storage object path under [prefix]/[scopeId]/
  /// while rejecting path traversal characters.
  static String buildStoragePath({
    required String prefix,
    required String scopeId,
    required String extension,
  }) {
    final cleanPrefix = prefix.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    final cleanScope = scopeId.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    final cleanExt = extension.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (cleanPrefix.isEmpty || cleanScope.isEmpty || !allowedExtensions.contains(cleanExt)) {
      throw ArgumentError('Invalid storage path parameters.');
    }
    final randomId = generateSecureRandomHex(16);
    return '$cleanPrefix/$cleanScope/$randomId.$cleanExt';
  }

  /// Inspects magic bytes header to verify the binary payload matches [extension].
  static bool validateMagicBytes(Uint8List bytes, String extension) {
    final ext = extension.trim().toLowerCase();
    if (bytes.length < 4) return false;

    switch (ext) {
      case 'pdf':
        // %PDF-
        return bytes.length >= 5 &&
            bytes[0] == 0x25 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x44 &&
            bytes[3] == 0x46 &&
            bytes[4] == 0x2D;
      case 'png':
        // 89 50 4E 47 0D 0A 1A 0A
        return bytes.length >= 8 &&
            bytes[0] == 0x89 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x4E &&
            bytes[3] == 0x47 &&
            bytes[4] == 0x0D &&
            bytes[5] == 0x0A &&
            bytes[6] == 0x1A &&
            bytes[7] == 0x0A;
      case 'jpg':
      case 'jpeg':
        // FF D8 FF
        return bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
      case 'webp':
        // RIFF....WEBP
        return bytes.length >= 12 &&
            bytes[0] == 0x52 &&
            bytes[1] == 0x49 &&
            bytes[2] == 0x46 &&
            bytes[3] == 0x46 &&
            bytes[8] == 0x57 &&
            bytes[9] == 0x45 &&
            bytes[10] == 0x42 &&
            bytes[11] == 0x50;
      case 'docx':
      case 'xlsx':
        // OOXML ZIP container: PK\x03\x04
        return bytes[0] == 0x50 &&
            bytes[1] == 0x4B &&
            bytes[2] == 0x03 &&
            bytes[3] == 0x04;
      case 'doc':
      case 'xls':
        // OLE2 Compound Document: D0 CF 11 E0 A1 B1 1A E1
        return bytes.length >= 8 &&
            bytes[0] == 0xD0 &&
            bytes[1] == 0xCF &&
            bytes[2] == 0x11 &&
            bytes[3] == 0xE0 &&
            bytes[4] == 0xA1 &&
            bytes[5] == 0xB1 &&
            bytes[6] == 0x1A &&
            bytes[7] == 0xE1;
      default:
        return false;
    }
  }

  /// Formats byte sizes concisely (B, KB, MB) for UI badges.
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  /// Returns an icon matching the file extension.
  static IconData iconForExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_outlined;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
        return Icons.image_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  /// Launches the platform document picker and validates extension, size, and magic bytes.
  // TODO(security): Integrate server-side malware scanning and CDR active-content stripping for uploaded binary documents.
  static Future<PickedDocumentData?> pickAllowedDocument(BuildContext context) async {
    if (_pickOverride != null) {
      return _pickOverride!(context);
    }

    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    String? sanitizedName;
    Uint8List? rawBytes;
    int? declaredSize;

    try {
      if (kIsWeb) {
        final uploadInput = html.FileUploadInputElement()..accept = webAcceptAttribute;
        uploadInput.click();
        await uploadInput.onChange.first;
        if (uploadInput.files == null || uploadInput.files!.isEmpty) {
          return null;
        }
        final file = uploadInput.files!.first;
        sanitizedName = sanitizeFileName(file.name);
        declaredSize = file.size;

        if (!isAllowedExtension(sanitizedName)) {
          messenger.showSnackBar(SnackBar(content: Text(l10n.unsupportedDocumentType)));
          return null;
        }
        if (declaredSize > maxUploadSizeBytes) {
          messenger.showSnackBar(SnackBar(content: Text(l10n.documentExceedsMaxSize)));
          return null;
        }

        final reader = html.FileReader();
        reader.readAsArrayBuffer(file);
        await reader.onLoadEnd.first;
        final res = reader.result;
        if (res is Uint8List) {
          rawBytes = res;
        } else if (res is ByteBuffer) {
          rawBytes = res.asUint8List();
        } else if (res is List<int>) {
          rawBytes = Uint8List.fromList(res);
        }
      } else {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: allowedExtensions,
          withData: true,
        );
        if (result == null || result.files.isEmpty) {
          return null;
        }
        final file = result.files.first;
        sanitizedName = sanitizeFileName(file.name);
        declaredSize = file.size;

        if (!isAllowedExtension(sanitizedName)) {
          messenger.showSnackBar(SnackBar(content: Text(l10n.unsupportedDocumentType)));
          return null;
        }
        if (declaredSize > maxUploadSizeBytes) {
          messenger.showSnackBar(SnackBar(content: Text(l10n.documentExceedsMaxSize)));
          return null;
        }

        rawBytes = file.bytes;
        if ((rawBytes == null || rawBytes.isEmpty) && file.path != null) {
          rawBytes = await DocumentCacheService().readFileBytesFromDisk(file.path!);
        }
      }
    } catch (e) {
      debugPrint('>>> [DocumentTransferHelper] Error picking file: ${e.runtimeType}');
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorLoadingDocument)));
      return null;
    }

    if (sanitizedName.isEmpty || rawBytes == null || rawBytes.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorLoadingDocument)));
      return null;
    }

    if (rawBytes.length > maxUploadSizeBytes) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.documentExceedsMaxSize)));
      return null;
    }

    final ext = extractExtension(sanitizedName);
    final contentType = resolveMimeType(ext);
    if (contentType == null || !validateMagicBytes(rawBytes, ext)) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.invalidDocumentContentError),
          backgroundColor: Colors.redAccent,
        ),
      );
      return null;
    }

    return PickedDocumentData(
      sanitizedFileName: sanitizedName,
      extension: ext,
      contentType: contentType,
      fileSize: rawBytes.length,
      bytes: rawBytes,
    );
  }

  /// Launches bounded camera capture (`1600px` max) so residents can photograph signed paper forms.
  static Future<PickedDocumentData?> captureDocumentPhoto(BuildContext context) async {
    if (_captureOverride != null) {
      return _captureOverride!(context);
    }

    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (photo == null) return null;

      final bytes = await photo.readAsBytes();
      if (bytes.isEmpty) {
        await TempImageCleanupService.deleteTempXFile(photo);
        messenger.showSnackBar(SnackBar(content: Text(l10n.errorLoadingDocument)));
        return null;
      }
      if (bytes.length > maxUploadSizeBytes) {
        await TempImageCleanupService.deleteTempXFile(photo);
        messenger.showSnackBar(SnackBar(content: Text(l10n.documentExceedsMaxSize)));
        return null;
      }

      var sanitized = sanitizeFileName(photo.name);
      var ext = extractExtension(sanitized);
      if (!imageExtensions.contains(ext)) {
        // Infer image extension from magic bytes when camera returns generic filename
        if (validateMagicBytes(bytes, 'jpg')) {
          ext = 'jpg';
        } else if (validateMagicBytes(bytes, 'png')) {
          ext = 'png';
        } else if (validateMagicBytes(bytes, 'webp')) {
          ext = 'webp';
        } else {
          await TempImageCleanupService.deleteTempXFile(photo);
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.invalidDocumentContentError),
              backgroundColor: Colors.redAccent,
            ),
          );
          return null;
        }
        sanitized = 'signed_document_${DateTime.now().millisecondsSinceEpoch}.$ext';
      } else if (!validateMagicBytes(bytes, ext)) {
        await TempImageCleanupService.deleteTempXFile(photo);
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.invalidDocumentContentError),
            backgroundColor: Colors.redAccent,
          ),
        );
        return null;
      }

      final contentType = resolveMimeType(ext)!;
      return PickedDocumentData(
        sanitizedFileName: sanitized,
        extension: ext,
        contentType: contentType,
        fileSize: bytes.length,
        bytes: bytes,
        tempCameraFile: photo,
      );
    } catch (e) {
      debugPrint('>>> [DocumentTransferHelper] Error capturing photo: ${e.runtimeType}');
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorLoadingDocument)));
      return null;
    }
  }

  /// Opens images in the interactive zoom/rotate dialog or downloads/opens documents via local cache.
  static Future<void> openOrDownloadDocument({
    required BuildContext context,
    required String cacheId,
    required String url,
    required String fileName,
    required String title,
  }) async {
    if (_openOverride != null) {
      return _openOverride!(
        context: context,
        cacheId: cacheId,
        url: url,
        fileName: fileName,
        title: title,
      );
    }

    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final safeFileName = sanitizeFileName(fileName).isEmpty ? 'document.pdf' : sanitizeFileName(fileName);
    final ext = extractExtension(safeFileName);

    if (url.trim().isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorLoadingDocument)));
      return;
    }

    if (imageExtensions.contains(ext)) {
      showInteractiveImageDialog(context, url, title: title);
      return;
    }

    final cacheService = DocumentCacheService();

    if (kIsWeb) {
      try {
        final isCached = await cacheService.isCached(cacheId, safeFileName);
        if (!isCached && context.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.downloadingDocument),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        final bytes = await cacheService.getOrDownloadBytes(cacheId, url, safeFileName);
        final mime = resolveMimeType(ext) ?? 'application/octet-stream';
        final blob = html.Blob([bytes], mime);
        final blobUrl = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: blobUrl)
          ..setAttribute('download', safeFileName)
          ..rel = 'noopener noreferrer';
        html.document.body?.append(anchor);
        anchor.click();
        anchor.remove();
        html.Url.revokeObjectUrl(blobUrl);

        if (context.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(isCached ? l10n.openingExternalDocument : l10n.downloadCodeSuccess),
              backgroundColor: AppConfig.secondaryColor,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        debugPrint('>>> [DocumentTransferHelper] Web download fallback triggered: ${e.runtimeType}');
        html.window.open(url, '_blank');
      }
      return;
    }

    try {
      final isCached = await cacheService.isCached(cacheId, safeFileName);
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(isCached ? l10n.openingExternalDocument : l10n.downloadingDocument),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      final filePath = await cacheService.getOrDownloadFilePath(cacheId, url, safeFileName);
      if (filePath != null && filePath.isNotEmpty) {
        final result = await OpenFilex.open(filePath);
        if (result.type != ResultType.done && context.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('${l10n.noAppToOpenFile}: ${result.message}'),
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.errorLoadingDocument)));
      }
    } catch (e) {
      debugPrint('>>> [DocumentTransferHelper] Native open error: ${e.runtimeType}');
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.errorLoadingDocument)));
      }
    }
  }
}
