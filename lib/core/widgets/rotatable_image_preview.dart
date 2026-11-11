import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import 'interactive_image_dialog.dart';
import 'storage_network_image.dart';

/// Reusable evidence/proof image preview container with inline 90-degree
/// clockwise rotation (`Icons.rotate_right`) and full-screen interactive
/// viewer launch (`Icons.open_in_full`) controls anchored at the top-right.
///
/// Tapping either the image surface or the full-screen icon opens
/// [showInteractiveImageDialog] while preserving the current inline orientation.
class RotatableImagePreview extends StatefulWidget {
  final String imageUrl;
  final String? dialogTitle;
  final double? height;
  final double? width;
  final BoxFit fit;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Key? thumbnailKey;
  final Key? rotatedBoxKey;
  final Key? rotateButtonKey;
  final Key? fullscreenButtonKey;

  const RotatableImagePreview({
    super.key,
    required this.imageUrl,
    this.dialogTitle,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = 14,
    this.thumbnailKey,
    this.rotatedBoxKey,
    this.rotateButtonKey,
    this.fullscreenButtonKey,
  });

  @override
  State<RotatableImagePreview> createState() => _RotatableImagePreviewState();
}

class _RotatableImagePreviewState extends State<RotatableImagePreview> {
  int _quarterTurns = 0;

  @override
  void didUpdateWidget(covariant RotatableImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _quarterTurns = 0;
    }
  }

  void _rotateInline() {
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
    });
  }

  void _openFullscreen() {
    showInteractiveImageDialog(
      context,
      widget.imageUrl,
      title: widget.dialogTitle,
      initialQuarterTurns: _quarterTurns,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context)!;
    final innerRadius = (widget.borderRadius - 1).clamp(0.0, double.infinity);

    return Container(
      width: widget.width ?? (widget.height != null ? double.infinity : null),
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(innerRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: widget.padding,
              child: IgnorePointer(
                child: RotatedBox(
                  key: widget.rotatedBoxKey,
                  quarterTurns: _quarterTurns,
                  child: StorageNetworkImage(
                    imageUrl: widget.imageUrl,
                    fit: widget.fit,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: widget.thumbnailKey,
                  onTap: _openFullscreen,
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      key: widget.rotateButtonKey,
                      tooltip: l10n.rotateImage,
                      icon: const Icon(
                        Icons.rotate_right,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: _rotateInline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      key: widget.fullscreenButtonKey,
                      tooltip: l10n.viewFullImage,
                      icon: const Icon(
                        Icons.open_in_full,
                        color: Colors.white,
                        size: 18,
                      ),
                      onPressed: _openFullscreen,
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
