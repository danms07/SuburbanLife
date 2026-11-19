import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart' hide Query;
import 'package:universal_html/html.dart' as html;
import '../config/app_config.dart';
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
    } catch (e, stack) {
      debugPrint('Sign in error: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'FirebaseAuthService.signIn');
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
    } catch (e, stack) {
      debugPrint('Sign up error: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'FirebaseAuthService.signUp');
      return null;
    }
  }

  @override
  Future<bool> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return true;
    } catch (e, stack) {
      debugPrint('Password reset error: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'FirebaseAuthService.sendPasswordReset');
      return false;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await Backend.notifications.unregisterCurrentDeviceToken();
    } catch (e) {
      debugPrint('Error unregistering FCM token on signOut: $e');
    }
    await _auth.signOut();
  }

  Future<Map<String, dynamic>?> _getCustomClaims({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final tokenResult = await user.getIdTokenResult(forceRefresh);
      return tokenResult.claims;
    } catch (e, stack) {
      debugPrint('Error getting ID token result (forceRefresh: $forceRefresh): $e');
      if (forceRefresh) {
        try {
          final cachedResult = await user.getIdTokenResult(false);
          return cachedResult.claims;
        } catch (cachedError) {
          debugPrint('Fallback to cached ID token result failed: $cachedError');
        }
      }
      Backend.crashlytics.recordError(e, stack, reason: 'FirebaseAuthService._getCustomClaims');
      return null;
    }
  }

  @override
  Future<void> reloadUserToken({bool forceRefresh = true}) async {
    await _getCustomClaims(forceRefresh: forceRefresh);
  }

  @override
  Future<bool> isAdmin() async {
    final claims = await _getCustomClaims();
    return claims?['admin'] == true;
  }

  @override
  Future<bool> isGuard() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final isGuardEmail = user.email?.toLowerCase().contains('guard') == true;
    final claims = await _getCustomClaims();
    final hasClaim = claims?['guard'] == true;
    return hasClaim || isGuardEmail;
  }

  @override
  Future<bool> isResident() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    if (await isGuard()) return false;
    final claims = await _getCustomClaims();
    return claims?['resident'] == true;
  }
}

class FirebaseDatabaseService implements DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Query _buildQuery(
    Query query,
    List<QueryFilter>? filters,
    List<QuerySort>? sorts, {
    int? limit,
    dynamic startAfter,
  }) {
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
    if (startAfter != null) {
      if (startAfter is DocumentSnapshot) {
        query = query.startAfterDocument(startAfter);
      } else if (startAfter is List) {
        query = query.startAfter(startAfter);
      } else {
        query = query.startAfter([startAfter]);
      }
    }
    if (limit != null && limit > 0) {
      query = query.limit(limit);
    }
    return query;
  }

  @override
  Future<Map<String, dynamic>?> getDocument(String collection, String docId) async {
    final doc = await _firestore.collection(collection).doc(docId).get();
    final data = doc.data();
    if (data == null) return null;
    final unmapped = _unmapData(data);
    unmapped['id'] = doc.id;
    return unmapped;
  }

  @override
  Stream<Map<String, dynamic>?> streamDocument(String collection, String docId) {
    return _firestore.collection(collection).doc(docId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      final unmapped = _unmapData(data);
      unmapped['id'] = doc.id;
      return unmapped;
    });
  }

  @override
  Stream<List<Map<String, dynamic>>> streamCollection(
    String collection, {
    List<QueryFilter>? filters,
    List<QuerySort>? sorts,
    int? limit,
  }) {
    Query query = _firestore.collection(collection);
    query = _buildQuery(query, filters, sorts, limit: limit);
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
  Future<List<Map<String, dynamic>>> getCollection(
    String collection, {
    List<QueryFilter>? filters,
    List<QuerySort>? sorts,
    int? limit,
    dynamic startAfter,
  }) async {
    Query query = _firestore.collection(collection);
    if (startAfter != null && startAfter is String) {
      final docSnap = await _firestore.collection(collection).doc(startAfter).get();
      if (docSnap.exists) {
        query = _buildQuery(query, filters, sorts, limit: limit, startAfter: docSnap);
      } else {
        query = _buildQuery(query, filters, sorts, limit: limit, startAfter: startAfter);
      }
    } else {
      query = _buildQuery(query, filters, sorts, limit: limit, startAfter: startAfter);
    }
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
  Future<String> uploadFile(
    String path,
    dynamic fileData, {
    String? contentType,
    String? contentDisposition,
    Map<String, String>? metadata,
  }) async {
    final ref = _storage.ref().child(path);
    final settableMetadata = SettableMetadata(
      contentType: contentType,
      contentDisposition: contentDisposition,
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
    final callable = _functions.httpsCallable(
      name,
      options: HttpsCallableOptions(
        limitedUseAppCheckToken: !AppConfig.useFirebaseEmulator,
      ),
    );
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

    try {
      // 5. App Check disabled for local emulator
      await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(false);
      debugPrint('  ✓ App Check token auto-refresh disabled for emulator');
    } catch (e) {
      debugPrint('  ! App Check emulator configuration note: $e');
    }

    try {
      // 6. Realtime Database Emulator (:9000)
      final rtdb = getRtdbInstance();
      if (rtdb != null) {
        rtdb.useDatabaseEmulator(targetHost, 9000);
        debugPrint('  ✓ Realtime Database emulator configured (:9000)');
      }
    } catch (e) {
      debugPrint('  ! Realtime Database emulator configuration note: $e');
    }
  }

  static String? resolveRtdbDatabaseUrl() {
    if (AppConfig.rtdbDatabaseUrl.trim().isNotEmpty) {
      return AppConfig.rtdbDatabaseUrl.trim();
    }
    try {
      final optionsUrl = Firebase.app().options.databaseURL?.trim() ?? '';
      if (optionsUrl.isNotEmpty) {
        return optionsUrl;
      }
    } catch (_) {}
    if (AppConfig.useFirebaseEmulator) {
      return 'https://privadacatania-3a7b8-default-rtdb.firebaseio.com';
    }
    return null;
  }

  static FirebaseDatabase? getRtdbInstance() {
    final dbUrl = resolveRtdbDatabaseUrl();
    if (dbUrl == null) return null;
    try {
      return FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: dbUrl,
      );
    } catch (e) {
      debugPrint('Failed to resolve FirebaseDatabase instance: $e');
      return null;
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

class FirebaseNotificationService implements NotificationService {
  final StreamController<AppNotification> _foregroundController =
      StreamController<AppNotification>.broadcast();
  final StreamController<String> _openedRouteController =
      StreamController<String>.broadcast();

  String? _activeUid;
  String? _activeToken;
  String _activeLocale = 'es';
  bool _listenersAttached = false;
  bool _initialMessageChecked = false;
  String? _pendingInitialRoute;

  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenedSub;
  StreamSubscription<String>? _onTokenRefreshSub;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  FirebaseDatabase? get _rtdb => FirebaseBackend.getRtdbInstance();

  String _normalizeLocale(String? languageCode) {
    if (languageCode != null && languageCode.toLowerCase().startsWith('en')) {
      return 'en';
    }
    return 'es';
  }

  @override
  Stream<AppNotification> get onForegroundMessage => _foregroundController.stream;

  @override
  Stream<String> get onNotificationOpenedRoute => _openedRouteController.stream;

  @override
  Future<void> initialize({
    required String uid,
    required String languageCode,
  }) async {
    if (uid.trim().isEmpty) return;
    final previousUid = _activeUid;
    _activeUid = uid;
    _activeLocale = _normalizeLocale(languageCode);

    if (previousUid != null && previousUid != uid && _activeToken != null) {
      await _removeTokenFromUserDoc(previousUid, _activeToken!);
    }

    _attachListenersIfNeeded();
    _captureWebQueryInitialRoute();
    await _checkInitialFcmMessage();
    await _ensureSettingsAndSyncLocale(uid, _activeLocale);

    // Sync device token only if push delivery is currently enabled in RTDB settings
    // and OS/browser permission is already granted.
    final pushEnabled = await _isPushEnabledInRtdb(uid);
    if (pushEnabled) {
      final status = await getPermissionStatus();
      if (status.isGranted) {
        await _configureForegroundPresentation();
        await _registerCurrentToken(uid);
      }
    }
  }

  void _attachListenersIfNeeded() {
    if (_listenersAttached) return;
    _listenersAttached = true;

    _onMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final parsed = AppNotification.fromRemoteData(
        message.data,
        fallbackTitle: message.notification?.title,
        fallbackBody: message.notification?.body,
        preferredLanguage: _activeLocale,
      );
      _foregroundController.add(parsed);
    });

    _onOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final route = sanitizeNotificationRoute(message.data['targetRoute']?.toString());
      _openedRouteController.add(route);
    });

    _onTokenRefreshSub = _messaging.onTokenRefresh.listen((String newToken) async {
      final uid = _activeUid;
      if (uid == null || newToken.trim().isEmpty) return;
      final pushEnabled = await _isPushEnabledInRtdb(uid);
      if (!pushEnabled) return;
      await _saveTokenForUser(uid, newToken.trim());
    });

    if (kIsWeb) {
      try {
        html.window.navigator.serviceWorker?.addEventListener(
          'message',
          (html.Event event) {
            if (event is html.MessageEvent) {
              final origin = event.origin;
              if (origin.isNotEmpty && origin != html.window.location.origin) {
                return;
              }
              final data = event.data;
              if (data is Map && data['type'] == 'NOTIFICATION_CLICK') {
                final route = sanitizeNotificationRoute(data['targetRoute']?.toString());
                _openedRouteController.add(route);
              }
            }
          },
        );
      } catch (e) {
        debugPrint('ServiceWorker message listener unavailable: $e');
      }
    }
  }

  void _captureWebQueryInitialRoute() {
    if (!kIsWeb) return;
    try {
      final rawRoute = Uri.base.queryParameters['notificationRoute'];
      if (rawRoute != null && rawRoute.trim().isNotEmpty) {
        _pendingInitialRoute = sanitizeNotificationRoute(rawRoute.trim());
        final cleanedParams = Map<String, String>.from(Uri.base.queryParameters)
          ..remove('notificationRoute');
        final cleanUri = Uri.base.replace(
          queryParameters: cleanedParams.isEmpty ? null : cleanedParams,
        );
        html.window.history.replaceState(null, '', cleanUri.toString());
      }
    } catch (e) {
      debugPrint('Failed to inspect Web initial notificationRoute: $e');
    }
  }

  Future<void> _checkInitialFcmMessage() async {
    if (_initialMessageChecked) return;
    _initialMessageChecked = true;
    try {
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _pendingInitialRoute = sanitizeNotificationRoute(
          initialMessage.data['targetRoute']?.toString(),
        );
      }
    } catch (e) {
      debugPrint('Failed to read initial FCM message: $e');
    }
  }

  @override
  String? consumeInitialRoute() {
    final route = _pendingInitialRoute;
    _pendingInitialRoute = null;
    return route;
  }

  @override
  Future<PushPermissionStatus> getPermissionStatus() async {
    try {
      if (kIsWeb) {
        final supported = await _messaging.isSupported();
        if (!supported) {
          return PushPermissionStatus.unsupported;
        }
      }
      final settings = await _messaging.getNotificationSettings();
      return _mapAuthStatus(settings.authorizationStatus);
    } catch (e) {
      debugPrint('Unable to determine notification permission status: $e');
      return PushPermissionStatus.unsupported;
    }
  }

  @override
  Future<PushPermissionStatus> requestPermissionAndRegister({
    required String uid,
    String? languageCode,
  }) async {
    if (uid.trim().isEmpty) return PushPermissionStatus.denied;
    _activeUid = uid;
    if (languageCode != null) {
      _activeLocale = _normalizeLocale(languageCode);
    }

    try {
      if (kIsWeb) {
        final supported = await _messaging.isSupported();
        if (!supported) {
          return PushPermissionStatus.unsupported;
        }
      }

      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      final mapped = _mapAuthStatus(settings.authorizationStatus);
      if (mapped.isGranted) {
        await _configureForegroundPresentation();
        await setPushEnabled(uid, true, languageCode: _activeLocale);
        await _registerCurrentToken(uid);
      }
      return mapped;
    } catch (e, stack) {
      debugPrint('Error requesting notification permission: $e');
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'FirebaseNotificationService.requestPermissionAndRegister',
      );
      return PushPermissionStatus.denied;
    }
  }

  PushPermissionStatus _mapAuthStatus(AuthorizationStatus status) {
    switch (status) {
      case AuthorizationStatus.authorized:
        return PushPermissionStatus.authorized;
      case AuthorizationStatus.provisional:
        return PushPermissionStatus.provisional;
      case AuthorizationStatus.denied:
      case AuthorizationStatus.deniedPermanently:
        return PushPermissionStatus.denied;
      case AuthorizationStatus.notDetermined:
        return PushPermissionStatus.notDetermined;
    }
  }

  Future<void> _configureForegroundPresentation() async {
    if (kIsWeb) return;
    try {
      // Keep native foreground alerts muted on Apple platforms so foreground alerts
      // render uniformly via Flutter's toggleable InAppNotificationBanner.
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );
    } catch (e) {
      debugPrint('Foreground presentation options skipped: $e');
    }
  }

  Future<String?> _getSafeFcmToken() async {
    try {
      final status = await getPermissionStatus();
      if (!status.isGranted) return null;

      if (kIsWeb) {
        final vapid = AppConfig.webPushVapidKey.trim();
        if (vapid.isEmpty) {
          debugPrint('WEB_PUSH_VAPID_KEY not configured; skipping Web push token retrieval.');
          return null;
        }
        return await _messaging.getToken(vapidKey: vapid);
      }

      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        final apnsToken = await _messaging.getAPNSToken();
        if (apnsToken == null) {
          debugPrint('APNs token not yet available (simulator or pending registration).');
          return null;
        }
      }

      return await _messaging.getToken();
    } catch (e) {
      debugPrint('FCM getToken skipped safely: $e');
      return null;
    }
  }

  Future<void> _registerCurrentToken(String uid) async {
    final token = await _getSafeFcmToken();
    if (token == null || token.trim().isEmpty) return;
    await _saveTokenForUser(uid, token.trim());
  }

  Future<void> _saveTokenForUser(String uid, String token) async {
    _activeToken = token;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmTokens': FieldValue.arrayUnion([token]),
      });
    } catch (e) {
      debugPrint('Could not persist FCM token to user profile: $e');
    }
  }

  Future<void> _removeTokenFromUserDoc(String uid, String token) async {
    if (uid.trim().isEmpty || token.trim().isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmTokens': FieldValue.arrayRemove([token]),
      });
    } catch (e) {
      debugPrint('Could not remove FCM token from user profile (ignored): $e');
    }
  }

  Future<void> _deactivateCurrentDevicePush(String uid) async {
    var token = _activeToken;
    if (token == null || token.isEmpty) {
      final status = await getPermissionStatus();
      if (status.isGranted) {
        token = await _getSafeFcmToken();
      }
    }
    if (token != null && token.isNotEmpty) {
      await _removeTokenFromUserDoc(uid, token);
    }
    try {
      final status = await getPermissionStatus();
      if (status.isGranted) {
        await _messaging.deleteToken();
      }
    } catch (e) {
      debugPrint('FCM deleteToken skipped: $e');
    }
    _activeToken = null;
  }

  @override
  Future<void> unregisterCurrentDeviceToken() async {
    final uid = _activeUid ?? fb_auth.FirebaseAuth.instance.currentUser?.uid;
    _activeUid = null;
    if (uid != null && uid.isNotEmpty) {
      await _deactivateCurrentDevicePush(uid);
    } else {
      _activeToken = null;
    }
  }

  Future<void> _ensureSettingsAndSyncLocale(String uid, String locale) async {
    final rtdb = _rtdb;
    if (rtdb == null) return;
    try {
      final ref = rtdb.ref('user_notification_settings/$uid');
      final snapshot = await ref.get();
      if (!snapshot.exists || snapshot.value is! Map) {
        await ref.set({
          'locale': locale,
          'pushEnabled': true,
          'inAppBannerEnabled': true,
          'updatedAt': ServerValue.timestamp,
        });
      } else {
        final raw = snapshot.value as Map;
        if (raw['locale']?.toString() != locale ||
            raw['inAppBannerEnabled'] == null ||
            raw['pushEnabled'] == null) {
          await ref.update({
            'locale': locale,
            if (raw['pushEnabled'] == null) 'pushEnabled': true,
            if (raw['inAppBannerEnabled'] == null) 'inAppBannerEnabled': true,
            'updatedAt': ServerValue.timestamp,
          });
        }
      }
    } catch (e) {
      debugPrint('Error synchronizing initial notification settings: $e');
    }
  }

  Future<bool> _isPushEnabledInRtdb(String uid) async {
    final rtdb = _rtdb;
    if (rtdb == null) return true;
    try {
      final snap = await rtdb.ref('user_notification_settings/$uid/pushEnabled').get();
      if (!snap.exists) return true;
      return snap.value != false;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<void> syncLocale(String uid, String languageCode) async {
    if (uid.trim().isEmpty) return;
    final normLocale = _normalizeLocale(languageCode);
    _activeLocale = normLocale;
    final rtdb = _rtdb;
    if (rtdb == null) return;
    try {
      await rtdb.ref('user_notification_settings/$uid').update({
        'locale': normLocale,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Failed to sync notification locale: $e');
    }
  }

  @override
  Future<void> setPushEnabled(
    String uid,
    bool enabled, {
    String? languageCode,
  }) async {
    if (uid.trim().isEmpty) return;
    final rtdb = _rtdb;
    if (languageCode != null) {
      _activeLocale = _normalizeLocale(languageCode);
    }
    if (rtdb != null) {
      try {
        await rtdb.ref('user_notification_settings/$uid').update({
          'pushEnabled': enabled,
          if (languageCode != null) 'locale': _normalizeLocale(languageCode),
          'updatedAt': ServerValue.timestamp,
        });
      } catch (e) {
        debugPrint('Failed to update pushEnabled in RTDB: $e');
      }
    }

    if (enabled) {
      final status = await getPermissionStatus();
      if (status.isGranted) {
        await _configureForegroundPresentation();
        await _registerCurrentToken(uid);
      }
    } else {
      await _deactivateCurrentDevicePush(uid);
    }
  }

  @override
  Future<void> setInAppBannerEnabled(String uid, bool enabled) async {
    if (uid.trim().isEmpty) return;
    final rtdb = _rtdb;
    if (rtdb == null) return;
    try {
      await rtdb.ref('user_notification_settings/$uid').update({
        'inAppBannerEnabled': enabled,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Failed to update inAppBannerEnabled in RTDB: $e');
    }
  }

  @override
  Future<void> setCategoryEnabled(
    String uid,
    NotificationCategory category,
    bool enabled,
  ) async {
    if (uid.trim().isEmpty) return;
    final rtdb = _rtdb;
    if (rtdb == null) return;
    try {
      await rtdb.ref('user_notification_settings/$uid').update({
        'categories/${category.key}': enabled,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Failed to update notification category in RTDB: $e');
    }
  }

  @override
  Stream<UserNotificationSettings> watchSettings(String uid) {
    final rtdb = _rtdb;
    if (rtdb == null || uid.trim().isEmpty) {
      return Stream.value(const UserNotificationSettings());
    }
    return rtdb
        .ref('user_notification_settings/$uid')
        .onValue
        .transform(
          StreamTransformer<DatabaseEvent, UserNotificationSettings>.fromHandlers(
            handleData: (event, sink) {
              final raw = event.snapshot.value;
              sink.add(
                raw is Map
                    ? UserNotificationSettings.fromRtdbMap(raw)
                    : const UserNotificationSettings(),
              );
            },
            handleError: (error, stackTrace, sink) {
              debugPrint('RTDB watchSettings stream error (ignored): $error');
            },
          ),
        );
  }

  @override
  Stream<List<AppNotification>> watchNotifications(String uid) {
    final rtdb = _rtdb;
    if (rtdb == null || uid.trim().isEmpty) {
      return Stream.value(const <AppNotification>[]);
    }
    return rtdb
        .ref('notifications/$uid')
        .orderByChild('createdAt')
        .limitToLast(100)
        .onValue
        .transform(
          StreamTransformer<DatabaseEvent, List<AppNotification>>.fromHandlers(
            handleData: (event, sink) {
              final raw = event.snapshot.value;
              if (raw is! Map) {
                sink.add(const <AppNotification>[]);
                return;
              }
              final items = <AppNotification>[];
              raw.forEach((key, value) {
                if (key != null && value is Map) {
                  items.add(AppNotification.fromRtdbMap(key.toString(), value));
                }
              });
              items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
              sink.add(items);
            },
            handleError: (error, stackTrace, sink) {
              debugPrint('RTDB watchNotifications stream error (ignored): $error');
            },
          ),
        );
  }

  @override
  Stream<int> watchUnreadCount(String uid) {
    return watchNotifications(uid).map(
      (items) => items.where((item) => !item.isRead).length,
    );
  }

  @override
  Future<void> markAsRead(String uid, String notificationId) async {
    final rtdb = _rtdb;
    if (rtdb == null || uid.trim().isEmpty || notificationId.trim().isEmpty) return;
    try {
      await rtdb.ref('notifications/$uid/$notificationId').update({
        'isRead': true,
        'readAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Failed to mark notification as read: $e');
    }
  }

  @override
  Future<void> markAllAsRead(String uid) async {
    final rtdb = _rtdb;
    if (rtdb == null || uid.trim().isEmpty) return;
    try {
      final snap = await rtdb
          .ref('notifications/$uid')
          .orderByChild('isRead')
          .equalTo(false)
          .get();
      if (!snap.exists || snap.value is! Map) return;
      final raw = snap.value as Map;
      final futures = <Future<void>>[];
      for (final key in raw.keys) {
        if (key == null) continue;
        futures.add(
          rtdb.ref('notifications/$uid/${key.toString()}').update({
            'isRead': true,
            'readAt': ServerValue.timestamp,
          }),
        );
      }
      await Future.wait(futures);
    } catch (e) {
      debugPrint('Failed to mark all notifications as read: $e');
    }
  }

  @override
  Future<void> deleteNotification(String uid, String notificationId) async {
    final rtdb = _rtdb;
    if (rtdb == null || uid.trim().isEmpty || notificationId.trim().isEmpty) return;
    try {
      await rtdb.ref('notifications/$uid/$notificationId').remove();
    } catch (e) {
      debugPrint('Failed to delete notification: $e');
    }
  }

  @override
  Future<void> clearAllNotifications(String uid) async {
    final rtdb = _rtdb;
    if (rtdb == null || uid.trim().isEmpty) return;
    try {
      await rtdb.ref('notifications/$uid').remove();
    } catch (e) {
      debugPrint('Failed to clear notifications: $e');
    }
  }

  void dispose() {
    _onMessageSub?.cancel();
    _onOpenedSub?.cancel();
    _onTokenRefreshSub?.cancel();
    _foregroundController.close();
    _openedRouteController.close();
  }
}
