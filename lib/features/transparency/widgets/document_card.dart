import 'package:flutter/material.dart';
import '../../../core/config/app_config.dart';
import '../../../l10n/app_localizations.dart';

class DocumentCard extends StatelessWidget {
  final String id;
  final String title;
  final String fileName;
  final String fileType;
  final int? fileSize;
  final String? category;
  final DateTime? publicationDate;
  final bool isCached;
  final bool isAdmin;
  final VoidCallback onTap;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;

  const DocumentCard({
    Key? key,
    required this.id,
    required this.title,
    required this.fileName,
    required this.fileType,
    this.fileSize,
    this.category,
    this.publicationDate,
    this.isCached = false,
    required this.isAdmin,
    required this.onTap,
    this.onMove,
    this.onDelete,
  }) : super(key: key);

  IconData _getFileIcon() {
    final ext = fileType.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'md':
        return Icons.menu_book;
      case 'txt':
        return Icons.text_snippet;
      case 'doc':
      case 'docx':
        return Icons.article;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
      case 'gif':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor() {
    final ext = fileType.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Colors.red.shade700;
      case 'md':
        return Colors.indigo.shade600;
      case 'txt':
        return Colors.blue.shade700;
      case 'doc':
      case 'docx':
        return Colors.blue.shade900;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Colors.green.shade700;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
      case 'gif':
        return Colors.purple.shade600;
      default:
        return Colors.blueGrey;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime dt) {
    final year = dt.year.toString().padLeft(4, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fileColor = _getFileColor();
    final fileIcon = _getFileIcon();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // File Type Avatar
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: fileColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  fileIcon,
                  color: fileColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),

              // File Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title.isNotEmpty ? title : fileName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppConfig.textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Metadata Chips Row
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Category
                        if (category != null && category!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppConfig.primaryColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AppConfig.primaryColor.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              category!.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppConfig.primaryColor,
                              ),
                            ),
                          ),

                        // Publication Date
                        if (publicationDate != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade600),
                              const SizedBox(width: 3),
                              Text(
                                _formatDate(publicationDate!),
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                              ),
                            ],
                          ),

                        // File Size
                        if (fileSize != null && fileSize! > 0)
                          Text(
                            _formatFileSize(fileSize!),
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),

                        // Cache status
                        if (isCached)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.offline_pin, size: 13, color: Colors.green.shade700),
                              const SizedBox(width: 2),
                              Text(
                                l10n.cachedLocally,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Trailing action menu / open button
              if (isAdmin && (onMove != null || onDelete != null))
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                  onSelected: (value) {
                    if (value == 'move' && onMove != null) {
                      onMove!();
                    } else if (value == 'delete' && onDelete != null) {
                      onDelete!();
                    }
                  },
                  itemBuilder: (context) => [
                    if (onMove != null)
                      PopupMenuItem(
                        value: 'move',
                        child: Row(
                          children: [
                            const Icon(Icons.drive_file_move_outlined, size: 18, color: AppConfig.primaryColor),
                            const SizedBox(width: 8),
                            Text(l10n.moveDocument),
                          ],
                        ),
                      ),
                    if (onDelete != null)
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                            const SizedBox(width: 8),
                            Text(l10n.delete, style: const TextStyle(color: Colors.redAccent)),
                          ],
                        ),
                      ),
                  ],
                )
              else
                Icon(
                  Icons.open_in_new,
                  size: 18,
                  color: Colors.grey.shade400,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
