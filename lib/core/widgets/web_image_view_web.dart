import 'dart:ui_web' as ui_web;
import 'package:flutter/widgets.dart';
import 'package:universal_html/html.dart' as html;

Widget buildWebImageView({
  required String imageUrl,
  required double? height,
  required double? width,
  required BoxFit fit,
}) {
  final String viewType = 'web-img-${imageUrl.hashCode}';

  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int viewId) {
      final html.ImageElement element = html.ImageElement()
        ..src = imageUrl
        ..style.height = '100%'
        ..style.width = '100%'
        ..style.objectFit = _getHtmlObjectFit(fit);
      return element;
    },
  );

  return SizedBox(
    height: height,
    width: width,
    child: HtmlElementView(viewType: viewType),
  );
}

String _getHtmlObjectFit(BoxFit fit) {
  switch (fit) {
    case BoxFit.cover:
      return 'cover';
    case BoxFit.contain:
      return 'contain';
    case BoxFit.fill:
      return 'fill';
    default:
      return 'cover';
  }
}
