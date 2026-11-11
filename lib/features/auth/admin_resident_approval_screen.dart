import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../core/widgets/rotatable_image_preview.dart';
import '../../l10n/app_localizations.dart';

class AdminResidentApprovalScreen extends StatefulWidget {
  final bool isEmbedded;

  const AdminResidentApprovalScreen({super.key, this.isEmbedded = false});

  @override
  State<AdminResidentApprovalScreen> createState() =>
      _AdminResidentApprovalScreenState();
}

class _AdminResidentApprovalScreenState
    extends State<AdminResidentApprovalScreen> {
  void _openResidentClaimDetail(Map<String, dynamic> doc) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminResidentDetailScreen(doc: doc),
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
              title: Text(
                l10n.approveResidentsMenu,
                style: const TextStyle(fontFamily: AppConfig.fontFamily),
              ),
              backgroundColor: AppConfig.primaryColor,
              foregroundColor: Colors.white,
            ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: DatabaseService().streamCollection('ownership_claims'),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(l10n.errorPrefix(snapshot.error.toString())),
            );
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
              return _ResidentSummaryCard(
                key: ValueKey(doc['id']),
                doc: doc,
                onTap: () => _openResidentClaimDetail(doc),
              );
            },
          );
        },
      ),
    );
  }
}

DbReference? _resolveClaimAddressRef(Map<String, dynamic> claimDoc) {
  final dynamic rawAddressRef = claimDoc['addressRef'];
  if (rawAddressRef is DbReference) {
    return rawAddressRef;
  }
  if (rawAddressRef is String && rawAddressRef.trim().isNotEmpty) {
    final id = rawAddressRef.trim().split('/').last;
    if (id.isNotEmpty) {
      return DatabaseService().createReference('addresses', id);
    }
  }
  return null;
}

Future<Map<String, dynamic>?> _fetchClaimAddress(
  Map<String, dynamic> claimDoc,
) async {
  final addressRef = _resolveClaimAddressRef(claimDoc);
  if (addressRef != null && addressRef.id.isNotEmpty) {
    return DatabaseService().getDocument('addresses', addressRef.id);
  }
  return null;
}

Future<Map<String, dynamic>?> _fetchClaimUser(
  Map<String, dynamic> claimDoc,
) async {
  final userUid = claimDoc['userUid']?.toString().trim() ?? '';
  if (userUid.isNotEmpty) {
    return DatabaseService().getDocument('users', userUid);
  }
  return null;
}

String _formatClaimAddressTitle(
  Map<String, dynamic>? addrData,
  String unknownFallback,
) {
  final street = addrData?['streetName']?.toString().trim() ?? '';
  final number = addrData?['number']?.toString().trim() ?? '';
  if (street.isEmpty) return unknownFallback;
  return number.isNotEmpty ? '$street #$number' : street;
}

DateTime? _parseClaimDateTime(dynamic rawDate) {
  if (rawDate == null) return null;
  if (rawDate is DateTime) return rawDate;
  if (rawDate is int && rawDate > 0) {
    return DateTime.fromMillisecondsSinceEpoch(rawDate);
  }
  if (rawDate is String && rawDate.trim().isNotEmpty) {
    final parsedInt = int.tryParse(rawDate.trim());
    if (parsedInt != null && parsedInt > 0) {
      return DateTime.fromMillisecondsSinceEpoch(parsedInt);
    }
    return DateTime.tryParse(rawDate.trim());
  }
  return null;
}

/// Masks an email address so full PII is not surfaced directly in UI labels.
String _maskEmail(String email) {
  final trimmed = email.trim();
  final atIndex = trimmed.indexOf('@');
  if (atIndex <= 0 || atIndex >= trimmed.length - 1) return '';
  final local = trimmed.substring(0, atIndex);
  final domain = trimmed.substring(atIndex + 1);
  final visiblePrefix = local.length <= 2 ? local.substring(0, 1) : local.substring(0, 2);
  return '$visiblePrefix***@$domain';
}

class _ResidentSummaryCard extends StatefulWidget {
  final Map<String, dynamic> doc;
  final VoidCallback onTap;

  const _ResidentSummaryCard({
    required Key key,
    required this.doc,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_ResidentSummaryCard> createState() => _ResidentSummaryCardState();
}

class _ResidentSummaryCardState extends State<_ResidentSummaryCard> {
  Future<List<Map<String, dynamic>?>>? _detailsFuture;

  @override
  void initState() {
    super.initState();
    _initDetailsFuture();
  }

  @override
  void didUpdateWidget(covariant _ResidentSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldAddressId = _resolveClaimAddressRef(oldWidget.doc)?.id;
    final newAddressId = _resolveClaimAddressRef(widget.doc)?.id;
    final oldUserUid = oldWidget.doc['userUid']?.toString();
    final newUserUid = widget.doc['userUid']?.toString();
    if (oldAddressId != newAddressId || oldUserUid != newUserUid) {
      _initDetailsFuture();
    }
  }

  void _initDetailsFuture() {
    _detailsFuture = Future.wait<Map<String, dynamic>?>([
      _fetchClaimAddress(widget.doc),
      _fetchClaimUser(widget.doc),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final deliveryDate = _parseClaimDateTime(widget.doc['deliveryDate']);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('resident_claim_card_${widget.doc['id']}'),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>?>>(
                  future: _detailsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
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

                    final addrData =
                        snapshot.data != null && snapshot.data!.isNotEmpty
                        ? snapshot.data![0]
                        : null;
                    final userData =
                        snapshot.data != null && snapshot.data!.length > 1
                        ? snapshot.data![1]
                        : null;
                    final addressTitle = _formatClaimAddressTitle(
                      addrData,
                      l10n.unknownAddress,
                    );
                    final applicantName =
                        userData?['name']?.toString().trim() ?? '';

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
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.amber.shade300,
                                ),
                              ),
                              child: Text(
                                l10n.pendingReview,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade900,
                                  fontSize: 12,
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
                            if (applicantName.isNotEmpty)
                              Chip(
                                avatar: const Icon(
                                  Icons.person_outline,
                                  size: 14,
                                  color: AppConfig.primaryColor,
                                ),
                                label: Text(
                                  applicantName,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.08),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              )
                            else
                              Chip(
                                avatar: const Icon(
                                  Icons.home_work_outlined,
                                  size: 14,
                                  color: AppConfig.primaryColor,
                                ),
                                label: Text(
                                  l10n.ownershipProofTitle,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.08),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            if (deliveryDate != null)
                              Chip(
                                avatar: const Icon(
                                  Icons.calendar_today,
                                  size: 14,
                                  color: Colors.teal,
                                ),
                                label: Text(
                                  '${l10n.deliveryDateLabel}: ${DateFormat('yyyy-MM-dd').format(deliveryDate)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                backgroundColor: Colors.teal.shade50,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
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

class AdminResidentDetailScreen extends StatefulWidget {
  final Map<String, dynamic> doc;

  const AdminResidentDetailScreen({
    super.key,
    required this.doc,
  });

  @override
  State<AdminResidentDetailScreen> createState() =>
      _AdminResidentDetailScreenState();
}

class _AdminResidentDetailScreenState extends State<AdminResidentDetailScreen> {
  bool _isProcessing = false;
  Future<Map<String, dynamic>?>? _addressFuture;
  Future<Map<String, dynamic>?>? _userFuture;

  @override
  void initState() {
    super.initState();
    _addressFuture = _fetchClaimAddress(widget.doc);
    _userFuture = _fetchClaimUser(widget.doc);
  }

  Future<void> _approveClaim(Map<String, dynamic> claimDoc) async {
    final userUid = claimDoc['userUid'] as String?;
    final addressRef = _resolveClaimAddressRef(claimDoc);
    final proofUrl = claimDoc['proofUrl'] as String?;
    final deliveryDate = _parseClaimDateTime(claimDoc['deliveryDate']);

    if (userUid == null || userUid.isEmpty || addressRef == null) {
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isProcessing = true;
    });

    try {
      // 1. Invoke setRole Cloud Function to assign resident custom claim
      await FunctionsService().callFunction('setRole', {
        'uid': userUid,
        'role': 'resident',
      });

      // 2. Assign residentUid, initialize paymentStatus to paid, and propagate deliveryDate on the address
      await DatabaseService().updateDocument('addresses', addressRef.id, {
        'residentUid': userUid,
        'paymentStatus': 'paid',
        'deliveryDate': ?deliveryDate,
      });

      // 3. Link addressRef on the user document if not already linked
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
      await DatabaseService().deleteDocument(
        'ownership_claims',
        claimDoc['id'] as String,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.residentApprovedSuccess),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e, stack) {
      debugPrint('Error approving claim: $e');
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'AdminResidentDetailScreen._approveClaim',
      );
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
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _rejectClaim(Map<String, dynamic> claimDoc) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isProcessing = true;
    });

    try {
      final proofUrl = claimDoc['proofUrl'] as String?;
      if (proofUrl != null && proofUrl.isNotEmpty) {
        try {
          await StorageService().deleteFileFromUrl(proofUrl);
        } catch (err, stack) {
          debugPrint('Error deleting proof storage image: $err');
          Backend.crashlytics.recordError(
            err,
            stack,
            reason: 'AdminResidentDetailScreen.deleteProofImage',
          );
        }
      }

      await DatabaseService().deleteDocument(
        'ownership_claims',
        claimDoc['id'] as String,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.residentRejectedSuccess),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e, stack) {
      debugPrint('Error rejecting claim: $e');
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'AdminResidentDetailScreen._rejectClaim',
      );
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
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final proofUrl = widget.doc['proofUrl'] as String? ?? '';
    final deliveryDate = _parseClaimDateTime(widget.doc['deliveryDate']);
    final submittedDate = _parseClaimDateTime(widget.doc['timestamp']);

    Widget buildClaimInfo() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Address Header & Pending Review Badge
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
              final addressTitle = _formatClaimAddressTitle(
                addrSnapshot.data,
                l10n.unknownAddress,
              );
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Text(
                      l10n.pendingReview,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),

          // 2. Claim & Applicant Metadata Badges
          FutureBuilder<Map<String, dynamic>?>(
            future: _userFuture,
            builder: (context, userSnapshot) {
              final userData = userSnapshot.data;
              final applicantName = userData?['name']?.toString().trim() ?? '';
              final maskedEmail = _maskEmail(
                userData?['email']?.toString() ?? '',
              );

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(
                      Icons.home_work_outlined,
                      size: 16,
                      color: AppConfig.primaryColor,
                    ),
                    label: Text(
                      l10n.ownershipProofTitle,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.08),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  if (applicantName.isNotEmpty)
                    Chip(
                      avatar: const Icon(
                        Icons.person_outline,
                        size: 16,
                        color: AppConfig.primaryColor,
                      ),
                      label: Text(
                        applicantName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.08),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (maskedEmail.isNotEmpty)
                    Chip(
                      avatar: const Icon(
                        Icons.alternate_email,
                        size: 16,
                        color: Colors.blueGrey,
                      ),
                      label: Text(
                        maskedEmail,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: Colors.blueGrey.shade50,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  Chip(
                    avatar: const Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: Colors.teal,
                    ),
                    label: Text(
                      deliveryDate != null
                          ? '${l10n.deliveryDateLabel}: ${DateFormat('yyyy-MM-dd').format(deliveryDate)}'
                          : '${l10n.deliveryDateLabel}: ${l10n.deliveryDateNotSet}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    backgroundColor: Colors.teal.shade50,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  if (submittedDate != null)
                    Chip(
                      avatar: const Icon(
                        Icons.schedule,
                        size: 16,
                        color: Colors.blueGrey,
                      ),
                      label: Text(
                        '${l10n.date}: ${DateFormat('yyyy-MM-dd').format(submittedDate)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: Colors.blueGrey.shade50,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),

          // 3. Privacy Notice Callout
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppConfig.warningColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppConfig.warningColor.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.privacy_tip_outlined,
                  color: AppConfig.warningColor,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.adminProofDeletionNotice,
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
        ],
      );
    }

    Widget buildProofPreview() {
      if (proofUrl.isEmpty) {
        return const SizedBox.shrink();
      }
      return RotatableImagePreview(
        imageUrl: proofUrl,
        dialogTitle: l10n.approveResidentsMenu,
        thumbnailKey: const ValueKey('ownership_proof_thumbnail'),
        rotatedBoxKey: const ValueKey('inline_proof_rotated_box'),
        rotateButtonKey: const ValueKey('inline_rotate_image_button'),
        fullscreenButtonKey: const ValueKey('fullscreen_proof_button'),
      );
    }

    Widget buildActionButtons(double bottomMargin) {
      return Padding(
        padding: EdgeInsets.only(bottom: bottomMargin),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: _isProcessing ? null : () => _rejectClaim(widget.doc),
              child: Text(
                l10n.rejectResidentButton,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
            ElevatedButton(
              onPressed: _isProcessing ? null : () => _approveClaim(widget.doc),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConfig.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(l10n.approveResidentButton),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(
          l10n.approveResidentsMenu,
          style: const TextStyle(fontFamily: AppConfig.fontFamily),
        ),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 650.0) {
                final actionBottomMargin = constraints.maxHeight > 500.0
                    ? constraints.maxHeight * 0.1
                    : 8.0;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: buildProofPreview(),
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
                              child: buildClaimInfo(),
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
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.42,
                    ),
                    child: SingleChildScrollView(
                      child: buildClaimInfo(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: buildProofPreview(),
                  ),
                  const SizedBox(height: 16),
                  buildActionButtons(12.0),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
