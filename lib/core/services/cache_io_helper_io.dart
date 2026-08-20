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
      return await file.exists() && (await file.length()) > 0;
    } catch (e) {
      debugPrint('Error checking cache: $e');
      return false;
    }
  }

  @override
  Future<Uint8List?> getCachedBytes(String key) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final file = File('${cacheDir.path}/$key');
      if (await file.exists() && (await file.length()) > 0) {
        return await file.readAsBytes();
      }
    } catch (e) {
      debugPrint('Error reading cached bytes: $e');
    }
    return null;
  }

  @override
  Future<void> saveCachedBytes(String key, Uint8List bytes) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final file = File('${cacheDir.path}/$key');
      await file.writeAsBytes(bytes, flush: true);
    } catch (e) {
      debugPrint('Error saving cached bytes: $e');
    }
  }

  @override
  Future<String?> getCachedFilePath(String key) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final file = File('${cacheDir.path}/$key');
      if (await file.exists() && (await file.length()) > 0) {
        return file.path;
      }
    } catch (e) {
      debugPrint('Error getting cached file path: $e');
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
      }
    } catch (e) {
      debugPrint('Error removing cached file: $e');
    }
  }

  @override
  Future<void> clearAllCache() async {
    try {
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }

  @override
  Future<Uint8List?> readFileBytesFromDisk(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e) {
      debugPrint('Error reading file bytes from disk: $e');
    }
    return null;
  }
}

CacheIoHelper createCacheIoHelper() => NativeCacheIoHelper();
