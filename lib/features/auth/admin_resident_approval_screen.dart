import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import 'package:suburban_life/core/config/app_config.dart';
import 'package:suburban_life/core/widgets/interactive_image_dialog.dart';
import 'package:suburban_life/l10n/app_localizations.dart';
import 'package:suburban_life/core/widgets/storage_network_image.dart';
import 'package:intl/intl.dart';

class AdminResidentApprovalScreen extends StatefulWidget {
  const AdminResidentApprovalScreen({super.key});

  @override
  State<AdminResidentApprovalScreen> createState() => _AdminResidentApprovalScreenState();
}

class _AdminResidentApprovalScreenState extends State<AdminResidentApprovalScreen> {
  bool _isProcessing = false;

  void _approveClaim(Map<String, dynamic> claimDoc) async {
    setState(() {
      _isProcessing = true;
    });

    final userUid = claimDoc['userUid'] as String?;
    final addressRef = claimDoc['addressRef'] as DbReference?;
    final proofUrl = claimDoc['proofUrl'] as String?;
    final deliveryDate = claimDoc['deliveryDate'] as DateTime?;

    if (userUid == null || addressRef == null) {
      setState(() {
        _isProcessing = false;
      });
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    try {
      // 1. Invoke setRole Cloud Function to assign resident custom claim
      await FunctionsService().callFunction('setRole', {
        'uid': userUid,
        'role': 'resident',
      });

      // 2. Assign residentUid and initialize paymentStatus to paid, and save deliveryDate on the underlying address document
      await DatabaseService().updateDocument('addresses', addressRef.id, {
        'residentUid': userUid,
        'paymentStatus': 'paid',
        if (deliveryDate != null) 'deliveryDate': deliveryDate,
      });

      // 3. If the user's active session addressRef is null, assign it
      final userData = await DatabaseService().getDocument('users', userUid);
      if (userData != null && userData['addressRef'] == null) {
        await DatabaseService().updateDocument('users', userUid, {
          'addressRef': addressRef,
        });
      }

      // 4. Delete the proof image from Storage to protect privacy
      if (proofUrl != null && proofUrl.isNotEmpty) {
        try {
          await StorageService().deleteFileFromUrl(proofUrl);
        } catch (err) {
          debugPrint('Error deleting proof storage image: $err');
        }
      }

      // 5. Delete the pending ownership claim document
      await DatabaseService().deleteDocument('ownership_claims', claimDoc['id']);

      messenger.showSnackBar(
        SnackBar(content: Text(l10n.residentApprovedSuccess)),
      );
    } catch (e) {
      debugPrint('Error approving claim: $e');
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.errorPrefix(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _rejectClaim(Map<String, dynamic> claimDoc) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final proofUrl = claimDoc['proofUrl'] as String?;
      if (proofUrl != null && proofUrl.isNotEmpty) {
        try {
          await StorageService().deleteFileFromUrl(proofUrl);
        } catch (err) {
          debugPrint('Error deleting proof storage image: $err');
        }
      }

      await DatabaseService().deleteDocument('ownership_claims', claimDoc['id']);
    } catch (e) {
      debugPrint('Error rejecting claim: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _showImagePreview(String url) {
    showInteractiveImageDialog(context, url);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Column(
        children: [
          // Premium Header
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top + 16,
              left: 20,
              right: 20,
              bottom: 30,
            ),
            decoration: const BoxDecoration(
              color: AppConfig.primaryColor,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.approveResidentsMenu,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: AppConfig.fontFamily,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Claims List
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: DatabaseService().streamCollection('ownership_claims'),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text(l10n.errorPrefix(snapshot.error.toString())));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data ?? [];

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      l10n.noResidentsToApprove,
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    return _ResidentApprovalCard(
                      key: ValueKey(doc['id']),
                      doc: doc,
                      isProcessing: _isProcessing,
                      onApprove: _approveClaim,
                      onReject: _rejectClaim,
                      onShowPreview: _showImagePreview,
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
}

class _ResidentApprovalCard extends StatefulWidget {
  final Map<String, dynamic> doc;
  final bool isProcessing;
  final Function(Map<String, dynamic>) onApprove;
  final Function(Map<String, dynamic>) onReject;
  final Function(String) onShowPreview;

  const _ResidentApprovalCard({
    required Key key,
    required this.doc,
    required this.isProcessing,
    required this.onApprove,
    required this.onReject,
    required this.onShowPreview,
  }) : super(key: key);

  @override
  State<_ResidentApprovalCard> createState() => _ResidentApprovalCardState();
}

class _ResidentApprovalCardState extends State<_ResidentApprovalCard> {
  Future<Map<String, dynamic>?>? _addressFuture;

  @override
  void initState() {
    super.initState();
    _initAddressFuture();
  }

  @override
  void didUpdateWidget(covariant _ResidentApprovalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    final oldAddressRef = oldWidget.doc['addressRef'] as DbReference?;
    final newAddressRef = widget.doc['addressRef'] as DbReference?;
 
    if (oldAddressRef?.id != newAddressRef?.id) {
      _initAddressFuture();
    }
  }

  void _initAddressFuture() {
    final addressRef = widget.doc['addressRef'] as DbReference?;
    _addressFuture = addressRef != null ? DatabaseService().getDocument('addresses', addressRef.id) : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final proofUrl = widget.doc['proofUrl'] as String? ?? '';
    final deliveryTimestamp = widget.doc['deliveryDate'] as DateTime?;
    final deliveryDate = deliveryTimestamp;
 
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: proofUrl.isNotEmpty ? () => widget.onShowPreview(proofUrl) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Fetch Address Details
                  FutureBuilder<Map<String, dynamic>?>(
                    future: _addressFuture,
                    builder: (context, addrSnapshot) {
                      if (addrSnapshot.connectionState == ConnectionState.waiting) {
                        return const SizedBox(
                          height: 20,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5),
                            ),
                          ),
                        );
                      }
                      final addrData = addrSnapshot.data;
                      final street = addrData?['streetName'] ?? 'Unknown Street';
                      final number = addrData?['number'] ?? '';
                      return Text(
                        '$street $number',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppConfig.primaryColor,
                        ),
                      );
                    },
                  ),
                  if (deliveryDate != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          '${l10n.deliveryDateLabel}: ${DateFormat('yyyy-MM-dd').format(deliveryDate)}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppConfig.textColor,
                            fontFamily: AppConfig.fontFamily,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (proofUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: StorageNetworkImage(
                        imageUrl: proofUrl,
                        height: 150,
                        fit: BoxFit.cover,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.isProcessing ? null : () => widget.onReject(widget.doc),
                  child: Text(
                    l10n.rejectResidentButton,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: widget.isProcessing ? null : () => widget.onApprove(widget.doc),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.secondaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: widget.isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(l10n.approveResidentButton),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
