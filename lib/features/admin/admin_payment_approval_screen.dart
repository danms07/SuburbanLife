import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../core/widgets/interactive_image_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../../core/widgets/storage_network_image.dart';
import '../payments/payment_service.dart';

class AdminPaymentApprovalScreen extends StatefulWidget {
  const AdminPaymentApprovalScreen({super.key});

  @override
  State<AdminPaymentApprovalScreen> createState() => _AdminPaymentApprovalScreenState();
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
    } catch (e, stack) {
      debugPrint('Error approving payment: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminPaymentApprovalScreen._approvePayment');
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorPrefix(e.toString())), backgroundColor: Colors.redAccent),
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

    // Load rejection reason pool from config/app_settings + defaults
    final pool = <String>[
      l10n.rejectionReasonPeriodMismatch,
      l10n.rejectionReasonAmountMismatch,
      l10n.rejectionReasonAddressMismatch,
      l10n.rejectionReasonFolioMismatch,
    ];

    try {
      final appSettings = await DatabaseService().getDocument('config', 'app_settings');
      if (appSettings != null && appSettings['paymentRejectionReasons'] is List) {
        for (var r in (appSettings['paymentRejectionReasons'] as List)) {
          final str = r?.toString().trim() ?? '';
          if (str.isNotEmpty && !pool.contains(str)) {
            pool.add(str);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading app_settings paymentRejectionReasons: $e');
    }
    pool.add(l10n.rejectionReasonOther);

    String selectedReason = pool.first;
    final customReasonController = TextEditingController();

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isOther = selectedReason == l10n.rejectionReasonOther;
            return AlertDialog(
              title: Text(l10n.rejectionReasonPoolTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.rejectionReasonSelect, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedReason,
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                      items: pool.map((r) => DropdownMenuItem(
                        value: r,
                        child: Text(r, maxLines: 2, overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedReason = val;
                          });
                        }
                      },
                    ),
                    if (isOther) ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: customReasonController,
                        decoration: InputDecoration(
                          labelText: l10n.rejectionReasonOther,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  child: Text(l10n.cancel),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                  onPressed: () => Navigator.of(dialogCtx).pop(true),
                  child: Text(l10n.rejectResidentButton),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      customReasonController.dispose();
      return;
    }

    final finalReason = selectedReason == l10n.rejectionReasonOther
        ? customReasonController.text.trim()
        : selectedReason;
    customReasonController.dispose();

    setState(() {
      _isProcessing = true;
    });

    try {
      final currentAdminUid = AuthService().currentUser?.uid ?? '';
      await DatabaseService().updateDocument('payments', paymentDoc['id'], {
        'status': 'rejected',
        'rejectionReason': finalReason.isNotEmpty ? finalReason : selectedReason,
        'rejectedAt': DateTime.now().millisecondsSinceEpoch,
        'rejectedBy': currentAdminUid,
      });

      // If this was a sanction payment, revert sanction back to active
      final concept = paymentDoc['concept'] as String? ?? 'monthly quota';
      final sanctionId = paymentDoc['sanctionId'] as String?;
      if (concept == 'sanction' && sanctionId != null && sanctionId.isNotEmpty) {
        try {
          await DatabaseService().updateDocument('sanctions', sanctionId, {
            'status': 'active',
            'rejectionReason': finalReason.isNotEmpty ? finalReason : selectedReason,
          });
        } catch (sErr) {
          debugPrint('Error reverting sanction status: $sErr');
        }
      }

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
    } catch (e, stack) {
      debugPrint('Error rejecting payment: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminPaymentApprovalScreen._rejectPayment');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorPrefix(e.toString())), backgroundColor: Colors.redAccent),
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
            return Center(child: Text(l10n.errorPrefix(snapshot.error.toString())));
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
    final dynamic rawAmount = widget.doc['amount'];
    final double? amount = rawAmount is num ? rawAmount.toDouble() : (rawAmount is String ? double.tryParse(rawAmount) : null);
    final concept = widget.doc['concept'] as String? ?? 'monthly quota';
    final folio = widget.doc['folio'] as String? ?? '';
    final dynamic rawPaymentDate = widget.doc['paymentDate'] ?? widget.doc['timestamp'];
    final DateTime? paymentDateTime = rawPaymentDate != null
        ? DateTime.fromMillisecondsSinceEpoch(rawPaymentDate is int ? rawPaymentDate : int.tryParse(rawPaymentDate.toString()) ?? 0)
        : null;

    final List<String> periodsList = [];
    if (widget.doc['periods'] is List) {
      for (var p in (widget.doc['periods'] as List)) {
        if (p != null && p.toString().trim().isNotEmpty) {
          periodsList.add(p.toString().trim());
        }
      }
    } else if (widget.doc['period'] != null) {
      for (var p in widget.doc['period'].toString().split(',')) {
        if (p.trim().isNotEmpty) periodsList.add(p.trim());
      }
    }
    
    // Enforcement: Cannot approve their own uploads
    final isSelfUploaded = uploaderUid == widget.currentAdminUid;
    final locale = Localizations.localeOf(context).languageCode;

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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppConfig.primaryColor,
                                  ),
                                ),
                              ),
                              if (amount != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.green.shade300),
                                  ),
                                  child: Text(
                                    '\$${amount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade800,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          Text(email, style: const TextStyle(color: Colors.grey)),
                          const SizedBox(height: 8),

                          // Badges: Concept, Folio, Payment Date
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              Chip(
                                avatar: Icon(
                                  concept == 'sanction' ? Icons.gavel : Icons.receipt_long,
                                  size: 14,
                                  color: concept == 'sanction' ? Colors.red.shade700 : AppConfig.primaryColor,
                                ),
                                label: Text(
                                  concept == 'sanction' ? l10n.conceptSanction : l10n.conceptMonthlyQuota,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: concept == 'sanction' ? Colors.red.shade800 : Colors.black87,
                                  ),
                                ),
                                backgroundColor: concept == 'sanction' ? Colors.red.shade50 : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              if (folio.isNotEmpty)
                                Chip(
                                  avatar: const Icon(Icons.tag, size: 14, color: Colors.blueGrey),
                                  label: Text(
                                    'Folio: $folio',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                  backgroundColor: Colors.blueGrey.shade50,
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              if (paymentDateTime != null)
                                Chip(
                                  avatar: const Icon(Icons.calendar_today, size: 14, color: Colors.teal),
                                  label: Text(
                                    '${paymentDateTime.year}-${paymentDateTime.month.toString().padLeft(2, '0')}-${paymentDateTime.day.toString().padLeft(2, '0')}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                  backgroundColor: Colors.teal.shade50,
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                            ],
                          ),

                          if (periodsList.isNotEmpty && concept != 'sanction') ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: periodsList.map((period) {
                                return Chip(
                                  avatar: const Icon(Icons.event, size: 14, color: AppConfig.primaryColor),
                                  label: Text(
                                    _formatPeriod(period, locale),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                  backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                );
                              }).toList(),
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

                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: widget.isProcessing ? null : () => widget.onReject(widget.doc, residentUid),
                      child: Text(
                        l10n.rejectResidentButton,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
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
                          : Text(l10n.approvePaymentButton),
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
