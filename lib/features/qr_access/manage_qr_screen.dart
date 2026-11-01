import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import 'qr_service.dart';
import 'qr_generator_screen.dart';
import '../../l10n/app_localizations.dart';

class ManageQrScreen extends StatefulWidget {
  const ManageQrScreen({super.key});

  @override
  State<ManageQrScreen> createState() => _ManageQrScreenState();
}

class _ManageQrScreenState extends State<ManageQrScreen> {
  final QrService _qrService = QrService();
  final String? _uid = AuthService().currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final uid = _uid;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(l10n.generateQr, style: const TextStyle(fontFamily: AppConfig.fontFamily)), // Or new string for history
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: uid == null
          ? Center(child: Text(l10n.userNotLoggedIn))
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: _qrService.getUserQrCodes(uid),
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
                    final status = QrService.resolveEffectiveStatus(qr);
                    final qrId = qr['id'] ?? 'unknown';
                    final guestName = qr['guestName'] as String?;
                    final vehiclePlates = qr['vehiclePlates'] as String?;
                    final vehicleType = qr['vehicleType'] as String?;
                    final passengers = qr['passengers'] as int?;
                    final accessCategory = qr['accessCategory'] as String? ?? 'visitor';
                    final isOneTimeUse = qr['isOneTimeUse'] == true || qr['isOneTime'] == true || accessCategory == 'supplier';

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
                            Text(l10n.qrItemCreated(DateFormat('MMM dd, yyyy hh:mm a').format(timestamp)), style: const TextStyle(fontSize: 12)),
                            if (vehicleType != null)
                              Text('${l10n.vehicleType}: ${_getTranslatedVehicleType(l10n, vehicleType)}', style: const TextStyle(fontSize: 12)),
                            if (vehiclePlates != null && vehiclePlates.isNotEmpty)
                              Text(l10n.qrItemPlates(vehiclePlates), style: const TextStyle(fontSize: 12, color: AppConfig.primaryColor, fontWeight: FontWeight.w500)),
                            if (passengers != null)
                              Text('${l10n.passengersCount}: $passengers', style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _buildStatusChip(l10n, status),
                                if (QrService.isVisitorInside(qr))
                                  _buildInsideChip(l10n, qrId),
                              ],
                            ),
                          ],
                        ),
                        trailing: status == 'active'
                            ? IconButton(
                                icon: const Icon(Icons.cancel, color: Colors.redAccent),
                                onPressed: () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  await _qrService.invalidateQrCode(qrId);
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                    SnackBar(content: Text(l10n.qrInvalidatedSuccess)),
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
      case 'revoked':
      case 'deactivated (revoked)':
        return l10n.deactivatedRevoked;
      case 'expired':
      case 'deactivated (expired)':
        return l10n.deactivatedExpired;
      case 'used':
      case 'deactivated (validated)':
        return l10n.deactivatedValidated;
      default:
        return status;
    }
  }

  Widget _buildInsideChip(AppLocalizations l10n, String qrId) {
    return Container(
      key: ValueKey('qr_inside_badge_$qrId'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sensor_door_outlined, size: 13, color: Colors.teal),
          const SizedBox(width: 4),
          Text(
            l10n.qrStatusInside.toUpperCase(),
            style: const TextStyle(color: Colors.teal, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(AppLocalizations l10n, String status) {
    Color color = Colors.grey;
    if (status == 'active') {
      color = Colors.green;
    } else if (status.startsWith('deactivated') || status == 'used' || status == 'revoked' || status == 'expired') {
      color = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
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
