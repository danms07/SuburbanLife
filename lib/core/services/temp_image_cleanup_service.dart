import 'package:image_picker/image_picker.dart';
import 'temp_image_cleanup_stub.dart';
import 'temp_image_cleanup_stub.dart'
    if (dart.library.io) 'temp_image_cleanup_io.dart'
    if (dart.library.html) 'temp_image_cleanup_web.dart' as impl;

export 'temp_image_cleanup_stub.dart';

class TempImageCleanupService {
  static TempImageCleanupHelper _instance = impl.createTempImageCleanupHelper();

  /// Allows injecting a custom helper in tests if needed.
  static void setHelperForTesting(TempImageCleanupHelper helper) {
    _instance = helper;
  }

  static void resetHelperForTesting() {
    _instance = impl.createTempImageCleanupHelper();
  }

  static Future<bool> deleteTempPath(
    String? filePath, {
    List<String>? extraAllowedRootPaths,
  }) {
    return _instance.deleteTempPath(
      filePath,
      extraAllowedRootPaths: extraAllowedRootPaths,
    );
  }

  static Future<bool> deleteTempXFile(
    XFile? file, {
    List<String>? extraAllowedRootPaths,
  }) {
    return _instance.deleteTempXFile(
      file,
      extraAllowedRootPaths: extraAllowedRootPaths,
    );
  }

  static Future<int> purgeStalePickerImages({
    Duration maxAge = const Duration(minutes: 30),
    List<String>? overrideCacheDirPaths,
  }) {
    return _instance.purgeStalePickerImages(
      maxAge: maxAge,
      overrideCacheDirPaths: overrideCacheDirPaths,
    );
  }
}
