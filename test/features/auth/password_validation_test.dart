import 'package:flutter_test/flutter_test.dart';

bool isPasswordValid(String password) {
  if (password.length < 8) return false;
  if (!password.contains(RegExp(r'[A-Z]'))) return false;
  if (!password.contains(RegExp(r'[a-z]'))) return false;
  if (!password.contains(RegExp(r'[0-9]'))) return false;
  return true;
}

void main() {
  group('Auth - Password Complexity Validation', () {
    test('passes on passwords with >=8 characters, uppercase, lowercase, and digit', () {
      expect(isPasswordValid('StrongPass1'), isTrue);
      expect(isPasswordValid('MySecurePass99!'), isTrue);
      expect(isPasswordValid('A1b2C3d4'), isTrue);
    });

    test('fails on passwords shorter than 8 characters even if all character classes present', () {
      expect(isPasswordValid('Abc123!'), isFalse); // 7 chars
      expect(isPasswordValid('A1b'), isFalse);
      expect(isPasswordValid(''), isFalse);
    });

    test('fails when uppercase letter is missing', () {
      expect(isPasswordValid('lowercase12345'), isFalse);
    });

    test('fails when lowercase letter is missing', () {
      expect(isPasswordValid('UPPERCASE12345'), isFalse);
    });

    test('fails when numeric digit is missing', () {
      expect(isPasswordValid('NoNumbersHere!'), isFalse);
    });

    test('handles whitespace and special symbols correctly without breaking requirements', () {
      expect(isPasswordValid('Pass word 123'), isTrue);
      expect(isPasswordValid('@#\$%^&*()A1b'), isTrue);
    });
  });
}
