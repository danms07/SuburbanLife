import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';

void main() {
  group('Auth - Firebase Auth Password Complexity Policy Validation', () {
    test('passes on valid passwords meeting all 4 character classes and >=8 length', () {
      expect(PasswordValidator.isValid('StrongPass1!'), isTrue);
      expect(PasswordValidator.isValid('MySecurePass99!'), isTrue);
      expect(PasswordValidator.isValid('A1b2C3d4#'), isTrue);
      expect(PasswordValidator.isValid('SecretPass123!'), isTrue);
      expect(PasswordValidator.isValid('P@ssword1'), isTrue);
      expect(PasswordValidator.isValid('@#\$%^&*()A1b'), isTrue);
    });

    test('fails on passwords shorter than 8 characters even if all classes present', () {
      expect(PasswordValidator.isValid('Abc12!'), isFalse); // 6 chars
      expect(PasswordValidator.isValid('Abc123!'), isFalse); // 7 chars
      expect(PasswordValidator.isValid('A1b!'), isFalse);
      expect(PasswordValidator.isValid(''), isFalse);
      expect(PasswordValidator.isValid(null), isFalse);
    });

    test('fails when special character is missing', () {
      expect(PasswordValidator.isValid('StrongPass1'), isFalse);
      expect(PasswordValidator.isValid('A1b2C3d4'), isFalse);
      expect(PasswordValidator.isValid('Password123'), isFalse);
    });

    test('fails when uppercase letter is missing', () {
      expect(PasswordValidator.isValid('lowercase12345!'), isFalse);
    });

    test('fails when lowercase letter is missing', () {
      expect(PasswordValidator.isValid('UPPERCASE12345!'), isFalse);
    });

    test('fails when numeric digit is missing', () {
      expect(PasswordValidator.isValid('NoNumbersHere!'), isFalse);
    });

    test('fails when password exceeds 4096 characters', () {
      final longPassword = 'A1b!${'a' * 4100}';
      expect(PasswordValidator.isValid(longPassword), isFalse);
    });
  });
}
