import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;

@JS('navigator')
external _JsNavigator? get _navigator;

extension type _JsNavigator(JSObject _) implements JSObject {
  external _JsClipboard? get clipboard;
}

extension type _JsClipboard(JSObject _) implements JSObject {
  external JSPromise<JSArray<_JsClipboardItem>> read();
}

extension type _JsClipboardItem(JSObject _) implements JSObject {
  external JSArray<JSString> get types;
  external JSPromise<_JsBlob> getType(JSString type);
}

extension type _JsBlob(JSObject _) implements JSObject {
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

Future<Uint8List?> getWebClipboardImageBytes() async {
  try {
    final clipboard = _navigator?.clipboard;
    if (clipboard != null) {
      final items = (await clipboard.read().toDart).toDart;
      for (final item in items) {
        for (final jsType in item.types.toDart) {
          if (jsType.toDart.startsWith('image/')) {
            final blob = await item.getType(jsType).toDart;
            final buffer = (await blob.arrayBuffer().toDart).toDart;
            return buffer.asUint8List();
          }
        }
      }
    }
  } catch (e) {
    debugPrint('Clipboard read error: $e');
  }
  return null;
}

StreamSubscription? listenToWebPaste(Function(Uint8List bytes) onImagePasted) {
  try {
    return html.document.onPaste.listen((html.ClipboardEvent event) async {
      final items = event.clipboardData?.items;
      if (items != null) {
        final int count = items.length ?? 0;
        for (int i = 0; i < count; i++) {
          final item = items[i];
          if (item.type?.startsWith('image/') == true) {
            final file = item.getAsFile();
            if (file != null) {
              final reader = html.FileReader();
              reader.readAsArrayBuffer(file);
              await reader.onLoadEnd.first;
              final bytes = Uint8List.fromList(reader.result as List<int>);
              onImagePasted(bytes);
              break;
            }
          }
        }
      }
    });
  } catch (e) {
    debugPrint('Web paste listener error: $e');
    return null;
  }
}
