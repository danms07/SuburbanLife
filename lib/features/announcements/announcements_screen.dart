import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import 'package:suburban_life/core/config/app_config.dart';
import 'package:suburban_life/features/announcements/announcement.dart';
import 'package:suburban_life/features/auth/auth_service.dart';
import 'package:suburban_life/l10n/app_localizations.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final AuthService _authService = AuthService();
  bool _isAdmin = false;
  bool _isResident = false;
  bool _isGuard = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  void _checkAdmin() async {
    final isAdmin = await _authService.isAdmin();
    final isResident = await _authService.isResident();
    final isGuard = await _authService.isGuard();
    setState(() {
      _isAdmin = isAdmin;
      _isResident = isResident;
      _isGuard = isGuard;
      _isLoading = false;
    });
  }

  void _markAnnouncementsAsRead(List<Map<String, dynamic>> docs) {
    final user = AuthService().currentUser;
    if (user == null) return;
    final uid = user.uid;

    for (var doc in docs) {
      final readBy = List<String>.from(doc['readBy'] ?? []);
      if (!readBy.contains(uid)) {
        final docId = doc['id'] as String;
        DatabaseService().updateDocument('announcements', docId, {
          'readBy': DbFieldValue.arrayUnion([uid])
        });
      }
    }
  }

  String _currentLang = 'es'; // Default to Spanish

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.announcements),
          backgroundColor: AppConfig.primaryColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Detect locale
    final locale = Localizations.localeOf(context);
    _currentLang = locale.languageCode;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.announcements),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: DatabaseService().streamCollection(
          'announcements',
          sorts: [QuerySort('timestamp', descending: true)],
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(l10n.errorAnnouncements));
          }
          final allDocs = snapshot.data ?? [];
          final allowedDocs = allDocs.where((doc) {
            final targetAudience = doc['targetAudience'] ?? 'all';
            
            if (targetAudience == 'all') return true;
            if (targetAudience == 'admin' && _isAdmin) return true;
            if (targetAudience == 'residents' && (_isResident || _isAdmin)) return true;
            
            return false;
          }).toList();

          if (allowedDocs.isEmpty) {
            return Center(child: Text(l10n.noAnnouncements));
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _markAnnouncementsAsRead(allowedDocs);
          });

          return ListView.builder(
            itemCount: allowedDocs.length,
            itemBuilder: (context, index) {
              final data = allowedDocs[index];
              final announcement = Announcement.fromMap(data['id'] ?? '', data);

              // Determine which title and content to show
              String title = announcement.title;
              String content = announcement.content;

              if (_currentLang != 'es') {
                title = announcement.translatedTitles[_currentLang] ?? announcement.title;
                content = announcement.translatedContents[_currentLang] ?? announcement.content;
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(content),
                  trailing: Text(
                    announcement.timestamp.toString().substring(0, 10),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton(
              onPressed: () {
                _showCreateDialog();
              },
              backgroundColor: AppConfig.secondaryColor,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _showCreateDialog() {
    final l10n = AppLocalizations.of(context)!;
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    String selectedAudience = 'all';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(l10n.createAnnouncement),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(labelText: l10n.titleSpanish),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: contentController,
                    decoration: InputDecoration(labelText: l10n.contentSpanish),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedAudience,
                    decoration: InputDecoration(labelText: l10n.targetAudienceLabel),
                    items: [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(l10n.audienceAll),
                      ),
                      DropdownMenuItem(
                        value: 'residents',
                        child: Text(l10n.audienceResidents),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setStateDialog(() {
                          selectedAudience = val;
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
                    final user = AuthService().currentUser;
                    if (user == null) return;

                    await DatabaseService().addDocument('announcements', {
                      'title': titleController.text.trim(),
                      'content': contentController.text.trim(),
                      'creatorUid': user.uid,
                      'timestamp': DbFieldValue.serverTimestamp(),
                      'translatedTitles': {},
                      'translatedContents': {},
                      'targetAudience': selectedAudience,
                      'readBy': [],
                    });
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(l10n.create),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
