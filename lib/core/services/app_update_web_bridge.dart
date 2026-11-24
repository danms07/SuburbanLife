import 'app_update_web_bridge_stub.dart';
import 'app_update_web_bridge_stub.dart'
    if (dart.library.js_interop) 'app_update_web_bridge_web.dart' as impl;

export 'app_update_web_bridge_stub.dart' show AppUpdateWebBridge;

AppUpdateWebBridge getAppUpdateWebBridge() => impl.createAppUpdateWebBridge();
