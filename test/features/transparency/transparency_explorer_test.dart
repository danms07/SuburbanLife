import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/core/services/cache_io_helper.dart';
import 'package:suburban_life/core/services/document_cache_service.dart';
import 'package:suburban_life/features/transparency/document_viewer_screen.dart';
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
  });
}
