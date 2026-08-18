import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../core/widgets/interactive_image_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../../core/widgets/storage_network_image.dart';
import 'package:intl/intl.dart';
import '../payments/payment_service.dart';

class AdminPaymentApprovalScreen extends StatefulWidget {
  const AdminPaymentApprovalScreen({Key? key}) : super(key: key);

  @override
  _AdminPaymentApprovalScreenState createState() => _AdminPaymentApprovalScreenState();
}

class _AdminPaymentApprovalScreenState extends State<AdminPaymentApprovalScreen> {
  bool _isProcessing = false;

  void _approvePayment(String paymentId, String residentUid) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isProcessing = true;
    });

    try {
      await FunctionsService().callFunction('approvePayment', {
        'paymentId': paymentId,
        'residentUid': residentUid,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.paymentApprovedSuccess), backgroundColor: AppConfig.secondaryColor),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _rejectPayment(Map<String, dynamic> paymentDoc, String residentUid) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isProcessing = true;
    });

    try {
      await DatabaseService().updateDocument('payments', paymentDoc['id'], {'status': 'rejected'});
      final userDoc = await DatabaseService().getDocument('users', residentUid);
      final addressRef = userDoc?['addressRef'] as DbReference?;
      if (addressRef != null) {
        await PaymentService().recalculatePaymentStatusForAddress(addressRef);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.paymentRejectedSuccess), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
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
    final currentAdminUid = AuthService().currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(l10n.reviewPaymentsMenu, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: DatabaseService().streamCollection('payments', filters: [QueryFilter('status', FilterOperator.equal, 'pending')]),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No pending payments for review.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              return _PaymentApprovalCard(
                key: ValueKey(doc['id']),
                doc: doc,
                currentAdminUid: currentAdminUid,
                isProcessing: _isProcessing,
                onApprove: _approvePayment,
                onReject: _rejectPayment,
                onShowPreview: _showImagePreview,
              );
            },
          );
        },
      ),
    );
  }
}

class _PaymentApprovalCard extends StatefulWidget {
  final Map<String, dynamic> doc;
  final String currentAdminUid;
  final bool isProcessing;
  final Function(String, String) onApprove;
  final Function(Map<String, dynamic>, String) onReject;
  final Function(String) onShowPreview;

  const _PaymentApprovalCard({
    required Key key,
    required this.doc,
    required this.currentAdminUid,
    required this.isProcessing,
    required this.onApprove,
    required this.onReject,
    required this.onShowPreview,
  }) : super(key: key);

  @override
  State<_PaymentApprovalCard> createState() => _PaymentApprovalCardState();
}

class _PaymentApprovalCardState extends State<_PaymentApprovalCard> {
  Future<Map<String, dynamic>?>? _userFuture;

  @override
  void initState() {
    super.initState();
    _initUserFuture();
  }

  @override
  void didUpdateWidget(covariant _PaymentApprovalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    final oldResidentUid = oldWidget.doc['residentUid'] as String?;
    final newResidentUid = widget.doc['residentUid'] as String?;

    if (oldResidentUid != newResidentUid) {
      _initUserFuture();
    }
  }

  void _initUserFuture() {
    final residentUid = widget.doc['residentUid'] as String? ?? '';
    _userFuture = DatabaseService().getDocument('users', residentUid);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final residentUid = widget.doc['residentUid'] as String? ?? '';
    final receiptUrl = widget.doc['receiptUrl'] as String? ?? '';
    final uploaderUid = widget.doc['uploaderUid'] as String? ?? residentUid;
    final period = widget.doc['period'] as String? ?? '';
    final formattedPeriod = _formatPeriod(period, Localizations.localeOf(context).languageCode);
    
    // Enforcement: Cannot approve their own uploads
    final isSelfUploaded = uploaderUid == widget.currentAdminUid;

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: receiptUrl.isNotEmpty ? () => widget.onShowPreview(receiptUrl) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Fetch Resident Information
                  FutureBuilder<Map<String, dynamic>?>(
                    future: _userFuture,
                    builder: (context, userSnapshot) {
                      if (userSnapshot.connectionState == ConnectionState.waiting) {
                        return const SizedBox(
                          height: 40,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final userData = userSnapshot.data;
                      final name = userData?['name'] ?? 'Unknown Resident';
                      final email = userData?['email'] ?? '';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppConfig.primaryColor,
                            ),
                          ),
                          Text(email, style: const TextStyle(color: Colors.grey)),
                          if (period.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.event, size: 16, color: Colors.grey),
                                const SizedBox(width: 6),
                                Text(
                                  formattedPeriod,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppConfig.textColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  if (receiptUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: StorageNetworkImage(
                        imageUrl: receiptUrl,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isSelfUploaded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      l10n.selfApprovalBlockedError,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                  ),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: widget.isProcessing ? null : () => widget.onReject(widget.doc, residentUid),
                      child: Text(
                        l10n.rejectResidentButton,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: widget.isProcessing || isSelfUploaded
                          ? null
                          : () => widget.onApprove(widget.doc['id'] as String, residentUid),
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
                          : const Text('Approve Payment'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
