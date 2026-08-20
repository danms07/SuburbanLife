import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/config/app_config.dart';
import '../../core/services/document_cache_service.dart';
import '../../l10n/app_localizations.dart';

class DocumentViewerScreen extends StatefulWidget {
  final String docId;
  final String title;
  final String fileName;
  final String fileType; // 'md' or 'txt'
  final String url;
  final String? category;
  final DateTime? publicationDate;
  final int? fileSize;

  const DocumentViewerScreen({
    Key? key,
    required this.docId,
    required this.title,
    required this.fileName,
    required this.fileType,
    required this.url,
    this.category,
    this.publicationDate,
    this.fileSize,
  }) : super(key: key);

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  final DocumentCacheService _cacheService = DocumentCacheService();
  String? _content;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isCached = false;
  double _fontSizeMultiplier = 1.0;

  @override
  void initState() {
    super.initState();
    _loadDocumentContent();
  }

  void _loadDocumentContent() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final isCachedBefore = await _cacheService.isCached(widget.docId, widget.fileName);
      final bytes = await _cacheService.getOrDownloadBytes(
        widget.docId,
        widget.url,
        widget.fileName,
      );

      final text = utf8.decode(bytes, allowMalformed: true);

      if (mounted) {
        setState(() {
          _content = text;
          _isLoading = false;
          _isCached = isCachedBefore || true;
        });
      }
    } catch (e) {
      debugPrint('Error loading document content: $e');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _shareContent() {
    if (_content != null && _content!.isNotEmpty) {
      Share.share(
        _content!,
        subject: widget.title,
      );
    }
  }

  void _copyToClipboard(BuildContext context) {
    if (_content != null && _content!.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _content!));
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.copiedToClipboard)),
      );
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
    final isMarkdown = widget.fileType.toLowerCase() == 'md' || widget.fileName.toLowerCase().endsWith('.md');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.publicationDate != null)
              Text(
                '${l10n.publicationDateLabel}: ${_formatDate(widget.publicationDate!)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          // Font size adjusters
          IconButton(
            icon: const Icon(Icons.text_decrease, size: 20),
            tooltip: l10n.decreaseFontSize,
            onPressed: _fontSizeMultiplier > 0.8
                ? () => setState(() => _fontSizeMultiplier -= 0.1)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.text_increase, size: 20),
            tooltip: l10n.increaseFontSize,
            onPressed: _fontSizeMultiplier < 1.6
                ? () => setState(() => _fontSizeMultiplier += 0.1)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: l10n.copyText,
            onPressed: () => _copyToClipboard(context),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: l10n.shareDocument,
            onPressed: _shareContent,
          ),
        ],
      ),
      body: _buildBody(context, l10n, isMarkdown),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n, bool isMarkdown) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n.loadingDocument),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
              const SizedBox(height: 16),
              Text(
                l10n.errorLoadingDocument,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadDocumentContent,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retry),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConfig.primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Metadata header bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            children: [
              // Category Chip
              if (widget.category != null && widget.category!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: AppConfig.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.category!.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppConfig.primaryColor,
                    ),
                  ),
                ),

              // File Size
              if (widget.fileSize != null)
                Text(
                  _formatFileSize(widget.fileSize!),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),

              const Spacer(),

              // Cache Status
              if (_isCached)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.offline_pin, size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 4),
                    Text(
                      l10n.cachedLocally,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),

        // Document Content Scrollable View
        Expanded(
          child: SelectionArea(
            child: isMarkdown
                ? Markdown(
                    data: _content ?? '',
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                      p: TextStyle(fontSize: 14 * _fontSizeMultiplier, height: 1.6),
                      h1: TextStyle(fontSize: 22 * _fontSizeMultiplier, fontWeight: FontWeight.bold),
                      h2: TextStyle(fontSize: 18 * _fontSizeMultiplier, fontWeight: FontWeight.bold),
                      h3: TextStyle(fontSize: 16 * _fontSizeMultiplier, fontWeight: FontWeight.w600),
                      code: TextStyle(
                        fontSize: 13 * _fontSizeMultiplier,
                        backgroundColor: Colors.grey.shade100,
                        fontFamily: 'monospace',
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                    ),
                    padding: const EdgeInsets.all(20.0),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20.0),
                    child: Text(
                      _content ?? '',
                      style: TextStyle(
                        fontSize: 14 * _fontSizeMultiplier,
                        height: 1.6,
                        fontFamily: 'monospace',
                        color: Colors.black87,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
