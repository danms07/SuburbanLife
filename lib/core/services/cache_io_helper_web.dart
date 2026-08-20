import 'package:flutter/foundation.dart';
import 'cache_io_helper_stub.dart';

class WebCacheIoHelper implements CacheIoHelper {
  final Map<String, Uint8List> _mem = {};

  @override
  Future<bool> isCached(String key) async {
    final cached = _mem.containsKey(key);
    debugPrint('>>> [WebCacheIoHelper] isCached(key="$key") => $cached');
    return cached;
  }

  @override
  Future<Uint8List?> getCachedBytes(String key) async {
    final bytes = _mem[key];
    debugPrint('>>> [WebCacheIoHelper] getCachedBytes(key="$key"): found=${bytes != null}, length=${bytes?.length}');
    return bytes;
  }

  @override
  Future<void> saveCachedBytes(String key, Uint8List bytes) async {
    _mem[key] = bytes;
    debugPrint('>>> [WebCacheIoHelper] saveCachedBytes(key="$key"): saved in-memory cache of ${bytes.length} bytes');
  }

  @override
  Future<String?> getCachedFilePath(String key) async => null;

  @override
  Future<void> removeCachedFile(String key) async {
    _mem.remove(key);
    debugPrint('>>> [WebCacheIoHelper] removeCachedFile(key="$key")');
  }

  @override
  Future<void> clearAllCache() async {
    _mem.clear();
    debugPrint('>>> [WebCacheIoHelper] clearAllCache: cleared in-memory cache');
  }

  @override
  Future<Uint8List?> readFileBytesFromDisk(String filePath) async => null;
}

CacheIoHelper createCacheIoHelper() => WebCacheIoHelper();
