import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

List<String> splitCsvLine(String line) {
  final List<String> cells = [];
  final StringBuffer buffer = StringBuffer();
  bool inQuotes = false;

  for (int i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      inQuotes = !inQuotes;
    } else if (char == ',' && !inQuotes) {
      cells.add(cleanCell(buffer.toString()));
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  cells.add(cleanCell(buffer.toString()));
  return cells;
}

String cleanCell(String val) {
  String trimmed = val.trim();
  if (trimmed.startsWith('"') && trimmed.endsWith('"') && trimmed.length >= 2) {
    trimmed = trimmed.substring(1, trimmed.length - 1).trim();
  }
  return trimmed;
}

List<Map<String, String>> parseUserCsv(String csvContent) {
  final List<Map<String, String>> result = [];
  final lines = const LineSplitter().convert(csvContent);
  if (lines.isEmpty) return result;

  int nameCol = -1;
  int emailCol = -1;
  int passwordCol = -1;
  int streetCol = -1;
  int numberCol = -1;

  final firstRowCells = splitCsvLine(lines[0]);
  final lowerHeaders = firstRowCells.map((c) => c.toLowerCase().trim()).toList();

  for (int i = 0; i < lowerHeaders.length; i++) {
    final h = lowerHeaders[i];
    if (h == 'name' || h == 'nombre' || h == 'full_name' || h == 'fullname' || h == 'display_name') {
      nameCol = i;
    } else if (h == 'email' || h == 'correo' || h == 'email_address') {
      emailCol = i;
    } else if (h == 'password' || h == 'contraseña' || h == 'contrasena' || h == 'pass') {
      passwordCol = i;
    } else if (h == 'street' || h == 'street_name' || h == 'calle' || h == 'streetname') {
      streetCol = i;
    } else if (h == 'number' || h == 'house_number' || h == 'numero' || h == 'número' || h == 'housenumber') {
      numberCol = i;
    }
  }

  int startIndex = 1;
  if (nameCol == -1 && emailCol == -1) {
    startIndex = 0;
    nameCol = 0;
    emailCol = 1;
    passwordCol = 2;
    streetCol = 3;
    numberCol = 4;
  }

  for (int i = startIndex; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;

    final cells = splitCsvLine(line);
    String name = nameCol >= 0 && nameCol < cells.length ? cells[nameCol] : '';
    String email = emailCol >= 0 && emailCol < cells.length ? cells[emailCol] : '';
    String password = passwordCol >= 0 && passwordCol < cells.length ? cells[passwordCol] : '';
    String street = streetCol >= 0 && streetCol < cells.length ? cells[streetCol] : '';
    String number = numberCol >= 0 && numberCol < cells.length ? cells[numberCol] : '';

    if (name.isNotEmpty && email.contains('@')) {
      result.add({
        'name': name,
        'email': email,
        'password': password,
        'streetName': street,
        'number': number,
      });
    }
  }

  return result;
}

String generateResultCsvString(List<Map<String, dynamic>> results) {
  final buffer = StringBuffer();
  buffer.writeln('name,email,password,street,number,status,assigned_password,email_sent,error');

  for (var r in results) {
    final name = (r['name'] ?? '').toString().replaceAll('"', '""');
    final email = (r['email'] ?? '').toString().replaceAll('"', '""');
    final inputPass = (r['password'] ?? '').toString().replaceAll('"', '""');
    final street = (r['streetName'] ?? '').toString().replaceAll('"', '""');
    final numStr = (r['number'] ?? '').toString().replaceAll('"', '""');
    final status = (r['status'] ?? '').toString().replaceAll('"', '""');
    final assignedPass = (r['assignedPassword'] ?? '').toString().replaceAll('"', '""');
    final emailSent = (r['emailSent'] == true) ? 'yes' : 'no';
    final error = (r['error'] ?? '').toString().replaceAll('"', '""');

    buffer.writeln('"$name","$email","$inputPass","$street","$numStr","$status","$assignedPass","$emailSent","$error"');
  }

  return buffer.toString();
}

void main() {
  group('Bulk User Import - CSV Parser & Formatter', () {
    test('parses standard English header CSV', () {
      const csv = 'name,email,password,street,number\n'
          'John Doe,john.doe@example.com,Pass123!,Oak St,10\n'
          'Jane Smith,jane.smith@example.com,,Pine St,20\n';

      final users = parseUserCsv(csv);

      expect(users.length, equals(2));
      expect(users[0]['name'], equals('John Doe'));
      expect(users[0]['email'], equals('john.doe@example.com'));
      expect(users[0]['password'], equals('Pass123!'));
      expect(users[0]['streetName'], equals('Oak St'));
      expect(users[0]['number'], equals('10'));

      expect(users[1]['name'], equals('Jane Smith'));
      expect(users[1]['password'], isEmpty);
    });

    test('parses Spanish header aliases (nombre, correo, contraseña, calle, número)', () {
      const csv = 'Nombre,Correo,Contraseña,Calle,Número\n'
          'Carlos Santana,carlos@musica.com,Guitar#1,Avenida Sol,100\n';

      final users = parseUserCsv(csv);

      expect(users.length, equals(1));
      expect(users[0]['name'], equals('Carlos Santana'));
      expect(users[0]['email'], equals('carlos@musica.com'));
      expect(users[0]['password'], equals('Guitar#1'));
      expect(users[0]['streetName'], equals('Avenida Sol'));
      expect(users[0]['number'], equals('100'));
    });

    test('parses headerless CSV with default positional columns', () {
      const csv = 'Alice Resident,alice@test.com,SecPass89,Maple Ave,42\n'
          'Bob Resident,bob@test.com,,Elm St,99\n';

      final users = parseUserCsv(csv);

      expect(users.length, equals(2));
      expect(users[0]['name'], equals('Alice Resident'));
      expect(users[0]['email'], equals('alice@test.com'));
      expect(users[0]['password'], equals('SecPass89'));
      expect(users[0]['streetName'], equals('Maple Ave'));
      expect(users[0]['number'], equals('42'));
    });

    test('correctly handles quoted fields containing commas', () {
      const csv = 'name,email,password,street,number\n'
          '"Doe, John Jr.",john.jr@example.com,Pass123!,"1st Avenue, North",50\n';

      final users = parseUserCsv(csv);

      expect(users.length, equals(1));
      expect(users[0]['name'], equals('Doe, John Jr.'));
      expect(users[0]['streetName'], equals('1st Avenue, North'));
      expect(users[0]['number'], equals('50'));
    });

    test('filters out invalid rows with empty names or missing @ in email', () {
      const csv = 'name,email,password,street,number\n'
          ',missingname@test.com,Pass123!,Oak St,10\n'
          'Invalid Email,invalid-email-address,Pass123!,Oak St,10\n'
          'Valid User,valid@test.com,Pass123!,Oak St,10\n';

      final users = parseUserCsv(csv);

      expect(users.length, equals(1));
      expect(users[0]['name'], equals('Valid User'));
    });

    test('generateResultCsvString compiles and escapes result rows', () {
      final results = [
        {
          'name': 'John "Johnny" Doe',
          'email': 'john@test.com',
          'password': '',
          'streetName': 'Oak St',
          'number': '10',
          'status': 'ok',
          'assignedPassword': 'AutoPass987!',
          'emailSent': true,
          'error': null,
        }
      ];

      final csvOut = generateResultCsvString(results);

      expect(csvOut, contains('"John ""Johnny"" Doe"'));
      expect(csvOut, contains('"john@test.com"'));
      expect(csvOut, contains('"ok"'));
      expect(csvOut, contains('"AutoPass987!"'));
      expect(csvOut, contains('"yes"'));
    });
  });
}
