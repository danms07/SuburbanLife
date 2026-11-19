import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:suburban_life/core/config/app_config.dart';
import 'package:suburban_life/features/auth/login_screen.dart';
import 'package:suburban_life/features/auth/roommates_screen.dart';
import 'package:suburban_life/features/auth/signup_screen.dart';
import 'package:suburban_life/features/auth/forgot_password_screen.dart';
import 'firebase_options.dart';
import 'package:suburban_life/features/booking/booking_screen.dart';
import 'package:suburban_life/features/booking/manage_bookings_screen.dart';
import 'package:suburban_life/features/transparency/transparency_screen.dart';
import 'package:suburban_life/features/payments/payment_screen.dart';
import 'package:suburban_life/features/sanctions/sanctions_screen.dart';
import 'package:suburban_life/features/announcements/announcements_screen.dart';
import 'package:suburban_life/features/qr_access/qr_generator_screen.dart';
import 'package:suburban_life/features/qr_access/manage_qr_screen.dart';
import 'package:suburban_life/features/qr_access/qr_scanner_screen.dart';
import 'package:suburban_life/features/admin/admin_shell_screen.dart';
import 'package:suburban_life/features/notifications/notifications_screen.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'l10n/app_localizations.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/core/backend/firebase_backend.dart';
import 'package:suburban_life/core/services/app_update_service.dart';
import 'package:suburban_life/core/services/notification_router.dart';
import 'package:suburban_life/core/services/temp_image_cleanup_service.dart';
import 'package:suburban_life/core/widgets/app_version_label.dart';
import 'package:suburban_life/core/widgets/error_fallback_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final crashlyticsService = FirebaseCrashlyticsService();

  if (AppConfig.useFirebaseEmulator) {
    await FirebaseBackend.useEmulator(
      host: AppConfig.emulatorHost.isNotEmpty ? AppConfig.emulatorHost : null,
    );
  } else {
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleAppAttestProvider(),
        providerWeb: ReCaptchaEnterpriseProvider(AppConfig.recaptchaSiteKey),
      );
    } catch (e) {
      debugPrint('App Check activation error (Enterprise): $e');
      try {
        await FirebaseAppCheck.instance.activate(
          providerWeb: ReCaptchaV3Provider(AppConfig.recaptchaSiteKey),
        );
      } catch (e2) {
        debugPrint('App Check activation error (V3): $e2');
      }
    }
  }

  Backend.initialize(
    auth: FirebaseAuthService(),
    db: FirebaseDatabaseService(),
    storage: FirebaseStorageService(),
    functions: FirebaseFunctionsService(),
    crashlytics: crashlyticsService,
    notifications: FirebaseNotificationService(),
  );

  // Configure Crashlytics collection (disable in debug/emulator unless forced)
  await crashlyticsService.setCrashlyticsCollectionEnabled(
    !kDebugMode && !AppConfig.useFirebaseEmulator,
  );

  // Intercept Flutter framework errors (widget build, layout, RenderFlex)
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    crashlyticsService.recordFlutterError(details, fatal: false);
  };

  // Intercept unhandled asynchronous errors (Futures, timers, microtasks)
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    crashlyticsService.recordError(error, stack, fatal: true);
    return true;
  };

  // User-friendly error widget for release mode
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return ErrorFallbackScreen(details: details);
  };

  // Preload bundled app version label before rendering UI
  unawaited(AppVersionLabel.loadVersion());

  // Initialize auto-upgrade service for web
  if (kIsWeb) {
    AppUpdateService.instance.initialize();
  }

  //FirebaseFirestore.setLoggingEnabled(true);
  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    return MaterialApp(
      title: AppConfig.appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppConfig.primaryColor,
          primary: AppConfig.primaryColor,
          secondary: AppConfig.secondaryColor,
        ),
        scaffoldBackgroundColor: AppConfig.backgroundColor,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: AppConfig.textColor),
          bodyMedium: TextStyle(color: AppConfig.textColor),
        ),
        fontFamily: AppConfig.fontFamily,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StreamBuilder<AppUser?>(
        stream: authService.userStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasData) {
            return MyHomePage(
              key: ValueKey(snapshot.data!.uid),
              title: AppConfig.appName,
            );
          }
          return const LoginScreen();
        },
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  bool _isGuard = false;
  bool _isAdmin = false;
  bool _isResident = false;
  bool _showAdminView = false;
  bool _isLoadingRoles = true;
  Map<String, dynamic>? _selectedApprovedAddress;

  final ImagePicker _picker = ImagePicker();
  String? _claimStreet;
  Map<String, dynamic>? _claimAddress;
  bool _isClaimSubmitting = false;
  bool _isOpeningQrScanner = false;
  int _onboardingModeIndex = 0;
  Stream<List<Map<String, dynamic>>>? _unclaimedAddressesStream;
  String? _userAddressesUid;
  Stream<List<Map<String, dynamic>>>? _userAddressesStream;
  String? _claimsUid;
  Stream<List<Map<String, dynamic>>>? _claimsStream;

  String? _notifInitializedUid;
  String? _lastSyncedLocale;
  UserNotificationSettings _notificationSettings = const UserNotificationSettings();
  PushPermissionStatus _permissionStatus = PushPermissionStatus.authorized;
  bool _permissionBannerDismissed = false;
  AppNotification? _activeForegroundBanner;
  Timer? _foregroundBannerTimer;
  String? _queuedNotificationRoute;
  AdminSection? _requestedAdminSection;
  int _requestedAdminSectionToken = 0;
  StreamSubscription<AppNotification>? _foregroundMessageSub;
  StreamSubscription<String>? _openedRouteSub;
  StreamSubscription<UserNotificationSettings>? _settingsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkRoles();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = Backend.auth.currentUser?.uid;
    final lang = Localizations.localeOf(context).languageCode;
    if (uid != null && _notifInitializedUid != uid) {
      _notifInitializedUid = uid;
      _lastSyncedLocale = lang;
      unawaited(_setupNotificationsForUser(uid, lang));
    } else if (uid != null && _lastSyncedLocale != lang) {
      _lastSyncedLocale = lang;
      unawaited(Backend.notifications.syncLocale(uid, lang));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPushPermissionStatus());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _foregroundBannerTimer?.cancel();
    _foregroundMessageSub?.cancel();
    _openedRouteSub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  Future<void> _setupNotificationsForUser(String uid, String languageCode) async {
    _settingsSub?.cancel();
    _foregroundMessageSub?.cancel();
    _openedRouteSub?.cancel();

    _settingsSub = Backend.notifications.watchSettings(uid).listen((settings) {
      if (!mounted) return;
      setState(() {
        _notificationSettings = settings;
        if (!settings.inAppBannerEnabled) {
          _activeForegroundBanner = null;
        }
      });
    });

    _foregroundMessageSub =
        Backend.notifications.onForegroundMessage.listen((notification) {
      if (!mounted) return;
      if (notification.type == 'ownership_claim_approved') {
        _checkRoles();
      }
      if (!_notificationSettings.pushEnabled ||
          !_notificationSettings.inAppBannerEnabled) {
        return;
      }
      if (notification.category != null &&
          !_notificationSettings.isCategoryEnabled(notification.category!)) {
        return;
      }
      _showForegroundBanner(notification);
    });

    _openedRouteSub = Backend.notifications.onNotificationOpenedRoute.listen((route) {
      if (!mounted) return;
      if (_isLoadingRoles) {
        _queuedNotificationRoute = route;
      } else {
        unawaited(_handleNotificationRoute(route));
      }
    });

    await Backend.notifications.initialize(
      uid: uid,
      languageCode: languageCode,
    );
    await _refreshPushPermissionStatus();

    final initialRoute = Backend.notifications.consumeInitialRoute();
    if (initialRoute != null && mounted) {
      if (_isLoadingRoles) {
        _queuedNotificationRoute = initialRoute;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_handleNotificationRoute(initialRoute));
          }
        });
      }
    }
  }

  Future<void> _refreshPushPermissionStatus() async {
    final status = await Backend.notifications.getPermissionStatus();
    if (!mounted) return;
    setState(() {
      _permissionStatus = status;
    });
  }

  Future<void> _requestPushPermissionFromBanner(String uid) async {
    final lang = Localizations.localeOf(context).languageCode;
    final status = await Backend.notifications.requestPermissionAndRegister(
      uid: uid,
      languageCode: lang,
    );
    if (!mounted) return;
    setState(() {
      _permissionStatus = status;
      if (status.isGranted || status == PushPermissionStatus.denied) {
        _permissionBannerDismissed = true;
      }
    });
  }

  void _showForegroundBanner(AppNotification notification) {
    _foregroundBannerTimer?.cancel();
    setState(() {
      _activeForegroundBanner = notification;
    });
    _foregroundBannerTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) {
        _dismissForegroundBanner();
      }
    });
  }

  void _dismissForegroundBanner() {
    _foregroundBannerTimer?.cancel();
    if (_activeForegroundBanner != null && mounted) {
      setState(() {
        _activeForegroundBanner = null;
      });
    }
  }

  Future<void> _handleNotificationRoute(String rawRoute) async {
    final uid = Backend.auth.currentUser?.uid;
    if (uid == null || !mounted || _isGuard) return;

    _dismissForegroundBanner();
    final safeRoute = sanitizeNotificationRoute(rawRoute);

    if (safeRoute == 'notifications') {
      _openNotificationsScreen(context);
      return;
    }

    final adminSection = NotificationRouter.adminSectionForRoute(safeRoute);
    if (adminSection != null) {
      if (_isAdmin) {
        setState(() {
          _showAdminView = true;
          _requestedAdminSection = adminSection;
          _requestedAdminSectionToken++;
        });
      }
      return;
    }

    await NotificationRouter.navigate(
      context: context,
      uid: uid,
      rawRoute: safeRoute,
      isAdmin: _isAdmin,
      isResident: _isResident,
      isAdminWorkspace: _showAdminView,
      onOpenAdminSection: (section) {
        if (!mounted) return;
        setState(() {
          _showAdminView = true;
          _requestedAdminSection = section;
          _requestedAdminSectionToken++;
        });
      },
      onOpenNotificationsInbox: () => _openNotificationsScreen(context),
    );
  }

  void _openNotificationsScreen(BuildContext context) {
    final uid = Backend.auth.currentUser?.uid;
    if (uid == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(
          uid: uid,
          isAdmin: _isAdmin,
          isResident: _isResident,
          isAdminWorkspace: _showAdminView,
          onOpenAdminSection: (section) {
            if (!mounted) return;
            setState(() {
              _showAdminView = true;
              _requestedAdminSection = section;
              _requestedAdminSectionToken++;
            });
          },
        ),
      ),
    );
  }

  Widget _buildPushPermissionOptInCard(AppLocalizations l10n, String uid) {
    if (_isGuard ||
        _permissionBannerDismissed ||
        _permissionStatus != PushPermissionStatus.notDetermined) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        key: const Key('push_permission_opt_in_card'),
        color: colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.notifications_active_outlined, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.notificationPermissionNotDetermined,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      key: const Key('home_enable_push_button'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: const Size(0, 30),
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                      ),
                      onPressed: () => _requestPushPermissionFromBanner(uid),
                      child: Text(l10n.notificationEnablePermissionButton),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.notificationBannerDismissTooltip,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  setState(() {
                    _permissionBannerDismissed = true;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openQrScanner() async {
    if (_isOpeningQrScanner || !mounted) return;
    setState(() {
      _isOpeningQrScanner = true;
    });
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const QrScannerScreen(),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningQrScanner = false;
        });
      }
    }
  }

  Stream<List<Map<String, dynamic>>> _getUnclaimedAddressesStream() {
    return _unclaimedAddressesStream ??= Backend.db
        .streamCollection('addresses')
        .map((docs) {
          final List<Map<String, dynamic>> unclaimed = [];
          for (var doc in docs) {
            final residentUid = doc['residentUid'];
            if (residentUid == null || residentUid.toString().trim().isEmpty) {
              unclaimed.add(doc);
            }
          }
          return unclaimed;
        });
  }

  Stream<List<Map<String, dynamic>>> _getUserAddressesStream(String uid) {
    if (_userAddressesUid != uid || _userAddressesStream == null) {
      _userAddressesUid = uid;
      _userAddressesStream = Backend.db.streamCollection(
        'addresses',
        filters: [QueryFilter('residentUid', FilterOperator.equal, uid)],
      );
    }
    return _userAddressesStream!;
  }

  Stream<List<Map<String, dynamic>>> _getClaimsStream(String uid) {
    if (_claimsUid != uid || _claimsStream == null) {
      _claimsUid = uid;
      _claimsStream = Backend.db.streamCollection(
        'ownership_claims',
        filters: [QueryFilter('userUid', FilterOperator.equal, uid)],
      );
    }
    return _claimsStream!;
  }

  void _checkRoles() async {
    try {
      await _authService.reloadUserToken(forceRefresh: true);
      final isGuard = await _authService.isGuard();
      bool isAdmin = await _authService.isAdmin();
      bool isResident = await _authService.isResident();

      final currentUser = _authService.currentUser;
      if (currentUser != null) {
        final userDoc = await Backend.db.getDocument('users', currentUser.uid);
        final firestoreRole = userDoc?['role']?.toString().toLowerCase();
        if (firestoreRole != null && firestoreRole != 'admin') {
          isAdmin = false;
          if (firestoreRole == 'resident' || firestoreRole == 'roommate') {
            isResident = true;
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _isGuard = isGuard;
        _isAdmin = isAdmin;
        _isResident = isResident;
        _showAdminView = isAdmin && !isResident && !isGuard;
        _isLoadingRoles = false;
      });

      final pendingRoute = _queuedNotificationRoute;
      if (pendingRoute != null) {
        _queuedNotificationRoute = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_handleNotificationRoute(pendingRoute));
          }
        });
      }
    } catch (e, stack) {
      debugPrint('Error checking roles: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'MyHomePageState._checkRoles');
      if (mounted) {
        setState(() {
          _isLoadingRoles = false;
        });
      }
    }
  }

  Future<Map<String, String>> _getUserData(
    String? uid,
    BuildContext context,
  ) async {
    if (uid == null) return {'name': '{NAME}', 'address': ''};

    final userData = await Backend.db.getDocument('users', uid);
    final name = userData?['name'] ?? '{NAME}';
    return {'name': name, 'address': ''};
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_isLoadingRoles) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    late final Widget workspace;
    if (!_showAdminView && _isGuard) {
      workspace = Scaffold(body: _buildGuardPanel(l10n));
    } else if (_showAdminView) {
      workspace = AdminShellScreen(
        appTitle: widget.title,
        isAdmin: _isAdmin,
        isResident: _isResident,
        requestedSection: _requestedAdminSection,
        requestedSectionToken: _requestedAdminSectionToken,
        onSwitchToResidentView: () {
          setState(() {
            _showAdminView = false;
          });
        },
        onResignAdminRole: () async {
          final user = Backend.auth.currentUser;
          if (user != null) {
            await Backend.functions.callFunction('setRole', {
              'uid': user.uid,
              'role': 'resident',
            });
            await Backend.db.updateDocument('users', user.uid, {
              'role': 'resident',
            });
            await _authService.reloadUserToken(forceRefresh: true);
            if (mounted) {
              setState(() {
                _isAdmin = false;
                _isResident = true;
                _showAdminView = false;
              });
            }
          }
        },
        onLogout: () => Backend.auth.signOut(),
      );
    } else {
      workspace = Scaffold(
        drawer: _buildDrawer(context, l10n),
        body: _buildResidentPanel(l10n),
      );
    }

    final showBanner = _activeForegroundBanner != null &&
        _notificationSettings.inAppBannerEnabled;

    return Stack(
      children: [
        workspace,
        if (showBanner)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: InAppNotificationBanner(
              notification: _activeForegroundBanner!,
              languageCode: Localizations.localeOf(context).languageCode,
              onTap: () {
                final item = _activeForegroundBanner!;
                _dismissForegroundBanner();
                final uid = Backend.auth.currentUser?.uid;
                if (uid != null) {
                  unawaited(Backend.notifications.markAsRead(uid, item.id));
                }
                unawaited(_handleNotificationRoute(item.targetRoute));
              },
              onDismiss: _dismissForegroundBanner,
            ),
          ),
      ],
    );
  }

  Widget _buildReviewStatusPage(AppLocalizations l10n, String uid) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _getClaimsStream(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final claims = snapshot.data ?? [];
        if (claims.isEmpty) {
          return _buildAddressSelectionAndProofForm(l10n, uid);
        }

        final claimDoc = claims.first;
        final addressRef = claimDoc['addressRef'] as DbReference?;

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPushPermissionOptInCard(l10n, uid),
                Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            NotificationBellButton(
                              uid: uid,
                              iconColor: AppConfig.primaryColor,
                              onPressed: () => _openNotificationsScreen(context),
                            ),
                          ],
                        ),
                        const Icon(
                          Icons.hourglass_top,
                          size: 80,
                          color: AppConfig.secondaryColor,
                        ),
                    const SizedBox(height: 24),
                    Text(
                      l10n.accountUnderReviewTitle,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppConfig.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.accountUnderReviewMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    FutureBuilder<Map<String, dynamic>?>(
                      future: addressRef != null
                          ? Backend.db.getDocument('addresses', addressRef.id)
                          : null,
                      builder: (context, addrSnap) {
                        final addrData = addrSnap.data;
                        final street = addrData?['streetName'] ?? '';
                        final number = addrData?['number'] ?? '';
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Text(
                            l10n.claimingAddress('$street $number'),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Backend.db.deleteDocument('ownership_claims', claimDoc['id']);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.reviewCancelledSuccess)),
                          );
                        }
                      },
                      icon: const Icon(Icons.cancel, color: Colors.redAccent),
                      label: Text(
                        l10n.cancelReviewButton,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Backend.auth.signOut(),
                      child: Text(
                        l10n.logout,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddressSelectionAndProofForm(AppLocalizations l10n, String uid) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _getUnclaimedAddressesStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final unclaimed = snapshot.data ?? [];

        // Extract streets
        final Set<String> streetsSet = {};
        for (var doc in unclaimed) {
          final street = doc['streetName']?.toString();
          if (street != null && street.isNotEmpty) {
            streetsSet.add(street);
          }
        }
        final streets = streetsSet.toList()..sort();

        // Filter numbers for selected street
        final numbers =
            _claimStreet == null
                  ? <Map<String, dynamic>>[]
                  : unclaimed.where((doc) {
                      return doc['streetName']?.toString() == _claimStreet;
                    }).toList()
              ..sort((a, b) {
                final numA = a['number'] ?? 0;
                final numB = b['number'] ?? 0;
                if (numA is int && numB is int) return numA.compareTo(numB);
                return numA.toString().compareTo(numB.toString());
              });

        // Make sure selection is still valid
        if (_claimAddress != null &&
            !unclaimed.any((doc) => doc['id'] == _claimAddress!['id'])) {
          _claimAddress = null;
        }

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: NotificationBellButton(
                        uid: uid,
                        iconColor: AppConfig.primaryColor,
                        onPressed: () => _openNotificationsScreen(context),
                      ),
                    ),
                    SegmentedButton<int>(
                      segments: [
                        ButtonSegment<int>(
                          value: 0,
                          label: Text(l10n.claimPropertyTab),
                          icon: const Icon(Icons.house),
                        ),
                        ButtonSegment<int>(
                          value: 1,
                          label: Text(l10n.joinAsRoommateTab),
                          icon: const Icon(Icons.qr_code),
                        ),
                      ],
                      selected: {_onboardingModeIndex},
                      onSelectionChanged: (Set<int> newSelection) {
                        setState(() {
                          _onboardingModeIndex = newSelection.first;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    if (_onboardingModeIndex == 1)
                      _buildRoommateQrCodeCard(l10n, uid)
                    else ...[
                      Text(
                        l10n.selectAddressTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppConfig.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppConfig.primaryColor.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppConfig.primaryColor.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: AppConfig.primaryColor),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                l10n.addressClaimInstructions,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black87,
                                  height: 1.4,
                                  fontFamily: AppConfig.fontFamily,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (streets.isEmpty)
                        Text(
                          l10n.noUnclaimedAddresses,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        )
                      else ...[
                        // Street Spinner
                        DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: l10n.selectStreetLabel,
                            prefixIcon: const Icon(
                              Icons.signpost,
                              color: AppConfig.primaryColor,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          initialValue: _claimStreet,
                          items: streets.map((street) {
                            return DropdownMenuItem<String>(
                              value: street,
                              child: Text(street),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _claimStreet = value;
                              _claimAddress = null;
                            });
                          },
                        ),
                        const SizedBox(height: 20),

                        // Number Spinner
                        DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: l10n.selectNumberLabel,
                            prefixIcon: const Icon(
                              Icons.home,
                              color: AppConfig.primaryColor,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          initialValue: _claimAddress?['id'],
                          items: numbers.map((doc) {
                            final numVal = doc['number'] ?? '';
                            return DropdownMenuItem<String>(
                              value: doc['id'],
                              child: Text(numVal.toString()),
                            );
                          }).toList(),
                          onChanged: _claimStreet == null
                              ? null
                              : (value) {
                                  setState(() {
                                    _claimAddress = numbers.firstWhere(
                                      (doc) => doc['id'] == value,
                                    );
                                  });
                                },
                        ),
                        const SizedBox(height: 24),

                        // Privacy Notice
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppConfig.warningColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppConfig.warningColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.privacy_tip,
                                color: AppConfig.warningColor,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  l10n.privacyNoticeProofDeletion,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black87,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Primary Camera Trigger Button
                        ElevatedButton.icon(
                          icon: _isClaimSubmitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.camera_alt),
                          label: Text(
                            _isClaimSubmitting
                                ? l10n.uploadingProof
                                : l10n.captureProofPhoto,
                          ),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(250, 50),
                            backgroundColor: AppConfig.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: (_claimAddress == null || _isClaimSubmitting)
                              ? null
                              : () => _takeClaimPhoto(uid),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          l10n.receiptNotice,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    TextButton.icon(
                      key: const ValueKey('onboarding_logout_button'),
                      onPressed: () => Backend.auth.signOut(),
                      icon: const Icon(Icons.logout, size: 18, color: Colors.grey),
                      label: Text(
                        l10n.logout,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoommateQrCodeCard(AppLocalizations l10n, String uid) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: Backend.db.streamDocument('users', uid),
      builder: (context, snapshot) {
        final userData = snapshot.data;
        final userName = userData?['name'] ?? '';
        final userEmail = userData?['email'] ?? '';

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.myRoommateQrCode,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppConfig.primaryColor,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppConfig.primaryColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppConfig.primaryColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppConfig.primaryColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.showQrToResidentInstructions,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                        height: 1.4,
                        fontFamily: AppConfig.fontFamily,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: QrImageView(
                  data: 'roommate_uid:$uid',
                  version: QrVersions.auto,
                  size: 200.0,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: AppConfig.primaryColor,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: AppConfig.primaryColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (userName.isNotEmpty || userEmail.isNotEmpty) ...[
              Text(
                userName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  fontFamily: AppConfig.fontFamily,
                ),
              ),
              if (userEmail.isNotEmpty)
                Text(
                  userEmail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                    fontFamily: AppConfig.fontFamily,
                  ),
                ),
              const SizedBox(height: 12),
            ],
            Center(
              child: Container(
                padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: SelectableText(
                        'UID: $uid',
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18, color: AppConfig.primaryColor),
                      tooltip: l10n.copyUidButton,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: uid));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.uidCopiedSnackbar),
                            backgroundColor: AppConfig.secondaryColor,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: Text(l10n.copyUidButton),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConfig.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: uid));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.uidCopiedSnackbar),
                    backgroundColor: AppConfig.secondaryColor,
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppConfig.primaryColor,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l10n.waitingToBeLinked,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _takeClaimPhoto(String uid) async {
    if (_claimAddress == null) return;

    setState(() {
      _isClaimSubmitting = true;
    });

    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    try {
      XFile? pickedFile;
      try {
        pickedFile = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 60,
        );
      } catch (cameraError) {
        debugPrint('Camera capture fallback to gallery on web/desktop: $cameraError');
        pickedFile = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 60,
        );
      }

      if (pickedFile == null) {
        setState(() {
          _isClaimSubmitting = false;
        });
        return;
      }

      // Upload to storage
      final storagePath = 'ownership_proofs/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
      String proofUrl = '';
      try {
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          proofUrl = await Backend.storage.uploadFile(
            storagePath,
            bytes,
            contentType: 'image/jpeg',
            metadata: {'uploaderUid': uid},
          );
        } else {
          proofUrl = await Backend.storage.uploadFile(
            storagePath,
            File(pickedFile.path),
            contentType: 'image/jpeg',
            metadata: {'uploaderUid': uid},
          );
        }
      } finally {
        await TempImageCleanupService.deleteTempXFile(pickedFile);
      }

      // Create claim in DB
      final addressRef = Backend.db.createReference('addresses', _claimAddress!['id']);
      await Backend.db.addDocument('ownership_claims', {
        'userUid': uid,
        'addressRef': addressRef,
        'proofUrl': proofUrl,
        'status': 'pending',
        'timestamp': DbFieldValue.serverTimestamp(),
      });

      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.proofUploadedSuccess),
          backgroundColor: AppConfig.secondaryColor,
        ),
      );

      setState(() {
        _claimStreet = null;
        _claimAddress = null;
        _isClaimSubmitting = false;
      });
    } catch (e, stack) {
      debugPrint('Error submitting claim photo: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'MyHomePage._takeClaimPhoto');
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.errorPrefix(e.toString())), backgroundColor: Colors.redAccent),
      );
      setState(() {
        _isClaimSubmitting = false;
      });
    }
  }

  Widget _buildResidentPanel(AppLocalizations l10n) {
    final user = Backend.auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<Map<String, dynamic>?>(
      stream: Backend.db.streamDocument('users', user.uid),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final userData = userSnapshot.data;
        final addressRef = userData?['addressRef'] as DbReference?;

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _getUserAddressesStream(user.uid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final approvedDocs = snapshot.data ?? [];

            // If zero approved homes exist and they don't have a roommate/manual addressRef, show claims screen
            if (approvedDocs.isEmpty && addressRef == null) {
              return _buildReviewStatusPage(l10n, user.uid);
            }

            // Maintain selection context for primary owners
            if (approvedDocs.isNotEmpty) {
              if (_selectedApprovedAddress == null ||
                  !approvedDocs.any(
                    (doc) => doc['id'] == _selectedApprovedAddress!['id'],
                  )) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _selectedApprovedAddress = approvedDocs.first;
                    });
                  }
                });
              }
            }

            final effectiveAddressStream = addressRef != null 
                ? Backend.db.streamDocument('addresses', addressRef.id)
                : (approvedDocs.isNotEmpty ? Backend.db.streamDocument('addresses', approvedDocs.first['id']) : null);

            if (effectiveAddressStream == null) {
              return _buildReviewStatusPage(l10n, user.uid);
            }

            return StreamBuilder<Map<String, dynamic>?>(
              stream: effectiveAddressStream,
              builder: (context, activeAddressSnapshot) {
                if (activeAddressSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final activeAddressDoc = activeAddressSnapshot.data;
                if (activeAddressDoc == null) {
                  return _buildReviewStatusPage(l10n, user.uid);
                }

                final addrData = activeAddressDoc;
                final street = addrData['streetName'] ?? '';
                final number = addrData['number'] ?? '';
                final addressLabel = '$street $number';

                return Column(
                  children: <Widget>[
                    // Custom Header Supporting Dynamic Toolbar Address Spinners
                    Container(
                      padding: EdgeInsets.only(
                        top: MediaQuery.paddingOf(context).top + 16,
                        left: 20,
                        right: 20,
                        bottom: 20,
                      ),
                      decoration: const BoxDecoration(
                        color: AppConfig.primaryColor,
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(30),
                          bottomRight: Radius.circular(30),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Builder(
                                builder: (context) => IconButton(
                                  icon: const Icon(Icons.menu, color: Colors.white),
                                  onPressed: () => Scaffold.of(context).openDrawer(),
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isAdmin)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.admin_panel_settings,
                                        color: Colors.white,
                                      ),
                                      tooltip: l10n.switchToAdminViewTooltip,
                                      onPressed: () {
                                        setState(() {
                                          _showAdminView = true;
                                        });
                                      },
                                    ),
                                  NotificationBellButton(
                                    uid: user.uid,
                                    iconColor: Colors.white,
                                    onPressed: () =>
                                        _openNotificationsScreen(context),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.welcomeUser(userData?['name'] ?? ''),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              fontFamily: AppConfig.fontFamily,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (approvedDocs.length > 1)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<Map<String, dynamic>>(
                                  dropdownColor: AppConfig.primaryColor,
                                  icon: const Icon(
                                    Icons.arrow_drop_down,
                                    color: Colors.white,
                                  ),
                                  isExpanded: true,
                                  value: approvedDocs.any(
                                            (d) => d['id'] == activeAddressDoc['id'],
                                          )
                                      ? approvedDocs.firstWhere(
                                          (d) => d['id'] == activeAddressDoc['id'],
                                        )
                                      : approvedDocs.first,
                                  items: approvedDocs.map((doc) {
                                    return DropdownMenuItem<Map<String, dynamic>>(
                                      value: doc,
                                      child: Text(
                                        '${doc['streetName']} ${doc['number']}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        _selectedApprovedAddress = value;
                                      });
                                      final ref = Backend.db.createReference('addresses', value['id']);
                                      Backend.db.updateDocument('users', user.uid, {'addressRef': ref});
                                    }
                                  },
                                ),
                              ),
                            )
                          else
                            Text(
                              addressLabel,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 15,
                              ),
                            ),
                          const SizedBox(height: 28), // Elegant spacer to prevent the floating status card from overlapping the address text/dropdown below
                        ],
                      ),
                    ),

                    // Floating Status Card
                    Transform.translate(
                      offset: const Offset(0, -25),
                      child: Builder(
                        builder: (context) {
                          final rawStatus = addrData['paymentStatus'] as String?;
                          final paymentStatus = (rawStatus == null || rawStatus.trim().isEmpty) ? 'restricted' : rawStatus;
                          final isWithinGrace = addrData['isWithinGracePeriod'] as bool? ?? false;

                          String statusText = l10n.allInOrder; // Default
                          String subtitleText = l10n.noDebts; // Default
                          IconData statusIcon = Icons.verified_user;
                          Color iconColor = Colors.white;
                          Color avatarBgColor = AppConfig.primaryColor;

                          if (paymentStatus == 'pending' || paymentStatus == 'reviewing') {
                            if (isWithinGrace) {
                              statusText = l10n.paymentRequired;
                              subtitleText = l10n.pleaseMakePayment;
                              statusIcon = Icons.warning;
                              avatarBgColor = Colors.orange;
                            } else {
                              statusText = l10n.accessRestricted;
                              subtitleText = l10n.accountRestrictedMsg;
                              statusIcon = Icons.block;
                              avatarBgColor = Colors.redAccent;
                            }
                          } else if (paymentStatus == 'restricted') {
                            statusText = l10n.accessRestricted;
                            subtitleText = l10n.accountRestrictedMsg;
                            statusIcon = Icons.block;
                            avatarBgColor = Colors.redAccent;
                          }

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 20),
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: avatarBgColor,
                                child: Icon(statusIcon, color: iconColor),
                              ),
                              title: Text(
                                statusText,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontFamily: AppConfig.fontFamily,
                                ),
                              ),
                              subtitle: Text(
                                subtitleText,
                                style: const TextStyle(
                                  fontFamily: AppConfig.fontFamily,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                color: AppConfig.primaryColor,
                                size: 16,
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        PaymentScreen(currentUid: user.uid),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),

            _buildPushPermissionOptInCard(l10n, user.uid),

            // Shortcuts Grid
            Expanded(
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: Backend.db.streamCollection('facilities'),
                    builder: (context, facilitiesSnapshot) {
                      final hasFacilities = !facilitiesSnapshot.hasData || (facilitiesSnapshot.data!.isNotEmpty);

                      return GridView.count(
                        crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 20,
                        childAspectRatio: MediaQuery.of(context).size.width > 600 ? 1.35 : 1.0,
                        children: [
                          _buildGridItem(
                            icon: Icons.description,
                            label: l10n.transparencyGrid,
                            color: AppConfig.primaryColor,
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const TransparencyScreen(isAdminView: false),
                              ),
                            ),
                          ),
                          StreamBuilder<List<Map<String, dynamic>>>(
                            stream: Backend.db.streamCollection('announcements'),
                            builder: (context, announcementsSnapshot) {
                              final docs = announcementsSnapshot.data ?? [];
                              final allowedDocs = docs.where((data) {
                                final targetAudience = data['targetAudience'] ?? 'all';
                                if (targetAudience == 'all') return true;
                                if (targetAudience == 'admin' && _isAdmin) return true;
                                if (targetAudience == 'residents' && (_isResident || _isAdmin)) return true;
                                return false;
                              });

                              final unreadCount = allowedDocs.where((data) {
                                final readBy = List<String>.from(data['readBy'] ?? []);
                                return !readBy.contains(user.uid);
                              }).length;

                              return _buildGridItem(
                                icon: Icons.campaign,
                                label: l10n.noticesGrid,
                                color: AppConfig.primaryColor,
                                badgeCount: unreadCount,
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const AnnouncementsScreen(),
                                  ),
                                ),
                              );
                            },
                          ),
                          _buildGridItem(
                            icon: Icons.qr_code,
                            label: l10n.generateQrGrid,
                            color: AppConfig.primaryColor,
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const QrGeneratorScreen(),
                              ),
                            ),
                          ),
                          if (hasFacilities)
                            _buildGridItem(
                              icon: Icons.calendar_today,
                              label: l10n.bookFacility,
                              color: AppConfig.primaryColor,
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const BookingScreen(),
                                ),
                              ),
                            ),
                          _buildGridItem(
                            icon: Icons.payment,
                            label: l10n.monthlyPayment,
                            color: AppConfig.primaryColor,
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    PaymentScreen(currentUid: user.uid),
                              ),
                            ),
                          ),
                          if (_isResident) ...[
                            _buildGridItem(
                              icon: Icons.gavel,
                              label: l10n.sanctionsMenu,
                              color: AppConfig.primaryColor,
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      SanctionsScreen(currentUid: user.uid),
                                ),
                              ),
                            ),
                            _buildGridItem(
                              icon: Icons.people,
                              label: l10n.familyGroupGrid,
                              color: AppConfig.primaryColor,
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const RoommatesScreen(),
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildGuardPanel(AppLocalizations l10n) {
    final user = Backend.auth.currentUser;

    return Column(
      children: <Widget>[
        FutureBuilder<Map<String, String>>(
          future: _getUserData(user?.uid, context),
          builder: (context, snapshot) {
            final data = snapshot.data ?? {'name': '{NAME}', 'address': ''};
            final userName = data['name']!;

            return Container(
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + 16,
                left: 20,
                right: 20,
                bottom: 30,
              ),
              decoration: const BoxDecoration(
                color: AppConfig.primaryColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          l10n.guardPanelTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: AppConfig.fontFamily,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.white),
                        tooltip: l10n.logout,
                        onPressed: () => Backend.auth.signOut(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.welcomeUser(userName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      fontFamily: AppConfig.fontFamily,
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        children: [
                          const SizedBox(height: 40),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Card(
                              elevation: 6,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: InkWell(
                                key: const ValueKey('guard_scan_qr_button'),
                                borderRadius: BorderRadius.circular(20),
                                onTap: _isOpeningQrScanner ? null : _openQrScanner,
                                child: Padding(
                                  padding: const EdgeInsets.all(30),
                                  child: Column(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.qr_code_scanner,
                                          size: 80,
                                          color: AppConfig.primaryColor,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      Text(
                                        l10n.scanQr,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: AppConfig.primaryColor,
                                          fontFamily: AppConfig.fontFamily,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        l10n.guardInstructions,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          color: Colors.black87,
                                          height: 1.3,
                                          fontFamily: AppConfig.fontFamily,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SafeArea(
                        top: false,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16, 24, 16, 16),
                          child: AppVersionLabel(
                            key: ValueKey('guard_app_version_label'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGridItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
    int badgeCount = 0,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Badge(
              isLabelVisible: badgeCount > 0,
              label: Text(badgeCount.toString()),
              child: Icon(icon, size: 65, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, AppLocalizations l10n) {
    final user = Backend.auth.currentUser;
    if (user == null) return const SizedBox();

    return Drawer(
      child: StreamBuilder<Map<String, dynamic>?>(
        stream: Backend.db.streamDocument('users', user.uid),
        builder: (context, snapshot) {
          final userData = snapshot.data;
          final addressRef = userData?['addressRef'] as DbReference?;
          final hasAddress = addressRef != null;

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: Backend.db.streamCollection('facilities'),
            builder: (context, facilitiesSnapshot) {
              final hasFacilities = !facilitiesSnapshot.hasData || (facilitiesSnapshot.data!.isNotEmpty);

              return Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        DrawerHeader(
                          decoration: const BoxDecoration(
                            color: AppConfig.primaryColor,
                          ),
                          child: Center(
                            child: Image.asset(
                              AppConfig.appLogoAsset,
                              height: 80,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.home),
                          title: Text(l10n.homepage),
                          onTap: () {
                            Navigator.pop(context);
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.notifications_outlined),
                          title: Text(l10n.notificationsInboxTitle),
                          onTap: () {
                            Navigator.pop(context);
                            _openNotificationsScreen(context);
                          },
                        ),
                        // Multi-Address Option
                        ListTile(
                          leading: const Icon(Icons.add_business),
                          title: Text(l10n.claimAnotherAddressMenu),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const SignupScreen(isAdditionalClaim: true),
                              ),
                            );
                          },
                        ),
                        if (hasAddress) ...[
                          if (hasFacilities)
                            ListTile(
                              leading: const Icon(Icons.calendar_today),
                              title: Text(l10n.manageBookings),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const ManageBookingsScreen(),
                                  ),
                                );
                              },
                            ),
                          ListTile(
                            leading: const Icon(Icons.payment),
                            title: Text(l10n.managePayments),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      PaymentScreen(currentUid: user.uid),
                                ),
                              );
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.gavel),
                            title: Text(l10n.sanctionsMenu),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      SanctionsScreen(currentUid: user.uid),
                                ),
                              );
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.qr_code),
                            title: Text(l10n.manageQrCodes),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ManageQrScreen(),
                                ),
                              );
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.lock_reset),
                            title: Text(l10n.resetPasswordTitle),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ForgotPasswordScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(),
                  if (hasAddress)
                    ListTile(
                      leading: const Icon(Icons.link_off, color: Colors.redAccent),
                      title: Text(
                        l10n.resignAddressLabel,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                      onTap: () async {
                        Navigator.pop(context);
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(l10n.resignAddressLabel),
                            content: Text(l10n.resignConfirmText),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(l10n.ok, style: const TextStyle(color: Colors.redAccent)),
                              ),
                            ],
                          ),
                        );

                        if (confirmed == true) {
                          try {
                            await Backend.functions.callFunction('unbindAddress', {
                              'uid': user.uid,
                            });
                            if (context.mounted) {
                              _checkRoles();
                            }
                          } catch (e, stack) {
                            debugPrint('Error unbinding address: $e');
                            Backend.crashlytics.recordError(e, stack, reason: 'MyHomePage.unbindAddress');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(l10n.errorPrefix(e.toString())), backgroundColor: Colors.redAccent),
                              );
                            }
                          }
                        }
                      },
                    ),
                  if (!hasAddress)
                    ListTile(
                      leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                      title: Text(
                        l10n.deleteAccountLabel,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                      onTap: () async {
                        Navigator.pop(context);
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(l10n.deleteAccountLabel),
                            content: Text(l10n.deleteAccountConfirmText),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(l10n.ok, style: const TextStyle(color: Colors.redAccent)),
                              ),
                            ],
                          ),
                        );

                        if (confirmed == true) {
                          try {
                            await Backend.functions.callFunction('deleteOwnAccount');
                            await Backend.auth.signOut();
                          } catch (e, stack) {
                            debugPrint('Error deleting account: $e');
                            Backend.crashlytics.recordError(e, stack, reason: 'MyHomePage.deleteOwnAccount');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(l10n.errorPrefix(e.toString())), backgroundColor: Colors.redAccent),
                              );
                            }
                          }
                        }
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: Text(l10n.logout),
                    onTap: () {
                      Navigator.pop(context);
                      Backend.auth.signOut();
                    },
                  ),
                  const SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Center(
                        child: AppVersionLabel(
                          key: ValueKey('resident_app_version_label'),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
