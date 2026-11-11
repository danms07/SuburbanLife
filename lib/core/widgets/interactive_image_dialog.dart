import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import 'storage_network_image.dart';

/// Displays a full-screen interactive image viewer with 20% padding,
/// pinch-to-zoom, pan support, and 90-degree rotation controls.
void showInteractiveImageDialog(
  BuildContext context,
  String imageUrl, {
  String? title,
  int initialQuarterTurns = 0,
}) {
  showDialog(
    context: context,
    useSafeArea: false,
    builder: (context) => _InteractiveImageDialog(
      imageUrl: imageUrl,
      title: title,
      initialQuarterTurns: initialQuarterTurns,
    ),
  );
}

class _InteractiveImageDialog extends StatefulWidget {
  final String imageUrl;
  final String? title;
  final int initialQuarterTurns;

  const _InteractiveImageDialog({
    required this.imageUrl,
    this.title,
    this.initialQuarterTurns = 0,
  });

  @override
  State<_InteractiveImageDialog> createState() =>
      _InteractiveImageDialogState();
}

class _InteractiveImageDialogState extends State<_InteractiveImageDialog> {
  late int _quarterTurns;
  final TransformationController _transformationController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    _quarterTurns = widget.initialQuarterTurns % 4;
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _rotateImage() {
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
      _transformationController.value = Matrix4.identity();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;

    return Dialog(
      backgroundColor: Colors.black.withValues(alpha: 0.85),
      insetPadding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(),
      child: SizedBox(
        width: screenSize.width,
        height: screenSize.height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _transformationController,
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                minScale: 0.5,
                maxScale: 4.0,
                child: Padding(
                  key: const ValueKey('interactive_image_padding'),
                  padding: EdgeInsets.symmetric(
                    horizontal: screenSize.width * 0.2,
                    vertical: screenSize.height * 0.2,
                  ),
                  child: SizedBox.expand(
                    child: RotatedBox(
                      key: const ValueKey('interactive_image_rotated_box'),
                      quarterTurns: _quarterTurns,
                      child: StorageNetworkImage(
                        imageUrl: widget.imageUrl,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.title != null && widget.title!.isNotEmpty)
              Positioned(
                top: topInset + 16,
                left: 16,
                right: 120,
                child: Text(
                  widget.title!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Positioned(
              top: topInset + 16,
              right: 16,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.black.withValues(alpha: 0.6),
                    child: IconButton(
                      key: const ValueKey('rotate_image_button'),
                      tooltip: l10n?.rotateImage ?? 'Rotate Image',
                      icon: const Icon(Icons.rotate_right, color: Colors.white),
                      onPressed: _rotateImage,
                    ),
                  ),
                  const SizedBox(width: 12),
                  CircleAvatar(
                    backgroundColor: Colors.black.withValues(alpha: 0.6),
                    child: IconButton(
                      key: const ValueKey('close_image_button'),
                      tooltip: l10n?.close ?? 'Close',
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
