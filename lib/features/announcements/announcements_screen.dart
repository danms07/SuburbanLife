import 'dart:async';
import 'dart:ui' as ui;
import 'dart:js_util' as js_util;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:universal_html/html.dart' as html;
import '../../core/backend/backend.dart';
import 'package:suburban_life/core/config/app_config.dart';
import 'package:suburban_life/core/widgets/interactive_image_dialog.dart';
import 'package:suburban_life/core/widgets/storage_network_image.dart';
import 'package:suburban_life/features/announcements/announcement.dart';
import 'package:suburban_life/l10n/app_localizations.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final AuthService _authService = AuthService();
  final ImagePicker _picker = ImagePicker();

  bool _isAdmin = false;
  bool _isResident = false;
  bool _isLoading = true;
  String _currentLang = 'es'; // Default to Spanish

  // Curated list of high-relevance announcement emojis
  static const List<String> _quickEmojis = [
    '📢', '🚨', '⚠️', 'ℹ️', '🔔', '📅', '🎉', '🛠️', '💡', '💧',
    '⚡', '🚗', '🏡', '🏊', '🌳', '🗑️', '🔒', '📌', '✅', '❌',
  ];

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  void _checkAdmin() async {
    final isAdmin = await _authService.isAdmin();
    final isResident = await _authService.isResident();
    if (mounted) {
      setState(() {
        _isAdmin = isAdmin;
        _isResident = isResident;
        _isLoading = false;
      });
    }
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

  /// Generates a proportionally scaled thumbnail supporting both horizontal and vertical orientations
  Future<Uint8List> _generateThumbnail(Uint8List originalBytes, {int maxDimension = 600}) async {
    try {
      final codec = await ui.instantiateImageCodec(originalBytes);
      final frameInfo = await codec.getNextFrame();
      final image = frameInfo.image;
      final int width = image.width;
      final int height = image.height;

      if (width <= maxDimension && height <= maxDimension) {
        return originalBytes;
      }

      int targetWidth;
      int targetHeight;

      if (width >= height) {
        // Horizontal (landscape) or square
        targetWidth = maxDimension;
        targetHeight = ((height * maxDimension) / width).round();
      } else {
        // Vertical (portrait)
        targetHeight = maxDimension;
        targetWidth = ((width * maxDimension) / height).round();
      }

      final scaledCodec = await ui.instantiateImageCodec(
        originalBytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final scaledFrame = await scaledCodec.getNextFrame();
      final byteData = await scaledFrame.image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        return byteData.buffer.asUint8List();
      }
    } catch (e) {
      debugPrint('Thumbnail generation error: $e');
    }
    return originalBytes;
  }

  /// Reads image bytes from system clipboard (Web and cross-platform)
  Future<Uint8List?> _getClipboardImageBytes() async {
    if (kIsWeb) {
      try {
        final nav = html.window.navigator;
        final clipboard = js_util.getProperty(nav, 'clipboard');
        if (clipboard != null) {
          final promise = js_util.callMethod(clipboard, 'read', []);
          final dynamic items = await js_util.promiseToFuture(promise);
          final dynamic rawLen = js_util.getProperty(items, 'length');
          final int length = (rawLen is num) ? rawLen.toInt() : 0;
          for (int i = 0; i < length; i++) {
            final item = js_util.callMethod(items, 'item', [i]) ?? js_util.getProperty(items, i.toString());
            final dynamic types = js_util.getProperty(item, 'types');
            final dynamic rawTypesLen = js_util.getProperty(types, 'length');
            final int typesLength = (rawTypesLen is num) ? rawTypesLen.toInt() : 0;
            for (int j = 0; j < typesLength; j++) {
              final String type = (js_util.callMethod(types, 'item', [j]) ?? js_util.getProperty(types, j.toString())).toString();
              if (type.startsWith('image/')) {
                final dynamic blobPromise = js_util.callMethod(item, 'getType', [type]);
                final html.Blob blob = await js_util.promiseToFuture(blobPromise);
                final reader = html.FileReader();
                reader.readAsArrayBuffer(blob);
                await reader.onLoadEnd.first;
                return Uint8List.fromList(reader.result as List<int>);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Clipboard read error: $e');
      }
    }
    return null;
  }

  Widget _buildAnnouncementBody(
    Announcement announcement,
    String title,
    String content,
    String audienceText,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: Audience Badge + Date
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: announcement.targetAudience == 'residents'
                    ? AppConfig.primaryColor.withValues(alpha: 0.1)
                    : AppConfig.secondaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    announcement.targetAudience == 'residents'
                        ? Icons.home_outlined
                        : Icons.public,
                    size: 14,
                    color: announcement.targetAudience == 'residents'
                        ? AppConfig.primaryColor
                        : AppConfig.secondaryColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    audienceText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: announcement.targetAudience == 'residents'
                          ? AppConfig.primaryColor
                          : AppConfig.secondaryColor,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              announcement.timestamp.toString().substring(0, 10),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Title with emoji support
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: AppConfig.fontFamily,
            color: AppConfig.primaryColor,
          ),
        ),
        const SizedBox(height: 8),

        // Content with emoji and multiline support
        Text(
          content,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black87,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDesktop = MediaQuery.sizeOf(context).width >= 600;

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
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.campaign_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text(
                    l10n.noAnnouncements,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _markAnnouncementsAsRead(allowedDocs);
          });

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12),
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

              final displayImageUrl = (announcement.thumbnailUrl ?? announcement.imageUrl)?.trim();
              final fullImageUrl = (announcement.imageUrl ?? announcement.thumbnailUrl)?.trim();
              final hasImage = displayImageUrl != null && displayImageUrl.isNotEmpty;
              final audienceText = announcement.targetAudience == 'residents'
                  ? l10n.audienceResidents
                  : l10n.audienceAll;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    elevation: 2,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: hasImage
                          ? () => showInteractiveImageDialog(context, fullImageUrl!, title: title)
                          : null,
                      child: isDesktop && hasImage
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left Column: Thumbnail on Desktop
                                Container(
                                  width: 220,
                                  height: 180,
                                  color: Colors.grey.withValues(alpha: 0.08),
                                  child: Center(
                                    child: StorageNetworkImage(
                                      imageUrl: displayImageUrl,
                                      width: 220,
                                      height: 180,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                                // Right Column: Content on Desktop
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: _buildAnnouncementBody(announcement, title, content, audienceText),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Top: Thumbnail on Mobile
                                if (hasImage)
                                  Container(
                                    width: double.infinity,
                                    constraints: const BoxConstraints(maxHeight: 240),
                                    color: Colors.grey.withValues(alpha: 0.08),
                                    child: Center(
                                      child: StorageNetworkImage(
                                        imageUrl: displayImageUrl,
                                        width: double.infinity,
                                        height: 220,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),

                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: _buildAnnouncementBody(announcement, title, content, audienceText),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _showCreateDialog,
              backgroundColor: AppConfig.secondaryColor,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(l10n.createAnnouncement),
            )
          : null,
    );
  }

  void _showCreateDialog() {
    final l10n = AppLocalizations.of(context)!;
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final titleFocusNode = FocusNode();
    final contentFocusNode = FocusNode();

    String selectedAudience = 'all';
    Uint8List? selectedImageBytes;
    String? selectedImageName;
    bool isUploading = false;
    TextEditingController activeController = contentController;
    StreamSubscription? pasteSubscription;

    // Track active text controller for emoji insertion
    titleFocusNode.addListener(() {
      if (titleFocusNode.hasFocus) activeController = titleController;
    });
    contentFocusNode.addListener(() {
      if (contentFocusNode.hasFocus) activeController = contentController;
    });

    void insertEmoji(String emoji, void Function(void Function()) setStateDialog) {
      final text = activeController.text;
      final selection = activeController.selection;
      if (selection.start >= 0 && selection.end >= 0) {
        final newText = text.replaceRange(selection.start, selection.end, emoji);
        activeController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: selection.start + emoji.length),
        );
      } else {
        activeController.text = '$text$emoji';
      }
      setStateDialog(() {});
    }

    void handlePastedBytes(Uint8List bytes, void Function(void Function()) setStateDialog) {
      setStateDialog(() {
        selectedImageBytes = bytes;
        selectedImageName = 'clipboard_${DateTime.now().millisecondsSinceEpoch}.png';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.imagePastedSuccess),
            backgroundColor: AppConfig.secondaryColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }

    Future<void> pasteFromClipboard(void Function(void Function()) setStateDialog) async {
      try {
        final bytes = await _getClipboardImageBytes();
        if (bytes != null && bytes.isNotEmpty) {
          handlePastedBytes(bytes, setStateDialog);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.noImageInClipboard),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Error pasting image: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.noImageInClipboard),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }

    showDialog(
      context: context,
      barrierDismissible: !isUploading,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            // Attach document paste listener on Web
            if (kIsWeb && pasteSubscription == null) {
              pasteSubscription = html.document.onPaste.listen((html.ClipboardEvent event) async {
                final items = event.clipboardData?.items;
                if (items != null) {
                  final int count = items.length ?? 0;
                  for (int i = 0; i < count; i++) {
                    final item = items[i];
                    if (item.type?.startsWith('image/') == true) {
                      final file = item.getAsFile();
                      if (file != null) {
                        final reader = html.FileReader();
                        reader.readAsArrayBuffer(file);
                        await reader.onLoadEnd.first;
                        final bytes = Uint8List.fromList(reader.result as List<int>);
                        handlePastedBytes(bytes, setStateDialog);
                        break;
                      }
                    }
                  }
                }
              });
            }

            return CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () => pasteFromClipboard(setStateDialog),
                const SingleActivator(LogicalKeyboardKey.keyV, control: true): () => pasteFromClipboard(setStateDialog),
              },
              child: Focus(
                autofocus: true,
                child: AlertDialog(
                  title: Row(
                    children: [
                      const Icon(Icons.campaign, color: AppConfig.primaryColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.createAnnouncement,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  content: SizedBox(
                    width: 480,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title TextField
                          TextField(
                            controller: titleController,
                            focusNode: titleFocusNode,
                            decoration: InputDecoration(
                              labelText: l10n.titleSpanish,
                              prefixIcon: const Icon(Icons.title, size: 20),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Content TextField
                          TextField(
                            controller: contentController,
                            focusNode: contentFocusNode,
                            decoration: InputDecoration(
                              labelText: l10n.contentSpanish,
                              alignLabelWithHint: true,
                              prefixIcon: const Padding(
                                padding: EdgeInsets.only(bottom: 50),
                                child: Icon(Icons.article_outlined, size: 20),
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            maxLines: 4,
                          ),
                          const SizedBox(height: 12),

                          // Quick Emoji Bar
                          Row(
                            children: [
                              const Icon(Icons.emoji_emotions_outlined, size: 16, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                l10n.emojisLabel,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                              ),
                              const Spacer(),
                              Text(
                                l10n.insertEmojiHint,
                                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _quickEmojis.length,
                              itemBuilder: (context, index) {
                                final emoji = _quickEmojis[index];
                                return InkWell(
                                  onTap: () => insertEmoji(emoji, setStateDialog),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    child: Center(
                                      child: Text(
                                        emoji,
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Image Attachment Preview / Selector Actions
                          if (selectedImageBytes != null)
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppConfig.secondaryColor.withValues(alpha: 0.5)),
                                borderRadius: BorderRadius.circular(10),
                                color: AppConfig.secondaryColor.withValues(alpha: 0.05),
                              ),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.memory(
                                      selectedImageBytes!,
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          selectedImageName ?? 'image.png',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        Text(
                                          '${(selectedImageBytes!.lengthInBytes / 1024).toStringAsFixed(1)} KB',
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.redAccent),
                                    tooltip: l10n.removeImage,
                                    onPressed: () {
                                      setStateDialog(() {
                                        selectedImageBytes = null;
                                        selectedImageName = null;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            )
                          else
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () async {
                                        try {
                                          final picked = await _picker.pickImage(
                                            source: ImageSource.gallery,
                                            imageQuality: 85,
                                          );
                                          if (picked != null) {
                                            final bytes = await picked.readAsBytes();
                                            setStateDialog(() {
                                              selectedImageBytes = bytes;
                                              selectedImageName = picked.name;
                                            });
                                          }
                                        } catch (e) {
                                          debugPrint('Image pick error: $e');
                                        }
                                      },
                                      icon: const Icon(Icons.add_photo_alternate_outlined),
                                      label: Text(l10n.attachImage),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppConfig.primaryColor,
                                        side: const BorderSide(color: AppConfig.primaryColor),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () => pasteFromClipboard(setStateDialog),
                                      icon: const Icon(Icons.content_paste_go_outlined),
                                      label: Text(l10n.pasteFromClipboard),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppConfig.secondaryColor,
                                        side: const BorderSide(color: AppConfig.secondaryColor),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  l10n.pasteImageHint,
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
                                ),
                              ],
                            ),
                          const SizedBox(height: 16),

                          // Target Audience Dropdown
                          DropdownButtonFormField<String>(
                            initialValue: selectedAudience,
                            decoration: InputDecoration(
                              labelText: l10n.targetAudienceLabel,
                              prefixIcon: const Icon(Icons.people_outline, size: 20),
                              border: const OutlineInputBorder(),
                            ),
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

                          if (isUploading) ...[
                            const SizedBox(height: 16),
                            const LinearProgressIndicator(),
                          ],
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: isUploading
                          ? null
                          : () {
                              pasteSubscription?.cancel();
                              Navigator.pop(dialogContext);
                            },
                      child: Text(l10n.cancel),
                    ),
                    ElevatedButton(
                      onPressed: isUploading
                          ? null
                          : () async {
                              final title = titleController.text.trim();
                              final content = contentController.text.trim();

                              if (title.isEmpty || content.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(l10n.fillRequiredFields),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                return;
                              }

                              final user = AuthService().currentUser;
                              if (user == null) return;

                              setStateDialog(() {
                                isUploading = true;
                              });

                              String? uploadedImageUrl;
                              String? uploadedThumbnailUrl;

                              try {
                                // Upload image and generated thumbnail if attached
                                if (selectedImageBytes != null) {
                                  final timestamp = DateTime.now().millisecondsSinceEpoch;
                                  
                                  // 1. Generate proportional thumbnail (horizontal or vertical)
                                  final thumbBytes = await _generateThumbnail(selectedImageBytes!);

                                  // 2. Upload full resolution image
                                  final fullPath = 'announcements/${timestamp}_full.jpg';
                                  uploadedImageUrl = await StorageService().uploadFile(
                                    fullPath,
                                    selectedImageBytes!,
                                    contentType: 'image/jpeg',
                                    metadata: {'uploaderUid': user.uid},
                                  );

                                  // 3. Upload thumbnail
                                  final thumbPath = 'announcements/${timestamp}_thumb.png';
                                  uploadedThumbnailUrl = await StorageService().uploadFile(
                                    thumbPath,
                                    thumbBytes,
                                    contentType: 'image/png',
                                    metadata: {'uploaderUid': user.uid},
                                  );
                                }

                                // Save announcement to Firestore
                                await DatabaseService().addDocument('announcements', {
                                  'title': title,
                                  'content': content,
                                  'imageUrl': uploadedImageUrl,
                                  'thumbnailUrl': uploadedThumbnailUrl,
                                  'creatorUid': user.uid,
                                  'timestamp': DbFieldValue.serverTimestamp(),
                                  'translatedTitles': {},
                                  'translatedContents': {},
                                  'targetAudience': selectedAudience,
                                  'readBy': [],
                                });

                                pasteSubscription?.cancel();

                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }

                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(l10n.announcementCreatedSuccess),
                                      backgroundColor: AppConfig.secondaryColor,
                                    ),
                                  );
                                }
                              } catch (e) {
                                debugPrint('Error publishing announcement: $e');
                                setStateDialog(() {
                                  isUploading = false;
                                });
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(l10n.imageUploadError(e.toString())),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConfig.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(l10n.create),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      pasteSubscription?.cancel();
    });
  }
}
