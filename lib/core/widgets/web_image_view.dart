import 'package:flutter/widgets.dart';
import 'web_image_view_stub.dart'
    if (dart.library.html) 'web_image_view_web.dart'
    if (dart.library.js_interop) 'web_image_view_web.dart' as impl;

Widget buildWebImageView({
  required String imageUrl,
  required double? height,
  required double? width,
  required BoxFit fit,
}) =>
    impl.buildWebImageView(
      imageUrl: imageUrl,
      height: height,
      width: width,
      fit: fit,
    );
