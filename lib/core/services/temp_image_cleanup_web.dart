import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'temp_image_cleanup_stub.dart';

class WebTempImageCleanupHelper extends TempImageCleanupHelper {
  @override
  Future<bool> deleteTempPath(String? filePath, {List<String>? extraAllowedRootPaths}) async {
    final trimmed = filePath?.trim() ?? '';
    if (trimmed.startsWith('blob:')) {
      try {
        web.URL.revokeObjectURL(trimmed);
        debugPrint('>>> [TempImageCleanup-Web] Revoked blob URL: $trimmed');
        return true;
      } catch (e) {
        debugPrint('>>> [TempImageCleanup-Web] Note revoking blob URL: $e');
      }
    }
    return false;
  }

  @override
  Future<int> purgeStalePickerImages({
    Duration maxAge = const Duration(minutes: 30),
    List<String>? overrideCacheDirPaths,
  }) async {
    return 0;
  }
}

TempImageCleanupHelper createTempImageCleanupHelper() => WebTempImageCleanupHelper();
