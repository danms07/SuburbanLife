import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import 'qr_service.dart';
import 'qr_generator_screen.dart';
import '../../l10n/app_localizations.dart';

class ManageQrScreen extends StatefulWidget {
  const ManageQrScreen({Key? key}) : super(key: key);

  @override
  _ManageQrScreenState createState() => _ManageQrScreenState();
}

class _ManageQrScreenState extends State<ManageQrScreen> {
  final QrService _qrService = QrService();
  final String? _uid = AuthService().currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(l10n.generateQr, style: const TextStyle(fontFamily: AppConfig.fontFamily)), // Or new string for history
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _uid == null
          ? const Center(child: Text("User not logged in"))
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: _qrService.getUserQrCodes(_uid!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(child: Text(l10n.noQrCodes));
                }

                final qrCodes = snapshot.data!;

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: qrCodes.length,
                  itemBuilder: (context, index) {
                    final qr = qrCodes[index];
                    final timestamp = qr['timestamp'] != null 
                      ? DateTime.fromMillisecondsSinceEpoch(qr['timestamp']) 
                      : DateTime.now();
                    final type = qr['type'] ?? 'temporary';
                    final status = qr['status'] ?? 'active';
                    final qrId = qr['id'] ?? 'unknown';
                    final guestName = qr['guestName'] as String?;
                    final vehiclePlates = qr['vehiclePlates'] as String?;
                    final vehicleType = qr['vehicleType'] as String?;
                    final passengers = qr['passengers'] as int?;
                    final accessCategory = qr['accessCategory'] as String? ?? 'visitor';
                    final isOneTimeUse = qr['isOneTimeUse'] == true;

                    final displayTitle = guestName != null && guestName.isNotEmpty 
                      ? guestName 
                      : '${l10n.type}: ${type.toUpperCase()}';

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        leading: const Icon(Icons.qr_code, color: AppConfig.primaryColor, size: 40),
                        title: Text(
                          displayTitle,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: AppConfig.fontFamily, fontSize: 16),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${l10n.accessCategory}: ${_getTranslatedCategory(l10n, accessCategory)}${isOneTimeUse ? ' (1x)' : ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            if (guestName != null && guestName.isNotEmpty)
                              Text('${l10n.type}: ${type.toUpperCase()}', style: const TextStyle(fontSize: 12)),
                            Text('Created: ${DateFormat('MMM dd, yyyy hh:mm a').format(timestamp)}', style: const TextStyle(fontSize: 12)),
                            if (vehicleType != null)
                              Text('${l10n.vehicleType}: ${_getTranslatedVehicleType(l10n, vehicleType)}', style: const TextStyle(fontSize: 12)),
                            if (vehiclePlates != null && vehiclePlates.isNotEmpty)
                              Text('Plates: $vehiclePlates', style: const TextStyle(fontSize: 12, color: AppConfig.primaryColor, fontWeight: FontWeight.w500)),
                            if (passengers != null)
                              Text('${l10n.passengersCount}: $passengers', style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 4),
                            _buildStatusChip(l10n, status),
                          ],
                        ),
                        trailing: status == 'active'
                            ? IconButton(
                                icon: const Icon(Icons.cancel, color: Colors.redAccent),
                                onPressed: () async {
                                  await _qrService.invalidateQrCode(qrId);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('QR Code invalidated.')),
                                  );
                                },
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const QrGeneratorScreen()),
          );
        },
      ),
    );
  }

  String _getTranslatedStatus(AppLocalizations l10n, String status) {
    switch (status) {
      case 'active':
        return l10n.active;
      case 'deactivated':
        return l10n.deactivated;
      case 'deactivated (revoked)':
        return l10n.deactivatedRevoked;
      case 'deactivated (expired)':
        return l10n.deactivatedExpired;
      case 'deactivated (validated)':
        return l10n.deactivatedValidated;
      default:
        return status;
    }
  }

  Widget _buildStatusChip(AppLocalizations l10n, String status) {
    Color color = Colors.grey;
    if (status == 'active') {
      color = Colors.green;
    } else if (status.startsWith('deactivated')) {
      color = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        _getTranslatedStatus(l10n, status).toUpperCase(),
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _getTranslatedVehicleType(AppLocalizations l10n, String type) {
    switch (type) {
      case 'car':
        return l10n.vehicleCar;
      case 'motorcycle':
        return l10n.vehicleMotorcycle;
      case 'walking':
        return l10n.vehicleWalking;
      default:
        return type.toUpperCase();
    }
  }

  String _getTranslatedCategory(AppLocalizations l10n, String cat) {
    switch (cat) {
      case 'visitor':
        return l10n.categoryVisitor;
      case 'supplier':
        return l10n.categorySupplier;
      default:
        return cat.toUpperCase();
    }
  }
}
