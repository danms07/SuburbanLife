import 'dart:async';
import 'dart:js_util' as js_util;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;

Future<Uint8List?> getWebClipboardImageBytes() async {
  try {
    final nav = html.window.navigator;
    final clipboard = js_util.getProperty(nav, 'clipboard');
    if (clipboard != null) {
      final promise = js_util.callMethod(clipboard, 'read', []);
      final dynamic items = await js_util.promiseToFuture(promise);
      final dynamic rawLen = js_util.getProperty(items, 'length');
      final int length = (rawLen is num) ? rawLen.toInt() : 0;
      for (int i = 0; i < length; i++) {
        final item = js_util.callMethod(items, 'item', [i]) ?? js_util.getProperty(items, i.toString());
        final dynamic types = js_util.getProperty(item, 'types');
        final dynamic rawTypesLen = js_util.getProperty(types, 'length');
        final int typesLength = (rawTypesLen is num) ? rawTypesLen.toInt() : 0;
        for (int j = 0; j < typesLength; j++) {
          final String type = (js_util.callMethod(types, 'item', [j]) ?? js_util.getProperty(types, j.toString())).toString();
          if (type.startsWith('image/')) {
            final dynamic blobPromise = js_util.callMethod(item, 'getType', [type]);
            final html.Blob blob = await js_util.promiseToFuture(blobPromise);
            final reader = html.FileReader();
            reader.readAsArrayBuffer(blob);
            await reader.onLoadEnd.first;
            return Uint8List.fromList(reader.result as List<int>);
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
