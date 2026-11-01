import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../core/widgets/interactive_image_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../../core/widgets/storage_network_image.dart';
import '../payments/payment_service.dart';

class AdminPaymentApprovalScreen extends StatefulWidget {
  final bool isEmbedded;

  const AdminPaymentApprovalScreen({super.key, this.isEmbedded = false});

  @override
  State<AdminPaymentApprovalScreen> createState() => _AdminPaymentApprovalScreenState();
}

class _AdminPaymentApprovalScreenState extends State<AdminPaymentApprovalScreen> {
  void _openPaymentDetail(Map<String, dynamic> doc) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminPaymentDetailScreen(doc: doc),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: widget.isEmbedded
          ? null
          : AppBar(
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
              return _PaymentSummaryCard(
                key: ValueKey(doc['id']),
                doc: doc,
                onTap: () => _openPaymentDetail(doc),
              );
            },
          );
        },
      ),
    );
  }
}

Future<Map<String, dynamic>?> _fetchPaymentAddress(Map<String, dynamic> paymentDoc) async {
  final dynamic rawAddressRef = paymentDoc['addressRef'];
  String? addressId;
  if (rawAddressRef is DbReference) {
    addressId = rawAddressRef.id;
  } else if (rawAddressRef is String && rawAddressRef.trim().isNotEmpty) {
    addressId = rawAddressRef.trim().split('/').last;
  }

  if (addressId != null && addressId.isNotEmpty) {
    final addrDoc = await DatabaseService().getDocument('addresses', addressId);
    if (addrDoc != null) return addrDoc;
  }

  final residentUid = paymentDoc['residentUid'] as String? ?? '';
  if (residentUid.isNotEmpty) {
    final userDoc = await DatabaseService().getDocument('users', residentUid);
    final userAddressRef = userDoc?['addressRef'];
    if (userAddressRef is DbReference) {
      return DatabaseService().getDocument('addresses', userAddressRef.id);
    }
  }
  return null;
}

String _formatAddressTitle(Map<String, dynamic>? addrData) {
  final street = addrData?['streetName']?.toString().trim() ?? '';
  final number = addrData?['number']?.toString().trim() ?? '';
  if (street.isEmpty) return 'Unknown Address';
  return number.isNotEmpty ? '$street #$number' : street;
}

Future<Map<String, dynamic>?> _fetchPaymentSanction(Map<String, dynamic> paymentDoc) async {
  final sanctionId = paymentDoc['sanctionId']?.toString().trim() ?? '';
  if (sanctionId.isNotEmpty) {
    final sanctionDoc = await DatabaseService().getDocument('sanctions', sanctionId);
    if (sanctionDoc != null) return sanctionDoc;
  }

  final paymentId = paymentDoc['id']?.toString().trim() ?? '';
  if (paymentId.isNotEmpty) {
    final byPayment = await DatabaseService().getCollection(
      'sanctions',
      filters: [QueryFilter('paymentId', FilterOperator.equal, paymentId)],
    );
    if (byPayment.isNotEmpty) return byPayment.first;
  }

  final dynamic rawAddressRef = paymentDoc['addressRef'];
  if (rawAddressRef is DbReference) {
    final byAddress = await DatabaseService().getCollection(
      'sanctions',
      filters: [QueryFilter('addressRef', FilterOperator.equal, rawAddressRef)],
    );
    final pendingOrActive = byAddress.where((s) {
      final st = s['status'] as String? ?? 'active';
      return st == 'pending_review' || st == 'active';
    }).toList();
    if (pendingOrActive.isNotEmpty) return pendingOrActive.first;
  }

  return null;
}

class _PaymentSummaryCard extends StatefulWidget {
  final Map<String, dynamic> doc;
  final VoidCallback onTap;

  const _PaymentSummaryCard({
    required Key key,
    required this.doc,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_PaymentSummaryCard> createState() => _PaymentSummaryCardState();
}

class _PaymentSummaryCardState extends State<_PaymentSummaryCard> {
  Future<Map<String, dynamic>?>? _addressFuture;

  @override
  void initState() {
    super.initState();
    _initAddressFuture();
  }

  @override
  void didUpdateWidget(covariant _PaymentSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldAddressRef = oldWidget.doc['addressRef'];
    final newAddressRef = widget.doc['addressRef'];
    final oldResidentUid = oldWidget.doc['residentUid'] as String?;
    final newResidentUid = widget.doc['residentUid'] as String?;
    if (oldAddressRef != newAddressRef || oldResidentUid != newResidentUid) {
      _initAddressFuture();
    }
  }

  void _initAddressFuture() {
    _addressFuture = _fetchPaymentAddress(widget.doc);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dynamic rawAmount = widget.doc['amount'];
    final double? amount = rawAmount is num
        ? rawAmount.toDouble()
        : (rawAmount is String ? double.tryParse(rawAmount) : null);
    final concept = widget.doc['concept'] as String? ?? 'monthly quota';
    final dynamic rawPaymentDate = widget.doc['paymentDate'] ?? widget.doc['timestamp'];
    final DateTime? paymentDateTime = rawPaymentDate != null
        ? DateTime.fromMillisecondsSinceEpoch(
            rawPaymentDate is int ? rawPaymentDate : int.tryParse(rawPaymentDate.toString()) ?? 0,
          )
        : null;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('payment_card_${widget.doc['id']}'),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: FutureBuilder<Map<String, dynamic>?>(
                  future: _addressFuture,
                  builder: (context, addrSnapshot) {
                    if (addrSnapshot.connectionState == ConnectionState.waiting) {
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
                    final addressTitle = _formatAddressTitle(addrSnapshot.data);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.home_outlined,
                                    size: 20,
                                    color: AppConfig.primaryColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      addressTitle,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: AppConfig.primaryColor,
                                      ),
                                    ),
                                  ),
                                ],
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
                        const SizedBox(height: 10),
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
                              backgroundColor: concept == 'sanction'
                                  ? Colors.red.shade50
                                  : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            if (paymentDateTime != null)
                              Chip(
                                avatar: const Icon(Icons.calendar_today, size: 14, color: Colors.teal),
                                label: Text(
                                  '${l10n.dateOfPaymentLabel}: ${paymentDateTime.year}-${paymentDateTime.month.toString().padLeft(2, '0')}-${paymentDateTime.day.toString().padLeft(2, '0')}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                backgroundColor: Colors.teal.shade50,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminPaymentDetailScreen extends StatefulWidget {
  final Map<String, dynamic> doc;

  const AdminPaymentDetailScreen({
    super.key,
    required this.doc,
  });

  @override
  State<AdminPaymentDetailScreen> createState() => _AdminPaymentDetailScreenState();
}

class _AdminPaymentDetailScreenState extends State<AdminPaymentDetailScreen> {
  bool _isProcessing = false;
  Future<Map<String, dynamic>?>? _addressFuture;
  Future<Map<String, dynamic>?>? _sanctionFuture;

  @override
  void initState() {
    super.initState();
    _addressFuture = _fetchPaymentAddress(widget.doc);
    if ((widget.doc['concept'] as String?) == 'sanction') {
      _sanctionFuture = _fetchPaymentSanction(widget.doc);
    }
  }

  Future<void> _approvePayment(String paymentId, String residentUid) async {
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
        Navigator.of(context).pop();
      }
    } catch (e, stack) {
      debugPrint('Error approving payment: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminPaymentDetailScreen._approvePayment');
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

  Future<void> _rejectPayment(Map<String, dynamic> paymentDoc, String residentUid) async {
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
    String customReasonText = '';

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
                        onChanged: (val) => customReasonText = val,
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
      return;
    }

    final finalReason = selectedReason == l10n.rejectionReasonOther
        ? customReasonText.trim()
        : selectedReason;

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

      DbReference? addressRef = paymentDoc['addressRef'] as DbReference?;
      if (addressRef == null && residentUid.isNotEmpty) {
        final userDoc = await DatabaseService().getDocument('users', residentUid);
        addressRef = userDoc?['addressRef'] as DbReference?;
      }
      if (addressRef != null) {
        await PaymentService().recalculatePaymentStatusForAddress(addressRef);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.paymentRejectedSuccess), backgroundColor: Colors.orange),
        );
        Navigator.of(context).pop();
      }
    } catch (e, stack) {
      debugPrint('Error rejecting payment: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminPaymentDetailScreen._rejectPayment');
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
    final residentUid = widget.doc['residentUid'] as String? ?? '';
    final receiptUrl = widget.doc['receiptUrl'] as String? ?? '';
    final uploaderUid = widget.doc['uploaderUid'] as String? ?? residentUid;
    final dynamic rawAmount = widget.doc['amount'];
    final double? amount = rawAmount is num
        ? rawAmount.toDouble()
        : (rawAmount is String ? double.tryParse(rawAmount) : null);
    final concept = widget.doc['concept'] as String? ?? 'monthly quota';
    final folio = widget.doc['folio'] as String? ?? '';
    final dynamic rawPaymentDate = widget.doc['paymentDate'] ?? widget.doc['timestamp'];
    final DateTime? paymentDateTime = rawPaymentDate != null
        ? DateTime.fromMillisecondsSinceEpoch(
            rawPaymentDate is int ? rawPaymentDate : int.tryParse(rawPaymentDate.toString()) ?? 0,
          )
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

    final isSelfUploaded = uploaderUid == currentAdminUid;
    final locale = Localizations.localeOf(context).languageCode;

    Widget buildPaymentInfo() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Address Header & Verified Amount Badge
          FutureBuilder<Map<String, dynamic>?>(
            future: _addressFuture,
            builder: (context, addrSnapshot) {
              if (addrSnapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 36,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final addressTitle = _formatAddressTitle(addrSnapshot.data);
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.home_outlined,
                          size: 24,
                          color: AppConfig.primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            addressTitle,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppConfig.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (amount != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Text(
                        '\$${amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),

          // 2. Payment Metadata Badges (Concept, Folio, Date, Billing Periods)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: Icon(
                  concept == 'sanction' ? Icons.gavel : Icons.receipt_long,
                  size: 16,
                  color: concept == 'sanction' ? Colors.red.shade700 : AppConfig.primaryColor,
                ),
                label: Text(
                  concept == 'sanction' ? l10n.conceptSanction : l10n.conceptMonthlyQuota,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: concept == 'sanction' ? Colors.red.shade800 : Colors.black87,
                  ),
                ),
                backgroundColor: concept == 'sanction'
                    ? Colors.red.shade50
                    : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              if (folio.isNotEmpty)
                Chip(
                  avatar: const Icon(Icons.tag, size: 16, color: Colors.blueGrey),
                  label: Text(
                    'Folio: $folio',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  backgroundColor: Colors.blueGrey.shade50,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              if (paymentDateTime != null)
                Chip(
                  avatar: const Icon(Icons.calendar_today, size: 16, color: Colors.teal),
                  label: Text(
                    '${l10n.dateOfPaymentLabel}: ${paymentDateTime.year}-${paymentDateTime.month.toString().padLeft(2, '0')}-${paymentDateTime.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
              spacing: 8,
              runSpacing: 8,
              children: periodsList.map((period) {
                return Chip(
                  avatar: const Icon(Icons.event, size: 16, color: AppConfig.primaryColor),
                  label: Text(
                    '${l10n.periodPaidLabel}: ${_formatPeriod(period, locale)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
          ],

          if (concept == 'sanction' && _sanctionFuture != null)
            FutureBuilder<Map<String, dynamic>?>(
              future: _sanctionFuture,
              builder: (context, sanctionSnap) {
                if (sanctionSnap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: SizedBox(
                      height: 24,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  );
                }
                final sanction = sanctionSnap.data;
                if (sanction == null) return const SizedBox.shrink();

                final reason = sanction['reason']?.toString().trim() ?? '';
                final dynamic rawSanctionAmount = sanction['amount'];
                final double? sanctionAmount = rawSanctionAmount is num
                    ? rawSanctionAmount.toDouble()
                    : (rawSanctionAmount is String ? double.tryParse(rawSanctionAmount) : null);
                final evidenceUrl = sanction['evidenceUrl']?.toString().trim() ?? '';

                return Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (sanctionAmount != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                l10n.sanctionAmountLabel,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '\$${sanctionAmount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade900,
                              ),
                            ),
                          ],
                        ),
                        if (reason.isNotEmpty) const SizedBox(height: 8),
                      ],
                      if (reason.isNotEmpty) ...[
                        Text(
                          l10n.sanctionReasonLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          reason,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                      if (evidenceUrl.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () => _showImagePreview(evidenceUrl),
                            icon: Icon(Icons.photo_library_outlined, size: 16, color: Colors.red.shade800),
                            label: Text(
                              l10n.sanctionEvidencePhoto,
                              style: TextStyle(fontSize: 12, color: Colors.red.shade800),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.red.shade300),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      );
    }

    Widget buildReceiptPreview() {
      if (receiptUrl.isEmpty) {
        return const SizedBox.shrink();
      }
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: IgnorePointer(
                  child: StorageNetworkImage(
                    imageUrl: receiptUrl,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const ValueKey('payment_receipt_thumbnail'),
                    onTap: () => _showImagePreview(receiptUrl),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildActionButtons(double bottomMargin) {
      return Padding(
        padding: EdgeInsets.only(bottom: bottomMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
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
                  onPressed: _isProcessing ? null : () => _rejectPayment(widget.doc, residentUid),
                  child: Text(
                    l10n.rejectResidentButton,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
                ElevatedButton(
                  onPressed: _isProcessing || isSelfUploaded
                      ? null
                      : () => _approvePayment(widget.doc['id'] as String, residentUid),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: _isProcessing
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
      );
    }

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(l10n.reviewPaymentsMenu, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final actionBottomMargin = constraints.maxHeight * 0.1;
              if (constraints.maxWidth > 650.0) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: buildReceiptPreview(),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: SingleChildScrollView(
                              child: buildPaymentInfo(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          buildActionButtons(actionBottomMargin),
                        ],
                      ),
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buildPaymentInfo(),
                  const SizedBox(height: 16),
                  Expanded(
                    child: buildReceiptPreview(),
                  ),
                  const SizedBox(height: 16),
                  buildActionButtons(actionBottomMargin),
                ],
              );
            },
          ),
        ),
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
