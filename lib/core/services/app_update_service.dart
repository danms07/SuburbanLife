import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:universal_html/html.dart' as html;

/// Service responsible for automatically detecting new deployments on Flutter Web
/// and seamlessly reloading the application when the user is idle or in the background.
class AppUpdateService with WidgetsBindingObserver {
  AppUpdateService._internal();

  static final AppUpdateService instance = AppUpdateService._internal();

  String? _currentVersion;
  Timer? _pollTimer;
  Timer? _idleTimer;
  bool _isUpdatePending = false;
  bool _isReloading = false;
  DateTime _lastInteractionTime = DateTime.now();

  bool? _webModeOverride;
  Future<String?> Function()? _remoteVersionFetcherOverride;
  Future<void> Function()? _onReloadOverride;
  bool Function()? _isTabHiddenOverride;
  DateTime Function()? _nowOverride;

  static const Duration _pollInterval = Duration(minutes: 15);
  static const Duration _idleThreshold = Duration(seconds: 45);

  bool get _isWebActive => _webModeOverride ?? kIsWeb;
  DateTime _now() => _nowOverride != null ? _nowOverride!() : DateTime.now();

  /// Parses raw `/version.json` text into a `version+build_number` string.
  static String? parseVersionPayload(String rawJson) {
    try {
      final dynamic decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) return null;
      final version = decoded['version']?.toString() ?? '1.0.0';
      final buildNumber = decoded['build_number']?.toString() ?? '1';
      return '$version+$buildNumber';
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  String? get currentVersion => _currentVersion;

  @visibleForTesting
  bool get isUpdatePending => _isUpdatePending;

  @visibleForTesting
  bool get isReloading => _isReloading;

  @visibleForTesting
  void configureForTesting({
    bool? webModeOverride,
    Future<String?> Function()? remoteVersionFetcher,
    Future<void> Function()? onReload,
    bool Function()? isTabHidden,
    DateTime Function()? nowProvider,
    DateTime? lastInteractionTime,
  }) {
    _webModeOverride = webModeOverride;
    _remoteVersionFetcherOverride = remoteVersionFetcher;
    _onReloadOverride = onReload;
    _isTabHiddenOverride = isTabHidden;
    _nowOverride = nowProvider;
    if (lastInteractionTime != null) {
      _lastInteractionTime = lastInteractionTime;
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    _currentVersion = null;
    _isUpdatePending = false;
    _isReloading = false;
    _webModeOverride = null;
    _remoteVersionFetcherOverride = null;
    _onReloadOverride = null;
    _isTabHiddenOverride = null;
    _nowOverride = null;
    _lastInteractionTime = DateTime.now();
  }

  @visibleForTesting
  void triggerUserIdleForTesting() => _onUserIdle();

  /// Initializes the update service for web platforms.
  Future<void> initialize() async {
    if (!_isWebActive) return;

    WidgetsBinding.instance.addObserver(this);

    // Establish baseline version
    await _fetchInitialVersion();

    // Start periodic background polling
    _startPeriodicPolling();

    // Listen to user interactions to track idle state
    _setupInteractionListeners();

    // Listen to browser tab visibility changes
    _setupVisibilityListener();
  }

  /// Fetches the initial version at app startup.
  Future<void> _fetchInitialVersion() async {
    try {
      final remote = await _fetchRemoteVersionData();
      if (remote != null) {
        _currentVersion = remote;
        debugPrint('[AppUpdateService] Initial version initialized: $_currentVersion');
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Failed to fetch initial version: $e');
    }
  }

  /// Sets up event listeners for user input (mouse, touch, keyboard) to track activity.
  void _setupInteractionListeners() {
    void onInteraction([html.Event? event]) {
      _lastInteractionTime = _now();
      _idleTimer?.cancel();
      _idleTimer = Timer(_idleThreshold, _onUserIdle);
    }

    if (kIsWeb) {
      try {
        html.window.onMouseMove.listen(onInteraction);
        html.window.onKeyDown.listen(onInteraction);
        html.window.onTouchStart.listen(onInteraction);
        html.window.onClick.listen(onInteraction);
      } catch (e) {
        debugPrint('[AppUpdateService] Failed to attach interaction listeners: $e');
      }
    }

    _idleTimer = Timer(_idleThreshold, _onUserIdle);
  }

  /// Triggered when no user interaction occurred within the idle threshold.
  void _onUserIdle() {
    if (_isUpdatePending && !_isReloading) {
      debugPrint('[AppUpdateService] User is idle with pending update. Triggering reload.');
      reloadApp();
    }
  }

  /// Listens to document visibility changes (e.g. user switching tabs).
  void _setupVisibilityListener() {
    if (!kIsWeb) return;
    try {
      html.document.onVisibilityChange.listen((_) {
        final isHidden = _isTabHiddenOverride != null
            ? _isTabHiddenOverride!()
            : (html.document.hidden == true);
        if (isHidden && _isUpdatePending && !_isReloading) {
          debugPrint('[AppUpdateService] Tab hidden with pending update. Triggering reload.');
          reloadApp();
        } else if (!isHidden) {
          // Tab became visible again; check if a newer version was deployed while away
          checkForUpdates();
        }
      });
    } catch (e) {
      debugPrint('[AppUpdateService] Failed to attach visibility listener: $e');
    }
  }

  /// Starts periodic polling timer.
  void _startPeriodicPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      checkForUpdates();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isWebActive) return;

    if (state == AppLifecycleState.resumed) {
      checkForUpdates();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      if (_isUpdatePending && !_isReloading) {
        debugPrint('[AppUpdateService] Lifecycle state ($state) with pending update. Triggering reload.');
        reloadApp();
      }
    }
  }

  /// Fetches `/version.json` from the server with cache-busting query parameter.
  Future<String?> _fetchRemoteVersionData() async {
    if (_remoteVersionFetcherOverride != null) {
      return await _remoteVersionFetcherOverride!();
    }
    try {
      final timestamp = _now().millisecondsSinceEpoch;
      final response = await html.HttpRequest.getString('/version.json?t=$timestamp');
      return parseVersionPayload(response);
    } catch (e) {
      return null;
    }
  }

  /// Manually or periodically checks if a newer version is available.
  Future<void> checkForUpdates() async {
    if (!_isWebActive || _isReloading) return;

    try {
      final remoteVersion = await _fetchRemoteVersionData();
      if (remoteVersion == null) return;

      if (_currentVersion == null) {
        _currentVersion = remoteVersion;
        return;
      }

      if (remoteVersion != _currentVersion) {
        debugPrint('[AppUpdateService] New version detected ($remoteVersion != $_currentVersion).');
        _isUpdatePending = true;

        final isHidden = _isTabHiddenOverride != null
            ? _isTabHiddenOverride!()
            : (kIsWeb && html.document.hidden == true);
        final isIdle = _now().difference(_lastInteractionTime) > _idleThreshold;

        if (isHidden || isIdle) {
          debugPrint('[AppUpdateService] Immediately reloading as tab is hidden or idle.');
          await reloadApp();
        } else {
          debugPrint('[AppUpdateService] Update queued until next idle or tab switch.');
        }
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Update check failed: $e');
    }
  }

  /// Purges browser cache storage and hard reloads the application.
  Future<void> reloadApp() async {
    if (!_isWebActive || _isReloading) return;
    _isReloading = true;

    if (_onReloadOverride != null) {
      await _onReloadOverride!();
      return;
    }

    try {
      // 1. Purge CacheStorage entries
      final caches = html.window.caches;
      if (caches != null) {
        final keys = await caches.keys();
        for (final key in keys) {
          await caches.delete(key);
        }
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Cache purging error: $e');
    }

    try {
      // 2. Trigger Service Worker update
      final sw = html.window.navigator.serviceWorker;
      if (sw != null) {
        final reg = await sw.getRegistration();
        await reg.update();
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Service worker update error: $e');
    }

    try {
      // 3. Hard reload window
      html.window.location.reload();
    } catch (e) {
      debugPrint('[AppUpdateService] Window reload error: $e');
    }
  }

  /// Disposes timers and observers when teardown is needed.
  void dispose() {
    if (_isWebActive) {
      WidgetsBinding.instance.removeObserver(this);
      _pollTimer?.cancel();
      _idleTimer?.cancel();
    }
  }
}
