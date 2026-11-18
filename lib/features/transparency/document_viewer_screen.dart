import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/config/app_config.dart';
import '../../core/services/document_cache_service.dart';
import '../../l10n/app_localizations.dart';
import 'transparency_localization_helper.dart';

class DocumentViewerScreen extends StatefulWidget {
  final String docId;
  final String title;
  final String fileName;
  final String fileType; // 'md' or 'txt'
  final String url;
  final String? category;
  final DateTime? publicationDate;
  final int? fileSize;
  final String? initialLanguageCode;
  final Map<String, String>? translatedTitles;
  final Map<String, Map<String, dynamic>>? translatedFiles;

  const DocumentViewerScreen({
    super.key,
    required this.docId,
    required this.title,
    required this.fileName,
    required this.fileType,
    required this.url,
    this.category,
    this.publicationDate,
    this.fileSize,
    this.initialLanguageCode,
    this.translatedTitles,
    this.translatedFiles,
  });

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
  late String _activeLang;

  List<String> get _availableLanguages {
    final files = widget.translatedFiles;
    if (files == null || files.isEmpty) return const [];
    final ordered = <String>[];
    for (final lang in const ['es', 'en']) {
      final url = files[lang]?['url']?.toString().trim() ?? '';
      if (url.isNotEmpty) ordered.add(lang);
    }
    return ordered;
  }

  String get _activeTitle {
    final localized = widget.translatedTitles?[_activeLang]?.trim();
    if (localized != null && localized.isNotEmpty) return localized;
    return widget.title;
  }

  String get _activeFileName {
    final localized =
        widget.translatedFiles?[_activeLang]?['fileName']?.toString().trim();
    if (localized != null && localized.isNotEmpty) return localized;
    return widget.fileName;
  }

  String get _activeUrl {
    final localized =
        widget.translatedFiles?[_activeLang]?['url']?.toString().trim();
    if (localized != null && localized.isNotEmpty) return localized;
    return widget.url;
  }

  int? get _activeFileSize {
    final localizedSize =
        (widget.translatedFiles?[_activeLang]?['fileSize'] as num?)?.toInt();
    return localizedSize ?? widget.fileSize;
  }

  @override
  void initState() {
    super.initState();
    _activeLang = _resolveInitialLanguage();
    _loadDocumentContent();
  }

  String _resolveInitialLanguage() {
    final available = _availableLanguages;
    if (available.isEmpty) {
      final initial = widget.initialLanguageCode?.trim().toLowerCase() ?? 'en';
      return initial.startsWith('es') ? 'es' : 'en';
    }
    final initial = widget.initialLanguageCode?.trim().toLowerCase() ?? 'en';
    final normalized = initial.startsWith('es') ? 'es' : 'en';
    if (available.contains(normalized)) return normalized;
    if (available.contains('en')) return 'en';
    return available.first;
  }

  void _switchLanguage(String lang) {
    if (lang == _activeLang || !_availableLanguages.contains(lang)) return;
    setState(() {
      _activeLang = lang;
    });
    _loadDocumentContent();
  }

  void _loadDocumentContent() async {
    final requestedLang = _activeLang;
    final activeFileName = _activeFileName;
    final activeUrl = _activeUrl;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final isCachedBefore = await _cacheService.isCached(widget.docId, activeFileName);
      final bytes = await _cacheService.getOrDownloadBytes(
        widget.docId,
        activeUrl,
        activeFileName,
      );

      final text = utf8.decode(bytes, allowMalformed: true);

      if (mounted && _activeLang == requestedLang) {
        setState(() {
          _content = text;
          _isLoading = false;
          _isCached = isCachedBefore || true;
        });
      }
    } catch (e) {
      debugPrint('Error loading document content: $e');
      if (mounted && _activeLang == requestedLang) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _shareContent() {
    if (_content != null && _content!.isNotEmpty) {
      SharePlus.instance.share(
        ShareParams(
          text: _content!,
          subject: _activeTitle,
        ),
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
    final availableLangs = _availableLanguages;
    final isMarkdown = widget.fileType.toLowerCase() == 'md' || _activeFileName.toLowerCase().endsWith('.md');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _activeTitle,
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
      body: _buildBody(context, l10n, isMarkdown, availableLangs),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    bool isMarkdown,
    List<String> availableLangs,
  ) {
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

    final resolvedCategory = (widget.category != null && widget.category!.isNotEmpty)
        ? TransparencyLocalizationHelper.resolveCategoryDisplayName(
            categoryId: widget.category!,
            rawName: widget.category!,
            l10n: l10n,
          )
        : null;
    final activeFileSize = _activeFileSize;

    return Column(
      children: [
        // Metadata header bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Category Chip
                    if (resolvedCategory != null && resolvedCategory.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppConfig.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          resolvedCategory.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppConfig.primaryColor,
                          ),
                        ),
                      ),

                    // File Size
                    if (activeFileSize != null)
                      Text(
                        _formatFileSize(activeFileSize),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),

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
              if (availableLangs.length > 1) ...[
                const SizedBox(width: 8),
                Semantics(
                  label: l10n.documentLanguageLabel,
                  child: Container(
                    key: const ValueKey('document_viewer_language_switcher'),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppConfig.primaryColor.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: availableLangs.map((lang) {
                        final isSelected = lang == _activeLang;
                        final tooltip = lang == 'es'
                            ? l10n.switchToSpanishTooltip
                            : l10n.switchToEnglishTooltip;
                        return Tooltip(
                          message: tooltip,
                          child: InkWell(
                            key: ValueKey('document_viewer_lang_$lang'),
                            onTap: () => _switchLanguage(lang),
                            borderRadius: BorderRadius.circular(7),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppConfig.primaryColor
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(
                                lang.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? Colors.white
                                      : AppConfig.primaryColor,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
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
