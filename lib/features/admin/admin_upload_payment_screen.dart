import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';

class AdminUploadPaymentScreen extends StatefulWidget {
  const AdminUploadPaymentScreen({Key? key}) : super(key: key);

  @override
  _AdminUploadPaymentScreenState createState() => _AdminUploadPaymentScreenState();
}

class _AdminUploadPaymentScreenState extends State<AdminUploadPaymentScreen> {
  String? _selectedStreetName;
  Map<String, dynamic>? _selectedAddress;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  void _captureAndUpload() async {
    if (_selectedAddress == null) return;

    final l10n = AppLocalizations.of(context)!;
    final currentAdminUid = AuthService().currentUser?.uid ?? '';
    final targetResidentUid = _selectedAddress!['residentUid'] as String?;
    final addressId = _selectedAddress!['id'] as String;
    final addressRef = DatabaseService().createReference('addresses', addressId);

    try {
      // Enforce direct camera captures to ensure authenticity
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 60,
      );

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

      final paymentId = DateTime.now().millisecondsSinceEpoch.toString();
      await DatabaseService().setDocument('payments', paymentId, {
        'id': paymentId,
        if (targetResidentUid != null) 'residentUid': targetResidentUid,
        'addressRef': addressRef,
        'uploaderUid': currentAdminUid, // Tag uploader to enforce segregation of duties
        'receiptUrl': downloadUrl,
        'status': isSelfUpload ? 'pending' : 'approved',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        if (!isSelfUpload) 'approvalDate': DateTime.now().millisecondsSinceEpoch,
      });

      await DatabaseService().updateDocument('addresses', addressId, {
        'paymentStatus': isSelfUpload ? 'reviewing' : 'paid',
        if (!isSelfUpload) 'lastPaymentApproval': DateTime.now().millisecondsSinceEpoch,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.proofUploadedSuccess), backgroundColor: AppConfig.secondaryColor),
      );

      setState(() {
        _selectedStreetName = null;
        _selectedAddress = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
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
                                  });
                                },
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),

                ElevatedButton.icon(
                  onPressed: _isLoading || _selectedAddress == null ? null : _captureAndUpload,
                  icon: const Icon(Icons.camera_alt),
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
}
