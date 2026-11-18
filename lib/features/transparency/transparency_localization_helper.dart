import '../../l10n/app_localizations.dart';

/// Pure helpers for resolving bilingual Transparency folder, category, and
/// document metadata cleanly without UI or backend dependencies.
class TransparencyLocalizationHelper {
  /// Normalizes system keys and `_token_` markers (e.g. `_financial-reports_` -> `financial_reports`).
  static String normalizeTokenKey(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final unwrapped = (trimmed.length > 2 &&
            trimmed.startsWith('_') &&
            trimmed.endsWith('_'))
        ? trimmed.substring(1, trimmed.length - 1).trim()
        : trimmed;
    return unwrapped.toLowerCase().replaceAll('-', '_');
  }

  /// Resolves a folder display label using:
  /// 1) `localizedNames[locale]`
  /// 2) Known system `nameKey`, `folderId`, or `_token_` name via [l10n]
  /// 3) Raw `name` fallback (or [folderId]).
  static String resolveFolderDisplayName({
    required String folderId,
    required Map<String, dynamic> folderData,
    required AppLocalizations l10n,
    String? languageCode,
  }) {
    final locale = _normalizeLocale(languageCode ?? l10n.localeName);
    final explicit = _readLocalizedMapValue(folderData['localizedNames'], locale);
    if (explicit != null) return explicit;

    final candidates = <String>[
      folderData['nameKey']?.toString() ?? '',
      folderId,
      folderData['name']?.toString() ?? '',
    ];

    for (final candidate in candidates) {
      final key = normalizeTokenKey(candidate);
      switch (key) {
        case 'financial_reports':
          return l10n.folderFinancialReports;
        case 'official_manuals':
          return l10n.folderOfficialManuals;
      }
    }

    final rawName = folderData['name']?.toString().trim() ?? '';
    return rawName.isNotEmpty ? rawName : folderId;
  }

  /// Resolves a category display label using:
  /// 1) `localizedNames[locale]`
  /// 2) Known seeded category `id` / `_token_` key via [l10n]
  /// 3) Raw `name` fallback (or [categoryId]).
  static String resolveCategoryDisplayName({
    required String categoryId,
    String? rawName,
    dynamic localizedNames,
    required AppLocalizations l10n,
    String? languageCode,
  }) {
    final locale = _normalizeLocale(languageCode ?? l10n.localeName);
    final explicit = _readLocalizedMapValue(localizedNames, locale);
    if (explicit != null) return explicit;

    final candidates = <String>[
      categoryId,
      rawName ?? '',
    ];

    for (final candidate in candidates) {
      final key = normalizeTokenKey(candidate);
      switch (key) {
        case 'financial':
          return l10n.docCategoryFinancial;
        case 'normatives':
          return l10n.docCategoryNormatives;
        case 'contracts':
          return l10n.docCategoryContracts;
        case 'communiques':
          return l10n.docCategoryCommuniques;
        case 'manuals':
          return l10n.docCategoryManuals;
        case 'general':
          return l10n.docCategoryGeneral;
      }
    }

    final cleanRaw = rawName?.trim() ?? '';
    return cleanRaw.isNotEmpty ? cleanRaw : categoryId;
  }

  /// Extracts a clean `{ locale: title }` map from a document record.
  static Map<String, String> extractTranslatedTitles(Map<String, dynamic> doc) {
    final result = <String, String>{};
    final raw = doc['translatedTitles'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final key = entry.key.toString().trim().toLowerCase();
        final value = entry.value?.toString().trim() ?? '';
        if (key.isNotEmpty && value.isNotEmpty) {
          result[key] = value;
        }
      }
    }
    return result;
  }

  /// Extracts per-locale `{ url, storagePath, fileName, fileSize }` file descriptors from a document record.
  static Map<String, Map<String, dynamic>> extractTranslatedFiles(
    Map<String, dynamic> doc,
  ) {
    final result = <String, Map<String, dynamic>>{};
    final raw = doc['translatedFiles'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final locale = entry.key.toString().trim().toLowerCase();
        if (locale.isEmpty || entry.value is! Map) continue;
        final rawMeta = entry.value as Map;
        final url = rawMeta['url']?.toString().trim() ?? '';
        if (url.isEmpty) continue;
        final fileName = rawMeta['fileName']?.toString().trim() ?? '';
        final storagePath = rawMeta['storagePath']?.toString().trim() ?? '';
        final fileSize = (rawMeta['fileSize'] as num?)?.toInt();
        result[locale] = {
          'url': url,
          'fileName': fileName,
          'storagePath': storagePath,
          'fileSize': ?fileSize,
        };
      }
    }
    return result;
  }

  /// Resolves the best display title for [doc] in [languageCode].
  static String resolveDocumentTitle(
    Map<String, dynamic> doc, {
    required String languageCode,
    String fallbackTitle = '',
  }) {
    final locale = _normalizeLocale(languageCode);
    final titles = extractTranslatedTitles(doc);
    final localized = titles[locale] ?? titles['en'];
    if (localized != null && localized.isNotEmpty) return localized;

    final topTitle = doc['title']?.toString().trim() ?? '';
    if (topTitle.isNotEmpty) return topTitle;

    final topFileName = doc['fileName']?.toString().trim() ?? '';
    if (topFileName.isNotEmpty) return topFileName;

    return fallbackTitle;
  }

  /// Resolves the active `{ fileName, fileType, url, fileSize }` variant for [doc] in [languageCode].
  static ({String fileName, String fileType, String url, int? fileSize})
      resolveDocumentFileVariant(
    Map<String, dynamic> doc, {
    required String languageCode,
  }) {
    final locale = _normalizeLocale(languageCode);
    final translatedFiles = extractTranslatedFiles(doc);
    final variant = translatedFiles[locale] ??
        translatedFiles['en'] ??
        (translatedFiles.isNotEmpty ? translatedFiles.values.first : null);

    final fallbackTitle = doc['title']?.toString().trim() ?? 'document';
    String rawFileName =
        variant?['fileName']?.toString().trim() ??
            doc['fileName']?.toString().trim() ??
            '';
    if (rawFileName.isEmpty) {
      rawFileName = '$fallbackTitle.bin';
    }

    final fileType = (doc['fileType']?.toString().trim().isNotEmpty == true
            ? doc['fileType'].toString().trim()
            : (rawFileName.contains('.') ? rawFileName.split('.').last : ''))
        .toLowerCase();

    var normalizedFileName = rawFileName;
    if (!normalizedFileName.contains('.') && fileType.isNotEmpty) {
      normalizedFileName = '$normalizedFileName.$fileType';
    }

    final url =
        variant?['url']?.toString().trim() ?? doc['url']?.toString().trim() ?? '';
    final fileSize =
        (variant?['fileSize'] as num?)?.toInt() ?? (doc['fileSize'] as num?)?.toInt();

    return (
      fileName: normalizedFileName,
      fileType: fileType,
      url: url,
      fileSize: fileSize,
    );
  }

  /// Collects all unique Storage URLs and cached filenames owned by [doc] for cleanup on deletion.
  static List<({String url, String fileName})> collectDocumentFilesForDeletion(
    Map<String, dynamic> doc,
  ) {
    final entries = <({String url, String fileName})>[];
    final seenUrls = <String>{};
    final seenFiles = <String>{};

    void addPair(String? rawUrl, String? rawFileName) {
      final url = rawUrl?.trim() ?? '';
      final fileName = rawFileName?.trim() ?? '';
      if (url.isEmpty && fileName.isEmpty) return;

      final isNewUrl = url.isNotEmpty && seenUrls.add(url);
      final isNewFile = fileName.isNotEmpty && seenFiles.add(fileName);
      if (isNewUrl || isNewFile) {
        entries.add((url: isNewUrl ? url : '', fileName: isNewFile ? fileName : ''));
      }
    }

    addPair(doc['url']?.toString(), doc['fileName']?.toString());
    final translatedFiles = extractTranslatedFiles(doc);
    for (final meta in translatedFiles.values) {
      addPair(meta['url']?.toString(), meta['fileName']?.toString());
    }

    return entries;
  }

  /// Checks whether [doc] matches [normalizedQuery] across default and translated metadata.
  static bool matchesDocumentSearch(
    Map<String, dynamic> doc,
    String normalizedQuery,
  ) {
    if (normalizedQuery.isEmpty) return true;

    final candidates = <String>[
      doc['title']?.toString() ?? '',
      doc['fileName']?.toString() ?? '',
      doc['category']?.toString() ?? '',
      ...extractTranslatedTitles(doc).values,
      for (final meta in extractTranslatedFiles(doc).values)
        meta['fileName']?.toString() ?? '',
    ];

    for (final text in candidates) {
      if (text.toLowerCase().contains(normalizedQuery)) {
        return true;
      }
    }
    return false;
  }

  static String _normalizeLocale(String raw) {
    final lower = raw.trim().toLowerCase();
    if (lower.startsWith('es')) return 'es';
    return 'en';
  }

  static String? _readLocalizedMapValue(dynamic rawMap, String locale) {
    if (rawMap is! Map) return null;
    final val = rawMap[locale]?.toString().trim();
    if (val != null && val.isNotEmpty) return val;
    return null;
  }
}
