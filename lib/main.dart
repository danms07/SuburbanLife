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
import 'package:suburban_life/features/auth/admin_resident_approval_screen.dart';
import 'package:suburban_life/features/auth/forgot_password_screen.dart';
import 'firebase_options.dart';
import 'package:suburban_life/features/booking/booking_screen.dart';
import 'package:suburban_life/features/booking/manage_bookings_screen.dart';
import 'package:suburban_life/features/transparency/transparency_screen.dart';
import 'package:suburban_life/features/payments/payment_screen.dart';
import 'package:suburban_life/features/announcements/announcements_screen.dart';
import 'package:suburban_life/features/qr_access/qr_generator_screen.dart';
import 'package:suburban_life/features/qr_access/manage_qr_screen.dart';
import 'package:suburban_life/features/qr_access/qr_scanner_screen.dart';
import 'package:suburban_life/features/admin/admin_create_user_screen.dart';
import 'package:suburban_life/features/admin/admin_payment_approval_screen.dart';
import 'package:suburban_life/features/admin/admin_upload_payment_screen.dart';
import 'package:suburban_life/features/admin/admin_user_management_screen.dart';
import 'package:suburban_life/features/admin/admin_facilities_screen.dart';
import 'package:suburban_life/features/admin/admin_settings_screen.dart';
import 'package:suburban_life/features/admin/admin_payment_report_screen.dart';
import 'package:suburban_life/features/admin/admin_guard_management_screen.dart';
import 'package:suburban_life/features/admin/admin_bulk_user_import_screen.dart';
import 'package:suburban_life/features/admin/admin_bulk_address_import_screen.dart';
import 'package:suburban_life/features/admin/admin_access_logs_screen.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'l10n/app_localizations.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/core/backend/firebase_backend.dart';
import 'package:suburban_life/core/services/app_update_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (AppConfig.useFirebaseEmulator) {
    await FirebaseBackend.useEmulator(
      host: AppConfig.emulatorHost.isNotEmpty ? AppConfig.emulatorHost : null,
    );
  } else {
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
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
  );

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

class _MyHomePageState extends State<MyHomePage> {
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
  int _onboardingModeIndex = 0;
  late final Stream<List<Map<String, dynamic>>> _unclaimedAddressesStream;

  @override
  void initState() {
    super.initState();
    _checkRoles();
    _unclaimedAddressesStream = Backend.db
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

  void _checkRoles() async {
    final isGuard = await _authService.isGuard();
    final isAdmin = await _authService.isAdmin();
    final isResident = await _authService.isResident();

    setState(() {
      _isGuard = isGuard;
      _isAdmin = isAdmin;
      _isResident = isResident;
      _showAdminView = isAdmin && !isResident && !isGuard;
      _isLoadingRoles = false;
    });
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

    if (!_showAdminView && _isGuard) {
      return Scaffold(body: _buildGuardPanel(l10n));
    }

    Widget currentBody;
    String currentTitle = widget.title;

    if (_showAdminView) {
      currentTitle = "$currentTitle (Admin)";
      currentBody = _buildAdminPanel(l10n);
    } else {
      currentBody = _buildResidentPanel(l10n);
    }

    return Scaffold(
      appBar: _showAdminView
          ? AppBar(
              backgroundColor: Theme.of(context).colorScheme.inversePrimary,
              title: Text(currentTitle),
              actions: [
                IconButton(
                  icon: const Icon(Icons.waving_hand),
                  tooltip: l10n.resignAdminRole,
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(l10n.resignAdminRole),
                        content: Text(l10n.resignAdminConfirm),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(l10n.cancel),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              Navigator.pop(context);
                              final user = Backend.auth.currentUser;
                              if (user != null) {
                                await Backend.functions.callFunction('setRole', {
                                  'uid': user.uid,
                                  'role': 'resident',
                                });
                                await Backend.db.updateDocument('users', user.uid, {
                                  'role': 'resident',
                                });
                                setState(() {
                                  _isAdmin = false;
                                  _showAdminView = false;
                                });
                              }
                            },
                            child: Text(l10n.resignAdminRole),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                if (_isAdmin && _isResident)
                  IconButton(
                    icon: const Icon(Icons.person),
                    tooltip: l10n.switchToResidentViewTooltip,
                    onPressed: () {
                      setState(() {
                        _showAdminView = false;
                      });
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () => Backend.auth.signOut(),
                ),
              ],
            )
          : null, // Resident panel uses custom action header without top native AppBar
      drawer: !_showAdminView ? _buildDrawer(context, l10n) : null,
      body: currentBody,
    );
  }

  Widget _buildReviewStatusPage(AppLocalizations l10n, String uid) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Backend.db.streamCollection('ownership_claims', filters: [
        QueryFilter('userUid', FilterOperator.equal, uid),
      ]),
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
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.reviewCancelledSuccess)),
                        );
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
          ),
        );
      },
    );
  }

  Widget _buildAddressSelectionAndProofForm(AppLocalizations l10n, String uid) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _unclaimedAddressesStream,
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
                Text(
                  l10n.waitingToBeLinked,
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[600],
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
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 60,
      );

      if (pickedFile == null) {
        setState(() {
          _isClaimSubmitting = false;
        });
        return;
      }

      // Upload to storage
      final storagePath = 'ownership_proofs/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
      String proofUrl = '';
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
    } catch (e) {
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
          stream: Backend.db.streamCollection(
            'addresses',
            filters: [QueryFilter('residentUid', FilterOperator.equal, user.uid)],
          ),
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
                                  IconButton(
                                    icon: const Icon(
                                      Icons.notifications,
                                      color: Colors.white,
                                    ),
                                    onPressed: () =>
                                        _showNotificationHistoryDialog(context),
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

                          String statusText = l10n.allInOrder; // Default
                          String subtitleText = l10n.noDebts; // Default
                          IconData statusIcon = Icons.verified_user;
                          Color iconColor = Colors.white;
                          Color avatarBgColor = AppConfig.primaryColor;

                          if (paymentStatus == 'pending') {
                            statusText = l10n.paymentRequired;
                            subtitleText = l10n.pleaseMakePayment;
                            statusIcon = Icons.warning;
                            avatarBgColor = Colors.orange;
                          } else if (paymentStatus == 'reviewing') {
                            statusText = l10n.paymentUnderReview;
                            subtitleText = l10n.receiptUnderReview;
                            statusIcon = Icons.hourglass_empty;
                            avatarBgColor = Colors.blue;
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
                                builder: (context) => const TransparencyScreen(),
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
                          if (_isResident)
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

  Widget _buildAdminPanel(AppLocalizations l10n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l10n.adminPanelTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppConfig.primaryColor,
              fontFamily: AppConfig.fontFamily,
            ),
          ),
          const SizedBox(height: 30),

          // Primary Approval Dashboard Option with Badge
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: Backend.db.streamCollection('ownership_claims'),
            builder: (context, snapshot) {
              final count = snapshot.data?.length ?? 0;
              return _buildAdminMenuButton(
                label: l10n.approveResidentsMenu,
                icon: Icons.verified_user,
                color: Colors.deepPurple,
                badgeCount: count,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdminResidentApprovalScreen(),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // Pending Payments Review Option with Badge
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: Backend.db.streamCollection('payments', filters: [
              QueryFilter('status', FilterOperator.equal, 'pending'),
            ]),
            builder: (context, snapshot) {
              final count = snapshot.data?.length ?? 0;
              return _buildAdminMenuButton(
                label: l10n.reviewPaymentsMenu,
                icon: Icons.payments,
                color: Colors.blue,
                badgeCount: count,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdminPaymentApprovalScreen(),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          _buildAdminMenuButton(
            label: l10n.downloadReportMenu,
            icon: Icons.table_chart,
            color: Colors.green[700]!,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AdminPaymentReportScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildAdminMenuButton(
            label: l10n.accessLogsMenu,
            icon: Icons.history,
            color: Colors.blueGrey[800]!,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AdminAccessLogsScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildAdminMenuButton(
            label: l10n.createUserMenu,
            icon: Icons.person_add_alt_1,
            color: AppConfig.primaryColor,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AdminCreateUserScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildAdminMenuButton(
            label: l10n.bulkUserImportMenu,
            icon: Icons.group_add,
            color: Colors.indigo,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AdminBulkUserImportScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildAdminMenuButton(
            label: l10n.bulkAddressImportMenu,
            icon: Icons.domain_add,
            color: Colors.teal,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AdminBulkAddressImportScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildAdminMenuButton(
            label: l10n.uploadPaymentOnBehalfMenu,
            icon: Icons.upload_file,
            color: Colors.orange,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AdminUploadPaymentScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildAdminMenuButton(
            label: l10n.manageUsersMenu,
            icon: Icons.people_alt,
            color: Colors.teal,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AdminUserManagementScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildAdminMenuButton(
            label: l10n.manageGuardsMenu,
            icon: Icons.security,
            color: Colors.blueGrey[700]!,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AdminGuardManagementScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildAdminMenuButton(
            label: l10n.manageFacilitiesMenu,
            icon: Icons.category,
            color: AppConfig.secondaryColor,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AdminFacilitiesScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildAdminMenuButton(
            label: l10n.manageTransparencyDocs,
            icon: Icons.description,
            color: Colors.brown,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const TransparencyScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildAdminMenuButton(
            label: l10n.manageAnnouncements,
            icon: Icons.announcement,
            color: Colors.blueGrey,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => AnnouncementsScreen()),
            ),
          ),
          const SizedBox(height: 16),

          _buildAdminMenuButton(
            label: l10n.generateQr,
            icon: Icons.qr_code,
            color: Colors.indigo,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const QrGeneratorScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildAdminMenuButton(
            label: l10n.adminSettingsMenu,
            icon: Icons.settings,
            color: Colors.grey[700]!,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AdminSettingsScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminMenuButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    int badgeCount = 0,
  }) {
    return ElevatedButton.icon(
      icon: Badge(
        isLabelVisible: badgeCount > 0,
        label: Text(badgeCount.toString()),
        child: Icon(icon, color: Colors.white),
      ),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(55),
        backgroundColor: color,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
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
                      Text(
                        l10n.guardPanelTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFamily: AppConfig.fontFamily,
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

        const SizedBox(height: 40),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const QrScannerScreen(),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
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
                              'assets/icon/app_icon.png',
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
                          } catch (e) {
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
                          } catch (e) {
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
                  const SizedBox(height: 20),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _showNotificationHistoryDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.notificationHistoryTitle),
          content: Text(l10n.notificationHistoryPlaceholder),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.close),
            ),
          ],
        );
      },
    );
  }
}
