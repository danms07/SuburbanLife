import 'dart:async';
import 'dart:typed_data';
import 'clipboard_image_helper_stub.dart'
    if (dart.library.html) 'clipboard_image_helper_web.dart'
    if (dart.library.js_interop) 'clipboard_image_helper_web.dart' as impl;

Future<Uint8List?> getWebClipboardImageBytes() => impl.getWebClipboardImageBytes();

StreamSubscription? listenToWebPaste(Function(Uint8List bytes) onImagePasted) =>
    impl.listenToWebPaste(onImagePasted);
