import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Scans [source] for `DropdownButtonFormField` invocations that pass the deprecated
/// top-level `value:` named argument (ignoring nested `DropdownMenuItem(value: ...)`).
List<int> findDeprecatedDropdownFormFieldValueLines(String source) {
  final violations = <int>[];
  final headerRegex = RegExp(r'DropdownButtonFormField(?:\s*<[^>]*>)?\s*\(');

  for (final match in headerRegex.allMatches(source)) {
    int depth = 1;
    int i = match.end;
    int argStart = i;

    while (i < source.length && depth > 0) {
      final ch = source[i];
      if (ch == '(' || ch == '[' || ch == '{') {
        depth++;
      } else if (ch == ')' || ch == ']' || ch == '}') {
        if (depth == 1 && ch == ')') {
          final segment = source.substring(argStart, i);
          if (RegExp(r'^\s*value\s*:').hasMatch(segment)) {
            final lineNum = '\n'.allMatches(source.substring(0, argStart)).length + 1;
            violations.add(lineNum);
          }
        }
        depth--;
      } else if (ch == ',' && depth == 1) {
        final segment = source.substring(argStart, i);
        if (RegExp(r'^\s*value\s*:').hasMatch(segment)) {
          final lineNum = '\n'.allMatches(source.substring(0, argStart)).length + 1;
          violations.add(lineNum);
        }
        argStart = i + 1;
      }
      i++;
    }
  }
  return violations;
}

void main() {
  group('Architectural Boundary & AGENTS.md Quality Rules', () {
    test('Enforce BaaS Abstraction layer import boundaries in lib/features/', () {
      final featuresDir = Directory('lib/features');
      expect(featuresDir.existsSync(), true, reason: 'lib/features directory should exist');

      final forbiddenImports = [
        'package:cloud_firestore/cloud_firestore.dart',
        'package:firebase_auth/firebase_auth.dart',
        'package:firebase_storage/firebase_storage.dart',
        'package:cloud_functions/cloud_functions.dart',
        'package:firebase_crashlytics/firebase_crashlytics.dart',
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
          '${violations.join('\n')}',
        );
      }
    });

    test('Enforce zero raw print() calls in lib/ (debugPrint required)', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), true);

      final dartFiles = libDir
          .listSync(recursive: true)
          .where((entity) => entity is File && entity.path.endsWith('.dart'))
          .cast<File>();

      final printRegex = RegExp(r'(?<!debug)print\s*\(');
      final violations = <String>[];

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('//') || line.startsWith('/*') || line.startsWith('*')) continue;
          if (printRegex.hasMatch(line)) {
            violations.add('${file.path}:${i + 1} - contains raw print(): "$line"');
          }
        }
      }

      if (violations.isNotEmpty) {
        fail(
          'Raw print() statements found in lib/. Always use debugPrint() instead.\n'
          'Violations found:\n'
          '${violations.join('\n')}',
        );
      }
    });

    test('Enforce zero deprecated .withOpacity() calls in lib/ (use .withValues() instead)', () {
      final libDir = Directory('lib');
      final dartFiles = libDir
          .listSync(recursive: true)
          .where((entity) => entity is File && entity.path.endsWith('.dart'))
          .cast<File>();

      final violations = <String>[];
      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('//') || line.startsWith('/*') || line.startsWith('*')) continue;
          if (line.contains('.withOpacity(')) {
            violations.add('${file.path}:${i + 1} - uses deprecated .withOpacity(): "$line"');
          }
        }
      }

      if (violations.isNotEmpty) {
        fail(
          'Deprecated .withOpacity() calls found in lib/. Use .withValues(alpha: ...) instead.\n'
          'Violations found:\n'
          '${violations.join('\n')}',
        );
      }
    });

    test('Enforce initialValue instead of deprecated value: in DropdownButtonFormField across lib/', () {
      // Self-test parser helper to prevent silent false negatives
      expect(
        findDeprecatedDropdownFormFieldValueLines(
          'DropdownButtonFormField<String>(value: x, items: [DropdownMenuItem(value: "a", child: Text("a"))])',
        ),
        isNotEmpty,
      );
      expect(
        findDeprecatedDropdownFormFieldValueLines(
          'DropdownButtonFormField<String>(initialValue: x, items: [DropdownMenuItem(value: "a", child: Text("a"))])',
        ),
        isEmpty,
      );

      final libDir = Directory('lib');
      final dartFiles = libDir
          .listSync(recursive: true)
          .where((entity) => entity is File && entity.path.endsWith('.dart'))
          .cast<File>();

      final violations = <String>[];
      for (final file in dartFiles) {
        final source = file.readAsStringSync();
        final badLines = findDeprecatedDropdownFormFieldValueLines(source);
        for (final line in badLines) {
          violations.add('${file.path}:$line - DropdownButtonFormField uses deprecated value: instead of initialValue:');
        }
      }

      if (violations.isNotEmpty) {
        fail(
          'Deprecated value: parameter used in DropdownButtonFormField. Use initialValue: instead.\n'
          'Violations found:\n'
          '${violations.join('\n')}',
        );
      }
    });

    test('Enforce exact English and Spanish localization key parity (app_en.arb vs app_es.arb)', () {
      final enFile = File('lib/l10n/app_en.arb');
      final esFile = File('lib/l10n/app_es.arb');
      expect(enFile.existsSync(), isTrue, reason: 'lib/l10n/app_en.arb must exist');
      expect(esFile.existsSync(), isTrue, reason: 'lib/l10n/app_es.arb must exist');

      final enMap = jsonDecode(enFile.readAsStringSync()) as Map<String, dynamic>;
      final esMap = jsonDecode(esFile.readAsStringSync()) as Map<String, dynamic>;

      final enKeys = enMap.keys.where((k) => !k.startsWith('@')).toSet();
      final esKeys = esMap.keys.where((k) => !k.startsWith('@')).toSet();

      final missingInSpanish = enKeys.difference(esKeys).toList()..sort();
      final missingInEnglish = esKeys.difference(enKeys).toList()..sort();

      expect(
        missingInSpanish,
        isEmpty,
        reason: 'Every UI key in app_en.arb must have a Spanish translation in app_es.arb. Missing: $missingInSpanish',
      );
      expect(
        missingInEnglish,
        isEmpty,
        reason: 'Every UI key in app_es.arb must have an English counterpart in app_en.arb. Missing: $missingInEnglish',
      );
    });
  });
}
