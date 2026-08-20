import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'backend.dart';

class FirebaseDbReference implements DbReference {
  final DocumentReference rawRef;
  FirebaseDbReference(this.rawRef);

  @override
  String get id => rawRef.id;

  @override
  String get path => rawRef.path;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DbReference && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => id;
}

class FirebaseDbBatch implements DbBatch {
  final WriteBatch _batch;
  FirebaseDbBatch(this._batch);

  @override
  void set(String collection, String docId, Map<String, dynamic> data) {
    final docRef = FirebaseFirestore.instance.collection(collection).doc(docId);
    _batch.set(docRef, _mapData(data));
  }

  @override
  void update(String collection, String docId, Map<String, dynamic> data) {
    final docRef = FirebaseFirestore.instance.collection(collection).doc(docId);
    _batch.update(docRef, _mapData(data));
  }

  @override
  void delete(String collection, String docId) {
    final docRef = FirebaseFirestore.instance.collection(collection).doc(docId);
    _batch.delete(docRef);
  }

  @override
  Future<void> commit() => _batch.commit();
}

dynamic _mapValue(dynamic value) {
  if (value == null) return null;
  if (value is DbFieldValue) {
    switch (value.type) {
      case DbFieldValueType.serverTimestamp:
        return FieldValue.serverTimestamp();
      case DbFieldValueType.arrayUnion:
        return FieldValue.arrayUnion((value.value as List).map(_mapValue).toList());
      case DbFieldValueType.arrayRemove:
        return FieldValue.arrayRemove((value.value as List).map(_mapValue).toList());
      case DbFieldValueType.delete:
        return FieldValue.delete();
    }
  }
  if (value is FirebaseDbReference) {
    return value.rawRef;
  }
  if (value is StringDbReference) {
    if (value.path.isNotEmpty) {
      return FirebaseFirestore.instance.doc(value.path);
    }
    return value.id;
  }
  if (value is Map<String, dynamic>) {
    return value.map((k, v) => MapEntry(k, _mapValue(v)));
  }
  if (value is List) {
    return value.map(_mapValue).toList();
  }
  return value;
}

Map<String, dynamic> _mapData(Map<String, dynamic> data) {
  return data.map((k, v) => MapEntry(k, _mapValue(v)));
}

dynamic _unmapValue(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DocumentReference) {
    return FirebaseDbReference(value);
  }
  if (value is Map<String, dynamic>) {
    return value.map((k, v) => MapEntry(k, _unmapValue(v)));
  }
  if (value is List) {
    return value.map(_unmapValue).toList();
  }
  return value;
}

Map<String, dynamic> _unmapData(Map<String, dynamic> data) {
  return data.map((k, v) => MapEntry(k, _unmapValue(v)));
}

class FirebaseAuthService implements AuthService {
  final fb_auth.FirebaseAuth _auth = fb_auth.FirebaseAuth.instance;

  AppUser? _mapUser(fb_auth.User? fbUser) {
    if (fbUser == null) {
      Backend.crashlytics.setUserIdentifier('');
      return null;
    }
    Backend.crashlytics.setUserIdentifier(fbUser.uid);
    return AppUser(
      uid: fbUser.uid,
      email: fbUser.email,
      displayName: fbUser.displayName,
    );
  }

  @override
  Stream<AppUser?> get userStream => _auth.authStateChanges().map(_mapUser);

  @override
  AppUser? get currentUser => _mapUser(_auth.currentUser);

  @override
  Future<AppUser?> signIn(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(email: email, password: password);
      return _mapUser(credential.user);
    } catch (e) {
      debugPrint('Sign in error: $e');
      return null;
    }
  }

  @override
  Future<AppUser?> signUp(String email, String password, {String? name}) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      final user = credential.user;
      if (user != null && name != null) {
        await Backend.db.setDocument('users', user.uid, {
          'uid': user.uid,
          'name': name,
          'email': email,
          'role': 'resident',
          'addressRef': null,
          'familyMembers': [],
        });
      }
      return _mapUser(user);
    } catch (e) {
      debugPrint('Sign up error: $e');
      return null;
    }
  }

  @override
  Future<bool> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return true;
    } catch (e) {
      debugPrint('Password reset error: $e');
      return false;
    }
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
  }

  @override
  Future<bool> isAdmin() async {
    final user = _auth.currentUser;
    if (user != null) {
      final idTokenResult = await user.getIdTokenResult(true);
      return idTokenResult.claims?['admin'] == true;
    }
    return false;
  }

  @override
  Future<bool> isGuard() async {
    final user = _auth.currentUser;
    if (user != null) {
      final idTokenResult = await user.getIdTokenResult(true);
      final hasClaim = idTokenResult.claims?['guard'] == true;
      final isGuardEmail = user.email?.toLowerCase().contains('guard') == true;
      return hasClaim || isGuardEmail;
    }
    return false;
  }

  @override
  Future<bool> isResident() async {
    final user = _auth.currentUser;
    if (user != null) {
      if (await isGuard()) return false;
      final idTokenResult = await user.getIdTokenResult(true);
      return idTokenResult.claims?['resident'] == true;
    }
    return false;
  }
}

class FirebaseDatabaseService implements DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Query _buildQuery(Query query, List<QueryFilter>? filters, List<QuerySort>? sorts) {
    if (filters != null) {
      for (var filter in filters) {
        final val = _mapValue(filter.value);
        switch (filter.operator) {
          case FilterOperator.equal:
            query = query.where(filter.field, isEqualTo: val);
            break;
          case FilterOperator.notEqual:
            query = query.where(filter.field, isNotEqualTo: val);
            break;
          case FilterOperator.greaterThan:
            query = query.where(filter.field, isGreaterThan: val);
            break;
          case FilterOperator.greaterThanOrEqual:
            query = query.where(filter.field, isGreaterThanOrEqualTo: val);
            break;
          case FilterOperator.lessThan:
            query = query.where(filter.field, isLessThan: val);
            break;
          case FilterOperator.lessThanOrEqual:
            query = query.where(filter.field, isLessThanOrEqualTo: val);
            break;
          case FilterOperator.arrayContains:
            query = query.where(filter.field, arrayContains: val);
            break;
          case FilterOperator.isNull:
            query = query.where(filter.field, isNull: filter.value as bool? ?? true);
            break;
        }
      }
    }
    if (sorts != null) {
      for (var sort in sorts) {
        query = query.orderBy(sort.field, descending: sort.descending);
      }
    }
    return query;
  }

  @override
  Future<Map<String, dynamic>?> getDocument(String collection, String docId) async {
    final doc = await _firestore.collection(collection).doc(docId).get();
    final data = doc.data();
    if (data == null) return null;
    return _unmapData(data);
  }

  @override
  Stream<Map<String, dynamic>?> streamDocument(String collection, String docId) {
    return _firestore.collection(collection).doc(docId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      return _unmapData(data);
    });
  }

  @override
  Stream<List<Map<String, dynamic>>> streamCollection(String collection, {List<QueryFilter>? filters, List<QuerySort>? sorts}) {
    Query query = _firestore.collection(collection);
    query = _buildQuery(query, filters, sorts);
    return query.snapshots().map((snap) {
      return snap.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final unmapped = _unmapData(data);
        unmapped['id'] = doc.id;
        return unmapped;
      }).toList();
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getCollection(String collection, {List<QueryFilter>? filters, List<QuerySort>? sorts}) async {
    Query query = _firestore.collection(collection);
    query = _buildQuery(query, filters, sorts);
    final snap = await query.get();
    return snap.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final unmapped = _unmapData(data);
      unmapped['id'] = doc.id;
      return unmapped;
    }).toList();
  }

  @override
  Future<void> setDocument(String collection, String docId, Map<String, dynamic> data) async {
    await _firestore.collection(collection).doc(docId).set(_mapData(data));
  }

  @override
  Future<String> addDocument(String collection, Map<String, dynamic> data) async {
    final docRef = await _firestore.collection(collection).add(_mapData(data));
    return docRef.id;
  }

  @override
  Future<void> updateDocument(String collection, String docId, Map<String, dynamic> data) async {
    await _firestore.collection(collection).doc(docId).update(_mapData(data));
  }

  @override
  Future<void> deleteDocument(String collection, String docId) async {
    await _firestore.collection(collection).doc(docId).delete();
  }

  @override
  Future<void> runBatch(Future<void> Function(DbBatch batch) action) async {
    final batch = _firestore.batch();
    final dbBatch = FirebaseDbBatch(batch);
    await action(dbBatch);
    await batch.commit();
  }

  @override
  DbReference createReference(String collection, String docId) {
    return FirebaseDbReference(_firestore.collection(collection).doc(docId));
  }

  @override
  dynamic toRawValue(dynamic value) {
    return _mapValue(value);
  }
}

class FirebaseStorageService implements StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  @override
  Future<String> uploadFile(String path, dynamic fileData, {String? contentType, Map<String, String>? metadata}) async {
    final ref = _storage.ref().child(path);
    final settableMetadata = SettableMetadata(
      contentType: contentType,
      customMetadata: metadata,
    );
    if (fileData is Uint8List) {
      await ref.putData(fileData, settableMetadata);
    } else if (fileData is File) {
      await ref.putFile(fileData, settableMetadata);
    } else {
      throw ArgumentError('Unsupported file data type');
    }
    return await ref.getDownloadURL();
  }

  @override
  Future<String> getDownloadUrl(String path) async {
    return await _storage.ref().child(path).getDownloadURL();
  }

  @override
  Future<void> deleteFileFromUrl(String url) async {
    await _storage.refFromURL(url).delete();
  }
}

class FirebaseFunctionsService implements FunctionsService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  @override
  Future<dynamic> callFunction(String name, [Map<String, dynamic>? parameters]) async {
    final callable = _functions.httpsCallable(name);
    final result = await callable.call(parameters);
    return result.data;
  }
}

class FirebaseBackend {
  static Future<void> useEmulator({String? host}) async {
    String targetHost = host ?? '';
    if (targetHost.isEmpty) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        targetHost = '10.0.2.2';
      } else {
        targetHost = '127.0.0.1';
      }
    }

    debugPrint('>>> [FirebaseBackend] Connecting to Local Emulators on host: $targetHost <<<');

    try {
      // 1. Auth Emulator (:9099)
      await fb_auth.FirebaseAuth.instance.useAuthEmulator(targetHost, 9099);
      debugPrint('  ✓ Auth emulator configured (:9099)');
    } catch (e) {
      debugPrint('  ! Auth emulator configuration note: $e');
    }

    try {
      // 2. Firestore Emulator (:8080)
      FirebaseFirestore.instance.useFirestoreEmulator(targetHost, 8080);
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
        sslEnabled: false,
      );
      debugPrint('  ✓ Firestore emulator configured (:8080)');
    } catch (e) {
      debugPrint('  ! Firestore emulator configuration note: $e');
    }

    try {
      // 3. Storage Emulator (:9199)
      await FirebaseStorage.instance.useStorageEmulator(targetHost, 9199);
      debugPrint('  ✓ Storage emulator configured (:9199)');
    } catch (e) {
      debugPrint('  ! Storage emulator configuration note: $e');
    }

    try {
      // 4. Cloud Functions Emulator (:5001)
      FirebaseFunctions.instance.useFunctionsEmulator(targetHost, 5001);
      debugPrint('  ✓ Functions emulator configured (:5001)');
    } catch (e) {
      debugPrint('  ! Functions emulator configuration note: $e');
    }
  }
}

class FirebaseCrashlyticsService implements CrashlyticsService {
  bool get _isSupportedPlatform => !kIsWeb;

  @override
  Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    dynamic reason,
    Iterable<Object> information = const [],
    bool fatal = false,
  }) async {
    if (_isSupportedPlatform) {
      try {
        await FirebaseCrashlytics.instance.recordError(
          exception,
          stack,
          reason: reason,
          information: information,
          fatal: fatal,
        );
      } catch (e) {
        debugPrint('[Crashlytics Native Error] Failed to record error: $e');
      }
    } else {
      debugPrint('[Crashlytics-Web Fallback] $exception (fatal: $fatal, reason: $reason)\n$stack');
    }
  }

  @override
  Future<void> recordFlutterError(FlutterErrorDetails details, {bool fatal = false}) async {
    if (_isSupportedPlatform) {
      try {
        await FirebaseCrashlytics.instance.recordFlutterError(details, fatal: fatal);
      } catch (e) {
        debugPrint('[Crashlytics Native Error] Failed to record Flutter error: $e');
      }
    } else {
      debugPrint('[Crashlytics-Web FlutterError] ${details.exceptionAsString()}\n${details.stack}');
    }
  }

  @override
  Future<void> log(String message) async {
    if (_isSupportedPlatform) {
      try {
        await FirebaseCrashlytics.instance.log(message);
      } catch (e) {
        debugPrint('[Crashlytics Native Error] Failed to log message: $e');
      }
    } else {
      debugPrint('[Crashlytics-Web Log] $message');
    }
  }

  @override
  Future<void> setUserIdentifier(String identifier) async {
    if (_isSupportedPlatform) {
      try {
        await FirebaseCrashlytics.instance.setUserIdentifier(identifier);
      } catch (e) {
        debugPrint('[Crashlytics Native Error] Failed to set user identifier: $e');
      }
    }
  }

  @override
  Future<void> setCustomKey(String key, Object value) async {
    if (_isSupportedPlatform) {
      try {
        await FirebaseCrashlytics.instance.setCustomKey(key, value);
      } catch (e) {
        debugPrint('[Crashlytics Native Error] Failed to set custom key: $e');
      }
    }
  }

  @override
  Future<void> setCrashlyticsCollectionEnabled(bool enabled) async {
    if (_isSupportedPlatform) {
      try {
        await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled);
      } catch (e) {
        debugPrint('[Crashlytics Native Error] Failed to set collection enabled: $e');
      }
    }
  }
}
