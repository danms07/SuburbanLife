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
  Future<void> reloadUserToken({bool forceRefresh = true});
  Future<bool> isAdmin();
  Future<bool> isGuard();
  Future<bool> isResident();
}

/// Centralized validator enforcing the Firebase Auth Password Policy:
/// - Minimum 8 characters, maximum 4096 characters
/// - At least 1 uppercase letter (A-Z)
/// - At least 1 lowercase letter (a-z)
/// - At least 1 numeric digit (0-9)
/// - At least 1 special character / symbol (non-alphanumeric)
class PasswordValidator {
  static bool isValid(String? password) {
    if (password == null) return false;
    final trimmed = password.trim();
    if (trimmed.length < 8 || trimmed.length > 4096) return false;
    if (!trimmed.contains(RegExp(r'[A-Z]'))) return false;
    if (!trimmed.contains(RegExp(r'[a-z]'))) return false;
    if (!trimmed.contains(RegExp(r'[0-9]'))) return false;
    if (!trimmed.contains(RegExp(r'[^A-Za-z0-9]'))) return false;
    return true;
  }
}

/// Centralized validator for user email addresses aligned with backend rules.
class EmailValidator {
  static final RegExp _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static bool isValid(String? email) {
    if (email == null) return false;
    final trimmed = email.trim().toLowerCase();
    if (trimmed.length < 3 || trimmed.length > 120) return false;
    return _emailRegex.hasMatch(trimmed);
  }
}

abstract class DatabaseService {
  factory DatabaseService() => Backend.db;

  Future<Map<String, dynamic>?> getDocument(String collection, String docId);
  Stream<Map<String, dynamic>?> streamDocument(String collection, String docId);
  Stream<List<Map<String, dynamic>>> streamCollection(String collection, {List<QueryFilter>? filters, List<QuerySort>? sorts, int? limit});
  Future<List<Map<String, dynamic>>> getCollection(String collection, {List<QueryFilter>? filters, List<QuerySort>? sorts, int? limit, dynamic startAfter});
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

  Future<String> uploadFile(
    String path,
    dynamic fileData, {
    String? contentType,
    String? contentDisposition,
    Map<String, String>? metadata,
  });
  Future<String> getDownloadUrl(String path);
  Future<void> deleteFileFromUrl(String url);
}

abstract class FunctionsService {
  factory FunctionsService() => Backend.functions;

  Future<dynamic> callFunction(String name, [Map<String, dynamic>? parameters]);
}

abstract class CrashlyticsService {
  factory CrashlyticsService() => Backend.crashlytics;

  Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    dynamic reason,
    Iterable<Object> information = const [],
    bool fatal = false,
  });

  Future<void> recordFlutterError(FlutterErrorDetails details, {bool fatal = false});
  Future<void> log(String message);
  Future<void> setUserIdentifier(String identifier);
  Future<void> setCustomKey(String key, Object value);
  Future<void> setCrashlyticsCollectionEnabled(bool enabled);
}

/// Strictly allow-listed deep-link destinations for push and in-app notifications.
const Set<String> allowedNotificationRoutes = {
  'home',
  'notifications',
  'payments',
  'sanctions',
  'bookings',
  'qr_codes',
  'roommates',
  'transparency',
  'announcements',
  'admin_claims',
  'admin_payments',
  'admin_bookings',
};

/// Normalizes untrusted notification target routes to the shared allow-list.
String sanitizeNotificationRoute(String? route) {
  if (route != null && allowedNotificationRoutes.contains(route)) {
    return route;
  }
  return 'home';
}

/// Matches backend RTDB/FCM notification category keys and Android channel IDs.
enum NotificationCategory {
  reviews('reviews'),
  sanctions('sanctions'),
  qrAccess('qr_access'),
  roommates('roommates'),
  transparency('transparency'),
  announcements('announcements'),
  adminReviews('admin_reviews');

  final String key;
  const NotificationCategory(this.key);

  static NotificationCategory? tryParse(String? raw) {
    if (raw == null) return null;
    for (final value in NotificationCategory.values) {
      if (value.key == raw) return value;
    }
    return null;
  }
}

/// Unified OS / Browser push notification authorization state.
enum PushPermissionStatus {
  authorized,
  provisional,
  denied,
  notDetermined,
  unsupported,
}

extension PushPermissionStatusX on PushPermissionStatus {
  bool get isGranted =>
      this == PushPermissionStatus.authorized ||
      this == PushPermissionStatus.provisional;
}

/// Localized notification record mirrored to `/notifications/{uid}/{notifId}`
/// or parsed from a foreground/tap FCM payload.
class AppNotification {
  final String id;
  final String type;
  final String categoryKey;
  final NotificationCategory? category;
  final Map<String, String> titles;
  final Map<String, String> bodies;
  final String targetRoute;
  final String? entityId;
  final DateTime createdAt;
  final bool isRead;
  final DateTime? readAt;
  final Map<String, dynamic> metadata;

  const AppNotification({
    required this.id,
    required this.type,
    required this.categoryKey,
    this.category,
    required this.titles,
    required this.bodies,
    required this.targetRoute,
    this.entityId,
    required this.createdAt,
    this.isRead = false,
    this.readAt,
    this.metadata = const {},
  });

  String localizedTitle(String languageCode) {
    final lang = languageCode.toLowerCase().startsWith('en') ? 'en' : 'es';
    return titles[lang] ?? titles['es'] ?? titles['en'] ?? '';
  }

  String localizedBody(String languageCode) {
    final lang = languageCode.toLowerCase().startsWith('en') ? 'en' : 'es';
    return bodies[lang] ?? bodies['es'] ?? bodies['en'] ?? '';
  }

  AppNotification copyWith({
    bool? isRead,
    DateTime? readAt,
  }) {
    return AppNotification(
      id: id,
      type: type,
      categoryKey: categoryKey,
      category: category,
      titles: titles,
      bodies: bodies,
      targetRoute: targetRoute,
      entityId: entityId,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      metadata: metadata,
    );
  }

  factory AppNotification.fromRtdbMap(String id, Map<dynamic, dynamic> raw) {
    final titlesRaw = raw['titles'];
    final bodiesRaw = raw['bodies'];
    final metadataRaw = raw['metadata'];

    final titles = <String, String>{};
    if (titlesRaw is Map) {
      titlesRaw.forEach((key, value) {
        if (key != null && value != null) {
          titles[key.toString()] = value.toString();
        }
      });
    }

    final bodies = <String, String>{};
    if (bodiesRaw is Map) {
      bodiesRaw.forEach((key, value) {
        if (key != null && value != null) {
          bodies[key.toString()] = value.toString();
        }
      });
    }

    final metadata = <String, dynamic>{};
    if (metadataRaw is Map) {
      metadataRaw.forEach((key, value) {
        if (key != null) {
          metadata[key.toString()] = value;
        }
      });
    }

    final categoryKey = (raw['category'] ?? '').toString();
    final createdAtMs = _parseMillis(raw['createdAt']);
    final readAtMs = _parseNullableMillis(raw['readAt']);

    return AppNotification(
      id: id,
      type: (raw['type'] ?? 'general').toString(),
      categoryKey: categoryKey,
      category: NotificationCategory.tryParse(categoryKey),
      titles: titles,
      bodies: bodies,
      targetRoute: sanitizeNotificationRoute(raw['targetRoute']?.toString()),
      entityId: raw['entityId']?.toString(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        createdAtMs > 0 ? createdAtMs : DateTime.now().millisecondsSinceEpoch,
      ),
      isRead: raw['isRead'] == true,
      readAt: readAtMs != null ? DateTime.fromMillisecondsSinceEpoch(readAtMs) : null,
      metadata: metadata,
    );
  }

  factory AppNotification.fromRemoteData(
    Map<String, dynamic> data, {
    String? fallbackTitle,
    String? fallbackBody,
    String preferredLanguage = 'es',
  }) {
    final lang = preferredLanguage.toLowerCase().startsWith('en') ? 'en' : 'es';
    final titleText = (data['title']?.toString().trim().isNotEmpty == true)
        ? data['title'].toString()
        : (fallbackTitle ?? '');
    final bodyText = (data['body']?.toString().trim().isNotEmpty == true)
        ? data['body'].toString()
        : (fallbackBody ?? '');
    final categoryKey = (data['category'] ?? '').toString();
    final notificationId = (data['notificationId']?.toString().trim().isNotEmpty == true)
        ? data['notificationId'].toString()
        : 'fcm_${DateTime.now().millisecondsSinceEpoch}';

    return AppNotification(
      id: notificationId,
      type: (data['type'] ?? 'general').toString(),
      categoryKey: categoryKey,
      category: NotificationCategory.tryParse(categoryKey),
      titles: {lang: titleText},
      bodies: {lang: bodyText},
      targetRoute: sanitizeNotificationRoute(data['targetRoute']?.toString()),
      entityId: data['entityId']?.toString().trim().isNotEmpty == true
          ? data['entityId'].toString()
          : null,
      createdAt: DateTime.now(),
      isRead: false,
    );
  }

  static int _parseMillis(dynamic raw) {
    if (raw is int) return raw;
    if (raw is double) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  static int? _parseNullableMillis(dynamic raw) {
    if (raw == null) return null;
    final parsed = _parseMillis(raw);
    return parsed > 0 ? parsed : null;
  }
}

/// User notification delivery preferences stored at `/user_notification_settings/{uid}`.
class UserNotificationSettings {
  final String locale;
  final bool pushEnabled;
  final bool inAppBannerEnabled;
  final Map<String, bool> categories;

  const UserNotificationSettings({
    this.locale = 'es',
    this.pushEnabled = true,
    this.inAppBannerEnabled = true,
    this.categories = const {},
  });

  bool isCategoryEnabled(NotificationCategory category) {
    return categories[category.key] != false;
  }

  UserNotificationSettings copyWith({
    String? locale,
    bool? pushEnabled,
    bool? inAppBannerEnabled,
    Map<String, bool>? categories,
  }) {
    return UserNotificationSettings(
      locale: locale ?? this.locale,
      pushEnabled: pushEnabled ?? this.pushEnabled,
      inAppBannerEnabled: inAppBannerEnabled ?? this.inAppBannerEnabled,
      categories: categories ?? this.categories,
    );
  }

  factory UserNotificationSettings.fromRtdbMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) return const UserNotificationSettings();
    final categoriesMap = <String, bool>{};
    final rawCategories = raw['categories'];
    if (rawCategories is Map) {
      rawCategories.forEach((key, value) {
        if (key != null && value is bool) {
          categoriesMap[key.toString()] = value;
        }
      });
    }
    final rawLocale = raw['locale']?.toString();
    return UserNotificationSettings(
      locale: rawLocale == 'en' ? 'en' : 'es',
      pushEnabled: raw['pushEnabled'] != false,
      inAppBannerEnabled: raw['inAppBannerEnabled'] != false,
      categories: categoriesMap,
    );
  }
}

/// Contract for push notifications (FCM) + inbox/preferences synchronization (RTDB).
abstract class NotificationService {
  factory NotificationService() => Backend.notifications;

  Stream<AppNotification> get onForegroundMessage;
  Stream<String> get onNotificationOpenedRoute;

  Future<void> initialize({
    required String uid,
    required String languageCode,
  });

  Future<PushPermissionStatus> getPermissionStatus();

  Future<PushPermissionStatus> requestPermissionAndRegister({
    required String uid,
    String? languageCode,
  });

  Future<void> syncLocale(String uid, String languageCode);

  Future<void> setPushEnabled(
    String uid,
    bool enabled, {
    String? languageCode,
  });

  Future<void> setInAppBannerEnabled(String uid, bool enabled);

  Future<void> setCategoryEnabled(
    String uid,
    NotificationCategory category,
    bool enabled,
  );

  Future<void> unregisterCurrentDeviceToken();

  Stream<UserNotificationSettings> watchSettings(String uid);
  Stream<List<AppNotification>> watchNotifications(String uid);
  Stream<int> watchUnreadCount(String uid);

  Future<void> markAsRead(String uid, String notificationId);
  Future<void> markAllAsRead(String uid);
  Future<void> deleteNotification(String uid, String notificationId);
  Future<void> clearAllNotifications(String uid);

  String? consumeInitialRoute();
}

class _NoOpNotificationService implements NotificationService {
  const _NoOpNotificationService();

  @override
  Stream<AppNotification> get onForegroundMessage => const Stream.empty();

  @override
  Stream<String> get onNotificationOpenedRoute => const Stream.empty();

  @override
  Future<void> initialize({required String uid, required String languageCode}) async {}

  @override
  Future<PushPermissionStatus> getPermissionStatus() async =>
      PushPermissionStatus.unsupported;

  @override
  Future<PushPermissionStatus> requestPermissionAndRegister({
    required String uid,
    String? languageCode,
  }) async =>
      PushPermissionStatus.unsupported;

  @override
  Future<void> syncLocale(String uid, String languageCode) async {}

  @override
  Future<void> setPushEnabled(String uid, bool enabled, {String? languageCode}) async {}

  @override
  Future<void> setInAppBannerEnabled(String uid, bool enabled) async {}

  @override
  Future<void> setCategoryEnabled(
    String uid,
    NotificationCategory category,
    bool enabled,
  ) async {}

  @override
  Future<void> unregisterCurrentDeviceToken() async {}

  @override
  Stream<UserNotificationSettings> watchSettings(String uid) =>
      Stream.value(const UserNotificationSettings());

  @override
  Stream<List<AppNotification>> watchNotifications(String uid) =>
      Stream.value(const <AppNotification>[]);

  @override
  Stream<int> watchUnreadCount(String uid) => Stream.value(0);

  @override
  Future<void> markAsRead(String uid, String notificationId) async {}

  @override
  Future<void> markAllAsRead(String uid) async {}

  @override
  Future<void> deleteNotification(String uid, String notificationId) async {}

  @override
  Future<void> clearAllNotifications(String uid) async {}

  @override
  String? consumeInitialRoute() => null;
}

class Backend {
  static AuthService get auth => _auth;
  static DatabaseService get db => _db;
  static StorageService get storage => _storage;
  static FunctionsService get functions => _functions;
  static CrashlyticsService get crashlytics => _crashlytics;
  static NotificationService get notifications => _notifications;

  static late AuthService _auth;
  static late DatabaseService _db;
  static late StorageService _storage;
  static late FunctionsService _functions;
  static late CrashlyticsService _crashlytics;
  static NotificationService _notifications = const _NoOpNotificationService();

  static void initialize({
    required AuthService auth,
    required DatabaseService db,
    required StorageService storage,
    required FunctionsService functions,
    required CrashlyticsService crashlytics,
    NotificationService? notifications,
  }) {
    _auth = auth;
    _db = db;
    _storage = storage;
    _functions = functions;
    _crashlytics = crashlytics;
    _notifications = notifications ?? const _NoOpNotificationService();
  }
}
