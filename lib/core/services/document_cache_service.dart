import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'cache_io_helper.dart';

/// Service that handles downloading, caching, and local retrieval of transparency documents.
/// On native platforms (iOS, Android, macOS, Linux, Windows), documents are persisted
/// to disk so subsequent accesses do not consume network bandwidth.
/// On Web, an in-memory byte cache is maintained.
class DocumentCacheService {
  static final DocumentCacheService _instance = DocumentCacheService._internal();
  factory DocumentCacheService() => _instance;
  DocumentCacheService._internal();

  final CacheIoHelper _helper = getCacheIoHelper();

  /// Generates a sanitized cache key / filename
  String _getCacheKey(String docId, String fileName) {
    final sanitizedName = fileName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
    return '${docId}_$sanitizedName';
  }

  /// Checks whether a document is already cached locally on disk or in memory
  Future<bool> isCached(String docId, String fileName) async {
    final key = _getCacheKey(docId, fileName);
    return await _helper.isCached(key);
  }

  /// Gets the cached local file path if available (native only), or null on Web.
  Future<String?> getCachedFilePath(String docId, String fileName) async {
    final key = _getCacheKey(docId, fileName);
    return await _helper.getCachedFilePath(key);
  }

  /// Gets the document bytes, either from local disk / memory cache, or by downloading over HTTP.
  Future<Uint8List> getOrDownloadBytes(
    String docId,
    String url,
    String fileName, {
    void Function(double progress)? onProgress,
  }) async {
    final key = _getCacheKey(docId, fileName);

    // 1. Check local cache
    final cachedBytes = await _helper.getCachedBytes(key);
    if (cachedBytes != null && cachedBytes.isNotEmpty) {
      return cachedBytes;
    }

    // 2. Download from network
    debugPrint('Downloading document from URL: $url');
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to download document: HTTP ${response.statusCode}');
    }

    final bytes = response.bodyBytes;

    // 3. Save to local cache
    await _helper.saveCachedBytes(key, bytes);

    return bytes;
  }

  /// Retrieves or downloads the document and returns its local file path (native only).
  /// On Web, returns null after caching bytes.
  Future<String?> getOrDownloadFilePath(
    String docId,
    String url,
    String fileName,
  ) async {
    final key = _getCacheKey(docId, fileName);

    final existingPath = await _helper.getCachedFilePath(key);
    if (existingPath != null) {
      return existingPath;
    }

    final bytes = await getOrDownloadBytes(docId, url, fileName);
    await _helper.saveCachedBytes(key, bytes);

    return await _helper.getCachedFilePath(key);
  }

  /// Removes a document from local cache.
  Future<void> removeCachedFile(String docId, String fileName) async {
    final key = _getCacheKey(docId, fileName);
    await _helper.removeCachedFile(key);
  }

  /// Clears the entire local cache.
  Future<void> clearAllCache() async {
    await _helper.clearAllCache();
  }
}
