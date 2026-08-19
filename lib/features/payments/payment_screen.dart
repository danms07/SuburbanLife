import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import 'payment_service.dart';
import '../../l10n/app_localizations.dart';

class PaymentScreen extends StatefulWidget {
  final String currentUid;

  const PaymentScreen({Key? key, required this.currentUid}) : super(key: key);

  @override
  _PaymentScreenState createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final PaymentService _paymentService = PaymentService();
  String? _selectedPeriod;

  void _takePhoto() async {
    if (_selectedPeriod == null) return;
    final l10n = AppLocalizations.of(context)!;
    try {
      await _paymentService.uploadPaymentReceipt(widget.currentUid, _selectedPeriod!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.proofUploadedSuccess),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorPrefix(e.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(l10n.maintenancePayment, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: DatabaseService().streamDocument('users', widget.currentUid),
        builder: (context, userSnap) {
          if (userSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final userData = userSnap.data;
          final addressRef = userData?['addressRef'] as DbReference?;
          if (addressRef == null) {
            return Center(
              child: Text(
                l10n.noPendingPeriods,
                style: const TextStyle(fontSize: 16, color: Colors.grey, fontFamily: AppConfig.fontFamily),
              ),
            );
          }

          return StreamBuilder<Map<String, dynamic>?>(
            stream: DatabaseService().streamDocument('addresses', addressRef.id),
            builder: (context, addressSnap) {
              if (addressSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final addressData = addressSnap.data;
              if (addressData == null) {
                return Center(child: Text(l10n.addressDetailsNotFound));
              }

              final paymentStatus = addressData['paymentStatus'] as String? ?? 'restricted';
              final deliveryTimestamp = addressData['deliveryDate'] as DateTime?;

              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: DatabaseService().streamCollection(
                  'payments',
                  filters: [QueryFilter('addressRef', FilterOperator.equal, addressRef)],
                ),
                builder: (context, paymentsSnap) {
                  if (paymentsSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // Compute missing periods!
                  final paymentsMap = <String, String>{};
                  final docs = paymentsSnap.data ?? [];
                  for (var pData in docs) {
                    final period = pData['period'] as String?;
                    final status = pData['status'] as String?;
                    if (period != null && status != null) {
                      final existing = paymentsMap[period];
                      if (existing == null ||
                          status == 'approved' ||
                          (status == 'pending' && existing == 'rejected')) {
                        paymentsMap[period] = status;
                      }
                    }
                  }

                  final List<String> requiredPeriods = [];
                  if (deliveryTimestamp != null) {
                    final deliveryDate = deliveryTimestamp;
                    var current = DateTime(deliveryDate.year, deliveryDate.month, 1);
                    final now = DateTime.now();
                    final target = DateTime(now.year, now.month, 1);

                    while (!current.isAfter(target)) {
                      final periodStr = "${current.year}-${current.month.toString().padLeft(2, '0')}";
                      requiredPeriods.add(periodStr);
                      current = DateTime(current.year, current.month + 1, 1);
                    }
                  }

                  final missingPeriods = requiredPeriods.where((period) {
                    final status = paymentsMap[period];
                    return status == null || status == 'rejected';
                  }).toList();

                  // Sort periods chronologically (earliest first)
                  missingPeriods.sort();

                  return _buildPaymentUI(context, paymentStatus, missingPeriods);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPaymentUI(BuildContext context, String paymentStatus, List<String> missingPeriods) {
    final l10n = AppLocalizations.of(context)!;

    // If the selected period is no longer in the list of missing periods, reset it
    if (_selectedPeriod != null && !missingPeriods.contains(_selectedPeriod)) {
      _selectedPeriod = null;
    }
    // If nothing is selected yet, and there are missing periods, default to the first one
    if (_selectedPeriod == null && missingPeriods.isNotEmpty) {
      _selectedPeriod = missingPeriods.first;
    }

    final locale = Localizations.localeOf(context).languageCode;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l10n.monthlyQuota,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontFamily: AppConfig.fontFamily,
                color: AppConfig.primaryColor,
              ),
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              decoration: BoxDecoration(
                color: _getStatusColor(paymentStatus).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${l10n.currentStatus}: ${_getTranslatedStatus(l10n, paymentStatus).toUpperCase()}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: AppConfig.fontFamily,
                  color: _getStatusColor(paymentStatus),
                ),
              ),
            ),
            const SizedBox(height: 40),

            if (missingPeriods.isEmpty) ...[
              Text(
                l10n.noPendingPeriods,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  fontFamily: AppConfig.fontFamily,
                ),
              ),
              const SizedBox(height: 40),
            ] else ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedPeriod,
                decoration: InputDecoration(
                  labelText: l10n.selectPeriodLabel,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                items: missingPeriods.map((period) {
                  return DropdownMenuItem<String>(
                    value: period,
                    child: Text(
                      _formatPeriod(period, locale),
                      style: const TextStyle(fontFamily: AppConfig.fontFamily),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedPeriod = val;
                  });
                },
              ),
              const SizedBox(height: 30),

              ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: Text(l10n.takePhotoReceipt),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(250, 50),
                  backgroundColor: AppConfig.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _selectedPeriod == null ? null : _takePhoto,
              ),
              const SizedBox(height: 20),
            ],

            Text(
              l10n.receiptNotice,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.grey,
                fontFamily: AppConfig.fontFamily,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPeriod(String period, String locale) {
    try {
      final parts = period.split('-');
      if (parts.length != 2) return period;
      final year = parts[0];
      final month = parts[1];
      if (locale.startsWith('es')) {
        return '$month-$year';
      } else {
        return '$year-$month';
      }
    } catch (_) {
      return period;
    }
  }

  String _getTranslatedStatus(AppLocalizations l10n, String status) {
    switch (status) {
      case 'paid':
        return l10n.statusPaid;
      case 'pending':
        return l10n.statusPending;
      case 'reviewing':
        return l10n.statusReviewing;
      case 'restricted':
        return l10n.statusRestricted;
      default:
        return status.toUpperCase();
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'paid':
        return AppConfig.successColor;
      case 'pending':
        return AppConfig.warningColor;
      case 'reviewing':
        return AppConfig.infoColor;
      case 'restricted':
        return AppConfig.dangerColor;
      default:
        return Colors.grey;
    }
  }
}
