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
  bool _isValidating = false;
  bool _isProcessing = false;
  bool _isUploadingImages = false;
  bool _isCapturingPhoto = false;
  int _activeValidationToken = 0;
  String? _statusMessage;
  bool _isValidQr = false;
  bool _isExitScan = false;
  Map<String, dynamic>? _openLogData;
  QrCode? _currentQrCode;
  XFile? _idCardPhoto;
  XFile? _carPlatePhoto;
  String? _uploadedIdPhotoUrl;
  String? _uploadedPlatePhotoUrl;

  bool get _isBlockingOperation => _isValidating || _isProcessing;
  bool get _isBusy => _isBlockingOperation || _isCapturingPhoto;

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
    _activeValidationToken++;
    _discardPendingTempPhotos();
    _qrCodesSubscription?.cancel();
    _controller.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _resetToScanMode() {
    if (_isBusy || !mounted) return;
    _activeValidationToken++;
    _discardPendingTempPhotos();
    setState(() {
      _isScanning = true;
      _isValidating = false;
      _isUploadingImages = false;
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
      if (mounted && _isScanning && !_isBusy) {
        _controller.start();
      }
    });
  }

  void _onDetect(BarcodeCapture capture) async {
    if (!_isScanning || _isBusy || !mounted) return;

    for (final barcode in capture.barcodes) {
      final code = (barcode.rawValue ?? barcode.displayValue)?.trim();
      if (code != null && code.isNotEmpty) {
        final validationToken = ++_activeValidationToken;
        setState(() {
          _isScanning = false;
          _isValidating = true;
          _isValidQr = false;
          _isExitScan = false;
          _openLogData = null;
          _currentQrCode = null;
          _statusMessage = AppLocalizations.of(context)?.validatingQr;
        });
        try {
          await _controller.stop();
        } catch (e) {
          debugPrint('Error stopping scanner controller: $e');
        }
        if (!mounted || validationToken != _activeValidationToken) return;
        await _validateQr(code, validationToken);
        break;
      }
    }
  }

  String _extractDestinationAddress(
    Map<String, dynamic>? qrData,
    Map<String, dynamic>? openLog,
  ) {
    final directQrAddress =
        (qrData?['addressDisplay'] ?? qrData?['destinationAddress'])?.toString().trim() ?? '';
    if (directQrAddress.isNotEmpty) return directQrAddress;

    final formattedQrAddress = QrCode.formatAddressParts(
      qrData?['streetName'],
      qrData?['number'],
    );
    if (formattedQrAddress.isNotEmpty) return formattedQrAddress;

    final openLogAddress = openLog?['addressDisplay']?.toString().trim() ?? '';
    if (openLogAddress.isNotEmpty) return openLogAddress;

    return QrCode.formatAddressParts(openLog?['streetName'], openLog?['number']);
  }

  Future<String> _resolveAddressFromFirestoreFallback(String creatorUid) async {
    try {
      final userDoc = await DatabaseService().getDocument('users', creatorUid);
      if (userDoc == null) return '';

      final rawAddrRef = userDoc['addressRef'];
      String? addressId;
      if (rawAddrRef is DbReference) {
        addressId = rawAddrRef.id;
      } else if (rawAddrRef is String && rawAddrRef.trim().isNotEmpty) {
        final trimmed = rawAddrRef.trim();
        addressId = trimmed.contains('/') ? trimmed.split('/').last : trimmed;
      } else if (userDoc['addressId'] != null) {
        addressId = userDoc['addressId'].toString().trim();
      }

      if (addressId != null && addressId.isNotEmpty) {
        final addrDoc = await DatabaseService().getDocument('addresses', addressId);
        if (addrDoc != null) {
          final formatted = QrCode.formatAddressParts(
            addrDoc['streetName'],
            addrDoc['number'],
          );
          if (formatted.isNotEmpty) return formatted;
        }
      }

      if (userDoc['role']?.toString().toLowerCase() == 'admin') {
        return 'Admin office';
      }
    } catch (e, stack) {
      debugPrint('Fallback destination address lookup error: $e');
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'QrScannerScreen._resolveAddressFromFirestoreFallback',
      );
    }
    return '';
  }

  String _localizeAddressDisplay(AppLocalizations l10n, String rawAddress) {
    final trimmed = rawAddress.trim();
    if (trimmed.isEmpty) return '';
    final normalized = trimmed.toLowerCase();
    if (normalized == 'admin office' ||
        normalized == 'admin office #0' ||
        normalized == 'oficina de administración' ||
        normalized == 'oficina de administración #0' ||
        normalized == 'oficina de administracion' ||
        normalized == 'oficina de administracion #0') {
      return l10n.adminOffice;
    }
    return trimmed;
  }

  QrCode _buildQrCodeFromResponse(
    String fallbackId,
    Map<String, dynamic> qrData, {
    required String destinationAddress,
    required bool isValid,
    required AppLocalizations l10n,
  }) {
    final rawType = qrData['type']?.toString().trim().toLowerCase();
    final parsedType =
        rawType == QrType.permanent.name ? QrType.permanent : QrType.temporary;
    return QrCode(
      id: qrData['id']?.toString() ?? fallbackId,
      creatorUid: qrData['creatorUid']?.toString() ?? '',
      guestName: (qrData['visitorName'] ?? qrData['guestName'])?.toString() ??
          l10n.guestFallback,
      destinationAddress: destinationAddress.isNotEmpty ? destinationAddress : null,
      vehicleType: qrData['vehicleType'] as String?,
      vehiclePlates: (qrData['vehiclePlate'] ?? qrData['vehiclePlates'])?.toString(),
      passengers: (qrData['passengers'] as num?)?.toInt(),
      type: parsedType,
      isValid: isValid,
    );
  }

  Future<void> _validateQr(String qrId, int validationToken) async {
    final cleanQrId = qrId.trim();
    try {
      final res = await FunctionsService().callFunction('validateAndRegisterQrAccess', {
        'qrId': cleanQrId,
        'mode': 'validate_only',
      });

      if (!mounted || validationToken != _activeValidationToken) return;

      final isGranted = res?['granted'] == true;
      final isExit = res?['isExit'] == true;
      final openLog = res?['openLog'] is Map
          ? Map<String, dynamic>.from(res!['openLog'] as Map)
          : null;
      final qrData = res?['qrData'] is Map
          ? Map<String, dynamic>.from(res!['qrData'] as Map)
          : null;
      final serverReason = res?['reason']?.toString();

      String resolvedAddress = _extractDestinationAddress(qrData, openLog);
      final creatorUid = qrData?['creatorUid']?.toString().trim() ?? '';
      if (isGranted && qrData != null && resolvedAddress.isEmpty && creatorUid.isNotEmpty) {
        resolvedAddress = await _resolveAddressFromFirestoreFallback(creatorUid);
        if (!mounted || validationToken != _activeValidationToken) return;
      }

      final l10n = AppLocalizations.of(context)!;
      final localizedAddress = _localizeAddressDisplay(l10n, resolvedAddress);

      if (!isGranted || qrData == null) {
        setState(() {
          _isValidating = false;
          _statusMessage = serverReason ?? l10n.invalidQrNotFound;
          _isValidQr = false;
          _isExitScan = false;
          _openLogData = null;
          if (qrData != null) {
            _currentQrCode = _buildQrCodeFromResponse(
              cleanQrId,
              qrData,
              destinationAddress: localizedAddress,
              isValid: false,
              l10n: l10n,
            );
          }
        });
        return;
      }

      final qrCode = _buildQrCodeFromResponse(
        cleanQrId,
        qrData,
        destinationAddress: localizedAddress,
        isValid: true,
        l10n: l10n,
      );

      setState(() {
        _isValidating = false;
        _statusMessage = isExit ? l10n.exitScanHeader : l10n.accessGrantedHeader;
        _isValidQr = true;
        _isExitScan = isExit;
        _openLogData = openLog;
        _currentQrCode = qrCode;
      });
    } catch (e, stack) {
      debugPrint('QR validation error: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'QrScannerScreen._validateQr');
      if (mounted && validationToken == _activeValidationToken) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _isValidating = false;
          _statusMessage = l10n.invalidQrNotFound;
          _isValidQr = false;
          _isExitScan = false;
          _openLogData = null;
        });
      }
    } finally {
      if (mounted && validationToken == _activeValidationToken && _isValidating) {
        setState(() {
          _isValidating = false;
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

  Future<void> _captureVisitorPhoto({required bool isIdPhoto}) async {
    if (_isBusy) return;
    setState(() {
      _isCapturingPhoto = true;
    });
    try {
      final photo = await _pickVisitorPhoto();
      if (photo == null) return;
      if (!mounted) {
        unawaited(TempImageCleanupService.deleteTempXFile(photo));
        return;
      }
      final previous = isIdPhoto ? _idCardPhoto : _carPlatePhoto;
      setState(() {
        if (isIdPhoto) {
          _idCardPhoto = photo;
          _uploadedIdPhotoUrl = null;
        } else {
          _carPlatePhoto = photo;
          _uploadedPlatePhotoUrl = null;
        }
      });
      if (previous != null && previous.path != photo.path) {
        unawaited(TempImageCleanupService.deleteTempXFile(previous));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturingPhoto = false;
        });
      }
    }
  }

  void _takeIdPhoto() => _captureVisitorPhoto(isIdPhoto: true);

  void _takePlatePhoto() => _captureVisitorPhoto(isIdPhoto: false);

  void _registerAccess(bool isAllowed) async {
    if (_currentQrCode == null || _isBusy) return;

    final wasExit = _isExitScan;
    final hasPendingUpload = !wasExit &&
        (((_uploadedIdPhotoUrl?.isEmpty ?? true) && _idCardPhoto != null) ||
            ((_uploadedPlatePhotoUrl?.isEmpty ?? true) && _carPlatePhoto != null));
    setState(() {
      _isProcessing = true;
      _isUploadingImages = hasPendingUpload;
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
        _isValidating = false;
        _isProcessing = false;
        _isUploadingImages = false;
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
          _isUploadingImages = false;
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
      onPressed: _isBusy ? null : () => showInteractiveImageDialog(context, imageUrl, title: label),
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

  Widget _buildLoadingOverlay(AppLocalizations l10n) {
    final statusText = _isValidating
        ? l10n.validatingQr
        : (_isUploadingImages ? l10n.uploadingImages : l10n.processingAccessOperation);

    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.45),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Material(
                key: const ValueKey('qr_scanner_loading_overlay'),
                elevation: 10,
                borderRadius: BorderRadius.circular(18),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          color: AppConfig.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        statusText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppConfig.primaryColor,
                          fontFamily: AppConfig.fontFamily,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.qrProcessingWaitHint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                          fontFamily: AppConfig.fontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final headerColor = _isValidating
        ? AppConfig.primaryColor
        : _isValidQr
            ? (_isExitScan ? Colors.teal : Colors.green)
            : Colors.redAccent;
    final headerIcon = _isValidating
        ? Icons.qr_code_scanner
        : _isValidQr
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
              onPressed: _isBusy ? null : () => _controller.switchCamera(),
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
                onPressed: _isBusy ? null : () => _controller.switchCamera(),
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
                            _isValidating ? '' : (_statusMessage ?? ''),
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
                            Builder(
                              builder: (cardContext) {
                                final colorScheme = Theme.of(cardContext).colorScheme;
                                final destinationAddress = _localizeAddressDisplay(
                                  l10n,
                                  _currentQrCode!.destinationAddress ?? '',
                                );
                                return Card(
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
                                        if (destinationAddress.isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          Container(
                                            key: const ValueKey('qr_scanner_destination_address'),
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: colorScheme.primary.withValues(alpha: 0.08),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(
                                                color: colorScheme.primary.withValues(alpha: 0.22),
                                              ),
                                            ),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 1),
                                                  child: Icon(
                                                    Icons.home_outlined,
                                                    size: 20,
                                                    color: colorScheme.primary,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    '${l10n.destinationAddress}: $destinationAddress',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.w600,
                                                      color: colorScheme.primary,
                                                      fontFamily: AppConfig.fontFamily,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
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
                                );
                              },
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
                                enabled: !_isBusy,
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                key: const ValueKey('register_exit_button'),
                                onPressed: _isBusy ? null : () => _registerAccess(true),
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
                                onPressed: _isBusy ? null : _takeIdPhoto,
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
                                onPressed: _isBusy ? null : _takePlatePhoto,
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
                                enabled: !_isBusy,
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      key: const ValueKey('allow_access_button'),
                                      onPressed: _isBusy ? null : () => _registerAccess(true),
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
                                      onPressed: _isBusy ? null : () => _registerAccess(false),
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
                          const SizedBox(height: 16),
                          OutlinedButton(
                            key: const ValueKey('scan_again_button'),
                            onPressed: _isBusy ? null : _resetToScanMode,
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
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_isBlockingOperation) _buildLoadingOverlay(l10n),
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
