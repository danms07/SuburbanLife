import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suburban_life/core/services/app_update_service.dart';
import 'package:suburban_life/core/services/cache_io_helper.dart';
import 'package:suburban_life/core/services/document_cache_service.dart';

class _InMemoryCacheIoHelper implements CacheIoHelper {
  final Map<String, Uint8List> store = {};

  @override
  Future<bool> isCached(String key) async => store.containsKey(key);

  @override
  Future<Uint8List?> getCachedBytes(String key) async => store[key];

  @override
  Future<void> saveCachedBytes(String key, Uint8List bytes) async {
    store[key] = bytes;
  }

  @override
  Future<String?> getCachedFilePath(String key) async =>
      store.containsKey(key) ? '/virtual_cache/$key' : null;

  @override
  Future<void> removeCachedFile(String key) async {
    store.remove(key);
  }

  @override
  Future<void> clearAllCache() async {
    store.clear();
  }

  @override
  Future<Uint8List?> readFileBytesFromDisk(String filePath) async {
    final key = filePath.split('/').last;
    return store[key];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppUpdateService', () {
    final service = AppUpdateService.instance;

    setUp(() {
      service.resetForTesting();
    });

    tearDown(() {
      service.dispose();
      service.resetForTesting();
    });

    test('parseVersionPayload parses valid version JSON and rejects malformed payloads', () {
      expect(
        AppUpdateService.parseVersionPayload('{"version":"1.0.20","build_number":"21"}'),
        equals('1.0.20+21'),
      );
      expect(
        AppUpdateService.parseVersionPayload('{}'),
        equals('1.0.0+1'),
      );
      expect(AppUpdateService.parseVersionPayload('not-json'), isNull);
      expect(AppUpdateService.parseVersionPayload('["array_not_map"]'), isNull);
    });

    test('initialize is a safe no-op when web mode is inactive', () async {
      int fetchCount = 0;
      service.configureForTesting(
        webModeOverride: false,
        remoteVersionFetcher: () async {
          fetchCount++;
          return '1.0.0+1';
        },
      );

      await service.initialize();
      expect(fetchCount, equals(0));
      expect(service.currentVersion, isNull);
    });

    test('queues update while user is active, then reloads on idle or background lifecycle transition', () async {
      String remoteVersion = '1.0.20+21';
      int reloadCalls = 0;
      final baseTime = DateTime(2026, 10, 28, 12, 0, 0);
      DateTime currentNow = baseTime;

      service.configureForTesting(
        webModeOverride: true,
        remoteVersionFetcher: () async => remoteVersion,
        onReload: () async {
          reloadCalls++;
        },
        isTabHidden: () => false,
        nowProvider: () => currentNow,
        lastInteractionTime: baseTime,
      );

      await service.initialize();
      expect(service.currentVersion, equals('1.0.20+21'));
      expect(service.isUpdatePending, isFalse);

      // Same remote version -> no pending update, no reload
      await service.checkForUpdates();
      expect(service.isUpdatePending, isFalse);
      expect(reloadCalls, equals(0));

      // Newer remote version deployed while user interacted 10s ago (< 45s threshold)
      remoteVersion = '1.0.21+22';
      currentNow = baseTime.add(const Duration(seconds: 10));
      await service.checkForUpdates();

      expect(service.isUpdatePending, isTrue);
      expect(reloadCalls, equals(0));

      // Once user goes idle or app pauses, reload executes exactly once
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(reloadCalls, equals(1));
      expect(service.isReloading, isTrue);

      // Subsequent triggers do not double-reload
      service.triggerUserIdleForTesting();
      expect(reloadCalls, equals(1));
    });

    test('reloads immediately when new version is detected while tab is hidden or user is idle', () async {
      String remoteVersion = '1.0.20+21';
      int reloadCalls = 0;
      final baseTime = DateTime(2026, 10, 28, 12, 0, 0);

      service.configureForTesting(
        webModeOverride: true,
        remoteVersionFetcher: () async => remoteVersion,
        onReload: () async {
          reloadCalls++;
        },
        isTabHidden: () => true,
        nowProvider: () => baseTime,
        lastInteractionTime: baseTime,
      );

      await service.initialize();
      remoteVersion = '1.0.22+23';

      // Resuming lifecycle triggers checkForUpdates -> tab hidden -> immediate reload
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      expect(service.isUpdatePending, isTrue);
      expect(reloadCalls, equals(1));
    });
  });

  group('DocumentCacheService', () {
    late _InMemoryCacheIoHelper memoryCache;
    final cacheService = DocumentCacheService();

    setUp(() {
      memoryCache = _InMemoryCacheIoHelper();
    });

    test('buildCacheKey sanitizes path traversal sequences and special characters', () {
      final key = DocumentCacheService.buildCacheKey(
        '../../etc/passwd',
        '..\\..\\secret/report 2026?.pdf',
      );
      expect(key.contains('/'), isFalse);
      expect(key.contains(r'\'), isFalse);
      expect(key, equals('______etc_passwd_.._.._secret_report_2026_.pdf'));
    });

    test('downloads on cache miss, serves from local cache on hit without network call, and evicts cleanly', () async {
      int networkHits = 0;
      final payload = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]);

      final mockClient = MockClient((request) async {
        networkHits++;
        return http.Response.bytes(payload, 200);
      });

      cacheService.configureForTesting(
        helper: memoryCache,
        httpClient: mockClient,
      );

      expect(await cacheService.isCached('doc_1', 'budget.pdf'), isFalse);

      // 1. Cache MISS -> downloads via HTTP and stores in cache
      final firstRead = await cacheService.getOrDownloadBytes(
        'doc_1',
        'https://127.0.0.1/docs/budget.pdf',
        'budget.pdf',
      );
      expect(firstRead, equals(payload));
      expect(networkHits, equals(1));
      expect(await cacheService.isCached('doc_1', 'budget.pdf'), isTrue);

      // 2. Cache HIT -> returns cached bytes without hitting network again
      final secondRead = await cacheService.getOrDownloadBytes(
        'doc_1',
        'https://127.0.0.1/docs/budget.pdf',
        'budget.pdf',
      );
      expect(secondRead, equals(payload));
      expect(networkHits, equals(1));

      // 3. File path lookup and eviction
      final path = await cacheService.getOrDownloadFilePath(
        'doc_1',
        'https://127.0.0.1/docs/budget.pdf',
        'budget.pdf',
      );
      expect(path, equals('/virtual_cache/doc_1_budget.pdf'));

      await cacheService.removeCachedFile('doc_1', 'budget.pdf');
      expect(await cacheService.isCached('doc_1', 'budget.pdf'), isFalse);
    });

    test('throws on non-200 HTTP response and does not poison local cache with error body', () async {
      final mockClient = MockClient((_) async {
        return http.Response('Forbidden', 403);
      });

      cacheService.configureForTesting(
        helper: memoryCache,
        httpClient: mockClient,
      );

      await expectLater(
        () => cacheService.getOrDownloadBytes(
          'doc_403',
          'https://127.0.0.1/docs/private.pdf',
          'private.pdf',
        ),
        throwsException,
      );
      expect(await cacheService.isCached('doc_403', 'private.pdf'), isFalse);
    });
  });
}
