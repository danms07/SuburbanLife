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
    {'id': 'normatives', 'name': 'NORMATIVES'},
    {'id': 'contracts', 'name': 'CONTRACTS'},
    {'id': 'financial', 'name': 'FINANCIAL'},
    {'id': 'communiques', 'name': 'COMMUNIQUES'},
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
    final isAdmin = await _authService.isAdmin();
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
        loaded.add({
          'id': doc['id']?.toString() ?? '',
          'name': doc['name']?.toString() ?? '',
        });
      }
      if (mounted) {
        setState(() {
          _categories = loaded;
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
        batch.set('document_categories', entry.key, {'name': entry.value});
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

  void _openDocument(BuildContext context, Map<String, dynamic> doc) async {
    final l10n = AppLocalizations.of(context)!;
    final docId = doc['id']?.toString() ?? '';
    final title = doc['title']?.toString() ?? doc['fileName']?.toString() ?? l10n.untitledDocument;
    final fileName = doc['fileName']?.toString() ?? '$title.bin';
    final fileType = (doc['fileType']?.toString() ?? fileName.split('.').last).toLowerCase();
    final url = doc['url']?.toString() ?? '';
    final category = doc['category']?.toString();
    final fileSize = doc['fileSize'] as int?;

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorLoadingDocument)),
      );
      return;
    }

    // 1. Text / Markdown Files -> Native In-App Document Viewer Screen
    if (fileType == 'md' || fileType == 'txt' || fileName.endsWith('.md') || fileName.endsWith('.txt')) {
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
      showInteractiveImageDialog(
        context,
        url,
        title: title,
      );
      return;
    }

    // 3. Binary Files (PDF, DOCX, XLSX, etc.) -> Cache locally & Open via Intent Resolver / Default App
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.openingExternalDocument), duration: const Duration(seconds: 2)),
    );

    if (kIsWeb) {
      html.window.open(url, '_blank');
      return;
    }

    try {
      final filePath = await _cacheService.getOrDownloadFilePath(docId, url, fileName);
      if (filePath != null && filePath.isNotEmpty) {
        setState(() {
          _cachedDocIds.add(docId);
        });

        final result = await OpenFilex.open(filePath);
        if (result.type != ResultType.done) {
          debugPrint('OpenFilex result: ${result.message}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${l10n.noAppToOpenFile}: ${result.message}'),
                backgroundColor: Colors.orange.shade800,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error opening document: $e');
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
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
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
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                final user = _authService.currentUser;
                await DatabaseService().addDocument('document_folders', {
                  'name': name,
                  'parentId': _currentFolderId,
                  'createdAt': DbFieldValue.serverTimestamp(),
                  'createdBy': user?.uid ?? '',
                });

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.folderCreated),
                      backgroundColor: AppConfig.secondaryColor,
                    ),
                  );
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
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final titleController = TextEditingController(text: file.name);
    final initialCategory = _categories.firstWhere((c) => c['id'] != 'all', orElse: () => {'id': 'normatives'})['id']!;
    String uploadCategory = initialCategory;
    DateTime publicationDate = DateTime.now();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                      items: _categories.where((c) => c['id'] != 'all').map((cat) {
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
                          context: context,
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
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancel),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.uploadingDocument)),
                    );

                    try {
                      final ext = file.extension ?? file.name.split('.').last;
                      final storagePath = 'documents/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
                      final downloadUrl = await StorageService().uploadFile(storagePath, file.bytes!);
                      final user = _authService.currentUser;

                      await DatabaseService().addDocument('documents', {
                        'title': titleController.text.trim(),
                        'fileName': file.name,
                        'fileType': ext.toLowerCase(),
                        'fileSize': file.size,
                        'category': uploadCategory,
                        'url': downloadUrl,
                        'storagePath': storagePath,
                        'folderId': _currentFolderId,
                        'publicationDate': publicationDate,
                        'uploadedAt': DbFieldValue.serverTimestamp(),
                        'uploaderUid': user?.uid ?? '',
                      });

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.documentUploadedSuccess),
                            backgroundColor: AppConfig.secondaryColor,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
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

  void _showMoveDocumentDialog(Map<String, dynamic> doc) async {
    final l10n = AppLocalizations.of(context)!;
    final docId = doc['id']?.toString() ?? '';
    final allFolders = await DatabaseService().getCollection('document_folders');

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        String targetFolderId = 'root';

        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancel),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await DatabaseService().updateDocument('documents', docId, {
                      'folderId': targetFolderId,
                    });
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.documentMoved),
                          backgroundColor: AppConfig.secondaryColor,
                        ),
                      );
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
    final docId = doc['id']?.toString() ?? '';
    final title = doc['title']?.toString() ?? doc['fileName']?.toString() ?? '';
    final url = doc['url']?.toString() ?? '';
    final fileName = doc['fileName']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteDocumentConfirmation),
        content: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(context);
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.documentDeleted)),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteFolderConfirmation),
        content: Text(folderName),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await DatabaseService().deleteDocument('document_folders', folderId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.folderDeleted)),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
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
                  final category = doc['category']?.toString();

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
                    category: category,
                    publicationDate: pubDate,
                    isCached: _cachedDocIds.contains(docId),
                    isAdmin: _isAdmin,
                    onTap: () => _openDocument(context, doc),
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
          heroTag: 'fab_create_folder',
          onPressed: _showCreateFolderDialog,
          icon: const Icon(Icons.create_new_folder),
          label: Text(l10n.newFolder),
          backgroundColor: Colors.amber.shade800,
          foregroundColor: Colors.white,
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'fab_upload_document',
          onPressed: _uploadDocument,
          icon: const Icon(Icons.upload_file),
          label: Text(l10n.uploadButton),
          backgroundColor: AppConfig.secondaryColor,
          foregroundColor: Colors.white,
        ),
      ],
    );
  }
}
