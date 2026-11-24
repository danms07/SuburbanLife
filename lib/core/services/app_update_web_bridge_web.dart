import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'app_update_web_bridge_stub.dart';

class _ListenerRecord {
  final web.EventTarget target;
  final String type;
  final JSFunction listener;

  const _ListenerRecord(this.target, this.type, this.listener);
}

/// Browser implementation of [AppUpdateWebBridge] using `package:web`.
class BrowserAppUpdateWebBridge implements AppUpdateWebBridge {
  final List<_ListenerRecord> _interactionListeners = [];
  _ListenerRecord? _visibilityListener;

  @override
  bool get isDocumentHidden => web.document.hidden;

  @override
  void attachInteractionListeners(void Function() onInteraction) {
    _clearInteractionListeners();
    try {
      const eventTypes = ['mousemove', 'keydown', 'touchstart', 'click'];
      for (final type in eventTypes) {
        final jsListener = (web.Event _) {
          onInteraction();
        }.toJS;
        web.window.addEventListener(type, jsListener);
        _interactionListeners.add(_ListenerRecord(web.window, type, jsListener));
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Failed to attach interaction listeners: $e');
    }
  }

  @override
  void attachVisibilityListener(void Function(bool isHidden) onVisibilityChange) {
    _clearVisibilityListener();
    try {
      final jsListener = (web.Event _) {
        onVisibilityChange(web.document.hidden);
      }.toJS;
      web.document.addEventListener('visibilitychange', jsListener);
      _visibilityListener =
          _ListenerRecord(web.document, 'visibilitychange', jsListener);
    } catch (e) {
      debugPrint('[AppUpdateService] Failed to attach visibility listener: $e');
    }
  }

  @override
  Future<void> purgeCachesUpdateSwAndReload() async {
    try {
      final caches = web.window.caches;
      final keys = (await caches.keys().toDart).toDart;
      for (final key in keys) {
        await caches.delete(key.toDart).toDart;
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Cache purging error: $e');
    }

    try {
      final sw = web.window.navigator.serviceWorker;
      final reg = await sw.getRegistration().toDart;
      if (reg != null) {
        await reg.update().toDart;
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Service worker update error: $e');
    }

    try {
      web.window.location.reload();
    } catch (e) {
      debugPrint('[AppUpdateService] Window reload error: $e');
    }
  }

  @override
  void dispose() {
    _clearInteractionListeners();
    _clearVisibilityListener();
  }

  void _clearInteractionListeners() {
    for (final record in _interactionListeners) {
      record.target.removeEventListener(record.type, record.listener);
    }
    _interactionListeners.clear();
  }

  void _clearVisibilityListener() {
    final existing = _visibilityListener;
    if (existing != null) {
      existing.target.removeEventListener(existing.type, existing.listener);
      _visibilityListener = null;
    }
  }
}

AppUpdateWebBridge createAppUpdateWebBridge() => BrowserAppUpdateWebBridge();
