
class Announcement {
  final String id;
  final String title; // Original title (usually Spanish)
  final String content; // Original content (usually Spanish)
  final Map<String, String> translatedTitles; // e.g., {'en': 'Hello'}
  final Map<String, String> translatedContents; // e.g., {'en': 'Content in English'}
  final String creatorUid;
  final DateTime timestamp;
  final String? targetUserUid; // Null if for all users

  Announcement({
    required this.id,
    required this.title,
    required this.content,
    this.translatedTitles = const {},
    this.translatedContents = const {},
    required this.creatorUid,
    required this.timestamp,
    this.targetUserUid,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'content': content,
      'translatedTitles': translatedTitles,
      'translatedContents': translatedContents,
      'creatorUid': creatorUid,
      'timestamp': timestamp,
      'targetUserUid': targetUserUid,
    };
  }

  factory Announcement.fromMap(String id, Map<String, dynamic> map) {
    return Announcement(
      id: id,
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      translatedTitles: Map<String, String>.from(map['translatedTitles'] ?? {}),
      translatedContents: Map<String, String>.from(map['translatedContents'] ?? {}),
      creatorUid: map['creatorUid'] ?? '',
      timestamp: map['timestamp'] as DateTime? ?? DateTime.now(),
      targetUserUid: map['targetUserUid'],
    );
  }
}
