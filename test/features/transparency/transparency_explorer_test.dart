import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/core/services/cache_io_helper.dart';
import 'package:suburban_life/core/services/document_cache_service.dart';
import 'package:suburban_life/features/transparency/document_viewer_screen.dart';
import 'package:suburban_life/features/transparency/transparency_localization_helper.dart';
import 'package:suburban_life/features/transparency/transparency_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import '../../helpers/fake_backend.dart';

class _InMemoryCacheIoHelper implements CacheIoHelper {
  final Map<String, Uint8List> store = {};

  @override
  Future<bool> isCached(String key) async => store.containsKey(key);

  @override
  Future<Uint8List?> getCachedBytes(String key) async => store[key];

  @override
  Future<void> saveCachedBytes(String key, Uint8List bytes) async {
    store[key] = bytes;
  }

  @override
  Future<String?> getCachedFilePath(String key) async =>
      store.containsKey(key) ? '/virtual_cache/$key' : null;

  @override
  Future<void> removeCachedFile(String key) async {
    store.remove(key);
  }

  @override
  Future<void> clearAllCache() async {
    store.clear();
  }

  @override
  Future<Uint8List?> readFileBytesFromDisk(String filePath) async => null;
}

Widget _wrapWithL10n(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('es')],
    locale: const Locale('en'),
    home: child,
  );
}

void main() {
  late _InMemoryCacheIoHelper memoryCache;
  String? copiedClipboardText;

  setUp(() {
    FakeBackendHelper.setUp();
    memoryCache = _InMemoryCacheIoHelper();
    DocumentCacheService().configureForTesting(helper: memoryCache);
    copiedClipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        copiedClipboardText = args?['text']?.toString();
      }
      return null;
    });
  });

  tearDown(() {
    DocumentCacheService().configureForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('TransparencyScreen - Production Static Filtering & Role Logic', () {
    final sampleFolders = [
      {'id': 'official_manuals', 'name': 'Official Manuals', 'parentId': 'root', 'visibility': 'admin'},
      {'id': 'community_rules', 'name': 'Reglamentos', 'parentId': 'root', 'visibility': 'all'},
      {'id': 'finances_2026', 'name': '2026', 'parentId': 'community_rules', 'visibility': 'all'},
    ];

    final sampleDocs = [
      {
        'id': 'admin_manual',
        'title': 'Admin Guide',
        'fileName': 'admin.pdf',
        'fileType': 'pdf',
        'folderId': 'official_manuals',
        'category': 'manuals',
        'visibility': 'admin',
      },
      {
        'id': 'internal_note',
        'title': 'Internal Note in Admin Folder',
        'fileName': 'note.txt',
        'fileType': 'txt',
        'folderId': 'official_manuals',
        'category': 'communiques',
        'visibility': 'all',
      },
      {
        'id': 'public_bylaws',
        'title': 'Internal Bylaws 2026',
        'fileName': 'reglamento_2026.md',
        'fileType': 'md',
        'folderId': 'community_rules',
        'category': 'normatives',
        'visibility': 'all',
      },
    ];

    test('isNativeInAppViewer distinguishes .md, .txt, and images from external binaries', () {
      expect(TransparencyScreen.isNativeInAppViewer('md'), isTrue);
      expect(TransparencyScreen.isNativeInAppViewer('txt'), isTrue);
      expect(TransparencyScreen.isNativeInAppViewer('', 'readme.md'), isTrue);
      expect(TransparencyScreen.isNativeInAppViewer('png'), isTrue);
      expect(TransparencyScreen.isNativeInAppViewer('pdf'), isFalse);
      expect(TransparencyScreen.isNativeInAppViewer('xlsx'), isFalse);
    });

    test('canDeleteCategory blocks deletion when active documents reference the category', () {
      expect(TransparencyScreen.canDeleteCategory('normatives', sampleDocs), isFalse);
      expect(TransparencyScreen.canDeleteCategory('contracts', sampleDocs), isTrue);
    });

    test('hides admin-only folders and their contents from residents while showing them to admins', () {
      final restrictedIds = TransparencyScreen.collectAdminOnlyFolderIds(sampleFolders);

      final residentFolders = TransparencyScreen.filterVisibleFolders(
        allFolders: sampleFolders,
        currentFolderId: 'root',
        isAdmin: false,
        adminOnlyFolderIds: restrictedIds,
      );
      expect(residentFolders.map((f) => f['id']), equals(['community_rules']));

      final residentSearchDocs = TransparencyScreen.filterVisibleDocuments(
        allDocs: sampleDocs,
        currentFolderId: 'root',
        isAdmin: false,
        searchQuery: 'note',
        adminOnlyFolderIds: restrictedIds,
      );
      expect(residentSearchDocs, isEmpty);

      final adminFolders = TransparencyScreen.filterVisibleFolders(
        allFolders: sampleFolders,
        currentFolderId: 'root',
        isAdmin: true,
        adminOnlyFolderIds: restrictedIds,
      );
      expect(adminFolders.map((f) => f['id']), containsAll(['official_manuals', 'community_rules']));
    });

    test('resolveEffectiveAdmin enforces resident view override and Firestore role check', () {
      expect(
        TransparencyScreen.resolveEffectiveAdmin(
          isAdminView: false,
          hasAdminClaim: true,
          firestoreRole: 'admin',
        ),
        isFalse,
      );
      expect(
        TransparencyScreen.resolveEffectiveAdmin(
          isAdminView: null,
          hasAdminClaim: true,
          firestoreRole: 'resident',
        ),
        isFalse,
      );
      expect(
        TransparencyScreen.resolveEffectiveAdmin(
          isAdminView: true,
          hasAdminClaim: true,
          firestoreRole: 'admin',
        ),
        isTrue,
      );
    });

    test('webUploadAcceptAttribute avoids wildcard */*, audio/*, and video/* to prevent mobile browser permission errors', () {
      const accept = TransparencyScreen.webUploadAcceptAttribute;
      expect(accept.contains('*/*'), isFalse);
      expect(accept.contains('audio/'), isFalse);
      expect(accept.contains('video/'), isFalse);
      expect(accept.contains('.pdf'), isTrue);
      expect(accept.contains('application/pdf'), isTrue);
      expect(accept.contains('.docx'), isTrue);
      expect(accept.contains('.xlsx'), isTrue);
      expect(accept.contains('.md'), isTrue);
      expect(accept.contains('.png'), isTrue);
      expect(TransparencyScreen.maxUploadSizeBytes, equals(10 * 1024 * 1024));
    });

    test('sanitizeUploadFileName strips path traversal and isAllowedUploadExtension enforces allow-list', () {
      expect(
        TransparencyScreen.sanitizeUploadFileName('../../etc/Presupuesto 2026.PDF'),
        equals('Presupuesto_2026.PDF'),
      );
      expect(
        TransparencyScreen.sanitizeUploadFileName(r'C:\Users\Admin\Documents\acta_final.docx'),
        equals('acta_final.docx'),
      );
      expect(TransparencyScreen.sanitizeUploadFileName('..'), isEmpty);
      expect(TransparencyScreen.sanitizeUploadFileName('   '), isEmpty);

      expect(TransparencyScreen.isAllowedUploadExtension('Presupuesto_2026.PDF'), isTrue);
      expect(TransparencyScreen.isAllowedUploadExtension('reglamento.md'), isTrue);
      expect(TransparencyScreen.isAllowedUploadExtension('reporte.xlsx'), isTrue);
      expect(TransparencyScreen.isAllowedUploadExtension('evidencia.webp'), isTrue);

      expect(TransparencyScreen.isAllowedUploadExtension('recording.mp3'), isFalse);
      expect(TransparencyScreen.isAllowedUploadExtension('script.html'), isFalse);
      expect(TransparencyScreen.isAllowedUploadExtension('installer.apk'), isFalse);
      expect(TransparencyScreen.isAllowedUploadExtension('README'), isFalse);
    });
  });

  group('TransparencyLocalizationHelper - Hybrid Resolution & Multi-Locale Support', () {
    test('resolveFolderDisplayName prioritizes localizedNames, then nameKey/folderId/_token_ patterns, then raw name', () {
      final enL10n = lookupAppLocalizations(const Locale('en'));
      final esL10n = lookupAppLocalizations(const Locale('es'));

      // 1. Explicit localizedNames wins over nameKey
      expect(
        TransparencyLocalizationHelper.resolveFolderDisplayName(
          folderId: 'financial_reports',
          folderData: {
            'name': '_financial-reports_',
            'nameKey': 'financial_reports',
            'localizedNames': {'en': 'Custom Budgets', 'es': 'Presupuestos Propios'},
          },
          l10n: esL10n,
          languageCode: 'es',
        ),
        equals('Presupuestos Propios'),
      );

      // 2. `_financial-reports_` token resolves on arbitrary folderId
      expect(
        TransparencyLocalizationHelper.resolveFolderDisplayName(
          folderId: 'arbitrary_doc_id',
          folderData: {'name': '_financial-reports_'},
          l10n: enL10n,
          languageCode: 'en',
        ),
        equals('Financial Reports'),
      );
      expect(
        TransparencyLocalizationHelper.resolveFolderDisplayName(
          folderId: 'arbitrary_doc_id',
          folderData: {'name': '_financial-reports_'},
          l10n: esL10n,
          languageCode: 'es',
        ),
        equals('Reportes Financieros'),
      );

      // 3. `official_manuals` via folderId or `_official-manuals_`
      expect(
        TransparencyLocalizationHelper.resolveFolderDisplayName(
          folderId: 'official_manuals',
          folderData: {'name': 'Manuales'},
          l10n: enL10n,
          languageCode: 'en',
        ),
        equals('Official Manuals'),
      );
      expect(
        TransparencyLocalizationHelper.resolveFolderDisplayName(
          folderId: 'x',
          folderData: {'name': '_official-manuals_'},
          l10n: esL10n,
          languageCode: 'es',
        ),
        equals('Manuales Oficiales'),
      );

      // 4. Custom folder preserves raw name
      expect(
        TransparencyLocalizationHelper.resolveFolderDisplayName(
          folderId: 'folder_2026',
          folderData: {'name': 'Asambleas 2026'},
          l10n: enL10n,
          languageCode: 'en',
        ),
        equals('Asambleas 2026'),
      );
    });

    test('resolveCategoryDisplayName localizes known category slugs and custom categories', () {
      final enL10n = lookupAppLocalizations(const Locale('en'));
      final esL10n = lookupAppLocalizations(const Locale('es'));

      expect(
        TransparencyLocalizationHelper.resolveCategoryDisplayName(
          categoryId: 'financial',
          rawName: 'Financial',
          l10n: esL10n,
          languageCode: 'es',
        ),
        equals('Finanzas'),
      );
      expect(
        TransparencyLocalizationHelper.resolveCategoryDisplayName(
          categoryId: 'normatives',
          rawName: 'Normatives',
          l10n: esL10n,
          languageCode: 'es',
        ),
        equals('Normativas'),
      );
      expect(
        TransparencyLocalizationHelper.resolveCategoryDisplayName(
          categoryId: 'custom_cat',
          rawName: 'Custom Label',
          l10n: enL10n,
          languageCode: 'en',
        ),
        equals('Custom Label'),
      );
    });

    test('resolveDocumentFileVariant, matchesDocumentSearch, and collectDocumentFilesForDeletion handle bilingual docs', () {
      final doc = {
        'id': 'financial_summary_2026-11',
        'title': '2026-11',
        'fileName': 'financial_summary_2026-11_en.md',
        'fileType': 'md',
        'category': 'financial',
        'url': 'https://storage.local/en.md',
        'fileSize': 500,
        'translatedTitles': {
          'en': '2026-11 Summary',
          'es': '2026-11 Resumen',
        },
        'translatedFiles': {
          'en': {
            'url': 'https://storage.local/en.md',
            'fileName': 'financial_summary_2026-11_en.md',
            'fileSize': 500,
          },
          'es': {
            'url': 'https://storage.local/es.md',
            'fileName': 'financial_summary_2026-11_es.md',
            'fileSize': 650,
          },
        },
      };

      final esVariant = TransparencyLocalizationHelper.resolveDocumentFileVariant(
        doc,
        languageCode: 'es',
      );
      expect(esVariant.url, equals('https://storage.local/es.md'));
      expect(esVariant.fileName, equals('financial_summary_2026-11_es.md'));
      expect(esVariant.fileSize, equals(650));

      expect(TransparencyLocalizationHelper.matchesDocumentSearch(doc, 'resumen'), isTrue);
      expect(TransparencyLocalizationHelper.matchesDocumentSearch(doc, 'summary'), isTrue);
      expect(TransparencyLocalizationHelper.matchesDocumentSearch(doc, 'missing_term'), isFalse);

      final filesForDeletion = TransparencyLocalizationHelper.collectDocumentFilesForDeletion(doc);
      expect(
        filesForDeletion.map((f) => f.url).where((u) => u.isNotEmpty).toSet(),
        equals({'https://storage.local/en.md', 'https://storage.local/es.md'}),
      );
      expect(
        filesForDeletion.map((f) => f.fileName).where((n) => n.isNotEmpty).toSet(),
        equals({'financial_summary_2026-11_en.md', 'financial_summary_2026-11_es.md'}),
      );
    });
  });

  group('TransparencyScreen & DocumentViewerScreen - Widget Flows', () {
    testWidgets('resident view hides admin-only items, navigates folders, searches, and disposes cleanly', (tester) async {
      FakeBackendHelper.auth.isAdminMock = true; // Even with stale claim, isAdminView: false forces resident mode!
      FakeBackendHelper.db.seedDocument('document_categories', 'normatives', {'name': 'Normatives'});
      FakeBackendHelper.db.seedDocument('document_folders', 'official_manuals', {
        'name': 'Secret Admin Folder',
        'parentId': 'root',
        'visibility': 'admin',
      });
      FakeBackendHelper.db.seedDocument('document_folders', 'rules_folder', {
        'name': 'Community Rules',
        'parentId': 'root',
        'visibility': 'all',
      });
      FakeBackendHelper.db.seedDocument('documents', 'doc_secret', {
        'title': 'Confidential Admin Manual',
        'fileName': 'secret.pdf',
        'fileType': 'pdf',
        'folderId': 'root',
        'category': 'normatives',
        'visibility': 'admin',
        'url': 'https://fake-storage.local/secret.pdf',
      });
      FakeBackendHelper.db.seedDocument('documents', 'doc_rules', {
        'title': 'Pool Rules 2026',
        'fileName': 'pool_rules.md',
        'fileType': 'md',
        'folderId': 'rules_folder',
        'category': 'normatives',
        'visibility': 'all',
        'url': 'https://fake-storage.local/pool_rules.md',
      });

      await tester.pumpWidget(_wrapWithL10n(const TransparencyScreen(isAdminView: false)));
      await tester.pumpAndSettle();

      // Admin FABs and admin-only items must be hidden
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Secret Admin Folder'), findsNothing);
      expect(find.text('Confidential Admin Manual'), findsNothing);
      expect(find.text('Community Rules'), findsOneWidget);

      // Navigate into Community Rules folder
      await tester.tap(find.text('Community Rules'));
      await tester.pumpAndSettle();
      expect(find.text('Pool Rules 2026'), findsOneWidget);

      // Return to root via breadcrumb, then search globally
      await tester.tap(find.byIcon(Icons.home_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Pool Rules 2026'), findsNothing);

      await tester.enterText(find.byType(TextField), 'pool');
      await tester.pumpAndSettle();
      expect(find.text('Pool Rules 2026'), findsOneWidget);

      // Unmount widget and emit category update after dispose to prove subscription was cancelled
      await tester.pumpWidget(const SizedBox.shrink());
      FakeBackendHelper.db.seedDocument('document_categories', 'extra_cat', {'name': 'Extra'});
      await tester.pump();
    });

    testWidgets('admin view renders FABs and creates a new virtual folder', (tester) async {
      FakeBackendHelper.auth.emitUser(AppUser(uid: 'admin_1', email: 'admin@test.com'));
      FakeBackendHelper.auth.isAdminMock = true;
      FakeBackendHelper.db.seedDocument('users', 'admin_1', {'role': 'admin'});
      FakeBackendHelper.db.seedDocument('document_categories', 'normatives', {'name': 'Normatives'});

      await tester.pumpWidget(_wrapWithL10n(const TransparencyScreen(isAdminView: true)));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.create_new_folder), findsOneWidget);
      await tester.tap(find.byIcon(Icons.create_new_folder));
      await tester.pumpAndSettle();

      final dialogTextField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogTextField, '2026 Financial Reports');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      final folders = await FakeBackendHelper.db.getCollection('document_folders');
      expect(folders.any((f) => f['name'] == '2026 Financial Reports'), isTrue);
      expect(find.text('2026 Financial Reports'), findsOneWidget);
    });

    testWidgets('DocumentViewerScreen renders cached Markdown content and copies text', (tester) async {
      const markdownText = '# Community Bylaws\n\nQuiet hours start at 10:00 PM.';
      final key = DocumentCacheService.buildCacheKey('doc_md_1', 'bylaws.md');
      await memoryCache.saveCachedBytes(key, Uint8List.fromList(utf8.encode(markdownText)));

      await tester.pumpWidget(
        _wrapWithL10n(
          DocumentViewerScreen(
            docId: 'doc_md_1',
            title: 'Community Bylaws',
            fileName: 'bylaws.md',
            fileType: 'md',
            url: 'https://fake-storage.local/bylaws.md',
            category: 'normatives',
            publicationDate: DateTime(2026, 4, 1),
            fileSize: 2048,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NORMATIVES'), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);
      expect(find.textContaining('Quiet hours start at 10:00 PM.'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.text_increase));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();
      expect(copiedClipboardText, equals(markdownText));
    });

    testWidgets('TransparencyScreen renders bilingual folder, category, and doc variant in Spanish and searches translated titles', (tester) async {
      FakeBackendHelper.db.seedDocument('document_categories', 'financial', {
        'name': 'Financial',
        'localizedNames': {'en': 'Financial', 'es': 'Finanzas'},
      });
      FakeBackendHelper.db.seedDocument('document_folders', 'fin_custom_id', {
        'name': '_financial-reports_',
        'parentId': 'root',
        'visibility': 'all',
      });
      FakeBackendHelper.db.seedDocument('documents', 'financial_summary_2026-06_to_2026-11', {
        'title': '2026-06 – 2026-11',
        'fileName': 'financial_summary_2026-06_to_2026-11_en.md',
        'fileType': 'md',
        'folderId': 'fin_custom_id',
        'category': 'financial',
        'visibility': 'all',
        'url': 'https://fake-storage.local/fin_en.md',
        'translatedTitles': {
          'en': '2026-06 – 2026-11',
          'es': '2026-06 – 2026-11',
        },
        'translatedFiles': {
          'en': {
            'url': 'https://fake-storage.local/fin_en.md',
            'fileName': 'financial_summary_2026-06_to_2026-11_en.md',
            'fileSize': 1024,
          },
          'es': {
            'url': 'https://fake-storage.local/fin_es.md',
            'fileName': 'financial_summary_2026-06_to_2026-11_es.md',
            'fileSize': 1200,
          },
        },
      });

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('es')],
          locale: const Locale('es'),
          home: const TransparencyScreen(isAdminView: false),
        ),
      );
      await tester.pumpAndSettle();

      // `_financial-reports_` token resolves cleanly in Spanish!
      expect(find.text('Reportes Financieros'), findsOneWidget);
      await tester.tap(find.text('Reportes Financieros'));
      await tester.pumpAndSettle();

      // Breadcrumb & category chip & doc card render in Spanish
      expect(find.text('Reportes Financieros'), findsWidgets);
      expect(find.text('2026-06 – 2026-11'), findsOneWidget);
      expect(find.text('FINANZAS'), findsWidgets);
    });

    testWidgets('DocumentViewerScreen switches between ES and EN cached variants using header language toggle', (tester) async {
      const esMarkdown = '# Resumen Financiero — 2026-11\n\nSaldo acumulado: \$1500.00';
      const enMarkdown = '# Financial Summary — 2026-11\n\nAccumulated budget: \$1500.00';

      final esKey = DocumentCacheService.buildCacheKey('fin_doc_1', 'fin_2026_11_es.md');
      final enKey = DocumentCacheService.buildCacheKey('fin_doc_1', 'fin_2026_11_en.md');
      await memoryCache.saveCachedBytes(esKey, Uint8List.fromList(utf8.encode(esMarkdown)));
      await memoryCache.saveCachedBytes(enKey, Uint8List.fromList(utf8.encode(enMarkdown)));

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('es')],
          locale: const Locale('es'),
          home: DocumentViewerScreen(
            docId: 'fin_doc_1',
            title: '2026-11',
            fileName: 'fin_2026_11_es.md',
            fileType: 'md',
            url: 'https://fake-storage.local/fin_2026_11_es.md',
            category: 'financial',
            fileSize: 1024,
            initialLanguageCode: 'es',
            translatedTitles: const {'es': '2026-11', 'en': '2026-11'},
            translatedFiles: const {
              'es': {
                'url': 'https://fake-storage.local/fin_2026_11_es.md',
                'fileName': 'fin_2026_11_es.md',
                'fileSize': 1536,
              },
              'en': {
                'url': 'https://fake-storage.local/fin_2026_11_en.md',
                'fileName': 'fin_2026_11_en.md',
                'fileSize': 2048,
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('document_viewer_language_switcher')), findsOneWidget);
      expect(find.text('FINANZAS'), findsOneWidget);
      expect(find.text('1.5 KB'), findsOneWidget);
      expect(find.textContaining('Saldo acumulado: \$1500.00'), findsOneWidget);

      // Switch to EN
      await tester.tap(find.byKey(const ValueKey('document_viewer_lang_en')));
      await tester.pumpAndSettle();

      expect(find.text('2.0 KB'), findsOneWidget);
      expect(find.textContaining('Accumulated budget: \$1500.00'), findsOneWidget);
    });
  });
}
