import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:universal_html/html.dart' as html;
import 'dart:ui_web' as ui_web;

class StorageNetworkImage extends StatefulWidget {
  final String imageUrl;
  final double? height;
  final double? width;
  final BoxFit fit;

  const StorageNetworkImage({
    super.key,
    required this.imageUrl,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
  });

  @override
  State<StorageNetworkImage> createState() => _StorageNetworkImageState();
}

class _StorageNetworkImageState extends State<StorageNetworkImage> {
  Future<Uint8List?>? _fetchFuture;

  @override
  void initState() {
    super.initState();
    _initFetch();
  }

  @override
  void didUpdateWidget(covariant StorageNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _initFetch();
    }
  }

  void _initFetch() {
    if (widget.imageUrl.startsWith('gs://') || 
        widget.imageUrl.contains('firebasestorage.googleapis.com')) {
      _fetchFuture = _downloadBytes(widget.imageUrl);
    } else {
      _fetchFuture = null;
    }
  }

  Future<Uint8List?> _downloadBytes(String url) async {
    try {
      final Reference ref = FirebaseStorage.instance.refFromURL(url);
      // Limit maximum size to 5MB to protect device memory limits
      return await ref.getData(5 * 1024 * 1024);
    } catch (e) {
      debugPrint('Error resolving storage reference bytes: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_fetchFuture == null) {
      if (kIsWeb) {
        return _buildWebFallback();
      }
      return Image.network(
        widget.imageUrl,
        height: widget.height,
        width: widget.width,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) => _buildErrorWidget(),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _fetchFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: widget.height,
            width: widget.width,
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          if (kIsWeb) {
            // Bypasses Web CORS errors instantly using a native HTML <img> element
            return _buildWebFallback();
          }
          // Fallback to standard Image.network if native bytes download fails
          return Image.network(
            widget.imageUrl,
            height: widget.height,
            width: widget.width,
            fit: widget.fit,
            errorBuilder: (context, error, stackTrace) => _buildErrorWidget(),
          );
        }

        return Image.memory(
          snapshot.data!,
          height: widget.height,
          width: widget.width,
          fit: widget.fit,
        );
      },
    );
  }

  Widget _buildWebFallback() {
    final String viewType = 'web-img-${widget.imageUrl.hashCode}';

    // Register view factory
    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (int viewId) {
        final html.ImageElement element = html.ImageElement()
          ..src = widget.imageUrl
          ..style.height = '100%'
          ..style.width = '100%'
          ..style.objectFit = _getHtmlObjectFit(widget.fit);
        return element;
      },
    );

    return SizedBox(
      height: widget.height,
      width: widget.width,
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

  Widget _buildErrorWidget() {
    return Container(
      height: widget.height,
      width: widget.width,
      color: Colors.grey[200],
      child: const Center(
        child: Icon(Icons.broken_image, color: Colors.grey, size: 40),
      ),
    );
  }
}
