import 'package:flutter/foundation.dart';

class AppUser {
  final String uid;
  final String? email;
  final String? displayName;

  AppUser({
    required this.uid,
    this.email,
    this.displayName,
  });
}

class AuthResult {
  final AppUser? user;
  final String? errorMessage;
  final bool isSuccess;

  AuthResult({
    this.user,
    this.errorMessage,
    this.isSuccess = false,
  });
}

enum FilterOperator {
  equal,
  notEqual,
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  arrayContains,
  isNull,
}

class QueryFilter {
  final String field;
  final FilterOperator operator;
  final dynamic value;

  QueryFilter(this.field, this.operator, this.value);
}

class QuerySort {
  final String field;
  final bool descending;

  QuerySort(this.field, {this.descending = false});
}

enum DbFieldValueType {
  serverTimestamp,
  arrayUnion,
  arrayRemove,
  delete,
}

class DbFieldValue {
  final DbFieldValueType type;
  final dynamic value;

  DbFieldValue._(this.type, this.value);

  factory DbFieldValue.serverTimestamp() => DbFieldValue._(DbFieldValueType.serverTimestamp, null);
  factory DbFieldValue.arrayUnion(List<dynamic> elements) => DbFieldValue._(DbFieldValueType.arrayUnion, elements);
  factory DbFieldValue.arrayRemove(List<dynamic> elements) => DbFieldValue._(DbFieldValueType.arrayRemove, elements);
  factory DbFieldValue.delete() => DbFieldValue._(DbFieldValueType.delete, null);
}

abstract class DbReference {
  String get id;
  String get path;
}

class StringDbReference implements DbReference {
  @override
  final String id;
  @override
  final String path;

  StringDbReference(this.id, {this.path = ''});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DbReference && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => id;
}

abstract class DbBatch {
  void set(String collection, String docId, Map<String, dynamic> data);
  void update(String collection, String docId, Map<String, dynamic> data);
  void delete(String collection, String docId);
  Future<void> commit();
}

abstract class AuthService {
  factory AuthService() => Backend.auth;

  Stream<AppUser?> get userStream;
  AppUser? get currentUser;

  Future<AppUser?> signIn(String email, String password);
  Future<AppUser?> signUp(String email, String password, {String? name});
  Future<bool> sendPasswordReset(String email);
  Future<void> signOut();
  Future<bool> isAdmin();
  Future<bool> isGuard();
  Future<bool> isResident();
}

abstract class DatabaseService {
  factory DatabaseService() => Backend.db;

  Future<Map<String, dynamic>?> getDocument(String collection, String docId);
  Stream<Map<String, dynamic>?> streamDocument(String collection, String docId);
  Stream<List<Map<String, dynamic>>> streamCollection(String collection, {List<QueryFilter>? filters, List<QuerySort>? sorts});
  Future<List<Map<String, dynamic>>> getCollection(String collection, {List<QueryFilter>? filters, List<QuerySort>? sorts});
  Future<void> setDocument(String collection, String docId, Map<String, dynamic> data);
  Future<String> addDocument(String collection, Map<String, dynamic> data);
  Future<void> updateDocument(String collection, String docId, Map<String, dynamic> data);
  Future<void> deleteDocument(String collection, String docId);
  Future<void> runBatch(Future<void> Function(DbBatch batch) action);
  DbReference createReference(String collection, String docId);
  dynamic toRawValue(dynamic value);
}

abstract class StorageService {
  factory StorageService() => Backend.storage;

  Future<String> uploadFile(String path, dynamic fileData, {String? contentType, Map<String, String>? metadata});
  Future<String> getDownloadUrl(String path);
  Future<void> deleteFileFromUrl(String url);
}

abstract class FunctionsService {
  factory FunctionsService() => Backend.functions;

  Future<dynamic> callFunction(String name, [Map<String, dynamic>? parameters]);
}

class Backend {
  static AuthService get auth => _auth;
  static DatabaseService get db => _db;
  static StorageService get storage => _storage;
  static FunctionsService get functions => _functions;

  static late AuthService _auth;
  static late DatabaseService _db;
  static late StorageService _storage;
  static late FunctionsService _functions;

  static void initialize({
    required AuthService auth,
    required DatabaseService db,
    required StorageService storage,
    required FunctionsService functions,
  }) {
    _auth = auth;
    _db = db;
    _storage = storage;
    _functions = functions;
  }
}
