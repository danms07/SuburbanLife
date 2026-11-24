import 'dart:typed_data';

import 'web_file_transfer_stub.dart';
import 'web_file_transfer_stub.dart'
    if (dart.library.js_interop) 'web_file_transfer_web.dart' as impl;

export 'web_file_transfer_stub.dart' show WebSelectedFile, sanitizeWebFileName;

/// Cross-platform bridge for browser file picking, Blob downloads, and new-tab opening.
class WebFileTransferHelper {
  const WebFileTransferHelper._();

  /// Opens a browser file picker filtered by [accept] and returns file metadata + lazy reader.
  static Future<WebSelectedFile?> pickFile({required String accept}) =>
      impl.pickWebFile(accept: accept);

  /// Downloads [bytes] as [fileName] on Web using a Blob and temporary AnchorElement.
  static void downloadBytes({
    required Uint8List bytes,
    required String fileName,
    String mimeType = 'application/octet-stream',
    String? rel,
    String? target,
  }) =>
      impl.downloadWebBytes(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        rel: rel,
        target: target,
      );

  /// Opens an `http`/`https` [url] in a new browser tab with `noopener,noreferrer`.
  static void openInNewTab(String url) => impl.openWebUrlInNewTab(url);
}
