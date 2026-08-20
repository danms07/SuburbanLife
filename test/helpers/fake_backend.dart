import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:suburban_life/core/backend/backend.dart';

/// In-memory implementation of [DbBatch] for testing.
class FakeDbBatch implements DbBatch {
  final FakeDatabaseService _db;
  final List<void Function()> _operations = [];

  FakeDbBatch(this._db);

  @override
  void set(String collection, String docId, Map<String, dynamic> data) {
    _operations.add(() => _db.setDocumentSync(collection, docId, data));
  }

  @override
  void update(String collection, String docId, Map<String, dynamic> data) {
    _operations.add(() => _db.updateDocumentSync(collection, docId, data));
  }

  @override
  void delete(String collection, String docId) {
    _operations.add(() => _db.deleteDocumentSync(collection, docId));
  }

  @override
  Future<void> commit() async {
    for (final op in _operations) {
      op();
    }
    _operations.clear();
  }
}

/// In-memory implementation of [DatabaseService] for fast, deterministic unit tests.
class FakeDatabaseService implements DatabaseService {
  final Map<String, Map<String, Map<String, dynamic>>> _store = {};
  final Map<String, StreamController<Map<String, dynamic>?>> _docControllers = {};
  final Map<String, StreamController<List<Map<String, dynamic>>>> _collectionControllers = {};
  int _autoIdCounter = 1;

  void clear() {
    _store.clear();
    for (final c in _docControllers.values) {
      c.close();
    }
    _docControllers.clear();
    for (final c in _collectionControllers.values) {
      c.close();
    }
    _collectionControllers.clear();
    _autoIdCounter = 1;
  }

  void seedDocument(String collection, String docId, Map<String, dynamic> data) {
    setDocumentSync(collection, docId, data);
  }

  void setDocumentSync(String collection, String docId, Map<String, dynamic> data) {
    _store.putIfAbsent(collection, () => {});
    final docData = Map<String, dynamic>.from(data);
    docData['id'] ??= docId;
    _store[collection]![docId] = docData;
    _notify(collection, docId);
  }

  void updateDocumentSync(String collection, String docId, Map<String, dynamic> data) {
    _store.putIfAbsent(collection, () => {});
    final existing = _store[collection]![docId] ?? {'id': docId};
    final updated = Map<String, dynamic>.from(existing);
    data.forEach((key, value) {
      updated[key] = value;
    });
    _store[collection]![docId] = updated;
    _notify(collection, docId);
  }

  void deleteDocumentSync(String collection, String docId) {
    _store[collection]?.remove(docId);
    _notify(collection, docId);
  }

  void _notify(String collection, String docId) {
    final docKey = '$collection/$docId';
    if (_docControllers.containsKey(docKey)) {
      final doc = _store[collection]?[docId];
      _docControllers[docKey]!.add(doc != null ? Map<String, dynamic>.from(doc) : null);
    }
    if (_collectionControllers.containsKey(collection)) {
      final list = (_store[collection]?.values ?? [])
          .map((d) => Map<String, dynamic>.from(d))
          .toList();
      _collectionControllers[collection]!.add(list);
    }
  }

  @override
  Future<Map<String, dynamic>?> getDocument(String collection, String docId) async {
    final doc = _store[collection]?[docId];
    if (doc == null) return null;
    return Map<String, dynamic>.from(doc);
  }

  @override
  Stream<Map<String, dynamic>?> streamDocument(String collection, String docId) {
    final docKey = '$collection/$docId';
    final controller = _docControllers.putIfAbsent(docKey, () {
      final sc = StreamController<Map<String, dynamic>?>.broadcast();
      return sc;
    });
    // Emit current state asynchronously
    Future.microtask(() {
      if (!controller.isClosed) {
        final doc = _store[collection]?[docId];
        controller.add(doc != null ? Map<String, dynamic>.from(doc) : null);
      }
    });
    return controller.stream;
  }

  @override
  Stream<List<Map<String, dynamic>>> streamCollection(
    String collection, {
    List<QueryFilter>? filters,
    List<QuerySort>? sorts,
  }) {
    final controller = _collectionControllers.putIfAbsent(collection, () {
      return StreamController<List<Map<String, dynamic>>>.broadcast();
    });

    Future.microtask(() async {
      if (!controller.isClosed) {
        final docs = await getCollection(collection, filters: filters, sorts: sorts);
        controller.add(docs);
      }
    });

    return controller.stream.map((list) => _applyFiltersAndSorts(list, filters, sorts));
  }

  @override
  Future<List<Map<String, dynamic>>> getCollection(
    String collection, {
    List<QueryFilter>? filters,
    List<QuerySort>? sorts,
  }) async {
    final docs = (_store[collection]?.values ?? [])
        .map((d) => Map<String, dynamic>.from(d))
        .toList();
    return _applyFiltersAndSorts(docs, filters, sorts);
  }

  List<Map<String, dynamic>> _applyFiltersAndSorts(
    List<Map<String, dynamic>> docs,
    List<QueryFilter>? filters,
    List<QuerySort>? sorts,
  ) {
    var result = List<Map<String, dynamic>>.from(docs);

    if (filters != null) {
      for (final filter in filters) {
        result = result.where((doc) {
          final docVal = doc[filter.field];
          return _matchesFilter(docVal, filter.operator, filter.value);
        }).toList();
      }
    }

    if (sorts != null) {
      for (final sort in sorts) {
        result.sort((a, b) {
          final valA = a[sort.field];
          final valB = b[sort.field];
          if (valA == null && valB == null) return 0;
          if (valA == null) return sort.descending ? 1 : -1;
          if (valB == null) return sort.descending ? -1 : 1;

          int comp;
          if (valA is Comparable && valB is Comparable) {
            comp = valA.compareTo(valB);
          } else {
            comp = valA.toString().compareTo(valB.toString());
          }
          return sort.descending ? -comp : comp;
        });
      }
    }

    return result;
  }

  bool _matchesFilter(dynamic docVal, FilterOperator op, dynamic targetVal) {
    dynamic normalize(dynamic val) {
      if (val is DbReference) return val.id;
      return val;
    }

    final nDocVal = normalize(docVal);
    final nTargetVal = normalize(targetVal);

    switch (op) {
      case FilterOperator.equal:
        return nDocVal == nTargetVal;
      case FilterOperator.notEqual:
        return nDocVal != nTargetVal;
      case FilterOperator.greaterThan:
        return (nDocVal as Comparable).compareTo(nTargetVal) > 0;
      case FilterOperator.greaterThanOrEqual:
        return (nDocVal as Comparable).compareTo(nTargetVal) >= 0;
      case FilterOperator.lessThan:
        return (nDocVal as Comparable).compareTo(nTargetVal) < 0;
      case FilterOperator.lessThanOrEqual:
        return (nDocVal as Comparable).compareTo(nTargetVal) <= 0;
      case FilterOperator.arrayContains:
        if (nDocVal is List) {
          return nDocVal.map(normalize).contains(nTargetVal);
        }
        return false;
      case FilterOperator.isNull:
        final bool shouldBeNull = (targetVal as bool?) ?? true;
        return shouldBeNull ? nDocVal == null : nDocVal != null;
    }
  }

  @override
  Future<void> setDocument(String collection, String docId, Map<String, dynamic> data) async {
    setDocumentSync(collection, docId, data);
  }

  @override
  Future<String> addDocument(String collection, Map<String, dynamic> data) async {
    final docId = 'fake_id_${_autoIdCounter++}';
    setDocumentSync(collection, docId, data);
    return docId;
  }

  @override
  Future<void> updateDocument(String collection, String docId, Map<String, dynamic> data) async {
    updateDocumentSync(collection, docId, data);
  }

  @override
  Future<void> deleteDocument(String collection, String docId) async {
    deleteDocumentSync(collection, docId);
  }

  @override
  Future<void> runBatch(Future<void> Function(DbBatch batch) action) async {
    final batch = FakeDbBatch(this);
    await action(batch);
    await batch.commit();
  }

  @override
  DbReference createReference(String collection, String docId) {
    return StringDbReference(docId, path: '$collection/$docId');
  }

  @override
  dynamic toRawValue(dynamic value) => value;
}

/// In-memory implementation of [AuthService] for testing.
class FakeAuthService implements AuthService {
  AppUser? currentUserMock;
  bool isAdminMock = false;
  bool isGuardMock = false;
  bool isResidentMock = true;

  final StreamController<AppUser?> _userStreamController = StreamController<AppUser?>.broadcast();

  void clear() {
    currentUserMock = null;
    isAdminMock = false;
    isGuardMock = false;
    isResidentMock = true;
  }

  @override
  AppUser? get currentUser => currentUserMock;

  @override
  Stream<AppUser?> get userStream => _userStreamController.stream;

  void emitUser(AppUser? user) {
    currentUserMock = user;
    _userStreamController.add(user);
  }

  @override
  Future<AppUser?> signIn(String email, String password) async {
    final user = AppUser(uid: 'uid_${email.split('@').first}', email: email, displayName: 'Test User');
    emitUser(user);
    return user;
  }

  @override
  Future<AppUser?> signUp(String email, String password, {String? name}) async {
    final user = AppUser(uid: 'uid_${email.split('@').first}', email: email, displayName: name);
    emitUser(user);
    return user;
  }

  @override
  Future<bool> sendPasswordReset(String email) async => true;

  @override
  Future<void> signOut() async {
    emitUser(null);
  }

  @override
  Future<bool> isAdmin() async => isAdminMock;

  @override
  Future<bool> isGuard() async => isGuardMock;

  @override
  Future<bool> isResident() async => isResidentMock;
}

/// In-memory implementation of [StorageService] for testing.
class FakeStorageService implements StorageService {
  final Map<String, dynamic> uploadedFiles = {};
  final List<String> deletedUrls = [];

  void clear() {
    uploadedFiles.clear();
    deletedUrls.clear();
  }

  @override
  Future<String> uploadFile(
    String path,
    dynamic fileData, {
    String? contentType,
    Map<String, String>? metadata,
  }) async {
    uploadedFiles[path] = fileData;
    return 'https://fake-storage.local/$path';
  }

  @override
  Future<String> getDownloadUrl(String path) async {
    return 'https://fake-storage.local/$path';
  }

  @override
  Future<void> deleteFileFromUrl(String url) async {
    deletedUrls.add(url);
  }
}

/// In-memory implementation of [FunctionsService] for testing.
class FakeFunctionsService implements FunctionsService {
  final Map<String, dynamic Function(Map<String, dynamic>?)> handlers = {};
  final List<Map<String, dynamic>> callHistory = [];

  void clear() {
    handlers.clear();
    callHistory.clear();
  }

  void registerHandler(String name, dynamic Function(Map<String, dynamic>?) handler) {
    handlers[name] = handler;
  }

  @override
  Future<dynamic> callFunction(String name, [Map<String, dynamic>? parameters]) async {
    callHistory.add({'name': name, 'parameters': parameters});
    if (handlers.containsKey(name)) {
      return handlers[name]!(parameters);
    }
    return {'success': true};
  }
}

class FakeCrashlyticsService implements CrashlyticsService {
  final List<String> recordedErrors = [];
  final List<String> logs = [];
  String currentUserId = '';
  final Map<String, Object> customKeys = {};
  bool isCollectionEnabled = false;

  void clear() {
    recordedErrors.clear();
    logs.clear();
    currentUserId = '';
    customKeys.clear();
    isCollectionEnabled = false;
  }

  @override
  Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    dynamic reason,
    Iterable<Object> information = const [],
    bool fatal = false,
  }) async {
    recordedErrors.add('$exception (fatal: $fatal, reason: $reason)');
  }

  @override
  Future<void> recordFlutterError(FlutterErrorDetails details, {bool fatal = false}) async {
    recordedErrors.add('${details.exceptionAsString()} (fatal: $fatal)');
  }

  @override
  Future<void> log(String message) async {
    logs.add(message);
  }

  @override
  Future<void> setUserIdentifier(String identifier) async {
    currentUserId = identifier;
  }

  @override
  Future<void> setCustomKey(String key, Object value) async {
    customKeys[key] = value;
  }

  @override
  Future<void> setCrashlyticsCollectionEnabled(bool enabled) async {
    isCollectionEnabled = enabled;
  }
}

/// Global testing helper to initialize and reset the [Backend] instance.
class FakeBackendHelper {
  static final FakeAuthService auth = FakeAuthService();
  static final FakeDatabaseService db = FakeDatabaseService();
  static final FakeStorageService storage = FakeStorageService();
  static final FakeFunctionsService functions = FakeFunctionsService();
  static final FakeCrashlyticsService crashlytics = FakeCrashlyticsService();

  static void setUp() {
    auth.clear();
    db.clear();
    storage.clear();
    functions.clear();
    crashlytics.clear();

    Backend.initialize(
      auth: auth,
      db: db,
      storage: storage,
      functions: functions,
      crashlytics: crashlytics,
    );
  }
}
