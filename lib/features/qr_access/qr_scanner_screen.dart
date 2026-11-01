import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/backend/backend.dart';
import '../../core/services/temp_image_cleanup_service.dart';
import '../../core/widgets/interactive_image_dialog.dart';
import 'package:image_picker/image_picker.dart';
import 'package:suburban_life/core/config/app_config.dart';
import 'package:suburban_life/features/qr_access/qr_code.dart';
import 'package:suburban_life/l10n/app_localizations.dart';

class QrScannerScreen extends StatefulWidget {
  final Future<XFile?> Function()? photoPickerOverride;

  const QrScannerScreen({super.key, this.photoPickerOverride});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  static const double _maxVisitorPhotoDimension = 1600;

  final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
  );
  final TextEditingController _reasonController = TextEditingController();
  StreamSubscription<List<Map<String, dynamic>>>? _qrCodesSubscription;
  bool _isScanning = true;
  bool _isProcessing = false;
  String? _statusMessage;
  bool _isValidQr = false;
  bool _isExitScan = false;
  Map<String, dynamic>? _openLogData;
  QrCode? _currentQrCode;
  XFile? _idCardPhoto;
  XFile? _carPlatePhoto;
  String? _uploadedIdPhotoUrl;
  String? _uploadedPlatePhotoUrl;

  @override
  void initState() {
    super.initState();
    // Reclaim internal storage from any stale temporary camera captures left by prior sessions
    unawaited(TempImageCleanupService.purgeStalePickerImages());
    // Realtime listener to cache active QR codes locally for reliable offline/intermittent operations
    _qrCodesSubscription = DatabaseService()
        .streamCollection('qr_codes', filters: [QueryFilter('status', FilterOperator.equal, 'active')])
        .listen((docs) {
      // Documents are automatically populated into the local cache by the SDK
    });
  }

  void _discardPendingTempPhotos() {
    final idPhoto = _idCardPhoto;
    final platePhoto = _carPlatePhoto;
    _idCardPhoto = null;
    _carPlatePhoto = null;
    if (idPhoto != null) {
      unawaited(TempImageCleanupService.deleteTempXFile(idPhoto));
    }
    if (platePhoto != null) {
      unawaited(TempImageCleanupService.deleteTempXFile(platePhoto));
    }
  }

  @override
  void dispose() {
    _discardPendingTempPhotos();
    _qrCodesSubscription?.cancel();
    _controller.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (!_isScanning || !mounted) return;

    for (final barcode in capture.barcodes) {
      final code = (barcode.rawValue ?? barcode.displayValue)?.trim();
      if (code != null && code.isNotEmpty) {
        setState(() {
          _isScanning = false;
          _statusMessage = AppLocalizations.of(context)?.validatingQr;
        });
        try {
          await _controller.stop();
        } catch (e) {
          debugPrint('Error stopping scanner controller: $e');
        }
        if (!mounted) return;
        _validateQr(code);
        break;
      }
    }
  }

  void _validateQr(String qrId) async {
    final cleanQrId = qrId.trim();
    try {
      final res = await FunctionsService().callFunction('validateAndRegisterQrAccess', {
        'qrId': cleanQrId,
        'mode': 'validate_only',
      });

      if (!mounted) return;

      final l10n = AppLocalizations.of(context)!;
      final isGranted = res?['granted'] == true;
      final isExit = res?['isExit'] == true;
      final openLog = res?['openLog'] is Map
          ? Map<String, dynamic>.from(res!['openLog'] as Map)
          : null;
      final qrData = res?['qrData'] is Map
          ? Map<String, dynamic>.from(res!['qrData'] as Map)
          : null;
      final serverReason = res?['reason']?.toString();

      if (!isGranted || qrData == null) {
        setState(() {
          _statusMessage = serverReason ?? l10n.invalidQrNotFound;
          _isValidQr = false;
          _isExitScan = false;
          _openLogData = null;
          if (qrData != null) {
            _currentQrCode = QrCode(
              id: qrData['id'] ?? cleanQrId,
              creatorUid: qrData['creatorUid'] ?? '',
              guestName: qrData['visitorName'] ?? qrData['guestName'] ?? l10n.guestFallback,
              vehicleType: qrData['vehicleType'] as String?,
              vehiclePlates: qrData['vehiclePlate'] ?? qrData['vehiclePlates'],
              passengers: qrData['passengers'] as int?,
              type: QrType.temporary,
              isValid: false,
            );
          }
        });
        return;
      }

      final qrCode = QrCode(
        id: qrData['id'] ?? cleanQrId,
        creatorUid: qrData['creatorUid'] ?? '',
        guestName: qrData['visitorName'] ?? qrData['guestName'] ?? l10n.guestFallback,
        vehicleType: qrData['vehicleType'] as String?,
        vehiclePlates: qrData['vehiclePlate'] ?? qrData['vehiclePlates'],
        passengers: qrData['passengers'] as int?,
        type: QrType.temporary,
        isValid: true,
      );

      setState(() {
        _statusMessage = isExit ? l10n.exitScanHeader : l10n.accessGrantedHeader;
        _isValidQr = true;
        _isExitScan = isExit;
        _openLogData = openLog;
        _currentQrCode = qrCode;
      });
    } catch (e, stack) {
      debugPrint('QR validation error: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'QrScannerScreen._validateQr');
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _statusMessage = l10n.invalidQrNotFound;
          _isValidQr = false;
          _isExitScan = false;
          _openLogData = null;
        });
      }
    }
  }

  Future<XFile?> _pickVisitorPhoto() async {
    XFile? photo;
    try {
      // Release mobile scanner camera lock before attempting image capture
      try {
        await _controller.stop();
      } catch (e, stack) {
        debugPrint('Scanner stop note: $e');
        Backend.crashlytics.recordError(e, stack, reason: 'QrScannerScreen.stopScanner');
      }

      if (widget.photoPickerOverride != null) {
        return await widget.photoPickerOverride!();
      }

      final picker = ImagePicker();
      try {
        photo = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: _maxVisitorPhotoDimension,
          maxHeight: _maxVisitorPhotoDimension,
          imageQuality: 60,
        );
      } catch (cameraError) {
        debugPrint('Camera capture note (falling back to gallery/file): $cameraError');
        // Graceful fallback to file selection if camera is busy or unavailable (common on Web)
        photo = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: _maxVisitorPhotoDimension,
          maxHeight: _maxVisitorPhotoDimension,
          imageQuality: 60,
        );
      }
    } catch (e, stack) {
      debugPrint('Error capturing visitor photo: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'QrScannerScreen._pickVisitorPhoto');
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorPrefix(e.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
    return photo;
  }

  void _takeIdPhoto() async {
    final photo = await _pickVisitorPhoto();
    if (photo == null) return;
    if (!mounted) {
      unawaited(TempImageCleanupService.deleteTempXFile(photo));
      return;
    }
    final previous = _idCardPhoto;
    setState(() {
      _idCardPhoto = photo;
      _uploadedIdPhotoUrl = null;
    });
    if (previous != null && previous.path != photo.path) {
      unawaited(TempImageCleanupService.deleteTempXFile(previous));
    }
  }

  void _takePlatePhoto() async {
    final photo = await _pickVisitorPhoto();
    if (photo == null) return;
    if (!mounted) {
      unawaited(TempImageCleanupService.deleteTempXFile(photo));
      return;
    }
    final previous = _carPlatePhoto;
    setState(() {
      _carPlatePhoto = photo;
      _uploadedPlatePhotoUrl = null;
    });
    if (previous != null && previous.path != photo.path) {
      unawaited(TempImageCleanupService.deleteTempXFile(previous));
    }
  }

  void _registerAccess(bool isAllowed) async {
    if (_currentQrCode == null) return;

    final wasExit = _isExitScan;
    setState(() {
      _isProcessing = true;
    });

    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    String visitorIdPhotoUrl = _uploadedIdPhotoUrl ?? '';
    String visitorPlatePhotoUrl = _uploadedPlatePhotoUrl ?? '';

    try {
      if (!wasExit) {
        // Upload ID photo if present, then immediately remove local device file
        if (visitorIdPhotoUrl.isEmpty && _idCardPhoto != null) {
          final idPhoto = _idCardPhoto!;
          final path = 'visitor_ids/${DateTime.now().millisecondsSinceEpoch}_id.jpg';
          final dynamic fileData = kIsWeb ? await idPhoto.readAsBytes() : File(idPhoto.path);
          visitorIdPhotoUrl = await StorageService().uploadFile(path, fileData);
          _uploadedIdPhotoUrl = visitorIdPhotoUrl;
          _idCardPhoto = null;
          await TempImageCleanupService.deleteTempXFile(idPhoto);
        }

        // Upload Plate photo if present, then immediately remove local device file
        if (visitorPlatePhotoUrl.isEmpty && _carPlatePhoto != null) {
          final platePhoto = _carPlatePhoto!;
          final path = 'visitor_plates/${DateTime.now().millisecondsSinceEpoch}_plate.jpg';
          final dynamic fileData = kIsWeb ? await platePhoto.readAsBytes() : File(platePhoto.path);
          visitorPlatePhotoUrl = await StorageService().uploadFile(path, fileData);
          _uploadedPlatePhotoUrl = visitorPlatePhotoUrl;
          _carPlatePhoto = null;
          await TempImageCleanupService.deleteTempXFile(platePhoto);
        }
      }

      // Call server-side atomic validation and logging Cloud Function
      await FunctionsService().callFunction('validateAndRegisterQrAccess', {
        'qrId': _currentQrCode!.id,
        'isAllowed': isAllowed,
        'visitorIdPhotoUrl': visitorIdPhotoUrl,
        'visitorPlatePhotoUrl': visitorPlatePhotoUrl,
        'reason': _reasonController.text.trim(),
        'mode': 'validate_and_register',
      });

      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(content: Text(wasExit ? l10n.exitRegisteredSuccess : l10n.accessRegisteredSuccess)),
      );

      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
        return;
      }

      // Fallback when rendered as a standalone root widget (e.g., isolated test harness)
      setState(() {
        _isScanning = true;
        _isProcessing = false;
        _statusMessage = null;
        _isValidQr = false;
        _isExitScan = false;
        _openLogData = null;
        _currentQrCode = null;
        _idCardPhoto = null;
        _carPlatePhoto = null;
        _uploadedIdPhotoUrl = null;
        _uploadedPlatePhotoUrl = null;
        _reasonController.clear();
      });
      _controller.start();
    } catch (e, stack) {
      debugPrint('Error registering access: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'QrScannerScreen._registerAccess');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.errorPrefix(e.toString()))),
        );
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  String _formatEntryMillis(dynamic rawMillis) {
    if (rawMillis is int && rawMillis > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(rawMillis).toLocal();
      return DateFormat('yyyy-MM-dd HH:mm').format(dt);
    }
    return '';
  }

  Widget _buildEntryPhotoButton({
    required BuildContext context,
    required String imageUrl,
    required String label,
    required IconData icon,
  }) {
    return OutlinedButton.icon(
      onPressed: () => showInteractiveImageDialog(context, imageUrl, title: label),
      icon: Icon(icon, size: 18, color: AppConfig.primaryColor),
      label: Text(
        label,
        style: const TextStyle(color: AppConfig.primaryColor, fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        side: BorderSide(color: AppConfig.primaryColor.withValues(alpha: 0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final headerColor = _isValidQr
        ? (_isExitScan ? Colors.teal : Colors.green)
        : Colors.redAccent;
    final headerIcon = _isValidQr
        ? (_isExitScan ? Icons.logout_rounded : Icons.check_circle_outline)
        : Icons.error_outline;

    final entryTimeFormatted = _formatEntryMillis(_openLogData?['entryTimestampMillis']);
    final entryIdPhotoUrl = _openLogData?['visitorIdPhotoUrl']?.toString().trim() ?? '';
    final entryPlatePhotoUrl = _openLogData?['visitorPlatePhotoUrl']?.toString().trim() ?? '';
    final hasIdPhoto = _idCardPhoto != null || (_uploadedIdPhotoUrl?.isNotEmpty ?? false);
    final hasPlatePhoto = _carPlatePhoto != null || (_uploadedPlatePhotoUrl?.isNotEmpty ?? false);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.scanQr),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (_isScanning)
            IconButton(
              icon: ValueListenableBuilder<MobileScannerState>(
                valueListenable: _controller,
                builder: (context, state, child) {
                  return Icon(
                    state.cameraDirection == CameraFacing.front
                        ? Icons.camera_front
                        : Icons.camera_rear,
                  );
                },
              ),
              tooltip: l10n.switchCamera,
              onPressed: () => _controller.switchCamera(),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Unmount MobileScanner when not scanning so camera/GPU buffers are freed before photo capture
          if (_isScanning)
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            ),
          if (_isScanning)
            Positioned(
              bottom: 24,
              right: 24,
              child: FloatingActionButton.small(
                heroTag: 'qr_scanner_switch_camera_fab',
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
                tooltip: l10n.switchCamera,
                onPressed: () => _controller.switchCamera(),
                child: ValueListenableBuilder<MobileScannerState>(
                  valueListenable: _controller,
                  builder: (context, state, child) {
                    return Icon(
                      state.cameraDirection == CameraFacing.front
                          ? Icons.camera_front
                          : Icons.camera_rear,
                    );
                  },
                ),
              ),
            ),
          // Overlay processing or validation result when not actively scanning
          if (!_isScanning)
            Container(
              color: AppConfig.backgroundColor,
              child: Column(
                children: [
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            headerIcon,
                            size: 80,
                            color: headerColor,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _statusMessage ?? '',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: headerColor,
                              fontFamily: AppConfig.fontFamily,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_isValidQr && _currentQrCode != null) ...[
                            Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.visitorDetails,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppConfig.primaryColor,
                                        fontFamily: AppConfig.fontFamily,
                                      ),
                                    ),
                                    const Divider(),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${l10n.guestName}: ${_currentQrCode!.guestName}',
                                      style: const TextStyle(fontSize: 16, fontFamily: AppConfig.fontFamily),
                                    ),
                                    if (_currentQrCode!.vehicleType?.isNotEmpty ?? false) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        '${l10n.vehicleType}: ${_getTranslatedVehicleType(l10n, _currentQrCode!.vehicleType)}',
                                        style: const TextStyle(fontSize: 16, fontFamily: AppConfig.fontFamily),
                                      ),
                                    ],
                                    if (_currentQrCode!.passengers != null) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        '${l10n.passengersCount}: ${_currentQrCode!.passengers}',
                                        style: const TextStyle(fontSize: 16, fontFamily: AppConfig.fontFamily),
                                      ),
                                    ],
                                    if (_currentQrCode!.vehiclePlates?.isNotEmpty ?? false) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        '${l10n.vehiclePlates}: ${_currentQrCode!.vehiclePlates}',
                                        style: const TextStyle(fontSize: 16, fontFamily: AppConfig.fontFamily),
                                      ),
                                    ],
                                    if (_isExitScan && entryTimeFormatted.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        '${l10n.entryTimeLabel}: $entryTimeFormatted',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.teal,
                                          fontFamily: AppConfig.fontFamily,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_isExitScan) ...[
                              if (entryIdPhotoUrl.isNotEmpty || entryPlatePhotoUrl.isNotEmpty) ...[
                                Text(
                                  l10n.entryPhotosLabel,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppConfig.primaryColor,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    if (entryIdPhotoUrl.isNotEmpty)
                                      _buildEntryPhotoButton(
                                        context: context,
                                        imageUrl: entryIdPhotoUrl,
                                        label: l10n.viewVisitorIdPhoto,
                                        icon: Icons.badge_outlined,
                                      ),
                                    if (entryPlatePhotoUrl.isNotEmpty)
                                      _buildEntryPhotoButton(
                                        context: context,
                                        imageUrl: entryPlatePhotoUrl,
                                        label: l10n.viewPlatePhoto,
                                        icon: Icons.pin_outlined,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],
                              TextField(
                                key: const ValueKey('exit_notes_field'),
                                controller: _reasonController,
                                decoration: InputDecoration(
                                  labelText: l10n.exitNotesOptional,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                enabled: !_isProcessing,
                              ),
                              const SizedBox(height: 20),
                              if (_isProcessing)
                                const Center(child: CircularProgressIndicator())
                              else
                                ElevatedButton.icon(
                                  key: const ValueKey('register_exit_button'),
                                  onPressed: () => _registerAccess(true),
                                  icon: const Icon(Icons.logout_rounded),
                                  label: Text(
                                    l10n.registerExitButton,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                            ] else ...[
                              ElevatedButton.icon(
                                key: const ValueKey('capture_id_photo_button'),
                                onPressed: _isProcessing ? null : _takeIdPhoto,
                                icon: Icon(hasIdPhoto ? Icons.check_circle : Icons.badge),
                                label: Text(
                                  l10n.captureIdPhoto,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                  backgroundColor: hasIdPhoto ? Colors.green : AppConfig.secondaryColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                key: const ValueKey('capture_plate_photo_button'),
                                onPressed: _isProcessing ? null : _takePlatePhoto,
                                icon: Icon(hasPlatePhoto ? Icons.check_circle : Icons.directions_car),
                                label: Text(
                                  l10n.capturePlatePhoto,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                  backgroundColor: hasPlatePhoto ? Colors.green : AppConfig.primaryColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _reasonController,
                                decoration: InputDecoration(
                                  labelText: l10n.reasonOptional,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                enabled: !_isProcessing,
                              ),
                              const SizedBox(height: 20),
                              if (_isProcessing)
                                Column(
                                  children: [
                                    const CircularProgressIndicator(),
                                    const SizedBox(height: 12),
                                    Text(l10n.uploadingImages, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
                                  ],
                                )
                              else
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        key: const ValueKey('allow_access_button'),
                                        onPressed: () => _registerAccess(true),
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        child: Text(
                                          l10n.allowAccessButton,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        key: const ValueKey('deny_access_button'),
                                        onPressed: () => _registerAccess(false),
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                                          backgroundColor: Colors.redAccent,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        child: Text(
                                          l10n.denyAccessButton,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ],
                          if (!_isProcessing) ...[
                            const SizedBox(height: 16),
                            OutlinedButton(
                              key: const ValueKey('scan_again_button'),
                              onPressed: () {
                                _discardPendingTempPhotos();
                                setState(() {
                                  _isScanning = true;
                                  _statusMessage = null;
                                  _isValidQr = false;
                                  _isExitScan = false;
                                  _openLogData = null;
                                  _currentQrCode = null;
                                  _uploadedIdPhotoUrl = null;
                                  _uploadedPlatePhotoUrl = null;
                                  _reasonController.clear();
                                });
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted && _isScanning) {
                                    _controller.start();
                                  }
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: Text(
                                l10n.scanAgainButton,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _getTranslatedVehicleType(AppLocalizations l10n, String? vType) {
    if (vType == 'car') return l10n.vehicleCar;
    if (vType == 'motorcycle') return l10n.vehicleMotorcycle;
    if (vType == 'walking') return l10n.vehicleWalking;
    return vType ?? '';
  }
}
