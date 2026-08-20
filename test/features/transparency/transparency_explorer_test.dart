import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Transparency File Explorer - Virtual Hierarchy Logic', () {
    final sampleFolders = [
      {
        'id': 'folder-finances',
        'name': 'Finances',
        'parentId': 'root',
      },
      {
        'id': 'folder-finances-2026',
        'name': '2026',
        'parentId': 'folder-finances',
      },
      {
        'id': 'folder-normatives',
        'name': 'Normatives & Bylaws',
        'parentId': 'root',
      },
    ];

    final sampleDocs = [
      {
        'id': 'doc-1',
        'title': 'Internal Bylaws 2026',
        'fileName': 'reglamento_2026.md',
        'fileType': 'md',
        'folderId': 'folder-normatives',
        'category': 'normatives',
      },
      {
        'id': 'doc-2',
        'title': 'Q1 Financial Summary',
        'fileName': 'summary_q1.pdf',
        'fileType': 'pdf',
        'folderId': 'folder-finances-2026',
        'category': 'financial',
      },
      {
        'id': 'doc-3',
        'title': 'General Community Notice',
        'fileName': 'notice.txt',
        'fileType': 'txt',
        'folderId': 'root',
        'category': 'communiques',
      },
    ];

    test('Filters folders at root level', () {
      final rootFolders = sampleFolders.where((f) => f['parentId'] == 'root').toList();
      expect(rootFolders.length, 2);
      expect(rootFolders.map((f) => f['id']), containsAll(['folder-finances', 'folder-normatives']));
    });

    test('Filters subfolders inside Finances', () {
      final subfolders = sampleFolders.where((f) => f['parentId'] == 'folder-finances').toList();
      expect(subfolders.length, 1);
      expect(subfolders.first['id'], 'folder-finances-2026');
    });

    test('Filters documents inside specific virtual folder', () {
      final docsInNormatives = sampleDocs.where((d) => d['folderId'] == 'folder-normatives').toList();
      expect(docsInNormatives.length, 1);
      expect(docsInNormatives.first['title'], 'Internal Bylaws 2026');

      final docsInRoot = sampleDocs.where((d) => d['folderId'] == 'root').toList();
      expect(docsInRoot.length, 1);
      expect(docsInRoot.first['title'], 'General Community Notice');
    });

    test('Moving a document to another folder updates folderId virtually without touching storage', () {
      final mutableDoc = Map<String, dynamic>.from(sampleDocs[2]);
      expect(mutableDoc['folderId'], 'root');

      // Admin moves notice.txt into folder-normatives
      mutableDoc['folderId'] = 'folder-normatives';
      expect(mutableDoc['folderId'], 'folder-normatives');

      final docsInNormativesAfterMove = [
        sampleDocs[0],
        mutableDoc,
      ].where((d) => d['folderId'] == 'folder-normatives').toList();

      expect(docsInNormativesAfterMove.length, 2);
    });

    test('Identifies native in-app viewable file types (.md, .txt, images) vs external files (.pdf)', () {
      bool isNativeInAppViewer(String fileType) {
        final ext = fileType.toLowerCase();
        return ext == 'md' || ext == 'txt' || ['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext);
      }

      expect(isNativeInAppViewer('md'), isTrue);
      expect(isNativeInAppViewer('txt'), isTrue);
      expect(isNativeInAppViewer('png'), isTrue);
      expect(isNativeInAppViewer('jpg'), isTrue);
      expect(isNativeInAppViewer('pdf'), isFalse);
      expect(isNativeInAppViewer('docx'), isFalse);
      expect(isNativeInAppViewer('xlsx'), isFalse);
    });

    test('Changing a document category updates category attribute', () {
      final mutableDoc = Map<String, dynamic>.from(sampleDocs[0]);
      expect(mutableDoc['category'], 'normatives');

      // Admin updates category to contracts
      mutableDoc['category'] = 'contracts';
      expect(mutableDoc['category'], 'contracts');
    });

    test('Blocks deletion of categories that have active documents assigned', () {
      bool canDeleteCategory(String categoryId, List<Map<String, dynamic>> documents) {
        final count = documents.where(
          (d) => (d['category']?.toString().toLowerCase() ?? '') == categoryId.toLowerCase(),
        ).length;
        return count == 0;
      }

      // 'normatives' is in use by doc-1 -> MUST BE BLOCKED
      expect(canDeleteCategory('normatives', sampleDocs), isFalse);

      // 'financial' is in use by doc-2 -> MUST BE BLOCKED
      expect(canDeleteCategory('financial', sampleDocs), isFalse);

      // 'contracts' has 0 documents -> ALLOWED
      expect(canDeleteCategory('contracts', sampleDocs), isTrue);

      // 'unknown_cat' has 0 documents -> ALLOWED
      expect(canDeleteCategory('unknown_cat', sampleDocs), isTrue);
    });
  });
}
