import 'dart:typed_data';

/// Represents metadata and lazy byte reader for a file picked in a Web browser.
class WebSelectedFile {
  final String name;
  final int size;
  final Future<Uint8List> Function() readBytes;

  const WebSelectedFile({
    required this.name,
    required this.size,
    required this.readBytes,
  });
}

/// Strips directory traversal sequences and control characters from a download filename.
String sanitizeWebFileName(String fileName, {String fallback = 'download'}) {
  final normalized = fileName.replaceAll('\\', '/');
  final segments = normalized
      .split('/')
      .where((segment) => segment.isNotEmpty && segment != '.' && segment != '..')
      .toList();
  if (segments.isEmpty) {
    return fallback;
  }
  final baseName = segments.last.replaceAll(RegExp(r'[\r\n\x00-\x1F]'), '').trim();
  return baseName.isEmpty ? fallback : baseName;
}

Future<WebSelectedFile?> pickWebFile({required String accept}) async => null;

void downloadWebBytes({
  required Uint8List bytes,
  required String fileName,
  String mimeType = 'application/octet-stream',
  String? rel,
  String? target,
}) {}

void openWebUrlInNewTab(String url) {}
