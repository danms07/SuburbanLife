import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:universal_html/html.dart' as html;
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../core/services/document_cache_service.dart';
import '../../core/widgets/interactive_image_dialog.dart';
import '../../l10n/app_localizations.dart';
import 'document_viewer_screen.dart';
import 'widgets/document_card.dart';
import 'widgets/file_explorer_breadcrumb.dart';
import 'widgets/folder_card.dart';

class TransparencyScreen extends StatefulWidget {
  const TransparencyScreen({Key? key}) : super(key: key);

  @override
  State<TransparencyScreen> createState() => _TransparencyScreenState();
}

class _TransparencyScreenState extends State<TransparencyScreen> {
  final AuthService _authService = AuthService();
  final DocumentCacheService _cacheService = DocumentCacheService();

  bool _isAdmin = false;
  String _currentFolderId = 'root';
  final List<BreadcrumbItem> _breadcrumbs = [];

  String _selectedCategory = 'all';
  List<Map<String, String>> _categories = [
    {'id': 'all', 'name': 'ALL'},
  ];

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _cachedDocIds = {};

  @override
  void initState() {
    super.initState();
    _checkAdmin();
    _listenToCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _checkAdmin() async {
    debugPrint('>>> [TransparencyScreen] Checking if current user is admin...');
    final isAdmin = await _authService.isAdmin();
    debugPrint('>>> [TransparencyScreen] User admin status: $isAdmin');
    if (mounted) {
      setState(() {
        _isAdmin = isAdmin;
      });
    }
  }

  void _listenToCategories() {
    DatabaseService().streamCollection('document_categories').listen((docs) {
      if (docs.isEmpty) {
        _seedDefaultCategories();
        return;
      }
      final List<Map<String, String>> loaded = [
        {'id': 'all', 'name': 'ALL'}
      ];
      for (var doc in docs) {
        final id = doc['id']?.toString() ?? '';
        final name = doc['name']?.toString() ?? id;
        if (id.isNotEmpty) {
          loaded.add({
            'id': id,
            'name': name,
          });
        }
      }
      if (mounted) {
        setState(() {
          _categories = loaded;
          if (!_categories.any((c) => c['id'] == _selectedCategory)) {
            _selectedCategory = 'all';
          }
        });
      }
    });
  }

  void _seedDefaultCategories() async {
    final defaults = {
      'normatives': 'Normatives',
      'contracts': 'Contracts',
      'financial': 'Financial',
      'communiques': 'Communiques',
    };
    await DatabaseService().runBatch((batch) async {
      for (var entry in defaults.entries) {
        batch.set('document_categories', entry.key, {
          'name': entry.value,
          'createdAt': DbFieldValue.serverTimestamp(),
        });
      }
    });
  }

  void _initBreadcrumbs(AppLocalizations l10n) {
    if (_breadcrumbs.isEmpty) {
      _breadcrumbs.add(BreadcrumbItem(id: 'root', name: l10n.rootFolder));
    }
  }

  void _navigateToFolder(String folderId, String folderName) {
    setState(() {
      _currentFolderId = folderId;
      _breadcrumbs.add(BreadcrumbItem(id: folderId, name: folderName));
    });
  }

  void _onBreadcrumbTap(BreadcrumbItem item) {
    final index = _breadcrumbs.indexWhere((b) => b.id == item.id);
    if (index != -1) {
      setState(() {
        _currentFolderId = item.id;
        _breadcrumbs.removeRange(index + 1, _breadcrumbs.length);
      });
    }
  }

  bool _onWillPop() {
    if (_breadcrumbs.length > 1) {
      setState(() {
        _breadcrumbs.removeLast();
        _currentFolderId = _breadcrumbs.last.id;
      });
      return false;
    }
    return true;
  }

  // --- Document Opening ---

  void _checkCachedDocuments(List<Map<String, dynamic>> docs) async {
    for (var doc in docs) {
      final docId = doc['id']?.toString() ?? '';
      if (docId.isEmpty || _cachedDocIds.contains(docId)) continue;

      final title = doc['title']?.toString() ?? doc['fileName']?.toString() ?? '';
      final rawFileName = doc['fileName']?.toString() ?? '$title.bin';
      final fileType = (doc['fileType']?.toString() ?? (rawFileName.contains('.') ? rawFileName.split('.').last : '')).toLowerCase();
      String fileName = rawFileName;
      if (!fileName.contains('.') && fileType.isNotEmpty) {
        fileName = '$fileName.$fileType';
      }

      final cached = await _cacheService.isCached(docId, fileName);
      if (cached && mounted && !_cachedDocIds.contains(docId)) {
        setState(() {
          _cachedDocIds.add(docId);
        });
      }
    }
  }

  void _openDocument(BuildContext context, Map<String, dynamic> doc) async {
    final l10n = AppLocalizations.of(context)!;
    final docId = doc['id']?.toString() ?? '';
    final title = doc['title']?.toString() ?? doc['fileName']?.toString() ?? l10n.untitledDocument;
    final rawFileName = doc['fileName']?.toString() ?? '$title.bin';
    final fileType = (doc['fileType']?.toString() ?? (rawFileName.contains('.') ? rawFileName.split('.').last : '')).toLowerCase();
    
    // Ensure fileName has proper extension if known
    String fileName = rawFileName;
    if (!fileName.contains('.') && fileType.isNotEmpty) {
      fileName = '$fileName.$fileType';
    }

    final url = doc['url']?.toString() ?? '';
    final category = doc['category']?.toString();
    final fileSize = doc['fileSize'] as int?;

    debugPrint('>>> [_openDocument] Document clicked: docId="$docId", title="$title", fileName="$fileName", fileType="$fileType", url="$url"');

    DateTime? publicationDate;
    final rawDate = doc['publicationDate'] ?? doc['uploadedAt'] ?? doc['timestamp'];
    if (rawDate != null) {
      if (rawDate is DateTime) {
        publicationDate = rawDate;
      } else if (rawDate is Map && rawDate['_seconds'] != null) {
        publicationDate = DateTime.fromMillisecondsSinceEpoch((rawDate['_seconds'] as int) * 1000);
      } else if (rawDate is int) {
        publicationDate = DateTime.fromMillisecondsSinceEpoch(rawDate);
      }
    }

    if (url.isEmpty) {
      debugPrint('>>> [_openDocument] ERROR: Document URL is empty.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorLoadingDocument)),
      );
      return;
    }

    // 1. Text / Markdown Files -> Native In-App Document Viewer Screen
    if (fileType == 'md' || fileType == 'txt' || fileName.endsWith('.md') || fileName.endsWith('.txt')) {
      debugPrint('>>> [_openDocument] Opening text/markdown file in DocumentViewerScreen');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DocumentViewerScreen(
            docId: docId,
            title: title,
            fileName: fileName,
            fileType: fileType,
            url: url,
            category: category,
            publicationDate: publicationDate,
            fileSize: fileSize,
          ),
        ),
      );
      return;
    }

    // 2. Images -> In-App Interactive Viewer Dialog
    if (['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(fileType)) {
      debugPrint('>>> [_openDocument] Opening image in interactive viewer dialog');
      showInteractiveImageDialog(
        context,
        url,
        title: title,
      );
      return;
    }

    // 3. Binary Files (PDF, DOCX, XLSX, etc.) -> Cache locally & Open via Intent Resolver / Default App
    debugPrint('>>> [_openDocument] Handling binary/external document: "$fileName" ($fileType)');

    // Web Platform: Download and/or Open via blob to support offline in-memory cache and bypass popup blockers
    if (kIsWeb) {
      try {
        final isCached = await _cacheService.isCached(docId, fileName);
        debugPrint('>>> [_openDocument] Web: isCached=$isCached');

        if (!isCached) {
          debugPrint('>>> [_openDocument] Web: downloading bytes for "$fileName"...');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.downloadingDocument),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          debugPrint('>>> [_openDocument] Web: reusing cached bytes for "$fileName" without re-downloading.');
        }

        final bytes = await _cacheService.getOrDownloadBytes(docId, url, fileName);
        if (mounted) {
          setState(() {
            _cachedDocIds.add(docId);
          });
        }

        debugPrint('>>> [_openDocument] Web: creating blob from ${bytes.length} bytes for "$fileName"');
        final blob = html.Blob([bytes]);
        final blobUrl = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: blobUrl)
          ..setAttribute('download', fileName)
          ..target = '_blank';
        html.document.body?.append(anchor);
        anchor.click();
        anchor.remove();
        html.Url.revokeObjectUrl(blobUrl);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isCached ? l10n.openingExternalDocument : l10n.downloadCodeSuccess),
              backgroundColor: AppConfig.secondaryColor,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e, stack) {
        debugPrint('>>> [_openDocument] Web download/open error: $e\n$stack');
        html.window.open(url, '_blank');
      }
      return;
    }

    // Native Platforms (Android, iOS, macOS, Windows, Linux)
    try {
      final isAlreadyCached = await _cacheService.isCached(docId, fileName);
      debugPrint('>>> [_openDocument] Native platform: isAlreadyCached=$isAlreadyCached for "$fileName"');

      if (!isAlreadyCached) {
        debugPrint('>>> [_openDocument] Native: Document not cached. Notifying user and starting download...');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.downloadingDocument),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        debugPrint('>>> [_openDocument] Native: Document ALREADY cached. Opening directly from disk without re-downloading.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.openingExternalDocument),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }

      final filePath = await _cacheService.getOrDownloadFilePath(docId, url, fileName);
      debugPrint('>>> [_openDocument] Native: Resolved local file path: "$filePath"');

      if (filePath != null && filePath.isNotEmpty) {
        if (mounted) {
          setState(() {
            _cachedDocIds.add(docId);
          });
        }

        debugPrint('>>> [_openDocument] Invoking OpenFilex.open on "$filePath"...');
        final result = await OpenFilex.open(filePath);
        debugPrint('>>> [_openDocument] OpenFilex response: type=${result.type}, message="${result.message}"');

        if (result.type != ResultType.done) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${l10n.noAppToOpenFile}: ${result.message}'),
                backgroundColor: Colors.orange.shade800,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else {
        debugPrint('>>> [_openDocument] ERROR: filePath was null or empty after cache resolution.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.errorLoadingDocument)),
          );
        }
      }
    } catch (e, stack) {
      debugPrint('>>> [_openDocument] Exception opening document: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorPrefix(e.toString()))),
        );
      }
    }
  }

  // --- Admin Folder & Document Management ---

  void _showCreateFolderDialog() {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.create_new_folder, color: AppConfig.primaryColor),
              const SizedBox(width: 8),
              Text(l10n.newFolder),
            ],
          ),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.folderName,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                Navigator.pop(dialogCtx);

                try {
                  final user = _authService.currentUser;
                  await DatabaseService().addDocument('document_folders', {
                    'name': name,
                    'parentId': _currentFolderId,
                    'createdAt': DbFieldValue.serverTimestamp(),
                    'createdBy': user?.uid ?? '',
                  });

                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(l10n.folderCreated),
                        backgroundColor: AppConfig.secondaryColor,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(l10n.errorPrefix(e.toString()))),
                    );
                  }
                }
              },
              child: Text(l10n.create),
            ),
          ],
        );
      },
    );
  }

  void _uploadDocument() async {
    final l10n = AppLocalizations.of(context)!;
    debugPrint('>>> [_uploadDocument] Triggered. Determining platform file picker...');

    String? selectedFileName;
    Uint8List? rawBytes;
    int? fileSize;

    try {
      if (kIsWeb) {
        debugPrint('>>> [_uploadDocument] Web platform: launching html.FileUploadInputElement...');
        final uploadInput = html.FileUploadInputElement()..accept = '*/*';
        uploadInput.click();

        await uploadInput.onChange.first;
        if (uploadInput.files == null || uploadInput.files!.isEmpty) {
          debugPrint('>>> [_uploadDocument] Web picker: user cancelled or empty.');
          return;
        }

        final file = uploadInput.files!.first;
        selectedFileName = file.name;
        fileSize = file.size;

        final reader = html.FileReader();
        reader.readAsArrayBuffer(file);
        await reader.onLoadEnd.first;

        final result = reader.result;
        if (result != null) {
          if (result is Uint8List) {
            rawBytes = result;
          } else if (result is ByteBuffer) {
            rawBytes = result.asUint8List();
          } else if (result is List<int>) {
            rawBytes = Uint8List.fromList(result);
          }
        }
        debugPrint('>>> [_uploadDocument] Web file read: name="$selectedFileName", bytes=${rawBytes?.length}, size=$fileSize');
      } else {
        debugPrint('>>> [_uploadDocument] Native platform: launching FilePicker...');
        final result = await FilePicker.pickFiles(
          type: FileType.any,
          withData: true,
        );
        debugPrint('>>> [_uploadDocument] FilePicker result: $result (files: ${result?.files.length})');

        if (result == null || result.files.isEmpty) {
          debugPrint('>>> [_uploadDocument] No file selected or picker cancelled.');
          return;
        }

        final file = result.files.first;
        selectedFileName = file.name;
        fileSize = file.size;
        rawBytes = file.bytes;

        if ((rawBytes == null || rawBytes.isEmpty) && file.path != null) {
          debugPrint('>>> [_uploadDocument] Reading bytes from path: ${file.path}');
          rawBytes = await _cacheService.readFileBytesFromDisk(file.path!);
          debugPrint('>>> [_uploadDocument] Read bytes length: ${rawBytes?.length}');
        }
      }
    } catch (e, stack) {
      debugPrint('>>> [_uploadDocument] Exception during file picking: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorPrefix(e.toString()))),
        );
      }
      return;
    }

    if (rawBytes == null || rawBytes.isEmpty || selectedFileName == null) {
      debugPrint('>>> [_uploadDocument] ERROR: File bytes or filename empty.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorLoadingDocument)),
        );
      }
      return;
    }

    final titleController = TextEditingController(text: selectedFileName);
    final availableCategories = _categories.where((c) => c['id'] != 'all').toList();
    if (availableCategories.isEmpty) {
      availableCategories.add({'id': 'general', 'name': 'General'});
    }
    final initialCategory = availableCategories.first['id']!;
    String uploadCategory = initialCategory;
    DateTime publicationDate = DateTime.now();

    if (!mounted) {
      debugPrint('>>> [_uploadDocument] Screen not mounted, aborting modal.');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    debugPrint('>>> [_uploadDocument] Presenting upload metadata dialog...');
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final pubDateStr = '${publicationDate.year}-${publicationDate.month.toString().padLeft(2, '0')}-${publicationDate.day.toString().padLeft(2, '0')}';

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.upload_file, color: AppConfig.primaryColor),
                  const SizedBox(width: 8),
                  Text(l10n.uploadDocumentTitle),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: l10n.documentTitleLabel,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Category Selector
                    DropdownButtonFormField<String>(
                      initialValue: uploadCategory,
                      decoration: InputDecoration(
                        labelText: l10n.categoryLabel,
                        border: const OutlineInputBorder(),
                      ),
                      items: availableCategories.map((cat) {
                        return DropdownMenuItem<String>(
                          value: cat['id'],
                          child: Text(cat['name']!.toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            uploadCategory = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    // Publication Date Picker Row
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: dialogCtx,
                          initialDate: publicationDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            publicationDate = picked;
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.publicationDateLabel,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  pubDateStr,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const Icon(Icons.calendar_month, color: AppConfig.primaryColor),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    debugPrint('>>> [_uploadDocument] Upload cancelled by user.');
                    Navigator.pop(dialogCtx);
                  },
                  child: Text(l10n.cancel),
                ),
                ElevatedButton(
                  onPressed: () async {
                    debugPrint('>>> [_uploadDocument] Confirm upload clicked.');
                    Navigator.pop(dialogCtx);
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text(l10n.uploadingDocument)),
                      );
                    }

                    try {
                      final ext = selectedFileName!.contains('.') ? selectedFileName.split('.').last : 'bin';
                      final storagePath = 'documents/${DateTime.now().millisecondsSinceEpoch}_$selectedFileName';
                      debugPrint('>>> [_uploadDocument] Uploading bytes to Cloud Storage path: $storagePath');
                      final downloadUrl = await StorageService().uploadFile(storagePath, rawBytes!);
                      debugPrint('>>> [_uploadDocument] Storage upload success. URL: $downloadUrl');

                      final user = _authService.currentUser;
                      debugPrint('>>> [_uploadDocument] Saving document in Firestore under folderId: $_currentFolderId');
                      final docId = await DatabaseService().addDocument('documents', {
                        'title': titleController.text.trim(),
                        'fileName': selectedFileName,
                        'fileType': ext.toLowerCase(),
                        'fileSize': fileSize ?? rawBytes.length,
                        'category': uploadCategory,
                        'url': downloadUrl,
                        'storagePath': storagePath,
                        'folderId': _currentFolderId,
                        'publicationDate': publicationDate,
                        'uploadedAt': DbFieldValue.serverTimestamp(),
                        'uploaderUid': user?.uid ?? '',
                      });
                      debugPrint('>>> [_uploadDocument] Firestore document saved with ID: $docId');

                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(l10n.documentUploadedSuccess),
                            backgroundColor: AppConfig.secondaryColor,
                          ),
                        );
                      }
                    } catch (e, stack) {
                      debugPrint('>>> [_uploadDocument] Error saving/uploading document: $e\n$stack');
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(content: Text(l10n.errorPrefix(e.toString()))),
                        );
                      }
                    }
                  },
                  child: Text(l10n.uploadButton),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showChangeDocumentCategoryDialog(Map<String, dynamic> doc) {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final docId = doc['id']?.toString() ?? '';
    final currentDocCategory = doc['category']?.toString() ?? '';
    final availableCategories = _categories.where((c) => c['id'] != 'all').toList();

    if (availableCategories.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.noCategoriesFound)),
      );
      return;
    }

    String selectedCategory = availableCategories.any((c) => c['id']?.toLowerCase() == currentDocCategory.toLowerCase())
        ? availableCategories.firstWhere((c) => c['id']?.toLowerCase() == currentDocCategory.toLowerCase())['id']!
        : availableCategories.first['id']!;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.category_outlined, color: AppConfig.primaryColor),
                  const SizedBox(width: 8),
                  Text(l10n.changeCategory),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    doc['title']?.toString() ?? doc['fileName']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${l10n.selectNewCategory}:',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: availableCategories.map((cat) {
                      return DropdownMenuItem<String>(
                        value: cat['id'],
                        child: Text(cat['name']!.toUpperCase()),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          selectedCategory = val;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text(l10n.cancel),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(dialogCtx);
                    try {
                      await DatabaseService().updateDocument('documents', docId, {
                        'category': selectedCategory,
                        'updatedAt': DbFieldValue.serverTimestamp(),
                      });
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(l10n.documentCategoryChanged),
                            backgroundColor: AppConfig.secondaryColor,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(content: Text(l10n.errorPrefix(e.toString()))),
                        );
                      }
                    }
                  },
                  child: Text(l10n.save),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMoveDocumentDialog(Map<String, dynamic> doc) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final docId = doc['id']?.toString() ?? '';
    final allFolders = await DatabaseService().getCollection('document_folders');

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        String targetFolderId = 'root';

        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.drive_file_move_outlined, color: AppConfig.primaryColor),
                  const SizedBox(width: 8),
                  Text(l10n.moveDocument),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${l10n.selectDestinationFolder}:',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: targetFolderId,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: [
                      DropdownMenuItem(
                        value: 'root',
                        child: Text('/ [${l10n.rootFolder}]'),
                      ),
                      ...allFolders.map((f) {
                        return DropdownMenuItem(
                          value: f['id']?.toString() ?? '',
                          child: Text('/ ${f['name'] ?? ''}'),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          targetFolderId = val;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text(l10n.cancel),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(dialogCtx);
                    try {
                      await DatabaseService().updateDocument('documents', docId, {
                        'folderId': targetFolderId,
                      });
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(l10n.documentMoved),
                            backgroundColor: AppConfig.secondaryColor,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(content: Text(l10n.errorPrefix(e.toString()))),
                        );
                      }
                    }
                  },
                  child: Text(l10n.save),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteDocument(Map<String, dynamic> doc) {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final docId = doc['id']?.toString() ?? '';
    final title = doc['title']?.toString() ?? doc['fileName']?.toString() ?? '';
    final url = doc['url']?.toString() ?? '';
    final fileName = doc['fileName']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.deleteDocumentConfirmation),
        content: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await DatabaseService().deleteDocument('documents', docId);
                if (url.isNotEmpty) {
                  try {
                    await StorageService().deleteFileFromUrl(url);
                  } catch (e) {
                    debugPrint('Storage deletion note: $e');
                  }
                }
                await _cacheService.removeCachedFile(docId, fileName);
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.documentDeleted)),
                  );
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.errorPrefix(e.toString()))),
                  );
                }
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteFolder(String folderId, String folderName) {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.deleteFolderConfirmation),
        content: Text(folderName),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await DatabaseService().deleteDocument('document_folders', folderId);
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.folderDeleted)),
                  );
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.errorPrefix(e.toString()))),
                  );
                }
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  // --- Admin Category Management ---

  void _showManageCategoriesDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: DatabaseService().streamCollection('document_categories'),
          builder: (context, catSnapshot) {
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: DatabaseService().streamCollection('documents'),
              builder: (context, docSnapshot) {
                final categories = catSnapshot.data ?? [];
                final documents = docSnapshot.data ?? [];

                return AlertDialog(
                  title: Row(
                    children: [
                      const Icon(Icons.category, color: AppConfig.primaryColor),
                      const SizedBox(width: 8),
                      Text(l10n.manageCategories),
                    ],
                  ),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _showAddOrEditCategoryDialog(context),
                          icon: const Icon(Icons.add),
                          label: Text(l10n.addCategory),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppConfig.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (categories.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24.0),
                            child: Center(
                              child: Text(
                                l10n.noCategoriesFound,
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),
                          )
                        else
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 300),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: categories.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final cat = categories[index];
                                final catId = cat['id']?.toString() ?? '';
                                final catName = cat['name']?.toString() ?? catId;
                                final docCount = documents.where((d) => (d['category']?.toString().toLowerCase() ?? '') == catId.toLowerCase()).length;

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  title: Text(
                                    catName,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    l10n.itemsCount(docCount),
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 20, color: AppConfig.primaryColor),
                                        tooltip: l10n.editCategory,
                                        onPressed: () => _showAddOrEditCategoryDialog(context, category: cat),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          docCount > 0 ? Icons.delete_forever : Icons.delete_outline,
                                          size: 20,
                                          color: docCount > 0 ? Colors.grey.shade400 : Colors.redAccent,
                                        ),
                                        tooltip: docCount > 0 ? l10n.cannotDeleteCategoryInUseTooltip(docCount) : l10n.deleteCategory,
                                        onPressed: () => _confirmDeleteCategory(context, cat, docCount),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: Text(l10n.cancel),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showAddOrEditCategoryDialog(BuildContext context, {Map<String, dynamic>? category}) {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final isEditing = category != null;
    final nameController = TextEditingController(text: isEditing ? (category['name']?.toString() ?? '') : '');

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            Icon(isEditing ? Icons.edit : Icons.add_circle_outline, color: AppConfig.primaryColor),
            const SizedBox(width: 8),
            Text(isEditing ? l10n.editCategory : l10n.addCategory),
          ],
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: l10n.categoryName,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              Navigator.pop(dialogCtx);

              try {
                if (isEditing) {
                  final catId = category['id']?.toString() ?? '';
                  await DatabaseService().updateDocument('document_categories', catId, {
                    'name': name,
                    'updatedAt': DbFieldValue.serverTimestamp(),
                  });
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(l10n.categoryUpdated),
                        backgroundColor: AppConfig.secondaryColor,
                      ),
                    );
                  }
                } else {
                  final catId = name.toLowerCase().replaceAll(RegExp(r'[^\w]'), '_');
                  await DatabaseService().setDocument('document_categories', catId, {
                    'name': name,
                    'createdAt': DbFieldValue.serverTimestamp(),
                  });
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(l10n.categoryCreated),
                        backgroundColor: AppConfig.secondaryColor,
                      ),
                    );
                  }
                }
              } catch (e) {
                debugPrint('Error saving category: $e');
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.errorPrefix(e.toString()))),
                  );
                }
              }
            },
            child: Text(isEditing ? l10n.save : l10n.create),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteCategory(BuildContext context, Map<String, dynamic> category, int docsCount) {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final catId = category['id']?.toString() ?? '';
    final catName = category['name']?.toString() ?? catId;

    if (docsCount > 0) {
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.block, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Text(l10n.deleteCategory),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(catName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.categoryInUseBlocked(docsCount),
                        style: TextStyle(fontSize: 13, color: Colors.red.shade900, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(l10n.understood),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.deleteCategoryConfirmation),
        content: Text(catName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await DatabaseService().deleteDocument('document_categories', catId);
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.categoryDeleted)),
                  );
                }
              } catch (e) {
                debugPrint('Error deleting category: $e');
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.errorPrefix(e.toString()))),
                  );
                }
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  // --- UI Building ---

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    _initBreadcrumbs(l10n);

    return PopScope(
      canPop: _breadcrumbs.length <= 1,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onWillPop();
      },
      child: Scaffold(
        backgroundColor: AppConfig.backgroundColor,
        appBar: AppBar(
          title: Text(
            l10n.transparencyDocs,
            style: const TextStyle(fontFamily: AppConfig.fontFamily),
          ),
          backgroundColor: AppConfig.primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        body: Column(
          children: [
            // Breadcrumbs Navigation Bar
            FileExplorerBreadcrumb(
              items: _breadcrumbs,
              onItemTap: _onBreadcrumbTap,
            ),

            // Search and Category Filter Bar
            _buildSearchAndFilterBar(context, l10n),

            // File Explorer Content (Folders & Documents)
            Expanded(
              child: _buildExplorerBody(context, l10n),
            ),
          ],
        ),
        floatingActionButton: _isAdmin ? _buildAdminSpeedDial(context, l10n) : null,
      ),
    );
  }

  Widget _buildSearchAndFilterBar(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      color: Colors.white,
      child: Column(
        children: [
          // Search Field
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: l10n.searchDocuments,
              prefixIcon: const Icon(Icons.search, color: AppConfig.primaryColor),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              isDense: true,
            ),
            onChanged: (val) {
              setState(() {
                _searchQuery = val.trim().toLowerCase();
              });
            },
          ),
          const SizedBox(height: 10),

          // Category Dropdown Filter
          Row(
            children: [
              Text(
                '${l10n.filterByCategory}:',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppConfig.textColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCategory,
                      isExpanded: true,
                      items: _categories.map((cat) {
                        return DropdownMenuItem<String>(
                          value: cat['id'],
                          child: Text(cat['name']!.toUpperCase(), style: const TextStyle(fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedCategory = value;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ),
              if (_isAdmin) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, color: AppConfig.primaryColor),
                  tooltip: l10n.manageCategories,
                  onPressed: () => _showManageCategoriesDialog(context),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExplorerBody(BuildContext context, AppLocalizations l10n) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: DatabaseService().streamCollection('document_folders'),
      builder: (context, folderSnapshot) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: DatabaseService().streamCollection('documents'),
          builder: (context, docSnapshot) {
            if (folderSnapshot.connectionState == ConnectionState.waiting ||
                docSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final allFolders = folderSnapshot.data ?? [];
            final allDocs = docSnapshot.data ?? [];
            _checkCachedDocuments(allDocs);

            // Filter folders for current level
            final currentFolders = allFolders.where((f) {
              final parent = f['parentId']?.toString() ?? 'root';
              return parent == _currentFolderId;
            }).toList();

            // Filter documents
            final currentDocs = allDocs.where((doc) {
              // 1. Folder level match (unless global search query is active)
              if (_searchQuery.isEmpty) {
                final folderId = doc['folderId']?.toString() ?? 'root';
                if (folderId != _currentFolderId) return false;
              }

              // 2. Category match
              if (_selectedCategory != 'all') {
                final cat = doc['category']?.toString().toLowerCase() ?? '';
                if (cat != _selectedCategory) return false;
              }

              // 3. Search query match
              if (_searchQuery.isNotEmpty) {
                final title = (doc['title'] ?? '').toString().toLowerCase();
                final fileName = (doc['fileName'] ?? '').toString().toLowerCase();
                final cat = (doc['category'] ?? '').toString().toLowerCase();
                if (!title.contains(_searchQuery) &&
                    !fileName.contains(_searchQuery) &&
                    !cat.contains(_searchQuery)) {
                  return false;
                }
              }

              return true;
            }).toList();

            // Calculate item counts for current folders
            final Map<String, int> folderItemCounts = {};
            for (var f in currentFolders) {
              final fid = f['id']?.toString() ?? '';
              final childDocs = allDocs.where((d) => (d['folderId']?.toString() ?? 'root') == fid).length;
              final childSubfolders = allFolders.where((sub) => (sub['parentId']?.toString() ?? 'root') == fid).length;
              folderItemCounts[fid] = childDocs + childSubfolders;
            }

            if (currentFolders.isEmpty && currentDocs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      l10n.emptyFolder,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }

            final isDesktop = MediaQuery.of(context).size.width >= 900;

            return ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // Folders Section
                if (currentFolders.isNotEmpty) ...[
                  if (isDesktop)
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 3.2,
                      ),
                      itemCount: currentFolders.length,
                      itemBuilder: (context, index) {
                        final folder = currentFolders[index];
                        final fid = folder['id']?.toString() ?? '';
                        final name = folder['name']?.toString() ?? '';
                        return FolderCard(
                          id: fid,
                          name: name,
                          itemCount: folderItemCounts[fid] ?? 0,
                          isAdmin: _isAdmin,
                          onTap: () => _navigateToFolder(fid, name),
                          onDelete: _isAdmin ? () => _confirmDeleteFolder(fid, name) : null,
                        );
                      },
                    )
                  else
                    ...currentFolders.map((folder) {
                      final fid = folder['id']?.toString() ?? '';
                      final name = folder['name']?.toString() ?? '';
                      return FolderCard(
                        id: fid,
                        name: name,
                        itemCount: folderItemCounts[fid] ?? 0,
                        isAdmin: _isAdmin,
                        onTap: () => _navigateToFolder(fid, name),
                        onDelete: _isAdmin ? () => _confirmDeleteFolder(fid, name) : null,
                      );
                    }),
                  const SizedBox(height: 16),
                ],

                // Documents Section
                ...currentDocs.map((doc) {
                  final docId = doc['id']?.toString() ?? '';
                  final title = doc['title']?.toString() ?? '';
                  final fileName = doc['fileName']?.toString() ?? '';
                  final fileType = doc['fileType']?.toString() ?? '';
                  final fileSize = doc['fileSize'] as int?;
                  final categoryId = doc['category']?.toString();
                  final categoryName = categoryId != null && categoryId.isNotEmpty
                      ? (_categories.firstWhere(
                          (c) => c['id']?.toLowerCase() == categoryId.toLowerCase(),
                          orElse: () => {'id': categoryId, 'name': categoryId},
                        )['name'])
                      : null;

                  DateTime? pubDate;
                  final raw = doc['publicationDate'] ?? doc['uploadedAt'] ?? doc['timestamp'];
                  if (raw != null) {
                    if (raw is DateTime) {
                      pubDate = raw;
                    } else if (raw is Map && raw['_seconds'] != null) {
                      pubDate = DateTime.fromMillisecondsSinceEpoch((raw['_seconds'] as int) * 1000);
                    } else if (raw is int) {
                      pubDate = DateTime.fromMillisecondsSinceEpoch(raw);
                    }
                  }

                  return DocumentCard(
                    id: docId,
                    title: title,
                    fileName: fileName,
                    fileType: fileType,
                    fileSize: fileSize,
                    category: categoryName,
                    publicationDate: pubDate,
                    isCached: _cachedDocIds.contains(docId),
                    isAdmin: _isAdmin,
                    onTap: () => _openDocument(context, doc),
                    onChangeCategory: _isAdmin ? () => _showChangeDocumentCategoryDialog(doc) : null,
                    onMove: _isAdmin ? () => _showMoveDocumentDialog(doc) : null,
                    onDelete: _isAdmin ? () => _confirmDeleteDocument(doc) : null,
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAdminSpeedDial(BuildContext context, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.extended(
          heroTag: 'fab_manage_categories',
          onPressed: () {
            debugPrint('>>> [TransparencyScreen] Manage Categories FAB tapped');
            _showManageCategoriesDialog(context);
          },
          icon: const Icon(Icons.category),
          label: Text(l10n.manageCategories),
          backgroundColor: Colors.teal.shade700,
          foregroundColor: Colors.white,
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'fab_create_folder',
          onPressed: () {
            debugPrint('>>> [TransparencyScreen] Create Folder FAB tapped');
            _showCreateFolderDialog();
          },
          icon: const Icon(Icons.create_new_folder),
          label: Text(l10n.newFolder),
          backgroundColor: Colors.amber.shade800,
          foregroundColor: Colors.white,
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'fab_upload_document',
          onPressed: () {
            debugPrint('>>> [TransparencyScreen] Upload Document FAB tapped');
            _uploadDocument();
          },
          icon: const Icon(Icons.upload_file),
          label: Text(l10n.uploadButton),
          backgroundColor: AppConfig.secondaryColor,
          foregroundColor: Colors.white,
        ),
      ],
    );
  }
}
