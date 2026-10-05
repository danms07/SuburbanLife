import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../core/widgets/interactive_image_dialog.dart';
import '../../core/widgets/storage_network_image.dart';
import '../../l10n/app_localizations.dart';
import '../payments/payment_screen.dart';

class SanctionsScreen extends StatelessWidget {
  final String currentUid;

  const SanctionsScreen({super.key, required this.currentUid});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(
          l10n.sanctionsMenu,
          style: const TextStyle(fontFamily: AppConfig.fontFamily),
        ),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        // "Rules Are Not Filters": Matches resource.data.authorizedUids.hasAny([request.auth.uid]) in firestore.rules
        stream: DatabaseService().streamCollection(
          'sanctions',
          filters: [
            QueryFilter('authorizedUids', FilterOperator.arrayContains, currentUid),
          ],
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.errorPrefix(snapshot.error.toString())));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final sanctions = snapshot.data ?? [];

          // Sort descending by creation date
          final sortedSanctions = List<Map<String, dynamic>>.from(sanctions)
            ..sort((a, b) {
              final aTime = (a['createdAt'] as num?) ?? 0;
              final bTime = (b['createdAt'] as num?) ?? 0;
              return bTime.compareTo(aTime);
            });

          final activeCount = sortedSanctions.where((s) {
            final st = s['status'] as String? ?? 'active';
            return st == 'active' || st == 'pending_review';
          }).length;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (activeCount > 0) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppConfig.dangerColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppConfig.dangerColor.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppConfig.dangerColor, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.activeSanctionsRestrictedWarning(activeCount),
                            style: const TextStyle(
                              color: AppConfig.dangerColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              fontFamily: AppConfig.fontFamily,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (sortedSanctions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.verified_outlined, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            l10n.noSanctions,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                              fontFamily: AppConfig.fontFamily,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...sortedSanctions.map((sanction) => _SanctionItemCard(
                    sanction: sanction,
                    currentUid: currentUid,
                  )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SanctionItemCard extends StatelessWidget {
  final Map<String, dynamic> sanction;
  final String currentUid;

  const _SanctionItemCard({required this.sanction, required this.currentUid});

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
    final rejectionReason = sanction['rejectionReason'] as String? ?? '';
    final dynamic rawCreated = sanction['createdAt'];
    final DateTime? createdDate = rawCreated != null
        ? DateTime.fromMillisecondsSinceEpoch(
            rawCreated is int ? rawCreated : int.tryParse(rawCreated.toString()) ?? 0,
          )
        : null;

    final isActive = status == 'active';

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status and Date Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatusChip(context, l10n, status),
                if (createdDate != null)
                  Text(
                    '${createdDate.year}-${createdDate.month.toString().padLeft(2, '0')}-${createdDate.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Fine Amount
            if (amount != null)
              Text(
                '\$${amount.toStringAsFixed(2)} MXN',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppConfig.primaryColor,
                  fontFamily: AppConfig.fontFamily,
                ),
              ),
            const SizedBox(height: 6),

            // Reason / Description
            Text(
              reason,
              style: const TextStyle(
                fontSize: 15,
                fontFamily: AppConfig.fontFamily,
              ),
            ),
            const SizedBox(height: 10),

            // Rejection reason note if previously rejected
            if (isActive && rejectionReason.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.paymentRejectedBannerMsg(rejectionReason),
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontSize: 13,
                          fontFamily: AppConfig.fontFamily,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Evidence Photo Preview
            if (evidenceUrl.isNotEmpty) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () => showInteractiveImageDialog(context, evidenceUrl),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      StorageNetworkImage(
                        imageUrl: evidenceUrl,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                      Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_in, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text(
                              'Zoom',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Pay Sanction Button for active unpaid fines
            if (isActive)
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.payment, size: 18),
                  label: Text(l10n.paySanction),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => PaymentScreen(
                          currentUid: currentUid,
                          initialConcept: 'sanction',
                          initialSanctionId: sanction['id'] as String?,
                          initialAmount: amount,
                        ),
                      ),
                    );
                  },
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}
