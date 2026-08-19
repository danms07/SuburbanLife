import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/backend/backend.dart';
import 'package:image_picker/image_picker.dart';
import 'package:suburban_life/core/config/app_config.dart';
import 'package:suburban_life/features/qr_access/qr_code.dart';
import 'package:suburban_life/l10n/app_localizations.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
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
  QrCode? _currentQrCode;
  XFile? _idCardPhoto;
  XFile? _carPlatePhoto;

  @override
  void initState() {
    super.initState();
    // Realtime listener to cache active QR codes locally for reliable offline/intermittent operations
    _qrCodesSubscription = DatabaseService()
        .streamCollection('qr_codes', filters: [QueryFilter('status', FilterOperator.equal, 'active')])
        .listen((docs) {
      // Documents are automatically populated into the local cache by the SDK
    });
  }

  @override
  void dispose() {
    _qrCodesSubscription?.cancel();
    _controller.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (!_isScanning) return;

    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue ?? barcode.displayValue;
      if (code != null && code.isNotEmpty) {
        setState(() {
          _isScanning = false;
          _statusMessage = AppLocalizations.of(context)!.validatingQr;
        });
        _validateQr(code);
        break;
      }
    }
  }

  void _validateQr(String qrId) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final res = await FunctionsService().callFunction('validateAndRegisterQrAccess', {
        'qrId': qrId,
        'mode': 'validate_only',
      });

      final isGranted = res?['granted'] == true;
      final qrData = res?['qrData'] as Map<String, dynamic>?;
      final serverReason = res?['reason']?.toString();

      if (!isGranted || qrData == null) {
        setState(() {
          _statusMessage = serverReason ?? l10n.invalidQrNotFound;
          _isValidQr = false;
          if (qrData != null) {
            _currentQrCode = QrCode(
              id: qrData['id'] ?? qrId,
              creatorUid: qrData['creatorUid'] ?? '',
              guestName: qrData['visitorName'] ?? qrData['guestName'] ?? l10n.guestFallback,
              vehiclePlates: qrData['vehiclePlate'] ?? qrData['vehiclePlates'],
              type: QrType.temporary,
              isValid: false,
            );
          }
        });
        return;
      }

      final qrCode = QrCode(
        id: qrData['id'] ?? qrId,
        creatorUid: qrData['creatorUid'] ?? '',
        guestName: qrData['visitorName'] ?? qrData['guestName'] ?? l10n.guestFallback,
        vehiclePlates: qrData['vehiclePlate'] ?? qrData['vehiclePlates'],
        type: QrType.temporary,
        isValid: true,
      );

      setState(() {
        _statusMessage = l10n.accessGrantedHeader;
        _isValidQr = true;
        _currentQrCode = qrCode;
      });
    } catch (e) {
      debugPrint('QR validation error: $e');
      setState(() {
        _statusMessage = l10n.invalidQrNotFound;
        _isValidQr = false;
      });
    }
  }

  void _takeIdPhoto() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 60);
    if (photo != null) {
      setState(() {
        _idCardPhoto = photo;
      });
    }
  }

  void _takePlatePhoto() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 60);
    if (photo != null) {
      setState(() {
        _carPlatePhoto = photo;
      });
    }
  }

  void _registerAccess(bool isAllowed) async {
    if (_currentQrCode == null) return;

    setState(() {
      _isProcessing = true;
    });

    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    String visitorIdPhotoUrl = '';
    String visitorPlatePhotoUrl = '';

    try {
      // Upload ID photo if present
      if (_idCardPhoto != null) {
        final path = 'visitor_ids/${DateTime.now().millisecondsSinceEpoch}_id.jpg';
        final dynamic fileData = kIsWeb ? await _idCardPhoto!.readAsBytes() : File(_idCardPhoto!.path);
        visitorIdPhotoUrl = await StorageService().uploadFile(path, fileData);
      }

      // Upload Plate photo if present
      if (_carPlatePhoto != null) {
        final path = 'visitor_plates/${DateTime.now().millisecondsSinceEpoch}_plate.jpg';
        final dynamic fileData = kIsWeb ? await _carPlatePhoto!.readAsBytes() : File(_carPlatePhoto!.path);
        visitorPlatePhotoUrl = await StorageService().uploadFile(path, fileData);
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

      messenger.showSnackBar(
        SnackBar(content: Text(l10n.accessRegisteredSuccess)),
      );

      // Reset state for next scan
      setState(() {
        _isScanning = true;
        _isProcessing = false;
        _statusMessage = null;
        _isValidQr = false;
        _currentQrCode = null;
        _idCardPhoto = null;
        _carPlatePhoto = null;
        _reasonController.clear();
      });
      _controller.start();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.errorPrefix(e.toString()))),
      );
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.scanQr),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // The MobileScanner widget is kept permanently mounted to preserve camera capture stream
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
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
                            _isValidQr ? Icons.check_circle_outline : Icons.error_outline,
                            size: 80,
                            color: _isValidQr ? Colors.green : Colors.redAccent,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _statusMessage ?? '',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: _isValidQr ? Colors.green : Colors.redAccent,
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
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isProcessing ? null : _takeIdPhoto,
                                    icon: Icon(_idCardPhoto != null ? Icons.check : Icons.badge),
                                    label: Text(l10n.captureIdPhoto),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      backgroundColor: _idCardPhoto != null ? Colors.green : AppConfig.secondaryColor,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isProcessing ? null : _takePlatePhoto,
                                    icon: Icon(_carPlatePhoto != null ? Icons.check : Icons.directions_car),
                                    label: Text(l10n.capturePlatePhoto),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      backgroundColor: _carPlatePhoto != null ? Colors.green : AppConfig.primaryColor,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ],
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
                                      onPressed: () => _registerAccess(true),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: Text(l10n.allowAccessButton, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () => _registerAccess(false),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        backgroundColor: Colors.redAccent,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: Text(l10n.denyAccessButton, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                          if (!_isProcessing) ...[
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _isScanning = true;
                                  _statusMessage = null;
                                  _isValidQr = false;
                                  _currentQrCode = null;
                                  _idCardPhoto = null;
                                  _carPlatePhoto = null;
                                  _reasonController.clear();
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: Text(l10n.scanAgainButton, style: const TextStyle(fontSize: 16)),
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
