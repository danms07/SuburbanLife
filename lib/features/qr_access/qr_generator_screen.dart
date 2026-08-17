import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:suburban_life/core/backend/backend.dart';
import 'package:suburban_life/core/config/app_config.dart';
import 'package:suburban_life/features/qr_access/qr_code.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:universal_html/html.dart' as html;

class QrGeneratorScreen extends StatefulWidget {
  const QrGeneratorScreen({super.key});

  @override
  State<QrGeneratorScreen> createState() => _QrGeneratorScreenState();
}

class _QrGeneratorScreenState extends State<QrGeneratorScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _platesController = TextEditingController();
  final TextEditingController _passengersController = TextEditingController(text: '1');
  String _accessCategory = 'visitor'; // visitor, supplier
  QrType _selectedType = QrType.temporary;
  String _selectedVehicleType = 'car'; // car, motorcycle, walking
  DateTime _expiryTime = DateTime.now().add(const Duration(hours: 24));
  String? _generatedQrId;
  bool _isLoading = false;

  void _generateQr() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the guest name')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final user = AuthService().currentUser;
    if (user == null) return;

    int? passengers;
    if (_selectedVehicleType != 'walking') {
      passengers = int.tryParse(_passengersController.text.trim());
    }

    bool isSupplier = _accessCategory == 'supplier';
    String actualType = isSupplier ? 'temporary' : _selectedType.name;
    DateTime? actualExpiry = isSupplier 
      ? DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59)
      : (_selectedType == QrType.temporary ? _expiryTime : null);

    final qrData = {
      'creatorUid': user.uid,
      'guestName': name,
      'accessCategory': _accessCategory,
      'isOneTimeUse': isSupplier,
      'vehicleType': _selectedVehicleType,
      'vehiclePlates': _selectedVehicleType != 'walking' ? _platesController.text.trim() : null,
      'passengers': passengers,
      'type': actualType,
      'expiryTime': actualExpiry,
      'status': 'active',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    try {
      final docId = await DatabaseService().addDocument('qr_codes', qrData);
      setState(() {
        _generatedQrId = docId;
      });
    } catch (e) {
      debugPrint('Error generating QR: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to generate QR code')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.generateQr),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: user == null
          ? const Center(child: Text('User not logged in'))
          : StreamBuilder<Map<String, dynamic>?>(
              stream: DatabaseService().streamDocument('users', user.uid),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final userData = userSnapshot.data;
                final role = userData?['role'] as String?;
                final isAdmin = role == 'admin';

                if (isAdmin) {
                  final mockAddressData = {
                    'streetName': l10n.adminOffice,
                    'number': '',
                  };
                  return _buildQrGeneratorForm(context, mockAddressData);
                }

                final addressRef = userData?['addressRef'] as DbReference?;

                if (addressRef == null) {
                  return Center(child: Text(l10n.noActiveAddressLinked));
                }

                return StreamBuilder<Map<String, dynamic>?>(
                  stream: DatabaseService().streamDocument('addresses', addressRef.id),
                  builder: (context, addressSnapshot) {
                    if (addressSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final addressData = addressSnapshot.data;
                    final rawStatus = addressData?['paymentStatus'] as String?;
                    final paymentStatus = (rawStatus == null || rawStatus.trim().isEmpty) ? 'restricted' : rawStatus;
                    final isRestricted = paymentStatus == 'restricted';

                    if (isRestricted) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.block, color: Colors.redAccent, size: 60),
                              const SizedBox(height: 16),
                              Text(
                                l10n.accessRestricted,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.accountRestrictedMsg,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context),
                                style: ElevatedButton.styleFrom(backgroundColor: AppConfig.primaryColor, foregroundColor: Colors.white),
                                child: Text(l10n.cancel),
                              )
                            ],
                          ),
                        ),
                      );
                    }

                    return _buildQrGeneratorForm(context, addressData);
                  },
                );
              },
            ),
    );
  }

  Widget _buildQrGeneratorForm(BuildContext context, Map<String, dynamic>? addressData) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: l10n.guestName,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _accessCategory,
            decoration: InputDecoration(labelText: l10n.accessCategory),
            items: [
              DropdownMenuItem(value: 'visitor', child: Text(l10n.categoryVisitor)),
              DropdownMenuItem(value: 'supplier', child: Text(l10n.categorySupplier)),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _accessCategory = value;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _selectedVehicleType,
            decoration: InputDecoration(labelText: l10n.vehicleType),
            items: [
              DropdownMenuItem(value: 'car', child: Text(l10n.vehicleCar)),
              DropdownMenuItem(value: 'motorcycle', child: Text(l10n.vehicleMotorcycle)),
              DropdownMenuItem(value: 'walking', child: Text(l10n.vehicleWalking)),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedVehicleType = value;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          if (_selectedVehicleType != 'walking') ...[
            TextField(
              controller: _platesController,
              decoration: InputDecoration(
                labelText: l10n.vehiclePlates,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passengersController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.passengersCount,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_accessCategory == 'supplier') ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '${l10n.categorySupplier}: Código temporal de un solo uso, válido hasta el final del día.',
                style: const TextStyle(color: Colors.blue, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            DropdownButtonFormField<QrType>(
              value: _selectedType,
              decoration: InputDecoration(labelText: l10n.type),
              items: QrType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(_getTranslatedQrType(l10n, type).toUpperCase()),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedType = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            if (_selectedType == QrType.temporary) ...[
              ListTile(
                title: Text('${l10n.expires}: ${DateFormat('MMM dd, yyyy hh:mm a').format(_expiryTime)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _expiryTime,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_expiryTime),
                    );
                    if (time != null) {
                      setState(() {
                        _expiryTime = DateTime(
                          picked.year,
                          picked.month,
                          picked.day,
                          time.hour,
                          time.minute,
                        );
                      });
                    }
                  }
                },
              ),
              const SizedBox(height: 16),
            ],
          ],
          ElevatedButton(
            onPressed: _isLoading ? null : _generateQr,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConfig.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : Text(l10n.generateQr),
          ),
          const SizedBox(height: 32),
          if (_generatedQrId != null) ...[
            Center(
              child: QrImageView(
                data: _generatedQrId!,
                version: QrVersions.auto,
                size: 200.0,
                foregroundColor: AppConfig.textColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.shareQrVisitor,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppConfig.textColor),
            ),
            const SizedBox(height: 16),
            if (kIsWeb)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.share),
                    label: Text(l10n.shareCodeButton),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConfig.secondaryColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _shareQrCode(
                      '${addressData?['streetName'] ?? ''} ${addressData?['number'] ?? ''}'.trim(),
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: Text(l10n.downloadCodeButton),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConfig.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _shareQrCode(
                      '${addressData?['streetName'] ?? ''} ${addressData?['number'] ?? ''}'.trim(),
                      forceDownload: true,
                    ),
                  ),
                ],
              )
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.share),
                label: Text(l10n.shareCodeButton),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConfig.secondaryColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _shareQrCode(
                  '${addressData?['streetName'] ?? ''} ${addressData?['number'] ?? ''}'.trim(),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _getTranslatedQrType(AppLocalizations l10n, QrType type) {
    switch (type) {
      case QrType.permanent:
        return l10n.qrTypePermanent;
      case QrType.temporary:
        return l10n.qrTypeTemporary;
    }
  }

  void _shareQrCode(String addressLabel, {bool forceDownload = false}) async {
    if (_generatedQrId == null) return;
    final l10n = AppLocalizations.of(context)!;
    
    setState(() { _isLoading = true; });
    
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 800, 1200));
      
      final paintBg = Paint()..color = Colors.white;
      canvas.drawRect(const Rect.fromLTWH(0, 0, 800, 1200), paintBg);
      
      final paintHeader = Paint()..color = AppConfig.primaryColor;
      canvas.drawRect(const Rect.fromLTWH(0, 0, 800, 240), paintHeader);
      
      final logoImage = await _loadAssetImage('assets/icon/app_icon.png');
      canvas.drawImageRect(
        logoImage,
        Rect.fromLTWH(0, 0, logoImage.width.toDouble(), logoImage.height.toDouble()),
        const Rect.fromLTWH(400 - 50, 95 - 50, 100, 100),
        Paint(),
      );
      
      final textPainter = TextPainter(
        text: const TextSpan(
          text: AppConfig.appName,
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(400 - textPainter.width / 2, 170));
      
      final qrPainter = QrPainter(
        data: _generatedQrId!,
        version: QrVersions.auto,
        gapless: true,
        color: AppConfig.textColor,
        emptyColor: Colors.white,
      );
      canvas.save();
      canvas.translate(400 - 200, 290);
      qrPainter.paint(canvas, const Size(400, 400));
      canvas.restore();
      
      final paintDivider = Paint()
        ..color = Colors.grey.shade300
        ..strokeWidth = 2;
      canvas.drawLine(const Offset(100, 740), const Offset(700, 740), paintDivider);
      
      final guestName = _nameController.text.trim();
      final categoryText = _accessCategory == 'supplier' ? l10n.categorySupplier : l10n.categoryVisitor;
      
      String vehicleDetails = '';
      if (_selectedVehicleType == 'walking') {
        vehicleDetails = l10n.vehicleWalking;
      } else {
        final typeText = _selectedVehicleType == 'car' ? l10n.vehicleCar : l10n.vehicleMotorcycle;
        final platesText = _platesController.text.trim();
        final passengersText = _passengersController.text.trim();
        vehicleDetails = '$typeText${platesText.isNotEmpty ? ' ($platesText)' : ''} - $passengersText ${l10n.passengersCount.toLowerCase()}';
      }
      
      String validityText = '';
      if (_accessCategory == 'supplier') {
        validityText = l10n.supplierSingleDayValidity;
      } else if (_selectedType == QrType.permanent) {
        validityText = l10n.qrTypePermanent;
      } else {
        validityText = DateFormat('MMM dd, yyyy hh:mm a').format(_expiryTime);
      }
      
      _drawTextRow(canvas, l10n.cardGuestName, guestName, 770);
      _drawTextRow(canvas, l10n.cardAuthorizedAddress, addressLabel, 850);
      _drawTextRow(canvas, l10n.cardAccessCategory, categoryText, 930);
      _drawTextRow(canvas, l10n.cardValidity, validityText, 1010);
      _drawTextRow(canvas, l10n.cardVehicleDetails, vehicleDetails, 1090);
      
      final picture = recorder.endRecording();
      final img = await picture.toImage(800, 1200);
      final picData = await img.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List bytes = picData!.buffer.asUint8List();
      final String fileName = 'qr_access_${DateTime.now().millisecondsSinceEpoch}.png';

      if (forceDownload && kIsWeb) {
        _triggerWebDownload(bytes, fileName, l10n);
        return;
      }

      try {
        final XFile file = XFile.fromData(
          bytes,
          mimeType: 'image/png',
        );

        final params = ShareParams(
          files: [file],
          fileNameOverrides: [fileName],
          text: l10n.shareQrAccessMessage,
          title: AppConfig.appName,
        );

        final ShareResult result = await SharePlus.instance.share(params);
        if (result.status == ShareResultStatus.success) {
          debugPrint('User successfully shared the QR code!');
        }
      } catch (e) {
        debugPrint('Error sharing image via SharePlus: $e');
        if (kIsWeb) {
          _triggerWebDownload(bytes, fileName, l10n);
        } else {
          rethrow;
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing/downloading: $e')),
      );
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  void _triggerWebDownload(Uint8List bytes, String fileName, AppLocalizations l10n) {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.downloadCodeSuccess), backgroundColor: AppConfig.secondaryColor),
    );
  }
  
  Future<ui.Image> _loadAssetImage(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }
  
  void _drawTextRow(Canvas canvas, String label, String value, double yOffset) {
    final labelPainter = TextPainter(
      text: TextSpan(
        text: label.toUpperCase(),
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    labelPainter.layout();
    labelPainter.paint(canvas, Offset(400 - labelPainter.width / 2, yOffset));

    final valPainter = TextPainter(
      text: TextSpan(
        text: value,
        style: const TextStyle(
          color: AppConfig.textColor,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    valPainter.layout();
    valPainter.paint(canvas, Offset(400 - valPainter.width / 2, yOffset + 25));
  }
}
