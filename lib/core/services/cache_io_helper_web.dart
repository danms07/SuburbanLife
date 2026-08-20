import 'dart:typed_data';
import 'cache_io_helper_stub.dart';

class WebCacheIoHelper implements CacheIoHelper {
  final Map<String, Uint8List> _mem = {};

  @override
  Future<bool> isCached(String key) async => _mem.containsKey(key);

  @override
  Future<Uint8List?> getCachedBytes(String key) async => _mem[key];

  @override
  Future<void> saveCachedBytes(String key, Uint8List bytes) async {
    _mem[key] = bytes;
  }

  @override
  Future<String?> getCachedFilePath(String key) async => null;

  @override
  Future<void> removeCachedFile(String key) async {
    _mem.remove(key);
  }

  @override
  Future<void> clearAllCache() async {
    _mem.clear();
  }
}

CacheIoHelper createCacheIoHelper() => WebCacheIoHelper();
