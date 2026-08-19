import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';

void main() {
  group('Backend Models - AppUser & AuthResult', () {
    test('AppUser initializes with required and optional properties', () {
      final user = AppUser(
        uid: 'user_123',
        email: 'user@example.com',
        displayName: 'John Resident',
      );

      expect(user.uid, equals('user_123'));
      expect(user.email, equals('user@example.com'));
      expect(user.displayName, equals('John Resident'));
    });

    test('AuthResult instantiates with success and error states', () {
      final user = AppUser(uid: 'u_1');
      final success = AuthResult(user: user, isSuccess: true);
      expect(success.isSuccess, isTrue);
      expect(success.user?.uid, equals('u_1'));
      expect(success.errorMessage, isNull);

      final failure = AuthResult(isSuccess: false, errorMessage: 'Invalid credentials');
      expect(failure.isSuccess, isFalse);
      expect(failure.user, isNull);
      expect(failure.errorMessage, equals('Invalid credentials'));
    });
  });

  group('Backend Models - DbFieldValue Factories', () {
    test('serverTimestamp factory creates serverTimestamp type', () {
      final fieldVal = DbFieldValue.serverTimestamp();
      expect(fieldVal.type, equals(DbFieldValueType.serverTimestamp));
      expect(fieldVal.value, isNull);
    });

    test('arrayUnion factory creates arrayUnion type with list elements', () {
      final fieldVal = DbFieldValue.arrayUnion(['item1', 'item2']);
      expect(fieldVal.type, equals(DbFieldValueType.arrayUnion));
      expect(fieldVal.value, equals(['item1', 'item2']));
    });

    test('arrayRemove factory creates arrayRemove type with list elements', () {
      final fieldVal = DbFieldValue.arrayRemove(['item_del']);
      expect(fieldVal.type, equals(DbFieldValueType.arrayRemove));
      expect(fieldVal.value, equals(['item_del']));
    });

    test('delete factory creates delete type', () {
      final fieldVal = DbFieldValue.delete();
      expect(fieldVal.type, equals(DbFieldValueType.delete));
      expect(fieldVal.value, isNull);
    });
  });

  group('Backend Models - StringDbReference', () {
    test('equality and hashCode are based on id', () {
      final ref1 = StringDbReference('addr_01', path: 'addresses/addr_01');
      final ref2 = StringDbReference('addr_01', path: 'addresses/addr_01');
      final ref3 = StringDbReference('addr_02', path: 'addresses/addr_02');

      expect(ref1 == ref2, isTrue);
      expect(ref1.hashCode, equals(ref2.hashCode));
      expect(ref1 == ref3, isFalse);
    });

    test('toString returns the document id', () {
      final ref = StringDbReference('doc_99', path: 'coll/doc_99');
      expect(ref.toString(), equals('doc_99'));
      expect(ref.id, equals('doc_99'));
      expect(ref.path, equals('coll/doc_99'));
    });
  });

  group('Backend Models - QueryFilter and QuerySort', () {
    test('QueryFilter holds field, operator, and value', () {
      final filter = QueryFilter('status', FilterOperator.equal, 'active');
      expect(filter.field, equals('status'));
      expect(filter.operator, equals(FilterOperator.equal));
      expect(filter.value, equals('active'));
    });

    test('QuerySort defaults descending to false', () {
      final sortAsc = QuerySort('createdAt');
      expect(sortAsc.field, equals('createdAt'));
      expect(sortAsc.descending, isFalse);

      final sortDesc = QuerySort('timestamp', descending: true);
      expect(sortDesc.descending, isTrue);
    });
  });
}
