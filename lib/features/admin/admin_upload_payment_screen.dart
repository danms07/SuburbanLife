import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../payments/payment_service.dart';

class AdminUploadPaymentScreen extends StatefulWidget {
  const AdminUploadPaymentScreen({super.key});

  @override
  State<AdminUploadPaymentScreen> createState() => _AdminUploadPaymentScreenState();
}

class _AdminUploadPaymentScreenState extends State<AdminUploadPaymentScreen> {
  final PaymentService _paymentService = PaymentService();
  final TextEditingController _amountController = TextEditingController();
  final Set<String> _selectedPeriods = <String>{};

  String? _selectedStreetName;
  Map<String, dynamic>? _selectedAddress;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDeliveryDate() async {
    if (_selectedAddress == null) return;
    final l10n = AppLocalizations.of(context)!;
    final addressId = _selectedAddress!['id'] as String;
    final currentDelivery = _selectedAddress!['deliveryDate'] as DateTime?;

    final picked = await showDatePicker(
      context: context,
      initialDate: currentDelivery ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      try {
        await DatabaseService().updateDocument('addresses', addressId, {
          'deliveryDate': picked,
        });
        await _paymentService.recalculatePaymentStatusForAddress(addressId);
        if (mounted) {
          setState(() {
            _selectedAddress!['deliveryDate'] = picked;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.deliveryDateUpdatedSuccess),
              backgroundColor: AppConfig.secondaryColor,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.deliveryDateUpdatedError(e.toString())),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  void _captureAndUpload() async {
    if (_selectedAddress == null) return;

    final l10n = AppLocalizations.of(context)!;
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.paymentAmountInvalid),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_selectedPeriods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.atLeastOnePeriodRequired),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final currentAdminUid = AuthService().currentUser?.uid ?? '';
    final targetResidentUid = _selectedAddress!['residentUid'] as String?;
    final addressId = _selectedAddress!['id'] as String;
    final addressRef = DatabaseService().createReference('addresses', addressId);

    try {
      XFile? pickedFile;
      try {
        pickedFile = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 60,
        );
      } catch (cameraError) {
        debugPrint('Camera capture fallback to gallery on web/desktop: $cameraError');
        pickedFile = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 60,
        );
      }

      if (pickedFile == null) return;

      setState(() {
        _isLoading = true;
      });

      // Save in storage under a path associated with the address ID
      final storagePath = 'payments/$addressId/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final dynamic fileData = kIsWeb ? await pickedFile.readAsBytes() : File(pickedFile.path);
      final downloadUrl = await StorageService().uploadFile(
        storagePath,
        fileData,
        contentType: 'image/jpeg',
        metadata: {'uploaderUid': currentAdminUid},
      );

      final bool isSelfUpload = targetResidentUid != null && targetResidentUid == currentAdminUid;
      final sortedPeriods = _selectedPeriods.toList()..sort();

      final paymentId = DateTime.now().millisecondsSinceEpoch.toString();
      await DatabaseService().setDocument('payments', paymentId, {
        'id': paymentId,
        'residentUid': ?targetResidentUid,
        'addressRef': addressRef,
        'uploaderUid': currentAdminUid, // Tag uploader to enforce segregation of duties
        'receiptUrl': downloadUrl,
        'amount': amount,
        'periods': sortedPeriods,
        'period': sortedPeriods.join(', '),
        'status': isSelfUpload ? 'pending' : 'approved',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        if (!isSelfUpload) 'approvalDate': DateTime.now().millisecondsSinceEpoch,
      });

      // Recalculate address payment standing
      await _paymentService.recalculatePaymentStatusForAddress(addressRef);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.proofUploadedSuccess), backgroundColor: AppConfig.secondaryColor),
        );

        setState(() {
          _selectedStreetName = null;
          _selectedAddress = null;
          _amountController.clear();
          _selectedPeriods.clear();
        });
      }
    } catch (e, stack) {
      debugPrint('Error uploading payment: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminUploadPaymentScreen._uploadPaymentReceipt');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorPrefix(e.toString())), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(l10n.uploadPaymentOnBehalfMenu, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.upload_file, size: 60, color: AppConfig.primaryColor),
                const SizedBox(height: 16),
                Text(
                  l10n.uploadPaymentOnBehalfMenu,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppConfig.primaryColor,
                    fontFamily: AppConfig.fontFamily,
                  ),
                ),
                const SizedBox(height: 24),

                // Select Address by Street and Number Cascading Dropdowns
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: DatabaseService().streamCollection('addresses'),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final addresses = snapshot.data ?? [];

                    // Extract unique street names
                    final streetNames = addresses
                        .map((doc) => doc['streetName']?.toString() ?? '')
                        .where((street) => street.isNotEmpty)
                        .toSet()
                        .toList()
                      ..sort();

                    // Filter numbers for selected street
                    final filteredAddresses = _selectedStreetName != null
                        ? (addresses.where((doc) {
                            return doc['streetName']?.toString() == _selectedStreetName;
                          }).toList()
                            ..sort((a, b) {
                              final numA = a['number'] ?? 0;
                              final numB = b['number'] ?? 0;
                              if (numA is int && numB is int) return numA.compareTo(numB);
                              return numA.toString().compareTo(numB.toString());
                            }))
                        : <Map<String, dynamic>>[];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Street Dropdown
                        DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: l10n.selectStreetLabel,
                            prefixIcon: const Icon(Icons.map, color: AppConfig.primaryColor),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          initialValue: streetNames.contains(_selectedStreetName) ? _selectedStreetName : null,
                          items: streetNames.map((street) {
                            return DropdownMenuItem<String>(
                              value: street,
                              child: Text(street),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedStreetName = val;
                              _selectedAddress = null; // Reset selection
                              _selectedPeriods.clear();
                            });
                          },
                        ),
                        const SizedBox(height: 20),

                        // Number Dropdown
                        DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: l10n.selectNumberLabel,
                            prefixIcon: const Icon(Icons.home, color: AppConfig.primaryColor),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          initialValue: (_selectedAddress != null && filteredAddresses.any((a) => a['id'] == _selectedAddress!['id'])) ? _selectedAddress!['id'] as String? : null,
                          items: filteredAddresses.map((doc) {
                            final isClaimed = doc['residentUid'] != null && doc['residentUid'].toString().trim().isNotEmpty;
                            final statusTag = isClaimed ? ' [Linked]' : ' [Available]';
                            return DropdownMenuItem<String>(
                              value: doc['id'] as String,
                              child: Text('${doc['number']}$statusTag'),
                            );
                          }).toList(),
                          onChanged: _selectedStreetName == null
                              ? null
                              : (val) {
                                  setState(() {
                                    _selectedAddress = filteredAddresses.firstWhere((a) => a['id'] == val);
                                    _selectedPeriods.clear();
                                  });
                                },
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),

                // If an address is selected, show Delivery Date & Payment details
                if (_selectedAddress != null) ...[
                  // Delivery Date Row
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 16, color: AppConfig.primaryColor),
                            const SizedBox(width: 8),
                            Text(
                              '${l10n.deliveryDateLabel}: ${_formatDeliveryDate(_selectedAddress!['deliveryDate'] as DateTime?, l10n)}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: _pickDeliveryDate,
                          icon: const Icon(Icons.edit_calendar, size: 16),
                          label: Text(
                            _selectedAddress!['deliveryDate'] != null ? l10n.editDeliveryDateButton : l10n.setDeliveryDateButton,
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Amount Field
                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.attach_money, color: AppConfig.primaryColor),
                      labelText: l10n.paymentAmountLabel,
                      hintText: l10n.paymentAmountHint,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Select Covered Periods
                  Text(
                    l10n.coveredPeriodsLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final candidatePeriods = _paymentService.generateSelectablePeriods(
                        _selectedAddress!['deliveryDate'] as DateTime?,
                        DateTime.now(),
                        advanceMonths: 12,
                      );

                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: candidatePeriods.map((period) {
                          final isSelected = _selectedPeriods.contains(period);
                          return FilterChip(
                            selected: isSelected,
                            label: Text(_formatPeriod(period, locale)),
                            selectedColor: AppConfig.primaryColor.withValues(alpha: 0.2),
                            checkmarkColor: AppConfig.primaryColor,
                            labelStyle: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? AppConfig.primaryColor : Colors.black87,
                            ),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedPeriods.add(period);
                                } else {
                                  _selectedPeriods.remove(period);
                                }
                              });
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                ],

                ElevatedButton.icon(
                  onPressed: _isLoading || _selectedAddress == null ? null : _captureAndUpload,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt),
                  label: Text(l10n.takePhotoReceipt),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.receiptNotice,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDeliveryDate(DateTime? date, AppLocalizations l10n) {
    if (date == null) return l10n.deliveryDateNotSet;
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
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
}

