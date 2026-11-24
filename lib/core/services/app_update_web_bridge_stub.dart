/// Platform abstraction for Web browser listeners, CacheStorage purge, and reload.
abstract class AppUpdateWebBridge {
  bool get isDocumentHidden;
  void attachInteractionListeners(void Function() onInteraction);
  void attachVisibilityListener(void Function(bool isHidden) onVisibilityChange);
  Future<void> purgeCachesUpdateSwAndReload();
  void dispose();
}

class _StubAppUpdateWebBridge implements AppUpdateWebBridge {
  @override
  bool get isDocumentHidden => false;

  @override
  void attachInteractionListeners(void Function() onInteraction) {}

  @override
  void attachVisibilityListener(void Function(bool isHidden) onVisibilityChange) {}

  @override
  Future<void> purgeCachesUpdateSwAndReload() async {}

  @override
  void dispose() {}
}

AppUpdateWebBridge createAppUpdateWebBridge() => _StubAppUpdateWebBridge();
