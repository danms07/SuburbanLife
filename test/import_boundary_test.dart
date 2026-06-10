import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Enforce BaaS Abstraction layer import boundaries', () {
    final featuresDir = Directory('lib/features');
    expect(featuresDir.existsSync(), true, reason: 'lib/features directory should exist');

    final forbiddenImports = [
      'package:cloud_firestore/cloud_firestore.dart',
      'package:firebase_auth/firebase_auth.dart',
      'package:firebase_storage/firebase_storage.dart',
      'package:cloud_functions/cloud_functions.dart',
    ];

    final dartFiles = featuresDir
        .listSync(recursive: true)
        .where((entity) => entity is File && entity.path.endsWith('.dart'))
        .cast<File>();

    final violations = <String>[];

    for (final file in dartFiles) {
      final lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('import ') || line.startsWith('export ')) {
          for (final forbidden in forbiddenImports) {
            if (line.contains(forbidden)) {
              violations.add('${file.path}:${i + 1} - imports $forbidden directly');
            }
          }
        }
      }
    }

    if (violations.isNotEmpty) {
      fail(
        'Direct Firebase SDK imports found in lib/features/. '
        'All features must use the BaaS Abstraction layer (lib/core/backend/backend.dart) instead.\n'
        'Violations found:\n'
        '${violations.join('\n')}'
      );
    }
  });
}
