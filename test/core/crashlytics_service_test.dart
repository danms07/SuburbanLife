import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/core/backend/backend.dart';

class MockCrashlyticsService implements CrashlyticsService {
  final List<String> recordedErrors = [];
  final List<String> logs = [];
  String currentUserId = '';
  final Map<String, Object> customKeys = {};
  bool isCollectionEnabled = false;

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

void main() {
  group('CrashlyticsService & BaaS Abstraction Tests', () {
    late MockCrashlyticsService mockCrashlytics;

    setUp(() {
      mockCrashlytics = MockCrashlyticsService();
    });

    test('Record non-fatal and fatal errors correctly', () async {
      await mockCrashlytics.recordError(
        Exception('Test non-fatal error'),
        StackTrace.current,
        reason: 'Testing handled exception',
        fatal: false,
      );

      await mockCrashlytics.recordError(
        Exception('Fatal uncaught error'),
        StackTrace.current,
        fatal: true,
      );

      expect(mockCrashlytics.recordedErrors.length, 2);
      expect(mockCrashlytics.recordedErrors.first, contains('Test non-fatal error (fatal: false, reason: Testing handled exception)'));
      expect(mockCrashlytics.recordedErrors.last, contains('Fatal uncaught error (fatal: true, reason: null)'));
    });

    test('Record FlutterErrorDetails correctly', () async {
      final details = FlutterErrorDetails(
        exception: Exception('Widget build failed'),
        stack: StackTrace.current,
        library: 'widgets library',
      );

      await mockCrashlytics.recordFlutterError(details, fatal: true);

      expect(mockCrashlytics.recordedErrors.length, 1);
      expect(mockCrashlytics.recordedErrors.first, contains('Widget build failed (fatal: true)'));
    });

    test('Manage user identification and custom keys', () async {
      await mockCrashlytics.setUserIdentifier('user-12345');
      expect(mockCrashlytics.currentUserId, 'user-12345');

      await mockCrashlytics.setCustomKey('role', 'admin');
      await mockCrashlytics.setCustomKey('app_version', '1.0.0');

      expect(mockCrashlytics.customKeys['role'], 'admin');
      expect(mockCrashlytics.customKeys['app_version'], '1.0.0');

      await mockCrashlytics.log('User navigated to Admin screen');
      expect(mockCrashlytics.logs, contains('User navigated to Admin screen'));
    });

    test('Toggle crash collection status', () async {
      await mockCrashlytics.setCrashlyticsCollectionEnabled(true);
      expect(mockCrashlytics.isCollectionEnabled, true);

      await mockCrashlytics.setCrashlyticsCollectionEnabled(false);
      expect(mockCrashlytics.isCollectionEnabled, false);
    });
  });
}
