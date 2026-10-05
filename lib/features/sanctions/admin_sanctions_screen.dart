import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../core/widgets/interactive_image_dialog.dart';
import '../../core/widgets/storage_network_image.dart';
import '../../l10n/app_localizations.dart';
import '../payments/payment_service.dart';

class AdminSanctionsScreen extends StatefulWidget {
  const AdminSanctionsScreen({super.key});

  @override
  State<AdminSanctionsScreen> createState() => _AdminSanctionsScreenState();
}

class _AdminSanctionsScreenState extends State<AdminSanctionsScreen> {
  String _selectedStatusFilter = 'all';

  void _showIssueSanctionDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _IssueSanctionModal(),
    );
  }

  Future<void> _waiveSanction(Map<String, dynamic> sanction) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.waiveSanction),
        content: Text(l10n.waiveSanctionConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(l10n.confirmAction),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final currentAdminUid = AuthService().currentUser?.uid ?? '';
      final sanctionId = sanction['id'] as String;
      await DatabaseService().updateDocument('sanctions', sanctionId, {
        'status': 'cancelled',
        'resolvedAt': DateTime.now().millisecondsSinceEpoch,
        'cancelledBy': currentAdminUid,
      });

      final addressRef = sanction['addressRef'];
      if (addressRef != null) {
        await PaymentService().recalculatePaymentStatusForAddress(addressRef);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.sanctionWaivedSuccess),
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
        title: Text(
          l10n.adminSanctionsTitle,
          style: const TextStyle(fontFamily: AppConfig.fontFamily),
        ),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(l10n.issueSanction),
        onPressed: _showIssueSanctionDialog,
      ),
      body: Column(
        children: [
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _buildFilterChip('all', l10n.filterAll),
                const SizedBox(width: 8),
                _buildFilterChip('active', l10n.sanctionStatusActive),
                const SizedBox(width: 8),
                _buildFilterChip('pending_review', l10n.sanctionStatusPendingReview),
                const SizedBox(width: 8),
                _buildFilterChip('paid', l10n.sanctionStatusPaid),
                const SizedBox(width: 8),
                _buildFilterChip('cancelled', l10n.sanctionStatusCancelled),
              ],
            ),
          ),
          const Divider(height: 1),

          // Sanctions List
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: DatabaseService().streamCollection('sanctions'),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text(l10n.errorPrefix(snapshot.error.toString())));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data ?? [];
                final filteredDocs = docs.where((doc) {
                  if (_selectedStatusFilter == 'all') return true;
                  return (doc['status'] as String? ?? 'active') == _selectedStatusFilter;
                }).toList();

                filteredDocs.sort((a, b) {
                  final aTime = (a['createdAt'] as num?) ?? 0;
                  final bTime = (b['createdAt'] as num?) ?? 0;
                  return bTime.compareTo(aTime);
                });

                if (filteredDocs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.gavel, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            l10n.noSanctions,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                              fontFamily: AppConfig.fontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    final sanction = filteredDocs[index];
                    return _AdminSanctionCard(
                      sanction: sanction,
                      onWaive: () => _waiveSanction(sanction),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label) {
    final isSelected = _selectedStatusFilter == filterKey;
    return FilterChip(
      selected: isSelected,
      label: Text(label),
      selectedColor: AppConfig.primaryColor.withValues(alpha: 0.2),
      checkmarkColor: AppConfig.primaryColor,
      labelStyle: TextStyle(
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? AppConfig.primaryColor : Colors.black87,
      ),
      onSelected: (_) {
        setState(() {
          _selectedStatusFilter = filterKey;
        });
      },
    );
  }
}

class _AdminSanctionCard extends StatelessWidget {
  final Map<String, dynamic> sanction;
  final VoidCallback onWaive;

  const _AdminSanctionCard({required this.sanction, required this.onWaive});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final status = sanction['status'] as String? ?? 'active';
    final reason = sanction['reason'] as String? ?? 'Infraction';
    final dynamic rawAmount = sanction['amount'];
    final double? amount = rawAmount is num
        ? rawAmount.toDouble()
        : (rawAmount is String ? double.tryParse(rawAmount) : null);
    final evidenceUrl = sanction['evidenceUrl'] as String? ?? '';
    final dynamic rawCreated = sanction['createdAt'];
    final DateTime? createdDate = rawCreated != null
        ? DateTime.fromMillisecondsSinceEpoch(
            rawCreated is int ? rawCreated : int.tryParse(rawCreated.toString()) ?? 0,
          )
        : null;

    final addressRef = sanction['addressRef'];
    final addressId = addressRef is DbReference
        ? addressRef.id
        : (addressRef is StringDbReference ? addressRef.id : addressRef?.toString().split('/').last ?? '');

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FutureBuilder<Map<String, dynamic>?>(
                  future: DatabaseService().getDocument('addresses', addressId),
                  builder: (context, snap) {
                    final addr = snap.data;
                    final street = addr?['streetName'] ?? 'Address';
                    final number = addr?['number'] ?? '';
                    return Text(
                      '$street $number',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppConfig.primaryColor,
                      ),
                    );
                  },
                ),
                _buildStatusChip(context, l10n, status),
              ],
            ),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (amount != null)
                  Text(
                    '\$${amount.toStringAsFixed(2)} MXN',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                if (createdDate != null)
                  Text(
                    '${createdDate.year}-${createdDate.month.toString().padLeft(2, '0')}-${createdDate.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            Text(
              reason,
              style: const TextStyle(fontSize: 14, fontFamily: AppConfig.fontFamily),
            ),
            const SizedBox(height: 10),

            if (evidenceUrl.isNotEmpty) ...[
              InkWell(
                onTap: () => showInteractiveImageDialog(context, evidenceUrl),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: StorageNetworkImage(
                    imageUrl: evidenceUrl,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],

            if (status == 'active')
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.cancel_outlined, size: 16, color: Colors.redAccent),
                  label: Text(l10n.waiveSanction, style: const TextStyle(color: Colors.redAccent)),
                  onPressed: onWaive,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context, AppLocalizations l10n, String status) {
    Color bg;
    Color fg;
    String text;

    switch (status) {
      case 'active':
        bg = Colors.red.shade50;
        fg = Colors.red.shade800;
        text = l10n.sanctionStatusActive;
        break;
      case 'pending_review':
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade800;
        text = l10n.sanctionStatusPendingReview;
        break;
      case 'paid':
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        text = l10n.sanctionStatusPaid;
        break;
      case 'cancelled':
      default:
        bg = Colors.grey.shade100;
        fg = Colors.grey.shade700;
        text = l10n.sanctionStatusCancelled;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }
}

class _IssueSanctionModal extends StatefulWidget {
  const _IssueSanctionModal();

  @override
  State<_IssueSanctionModal> createState() => _IssueSanctionModalState();
}

class _IssueSanctionModalState extends State<_IssueSanctionModal> {
  final _picker = ImagePicker();
  final _reasonController = TextEditingController();
  final _amountController = TextEditingController();
  String? _selectedAddressId;
  XFile? _evidenceImage;
  bool _isSaving = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickEvidence() async {
    try {
      XFile? picked;
      try {
        picked = await _picker.pickImage(source: ImageSource.camera, imageQuality: 60);
      } catch (_) {
        picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 60);
      }
      if (picked != null && mounted) {
        setState(() {
          _evidenceImage = picked;
        });
      }
    } catch (e) {
      debugPrint('Error picking evidence: $e');
    }
  }

  Future<void> _submitSanction() async {
    final l10n = AppLocalizations.of(context)!;
    if (_selectedAddressId == null || _selectedAddressId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.selectAddressPrompt), backgroundColor: Colors.orange),
      );
      return;
    }

    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sanctionReasonLabel), backgroundColor: Colors.orange),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.paymentAmountInvalid), backgroundColor: Colors.orange),
      );
      return;
    }

    if (_evidenceImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sanctionEvidenceRequired), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final currentAdminUid = AuthService().currentUser?.uid ?? '';
      final addressId = _selectedAddressId!;
      final addressRef = DatabaseService().createReference('addresses', addressId);

      // Upload evidence photo
      final storagePath = 'sanctions/$addressId/${DateTime.now().millisecondsSinceEpoch}.jpg';
      String downloadUrl;
      if (kIsWeb) {
        final bytes = await _evidenceImage!.readAsBytes();
        downloadUrl = await StorageService().uploadFile(
          storagePath,
          bytes,
          contentType: 'image/jpeg',
          metadata: {'uploaderUid': currentAdminUid},
        );
      } else {
        final file = File(_evidenceImage!.path);
        downloadUrl = await StorageService().uploadFile(
          storagePath,
          file,
          contentType: 'image/jpeg',
          metadata: {'uploaderUid': currentAdminUid},
        );
      }

      // Query residents living at this address to build authorizedUids array for security rules
      final residentsQuery = await DatabaseService().getCollection(
        'users',
        filters: [QueryFilter('addressRef', FilterOperator.equal, addressRef)],
      );
      final authorizedUids = <String>[];
      for (var u in residentsQuery) {
        final uid = u['uid']?.toString();
        if (uid != null && uid.isNotEmpty) {
          authorizedUids.add(uid);
        }
      }
      final residentUid = authorizedUids.isNotEmpty ? authorizedUids.first : '';

      final sanctionId = DateTime.now().millisecondsSinceEpoch.toString();
      await DatabaseService().setDocument('sanctions', sanctionId, {
        'id': sanctionId,
        'addressRef': addressRef,
        'residentUid': residentUid,
        'authorizedUids': authorizedUids,
        'reason': reason,
        'amount': amount,
        'evidenceUrl': downloadUrl,
        'status': 'active',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'createdBy': currentAdminUid,
      });

      // Recalculate address payment status (active sanction sets address to 'restricted')
      await PaymentService().recalculatePaymentStatusForAddress(addressRef);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.sanctionIssuedSuccess),
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
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.issueSanction,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppConfig.primaryColor,
                    fontFamily: AppConfig.fontFamily,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 12),

            // Address Selector
            Text(
              l10n.selectAddressPrompt,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: DatabaseService().streamCollection('addresses'),
              builder: (context, snap) {
                final addresses = snap.data ?? [];
                addresses.sort((a, b) {
                  final sA = (a['streetName'] ?? '').toString();
                  final sB = (b['streetName'] ?? '').toString();
                  final comp = sA.compareTo(sB);
                  if (comp != 0) return comp;
                  final nA = (a['number'] as num?) ?? 0;
                  final nB = (b['number'] as num?) ?? 0;
                  return nA.compareTo(nB);
                });

                return DropdownButtonFormField<String>(
                  initialValue: _selectedAddressId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.home_outlined, color: AppConfig.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                  items: addresses.map((addr) {
                    final id = addr['id']?.toString() ?? '';
                    final street = addr['streetName'] ?? '';
                    final number = addr['number'] ?? '';
                    return DropdownMenuItem(
                      value: id,
                      child: Text('$street $number'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedAddressId = val;
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 16),

            // Reason / Description
            Text(
              l10n.sanctionReasonLabel,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _reasonController,
              decoration: InputDecoration(
                hintText: l10n.sanctionReasonHint,
                prefixIcon: const Icon(Icons.description_outlined, color: AppConfig.primaryColor),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // Fine Amount
            Text(
              l10n.sanctionAmountLabel,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.attach_money, color: AppConfig.primaryColor),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),

            // Evidence Photo
            Text(
              l10n.sanctionEvidencePhoto,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickEvidence,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _evidenceImage != null ? AppConfig.primaryColor : Colors.grey.shade300,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  color: _evidenceImage != null ? AppConfig.primaryColor.withValues(alpha: 0.05) : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      _evidenceImage != null ? Icons.check_circle : Icons.camera_alt_outlined,
                      color: _evidenceImage != null ? AppConfig.primaryColor : Colors.grey,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _evidenceImage != null
                            ? _evidenceImage!.name
                            : l10n.sanctionEvidenceRequired,
                        style: TextStyle(
                          fontSize: 13,
                          color: _evidenceImage != null ? Colors.black87 : Colors.grey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: _pickEvidence,
                      child: Text(_evidenceImage != null ? l10n.edit : l10n.takePhotoReceipt),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Submit Button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConfig.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isSaving ? null : _submitSanction,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }
}
