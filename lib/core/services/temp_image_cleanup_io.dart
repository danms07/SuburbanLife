import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'temp_image_cleanup_stub.dart';

class NativeTempImageCleanupHelper extends TempImageCleanupHelper {
  static const Set<String> _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.heic',
    '.heif',
  };

  List<Directory>? _cachedPlatformCacheDirs;

  Future<List<Directory>> _getPlatformCacheDirs() async {
    if (_cachedPlatformCacheDirs != null) {
      return _cachedPlatformCacheDirs!;
    }
    final dirs = <Directory>[];
    try {
      dirs.add(await getTemporaryDirectory());
    } catch (_) {}

    try {
      dirs.add(await getApplicationCacheDirectory());
    } catch (_) {}

    try {
      final extDirs = await getExternalCacheDirectories();
      if (extDirs != null) {
        dirs.addAll(extDirs);
      }
    } catch (_) {}

    _cachedPlatformCacheDirs = dirs;
    return dirs;
  }

  List<String> _buildAllowedPrefixesSync(
    List<Directory> dirs, {
    List<String>? extraRoots,
  }) {
    final candidates = <Directory>[
      Directory.systemTemp,
      ...dirs,
    ];

    if (extraRoots != null) {
      for (final p in extraRoots) {
        if (p.trim().isNotEmpty) {
          candidates.add(Directory(p));
        }
      }
    }

    final resolvedRoots = <String>{};
    final sep = Platform.pathSeparator;
    for (final dir in candidates) {
      try {
        if (dir.existsSync()) {
          final canonical = dir.resolveSymbolicLinksSync();
          final withTrailingSep = canonical.endsWith(sep) ? canonical : '$canonical$sep';
          resolvedRoots.add(withTrailingSep);
        }
      } catch (_) {}
    }
    return resolvedRoots.toList();
  }

  Future<List<String>> _resolveAllowedCacheRoots({List<String>? extraRoots}) async {
    final platformDirs = await _getPlatformCacheDirs();
    return _buildAllowedPrefixesSync(platformDirs, extraRoots: extraRoots);
  }

  bool _isSafeTempFileSync(File file, List<String> allowedPrefixes) {
    try {
      if (!file.existsSync()) return false;
      final canonicalPath = file.resolveSymbolicLinksSync();
      for (final prefix in allowedPrefixes) {
        if (canonicalPath.startsWith(prefix)) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  String _basename(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx >= 0 ? normalized.substring(idx + 1) : normalized;
  }

  @override
  Future<bool> deleteTempPath(String? filePath, {List<String>? extraAllowedRootPaths}) async {
    final trimmed = filePath?.trim() ?? '';
    if (trimmed.isEmpty) return false;

    bool deletedAny = false;
    try {
      final targetFile = File(trimmed);
      if (!targetFile.existsSync()) return false;

      // Fast synchronous check against Directory.systemTemp, any already-cached platform dirs,
      // and extraAllowedRootPaths before awaiting platform channel lookups.
      var allowedPrefixes = _buildAllowedPrefixesSync(
        _cachedPlatformCacheDirs ?? const [],
        extraRoots: extraAllowedRootPaths,
      );
      var isAllowed = _isSafeTempFileSync(targetFile, allowedPrefixes);

      if (!isAllowed && _cachedPlatformCacheDirs == null) {
        allowedPrefixes = await _resolveAllowedCacheRoots(extraRoots: extraAllowedRootPaths);
        isAllowed = _isSafeTempFileSync(targetFile, allowedPrefixes);
      }

      if (isAllowed) {
        final parentDir = targetFile.parent;
        final baseName = _basename(targetFile.path);

        targetFile.deleteSync();
        deletedAny = true;
        debugPrint('>>> [TempImageCleanup] Deleted temporary file: ${targetFile.path}');

        // Android image_picker creates <uuid>.jpg and a resized scaled_<uuid>.jpg in cacheDir.
        // Clean up the raw companion capture if present in the exact same allowed cache directory.
        if (baseName.startsWith('scaled_') && baseName.length > 'scaled_'.length) {
          final rawCompanionName = baseName.substring('scaled_'.length);
          if (!rawCompanionName.contains('/') && !rawCompanionName.contains('\\') && rawCompanionName != '..') {
            final companionFile = File('${parentDir.path}${Platform.pathSeparator}$rawCompanionName');
            if (_isSafeTempFileSync(companionFile, allowedPrefixes)) {
              companionFile.deleteSync();
              debugPrint('>>> [TempImageCleanup] Deleted raw companion capture: ${companionFile.path}');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('>>> [TempImageCleanup] Note while deleting temp image: $e');
    }
    return deletedAny;
  }

  @override
  Future<int> purgeStalePickerImages({
    Duration maxAge = const Duration(minutes: 30),
    List<String>? overrideCacheDirPaths,
  }) async {
    int deletedCount = 0;
    try {
      final List<Directory> targetDirs = [];
      if (overrideCacheDirPaths != null) {
        for (final p in overrideCacheDirPaths) {
          if (p.trim().isNotEmpty) {
            targetDirs.add(Directory(p));
          }
        }
      } else {
        targetDirs.addAll(await _getPlatformCacheDirs());
      }

      final allowedPrefixes = await _resolveAllowedCacheRoots(extraRoots: overrideCacheDirPaths);
      if (allowedPrefixes.isEmpty) return 0;

      final visitedDirs = <String>{};
      final cutoff = DateTime.now().subtract(maxAge);

      for (final dir in targetDirs) {
        try {
          if (!dir.existsSync()) continue;
          final canonicalDir = dir.resolveSymbolicLinksSync();
          if (!visitedDirs.add(canonicalDir)) continue;

          // Non-recursive listing protects structured cache subdirectories (e.g. libCachedImageData)
          final entries = dir.listSync(recursive: false, followLinks: false);
          for (final entity in entries) {
            if (entity is! File) continue;
            final lowerName = _basename(entity.path).toLowerCase();
            final dotIdx = lowerName.lastIndexOf('.');
            if (dotIdx < 0) continue;
            final ext = lowerName.substring(dotIdx);
            if (!_imageExtensions.contains(ext)) continue;

            final stat = entity.statSync();
            final isStale = maxAge <= Duration.zero || !stat.modified.isAfter(cutoff);
            if (!isStale) continue;

            if (_isSafeTempFileSync(entity, allowedPrefixes)) {
              entity.deleteSync();
              deletedCount++;
            }
          }
        } catch (dirErr) {
          debugPrint('>>> [TempImageCleanup] Note scanning cache dir: $dirErr');
        }
      }

      if (deletedCount > 0) {
        debugPrint('>>> [TempImageCleanup] Purged $deletedCount stale temporary image(s)');
      }
    } catch (e) {
      debugPrint('>>> [TempImageCleanup] Note purging stale picker images: $e');
    }
    return deletedCount;
  }
}

TempImageCleanupHelper createTempImageCleanupHelper() => NativeTempImageCleanupHelper();
