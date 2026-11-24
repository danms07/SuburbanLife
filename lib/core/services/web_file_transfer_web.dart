import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'web_file_transfer_stub.dart';

/// Prompts the user to select a single file via a browser `<input type="file">` element.
Future<WebSelectedFile?> pickWebFile({required String accept}) {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept;
  final completer = Completer<WebSelectedFile?>();

  late final JSFunction onChangeJs;
  late final JSFunction onCancelJs;

  void cleanup() {
    input.removeEventListener('change', onChangeJs);
    input.removeEventListener('cancel', onCancelJs);
  }

  onChangeJs = (web.Event _) {
    if (completer.isCompleted) return;
    cleanup();
    final files = input.files;
    if (files == null || files.length == 0) {
      completer.complete(null);
      return;
    }
    final file = files.item(0);
    if (file == null) {
      completer.complete(null);
      return;
    }
    completer.complete(
      WebSelectedFile(
        name: file.name,
        size: file.size,
        readBytes: () async {
          final buffer = (await file.arrayBuffer().toDart).toDart;
          return buffer.asUint8List();
        },
      ),
    );
  }.toJS;

  onCancelJs = (web.Event _) {
    if (completer.isCompleted) return;
    cleanup();
    completer.complete(null);
  }.toJS;

  input.addEventListener('change', onChangeJs);
  input.addEventListener('cancel', onCancelJs);
  input.click();
  return completer.future;
}

/// Triggers a browser download from raw [bytes] via a temporary Blob URL.
void downloadWebBytes({
  required Uint8List bytes,
  required String fileName,
  String mimeType = 'application/octet-stream',
  String? rel,
  String? target,
}) {
  final safeName = sanitizeWebFileName(fileName);
  final blobParts = <JSAny>[bytes.toJS].toJS;
  final blob = web.Blob(blobParts, web.BlobPropertyBag(type: mimeType));
  final blobUrl = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = blobUrl
    ..download = safeName;
  if (rel != null && rel.isNotEmpty) {
    anchor.rel = rel;
  }
  if (target != null && target.isNotEmpty) {
    anchor.target = target;
  }
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(blobUrl);
}

/// Opens an `http`/`https` [url] in a new browser tab with `noopener,noreferrer`.
void openWebUrlInNewTab(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    debugPrint('>>> [WebFileTransferHelper] Blocked non-HTTP(S) URL for new tab');
    return;
  }
  web.window.open(url, '_blank', 'noopener,noreferrer');
}
