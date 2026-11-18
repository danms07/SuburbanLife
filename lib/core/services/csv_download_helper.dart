import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;

/// Cross-platform CSV download and native file export utility.
class CsvDownloadHelper {
  const CsvDownloadHelper._();

  /// Strips directory traversal segments from [fileName] so native exports
  /// always write strictly inside the target application documents directory.
  static String sanitizeFileName(String fileName) {
    final normalized = fileName.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty && segment != '.' && segment != '..')
        .toList();
    if (segments.isEmpty) {
      return 'export.csv';
    }
    final baseName = segments.last.trim();
    return baseName.isEmpty ? 'export.csv' : baseName;
  }

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
      final bytes = utf8.encode(content);
      final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', safeName);
      html.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      html.Url.revokeObjectUrl(url);
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
