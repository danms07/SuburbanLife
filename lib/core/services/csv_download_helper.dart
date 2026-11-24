import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'web_file_transfer_helper.dart';

/// Cross-platform CSV download and native file export utility.
class CsvDownloadHelper {
  const CsvDownloadHelper._();

  /// Strips directory traversal segments from [fileName] so native exports
  /// always write strictly inside the target application documents directory.
  static String sanitizeFileName(String fileName) =>
      sanitizeWebFileName(fileName, fallback: 'export.csv');

  /// Exports UTF-8 [content] as [fileName].
  ///
  /// On Web, initiates a browser file download via `Blob` and `AnchorElement`
  /// and returns `null`. On native platforms, writes to the application
  /// documents directory (or [directoryOverride] when supplied in tests) and
  /// returns the written file path.
  static Future<String?> saveCsvFile({
    required String content,
    required String fileName,
    Future<Directory> Function()? directoryOverride,
  }) async {
    final safeName = sanitizeFileName(fileName);
    if (kIsWeb) {
      final bytes = Uint8List.fromList(utf8.encode(content));
      WebFileTransferHelper.downloadBytes(
        bytes: bytes,
        fileName: safeName,
        mimeType: 'text/csv;charset=utf-8',
      );
      return null;
    }

    final directory = directoryOverride != null
        ? await directoryOverride()
        : await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$safeName';
    final file = File(filePath);
    await file.writeAsString(content);
    return filePath;
  }
}
