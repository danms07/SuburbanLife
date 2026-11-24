import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Registers a service-worker `message` listener for same-origin notification clicks.
void attachServiceWorkerNotificationListener(
  void Function(String? targetRoute) onNotificationClick,
) {
  try {
    web.window.navigator.serviceWorker.addEventListener(
      'message',
      (web.MessageEvent event) {
        final origin = event.origin;
        if (origin.isNotEmpty && origin != web.window.location.origin) {
          return;
        }
        final data = event.data.dartify();
        if (data is Map && data['type'] == 'NOTIFICATION_CLICK') {
          onNotificationClick(data['targetRoute']?.toString());
        }
      }.toJS,
    );
  } catch (e) {
    debugPrint('ServiceWorker message listener unavailable: $e');
  }
}

/// Replaces the current browser history URL without reloading the page.
void replaceBrowserHistoryUrl(String url) {
  try {
    web.window.history.replaceState(null, '', url);
  } catch (e) {
    debugPrint('Failed to inspect Web initial notificationRoute: $e');
  }
}
