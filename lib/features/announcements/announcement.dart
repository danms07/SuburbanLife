
class Announcement {
  final String id;
  final String title; // Original title (usually Spanish)
  final String content; // Original content (usually Spanish)
  final String? imageUrl; // Optional image URL for visual announcements
  final Map<String, String> translatedTitles; // e.g., {'en': 'Hello'}
  final Map<String, String> translatedContents; // e.g., {'en': 'Content in English'}
  final String creatorUid;
  final DateTime timestamp;
  final String? targetUserUid; // Null if for all users
  final String targetAudience; // 'all' | 'residents'

  Announcement({
    required this.id,
    required this.title,
    required this.content,
    this.imageUrl,
    this.translatedTitles = const {},
    this.translatedContents = const {},
    required this.creatorUid,
    required this.timestamp,
    this.targetUserUid,
    this.targetAudience = 'all',
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'content': content,
      'imageUrl': imageUrl,
      'translatedTitles': translatedTitles,
      'translatedContents': translatedContents,
      'creatorUid': creatorUid,
      'timestamp': timestamp,
      'targetUserUid': targetUserUid,
      'targetAudience': targetAudience,
    };
  }

  factory Announcement.fromMap(String id, Map<String, dynamic> map) {
    DateTime parsedTimestamp = DateTime.now();
    final rawTs = map['timestamp'];
    if (rawTs is DateTime) {
      parsedTimestamp = rawTs;
    } else if (rawTs != null) {
      try {
        parsedTimestamp = DateTime.parse(rawTs.toString());
      } catch (_) {}
    }

    return Announcement(
      id: id,
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      imageUrl: map['imageUrl'] as String?,
      translatedTitles: Map<String, String>.from(map['translatedTitles'] ?? {}),
      translatedContents: Map<String, String>.from(map['translatedContents'] ?? {}),
      creatorUid: map['creatorUid'] ?? '',
      timestamp: parsedTimestamp,
      targetUserUid: map['targetUserUid'] as String?,
      targetAudience: map['targetAudience'] as String? ?? 'all',
    );
  }
}
