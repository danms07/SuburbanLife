import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

List<String> splitAddressCsvLine(String line, [String delimiter = ',']) {
  final List<String> cells = [];
  final StringBuffer buffer = StringBuffer();
  bool inQuotes = false;

  for (int i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      inQuotes = !inQuotes;
    } else if (char == delimiter && !inQuotes) {
      cells.add(cleanAddressCell(buffer.toString()));
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  cells.add(cleanAddressCell(buffer.toString()));
  return cells;
}

String cleanAddressCell(String val) {
  String trimmed = val.trim();
  if (trimmed.startsWith('"') && trimmed.endsWith('"') && trimmed.length >= 2) {
    trimmed = trimmed.substring(1, trimmed.length - 1).trim();
  }
  return trimmed;
}

List<Map<String, dynamic>> parseAddressCsvContent(String content) {
  String cleanedContent = content;
  if (cleanedContent.startsWith('\uFEFF')) {
    cleanedContent = cleanedContent.substring(1);
  }

  final rawLines = const LineSplitter().convert(cleanedContent);
  final lines = rawLines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) return [];

  final firstLine = lines.first;
  String delimiter = ',';
  if (!firstLine.contains(',') && firstLine.contains(';')) {
    delimiter = ';';
  } else if (!firstLine.contains(',') && firstLine.contains('\t')) {
    delimiter = '\t';
  }

  int streetCol = -1;
  int initNumCol = -1;
  int finalNumCol = -1;
  int numCol = -1;
  int exclCol = -1;

  final firstRowCells = splitAddressCsvLine(lines[0], delimiter);
  final lowerHeaders = firstRowCells.map((c) => c.toLowerCase().trim()).toList();

  for (int i = 0; i < lowerHeaders.length; i++) {
    final h = lowerHeaders[i];
    if (h == 'street' || h == 'streetname' || h == 'street_name' || h == 'calle' || h == 'nombre_calle' || h == 'address' || h == 'direccion' || h == 'dirección') {
      streetCol = i;
    } else if (h == 'initialnumber' || h == 'initial_number' || h == 'initial' || h == 'start' || h == 'start_number' || h == 'from' || h == 'numero_inicial' || h == 'numeroinicial' || h == 'desde' || h == 'inicio') {
      initNumCol = i;
    } else if (h == 'finalnumber' || h == 'final_number' || h == 'final' || h == 'end' || h == 'end_number' || h == 'to' || h == 'numero_final' || h == 'numerofinal' || h == 'hasta' || h == 'fin') {
      finalNumCol = i;
    } else if (h == 'number' || h == 'house_number' || h == 'numero' || h == 'número' || h == 'no' || h == 'num') {
      numCol = i;
    } else if (h == 'exclusions' || h == 'exclusion' || h == 'exclusiones' || h == 'excluidos' || h == 'except' || h == 'excepto' || h == 'omit') {
      exclCol = i;
    }
  }

  int startIndex = 1;
  if (streetCol == -1 && initNumCol == -1 && numCol == -1) {
    startIndex = 0;
    streetCol = 0;
    initNumCol = 1;
    finalNumCol = 2;
    exclCol = 3;
  }

  final List<Map<String, dynamic>> items = [];

  for (int i = startIndex; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;

    final cells = splitAddressCsvLine(line, delimiter);
    if (cells.isEmpty) continue;

    String street = streetCol >= 0 && streetCol < cells.length ? cells[streetCol] : '';
    if (street.isEmpty && cells.isNotEmpty) {
      street = cells[0];
    }

    int initialNum = 0;
    int finalNum = 0;
    String exclusions = '';

    if (initNumCol >= 0 && initNumCol < cells.length && finalNumCol >= 0 && finalNumCol < cells.length) {
      initialNum = int.tryParse(cells[initNumCol].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      finalNum = int.tryParse(cells[finalNumCol].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    } else if (numCol >= 0 && numCol < cells.length) {
      initialNum = int.tryParse(cells[numCol].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      finalNum = initialNum;
    } else if (cells.length >= 3) {
      initialNum = int.tryParse(cells[1].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      finalNum = int.tryParse(cells[2].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    } else if (cells.length == 2) {
      initialNum = int.tryParse(cells[1].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      finalNum = initialNum;
    }

    if (exclCol >= 0 && exclCol < cells.length) {
      exclusions = cells[exclCol];
    } else if (cells.length >= 4) {
      exclusions = cells[3];
    }

    if (street.isNotEmpty && initialNum > 0 && finalNum > 0) {
      items.add({
        'streetName': street,
        'initialNumber': initialNum,
        'finalNumber': finalNum,
        'exclusions': exclusions,
      });
    }
  }

  return items;
}

int calculateTotalAddressCount(List<Map<String, dynamic>> parsedItems) {
  int total = 0;
  for (final item in parsedItems) {
    final initN = item['initialNumber'] as int? ?? 0;
    final finN = item['finalNumber'] as int? ?? 0;
    final exclStr = item['exclusions']?.toString() ?? '';

    int exclCount = 0;
    if (exclStr.isNotEmpty) {
      final exclList = exclStr
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .where((n) => n != null && n >= math.min(initN, finN) && n <= math.max(initN, finN))
          .toSet();
      exclCount = exclList.length;
    }

    final rangeCount = (finN - initN).abs() + 1;
    total += (rangeCount - exclCount).clamp(0, rangeCount);
  }
  return total;
}

void main() {
  group('Bulk Address Import - CSV Parser & Counter', () {
    test('parses address ranges with exclusions and standard headers', () {
      const csv = 'streetName,initialNumber,finalNumber,exclusions\n'
          '"Avenida Olmos",1,50,"12,14"\n'
          '"Calle Robles",10,30,""\n';

      final items = parseAddressCsvContent(csv);

      expect(items.length, equals(2));
      expect(items[0]['streetName'], equals('Avenida Olmos'));
      expect(items[0]['initialNumber'], equals(1));
      expect(items[0]['finalNumber'], equals(50));
      expect(items[0]['exclusions'], equals('12,14'));

      expect(items[1]['streetName'], equals('Calle Robles'));
      expect(items[1]['initialNumber'], equals(10));
      expect(items[1]['finalNumber'], equals(30));
    });

    test('strips UTF-8 BOM character from the beginning of file content', () {
      const csvWithBom = '\uFEFFstreetName,initialNumber,finalNumber,exclusions\n'
          'Paseo del Valle,100,105,""\n';

      final items = parseAddressCsvContent(csvWithBom);
      expect(items.length, equals(1));
      expect(items[0]['streetName'], equals('Paseo del Valle'));
    });

    test('auto-detects semicolon delimiter', () {
      const csvSemicolon = 'calle;desde;hasta;exclusiones\n'
          'Calle Real;1;10;5\n';

      final items = parseAddressCsvContent(csvSemicolon);
      expect(items.length, equals(1));
      expect(items[0]['streetName'], equals('Calle Real'));
      expect(items[0]['initialNumber'], equals(1));
      expect(items[0]['finalNumber'], equals(10));
      expect(items[0]['exclusions'], equals('5'));
    });

    test('calculateTotalAddressCount accurately calculates total excluding filtered house numbers', () {
      final items = [
        {
          'streetName': 'Avenida Olmos',
          'initialNumber': 1,
          'finalNumber': 10,
          'exclusions': '2, 4, 99', // 99 is outside 1-10 range and should be ignored
        },
        {
          'streetName': 'Calle Roble',
          'initialNumber': 20,
          'finalNumber': 25,
          'exclusions': '',
        },
      ];

      final total = calculateTotalAddressCount(items);
      // Item 1: (10 - 1 + 1) - 2 (2 and 4) = 8
      // Item 2: (25 - 20 + 1) - 0 = 6
      // Total = 14
      expect(total, equals(14));
    });
  });
}
