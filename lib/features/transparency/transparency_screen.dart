import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_service.dart';

class TransparencyScreen extends StatefulWidget {
  const TransparencyScreen({Key? key}) : super(key: key);

  @override
  _TransparencyScreenState createState() => _TransparencyScreenState();
}

class _TransparencyScreenState extends State<TransparencyScreen> {
  final AuthService _authService = AuthService();
  bool _isAdmin = false;
  String _selectedCategory = 'all';
  List<Map<String, String>> _categories = [
    {'id': 'all', 'name': 'ALL'},
    {'id': 'normatives', 'name': 'NORMATIVES'},
    {'id': 'contracts', 'name': 'CONTRACTS'},
    {'id': 'communiques', 'name': 'COMMUNIQUES'},
  ];

  @override
  void initState() {
    super.initState();
    _checkAdmin();
    _listenToCategories();
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
      'communiques': 'Communiques',
    };
    await DatabaseService().runBatch((batch) async {
      for (var entry in defaults.entries) {
        batch.set('document_categories', entry.key, {'name': entry.value});
      }
    });
  }

  void _showAddCategoryDialog() {
    final l10n = AppLocalizations.of(context)!;
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.addCategoryTitle),
          content: TextField(
            controller: nameController,
            decoration: InputDecoration(labelText: l10n.categoryNameLabel),
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
                final id = name.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
                await DatabaseService().setDocument('document_categories', id, {
                  'name': name,
                });
                if (mounted) Navigator.pop(context);
              },
              child: Text(l10n.create),
            ),
          ],
        );
      },
    );
  }

  void _checkAdmin() async {
    final isAdmin = await _authService.isAdmin();
    setState(() {
      _isAdmin = isAdmin;
    });
  }

  void _uploadDocument() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final titleController = TextEditingController(text: file.name);
    final initialCategory = _categories.firstWhere((c) => c['id'] != 'all', orElse: () => {'id': 'normatives'})['id']!;
    String uploadCategory = initialCategory;
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.uploadDocumentTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(labelText: l10n.documentTitleLabel),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: uploadCategory,
                decoration: InputDecoration(labelText: l10n.categoryLabel),
                items: _categories.where((c) => c['id'] != 'all').map((cat) {
                  return DropdownMenuItem<String>(
                    value: cat['id'],
                    child: Text(cat['name']!.toUpperCase()),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    uploadCategory = value;
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
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.uploadingDocument)),
                );

                try {
                  final path = 'documents/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
                  final downloadUrl = await StorageService().uploadFile(path, file.bytes!);

                  await DatabaseService().addDocument('documents', {
                    'title': titleController.text.trim(),
                    'category': uploadCategory,
                    'url': downloadUrl,
                    'timestamp': DbFieldValue.serverTimestamp(),
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.documentUploadedSuccess),
                      backgroundColor: AppConfig.secondaryColor,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              },
              child: Text(l10n.uploadButton),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final List<QueryFilter> filters = [];
    if (_selectedCategory != 'all') {
      filters.add(QueryFilter('category', FilterOperator.equal, _selectedCategory));
    }

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(l10n.transparencyDocs, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            color: AppConfig.backgroundColor,
            child: Row(
              children: [
                Text(
                  l10n.filterByCategory,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontFamily: AppConfig.fontFamily,
                    color: AppConfig.textColor,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    items: _categories.map((cat) {
                      return DropdownMenuItem<String>(
                        value: cat['id'],
                        child: Text(cat['name']!.toUpperCase()),
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
                if (_isAdmin) ...[
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const Icon(Icons.add_box, color: AppConfig.primaryColor),
                    tooltip: l10n.addCategoryTitle,
                    onPressed: _showAddCategoryDialog,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: DatabaseService().streamCollection('documents', filters: filters),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(child: Text(l10n.noDocuments));
                }
                return ListView.builder(
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final doc = snapshot.data![index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                      elevation: 2,
                      child: ListTile(
                        leading: const Icon(Icons.description, color: AppConfig.primaryColor),
                        title: Text(doc['title'] ?? l10n.untitledDocument, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Builder(
                          builder: (context) {
                            final catId = doc['category'] as String? ?? '';
                            final catMap = _categories.firstWhere((c) => c['id'] == catId, orElse: () => {'name': catId.toUpperCase()});
                            final catName = catMap['name']!;
                            return Text('${l10n.categoryLabel}: ${catName.toUpperCase()}');
                          },
                        ),
                        trailing: const Icon(Icons.download, color: AppConfig.secondaryColor),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.downloadingDocument),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          )
        ],
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton(
              onPressed: _uploadDocument,
              backgroundColor: AppConfig.secondaryColor,
              child: const Icon(Icons.upload_file, color: Colors.white),
            )
          : null,
    );
  }
}
