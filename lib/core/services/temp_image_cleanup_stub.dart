import 'package:image_picker/image_picker.dart';

abstract class TempImageCleanupHelper {
  /// Safely deletes a temporary/cached local image file (or revokes a Web blob URL).
  /// Returns true if a file or blob URL was removed.
  Future<bool> deleteTempPath(String? filePath, {List<String>? extraAllowedRootPaths});

  /// Convenience wrapper for an [XFile] returned by `ImagePicker`.
  Future<bool> deleteTempXFile(XFile? file, {List<String>? extraAllowedRootPaths}) {
    if (file == null) return Future.value(false);
    return deleteTempPath(file.path, extraAllowedRootPaths: extraAllowedRootPaths);
  }

  /// Purges stale top-level temporary image files left behind in the app's
  /// temporary/cache directories older than [maxAge].
  /// Returns the number of files deleted.
  Future<int> purgeStalePickerImages({
    Duration maxAge = const Duration(minutes: 30),
    List<String>? overrideCacheDirPaths,
  });
}

TempImageCleanupHelper createTempImageCleanupHelper() =>
    throw UnsupportedError('Cannot create TempImageCleanupHelper');
