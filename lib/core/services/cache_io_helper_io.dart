import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'cache_io_helper_stub.dart';

class NativeCacheIoHelper implements CacheIoHelper {
  Future<Directory> _getCacheDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${docsDir.path}/transparency_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  @override
  Future<bool> isCached(String key) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final file = File('${cacheDir.path}/$key');
      final exists = await file.exists();
      final length = exists ? await file.length() : 0;
      final cached = exists && length > 0;
      debugPrint('>>> [NativeCacheIoHelper] isCached(key="$key"): exists=$exists, size=$length bytes => $cached');
      return cached;
    } catch (e) {
      debugPrint('>>> [NativeCacheIoHelper] Error checking cache: $e');
      return false;
    }
  }

  @override
  Future<Uint8List?> getCachedBytes(String key) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final file = File('${cacheDir.path}/$key');
      if (await file.exists() && (await file.length()) > 0) {
        debugPrint('>>> [NativeCacheIoHelper] getCachedBytes: reading from ${file.path}');
        return await file.readAsBytes();
      }
    } catch (e) {
      debugPrint('>>> [NativeCacheIoHelper] Error reading cached bytes: $e');
    }
    return null;
  }

  @override
  Future<void> saveCachedBytes(String key, Uint8List bytes) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final file = File('${cacheDir.path}/$key');
      await file.writeAsBytes(bytes, flush: true);
      debugPrint('>>> [NativeCacheIoHelper] saveCachedBytes: wrote ${bytes.length} bytes to ${file.path}');
    } catch (e) {
      debugPrint('>>> [NativeCacheIoHelper] Error saving cached bytes: $e');
    }
  }

  @override
  Future<String?> getCachedFilePath(String key) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final file = File('${cacheDir.path}/$key');
      if (await file.exists() && (await file.length()) > 0) {
        debugPrint('>>> [NativeCacheIoHelper] getCachedFilePath: found valid cached file at ${file.path}');
        return file.path;
      }
    } catch (e) {
      debugPrint('>>> [NativeCacheIoHelper] Error getting cached file path: $e');
    }
    return null;
  }

  @override
  Future<void> removeCachedFile(String key) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final file = File('${cacheDir.path}/$key');
      if (await file.exists()) {
        await file.delete();
        debugPrint('>>> [NativeCacheIoHelper] removeCachedFile: deleted ${file.path}');
      }
    } catch (e) {
      debugPrint('>>> [NativeCacheIoHelper] Error removing cached file: $e');
    }
  }

  @override
  Future<void> clearAllCache() async {
    try {
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        debugPrint('>>> [NativeCacheIoHelper] clearAllCache: deleted cache directory at ${cacheDir.path}');
      }
    } catch (e) {
      debugPrint('>>> [NativeCacheIoHelper] Error clearing cache: $e');
    }
  }

  @override
  Future<Uint8List?> readFileBytesFromDisk(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        debugPrint('>>> [NativeCacheIoHelper] readFileBytesFromDisk: reading ${file.path}');
        return await file.readAsBytes();
      }
    } catch (e) {
      debugPrint('>>> [NativeCacheIoHelper] Error reading file bytes from disk: $e');
    }
    return null;
  }
}

CacheIoHelper createCacheIoHelper() => NativeCacheIoHelper();
