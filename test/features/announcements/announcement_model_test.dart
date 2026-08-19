import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/features/announcements/announcement.dart';

void main() {
  group('Announcement Model', () {
    final fixedDate = DateTime(2026, 8, 18, 14, 30);

    test('toMap serializes all properties correctly', () {
      final announcement = Announcement(
        id: 'ann_1',
        title: 'Mantenimiento del Parque',
        content: 'El parque estará cerrado el viernes.',
        imageUrl: 'https://storage/full.jpg',
        thumbnailUrl: 'https://storage/thumb.jpg',
        translatedTitles: {'en': 'Park Maintenance'},
        translatedContents: {'en': 'The park will be closed on Friday.'},
        creatorUid: 'admin_uid',
        timestamp: fixedDate,
        targetUserUid: 'resident_uid_1',
        targetAudience: 'residents',
      );

      final map = announcement.toMap();

      expect(map['title'], equals('Mantenimiento del Parque'));
      expect(map['content'], equals('El parque estará cerrado el viernes.'));
      expect(map['imageUrl'], equals('https://storage/full.jpg'));
      expect(map['thumbnailUrl'], equals('https://storage/thumb.jpg'));
      expect(map['translatedTitles'], equals({'en': 'Park Maintenance'}));
      expect(map['translatedContents'], equals({'en': 'The park will be closed on Friday.'}));
      expect(map['creatorUid'], equals('admin_uid'));
      expect(map['timestamp'], equals(fixedDate));
      expect(map['targetUserUid'], equals('resident_uid_1'));
      expect(map['targetAudience'], equals('residents'));
    });

    test('fromMap parses DateTime instance timestamp', () {
      final map = {
        'title': 'Aviso',
        'content': 'Contenido',
        'creatorUid': 'admin_1',
        'timestamp': fixedDate,
      };

      final result = Announcement.fromMap('ann_id', map);
      expect(result.id, equals('ann_id'));
      expect(result.title, equals('Aviso'));
      expect(result.timestamp, equals(fixedDate));
      expect(result.targetAudience, equals('all'));
    });

    test('fromMap parses ISO string timestamp', () {
      final map = {
        'title': 'Aviso ISO',
        'content': 'Contenido ISO',
        'creatorUid': 'admin_1',
        'timestamp': '2026-08-18T14:30:00.000',
      };

      final result = Announcement.fromMap('ann_iso', map);
      expect(result.timestamp.year, equals(2026));
      expect(result.timestamp.month, equals(8));
      expect(result.timestamp.day, equals(18));
    });

    test('fromMap falls back to DateTime.now() when timestamp is missing or malformed', () {
      final before = DateTime.now();
      final map = {
        'title': 'Aviso Sin Fecha',
        'content': 'Contenido',
        'creatorUid': 'admin_1',
        'timestamp': 'invalid-date-string-xyz',
      };

      final result = Announcement.fromMap('ann_fallback', map);
      final after = DateTime.now();

      expect(result.timestamp.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(result.timestamp.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('fromMap defaults thumbnailUrl to imageUrl when thumbnailUrl is null', () {
      final map = {
        'title': 'Aviso Imagen',
        'content': 'Contenido',
        'imageUrl': 'https://storage/full_image.jpg',
        'thumbnailUrl': null,
        'creatorUid': 'admin_1',
      };

      final result = Announcement.fromMap('ann_img', map);
      expect(result.imageUrl, equals('https://storage/full_image.jpg'));
      expect(result.thumbnailUrl, equals('https://storage/full_image.jpg'));
    });

    test('fromMap handles empty translation maps safely', () {
      final map = {
        'title': 'Aviso',
        'content': 'Contenido',
        'creatorUid': 'admin_1',
        'translatedTitles': null,
        'translatedContents': null,
      };

      final result = Announcement.fromMap('ann_trans', map);
      expect(result.translatedTitles, isEmpty);
      expect(result.translatedContents, isEmpty);
    });
  });
}
