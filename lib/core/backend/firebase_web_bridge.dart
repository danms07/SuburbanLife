import 'firebase_web_bridge_stub.dart'
    if (dart.library.js_interop) 'firebase_web_bridge_web.dart' as impl;

/// Attaches a same-origin Web Service Worker notification click listener.
void attachServiceWorkerNotificationListener(
  void Function(String? targetRoute) onNotificationClick,
) =>
    impl.attachServiceWorkerNotificationListener(onNotificationClick);

/// Replaces the current browser history URL when running on Web.
void replaceBrowserHistoryUrl(String url) => impl.replaceBrowserHistoryUrl(url);
