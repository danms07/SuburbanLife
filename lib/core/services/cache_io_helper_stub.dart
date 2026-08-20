import 'dart:typed_data';

abstract class CacheIoHelper {
  Future<bool> isCached(String key);
  Future<Uint8List?> getCachedBytes(String key);
  Future<void> saveCachedBytes(String key, Uint8List bytes);
  Future<String?> getCachedFilePath(String key);
  Future<void> removeCachedFile(String key);
  Future<void> clearAllCache();
  Future<Uint8List?> readFileBytesFromDisk(String filePath);
}

CacheIoHelper createCacheIoHelper() => throw UnsupportedError('Cannot create CacheIoHelper');
