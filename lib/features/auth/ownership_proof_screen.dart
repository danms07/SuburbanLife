import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:suburban_life/core/config/app_config.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import '../../core/backend/backend.dart';


class OwnershipProofScreen extends StatefulWidget {
  final DbReference addressRef;

  const OwnershipProofScreen({super.key, required this.addressRef});

  @override
  State<OwnershipProofScreen> createState() => _OwnershipProofScreenState();
}

class _OwnershipProofScreenState extends State<OwnershipProofScreen> {
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();
  DateTime? _selectedHandoverDate;

  void _takePhoto() async {
    final currentUser = AuthService().currentUser;
    if (currentUser == null) return;

    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (_selectedHandoverDate == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.selectDeliveryDate),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Force camera permissions and enforce taking a photo directly
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80, // High compression to reduce size
      );

      if (pickedFile == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      } 

      String proofUrl = '';

      try {
        final path = 'ownership_proofs/${currentUser.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        final dynamic fileData = kIsWeb ? await pickedFile.readAsBytes() : File(pickedFile.path);
        proofUrl = await StorageService().uploadFile(
          path,
          fileData,
          contentType: 'image/jpeg',
          metadata: {'uploaderUid': currentUser.uid},
        );
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        debugPrint(e.toString());
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.errorPrefix(e.toString())), backgroundColor: Colors.redAccent),
        );
        return;
      }

      // Create Document in ownership_claims Collection
      await DatabaseService().addDocument('ownership_claims', {
        'userUid': currentUser.uid,
        'addressRef': widget.addressRef,
        'proofUrl': proofUrl,
        'status': 'pending',
        'timestamp': DbFieldValue.serverTimestamp(),
        'deliveryDate': _selectedHandoverDate!,
      });

      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.proofUploadedSuccess),
          backgroundColor: AppConfig.secondaryColor,
        ),
      );

      // Pop back to root navigation stream
      navigator.popUntil((route) => route.isFirst);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.errorPrefix(e.toString())), backgroundColor: Colors.redAccent),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(
          l10n.ownershipProofTitle,
          style: const TextStyle(fontFamily: AppConfig.fontFamily),
        ),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.home_work,
                size: 80,
                color: AppConfig.primaryColor,
              ),
              const SizedBox(height: 30),
              Text(
                l10n.ownershipProofInstructions,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  fontFamily: AppConfig.fontFamily,
                  color: AppConfig.textColor,
                ),
              ),
              const SizedBox(height: 20),
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
              const SizedBox(height: 20),
              InkWell(
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedHandoverDate ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: AppConfig.primaryColor,
                            onPrimary: Colors.white,
                            onSurface: AppConfig.textColor,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null && picked != _selectedHandoverDate) {
                    setState(() {
                      _selectedHandoverDate = picked;
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month, color: AppConfig.primaryColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.deliveryDateLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontFamily: AppConfig.fontFamily,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedHandoverDate == null
                                  ? l10n.selectDeliveryDate
                                  : DateFormat('yyyy-MM-dd').format(_selectedHandoverDate!),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: AppConfig.fontFamily,
                                color: AppConfig.textColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                icon: _isLoading
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
                  _isLoading ? l10n.uploadingProof : l10n.captureProofPhoto,
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(250, 50),
                  backgroundColor: AppConfig.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _isLoading ? null : _takePhoto,
              ),
              const SizedBox(height: 20),
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
      ),
    );
  }
}
