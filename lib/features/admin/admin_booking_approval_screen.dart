import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../core/services/document_transfer_helper.dart';
import '../../core/widgets/rotatable_image_preview.dart';
import '../../l10n/app_localizations.dart';
import '../booking/booking_service.dart';
import '../booking/facility_document_models.dart';
import '../booking/widgets/facility_documents_section.dart';

/// Master list screen displaying all amenity bookings awaiting administrator
/// review in a compact summary card format. Tapping any card opens
/// [AdminBookingDetailScreen].
class AdminBookingApprovalScreen extends StatelessWidget {
  final bool isEmbedded;

  const AdminBookingApprovalScreen({super.key, this.isEmbedded = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: isEmbedded
          ? null
          : AppBar(
              title: Text(
                l10n.adminBookingApprovalTitle,
                style: const TextStyle(fontFamily: AppConfig.fontFamily),
              ),
              backgroundColor: AppConfig.primaryColor,
              foregroundColor: Colors.white,
            ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: DatabaseService().streamCollection(
          'bookings',
          filters: [
            QueryFilter('status', FilterOperator.equal, 'pending review'),
          ],
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(l10n.errorPrefix(snapshot.error.toString())),
            );
          }

          final bookings = snapshot.data ?? const [];
          if (bookings.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.event_available,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noPendingBookings,
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: bookings.length,
            itemBuilder: (context, index) {
              final booking = bookings[index];
              final bookingId = (booking['id'] ?? index).toString();
              return _BookingSummaryCard(
                key: ValueKey(bookingId),
                booking: booking,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          AdminBookingDetailScreen(booking: booking),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Detail review screen for a single pending booking request, presenting full
/// facility schedule metadata, household & applicant details, submitted
/// resident documentation with inline image controls, and Approve/Reject
/// actions.
class AdminBookingDetailScreen extends StatefulWidget {
  final Map<String, dynamic> booking;
  final BookingService? bookingService;

  const AdminBookingDetailScreen({
    super.key,
    required this.booking,
    this.bookingService,
  });

  @override
  State<AdminBookingDetailScreen> createState() =>
      _AdminBookingDetailScreenState();
}

class _AdminBookingDetailScreenState extends State<AdminBookingDetailScreen> {
  late final BookingService _bookingService;
  late final Stream<Map<String, dynamic>?>? _facilityStream;
  late final Future<_BookingUserAndAddress> _userAndAddressFuture;
  late final Stream<List<SubmittedBookingAttachment>> _attachmentsStream;
  bool _isProcessing = false;

  String get _bookingId => widget.booking['id']?.toString().trim() ?? '';
  String get _facilityId =>
      widget.booking['facilityId']?.toString().trim() ?? '';
  String get _userUid => widget.booking['userUid']?.toString().trim() ?? '';

  @override
  void initState() {
    super.initState();
    _bookingService = widget.bookingService ?? BookingService();
    _facilityStream = _facilityId.isNotEmpty
        ? DatabaseService().streamDocument('facilities', _facilityId)
        : null;
    _userAndAddressFuture = _fetchUserAndAddress(widget.booking);
    _attachmentsStream = _bookingId.isNotEmpty
        ? _bookingService.streamBookingAttachments(_bookingId)
        : Stream.value(const <SubmittedBookingAttachment>[]);
  }

  Future<void> _approveBooking(String bookingId, String? presetMessage) async {
    final instructions = await showDialog<String>(
      context: context,
      builder: (_) => _ApproveBookingDialog(presetMessage: presetMessage),
    );
    if (instructions == null || !mounted) return;

    final l10n = AppLocalizations.of(context)!;
    setState(() => _isProcessing = true);

    try {
      await DatabaseService().updateDocument('bookings', bookingId, {
        'status': 'approved (upcoming)',
        'isConfirmed': true,
        'approvalMessage': instructions,
        'updatedAt': DbFieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.bookingApprovedSuccess),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e, stack) {
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'AdminBookingDetailScreen._approveBooking',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorPrefix(e.toString())),
            backgroundColor: AppConfig.dangerColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _rejectBooking(String bookingId) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectBookingDialog(),
    );
    if (reason == null || !mounted) return;

    final l10n = AppLocalizations.of(context)!;
    setState(() => _isProcessing = true);

    try {
      await DatabaseService().updateDocument('bookings', bookingId, {
        'status': 'rejected',
        'isConfirmed': false,
        'notes': reason,
        'rejectionReason': reason,
        'updatedAt': DbFieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.bookingRejectedSuccess)),
        );
        Navigator.of(context).pop();
      }
    } catch (e, stack) {
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'AdminBookingDetailScreen._rejectBooking',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorPrefix(e.toString())),
            backgroundColor: AppConfig.dangerColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Widget _buildBookingInfo(
    BuildContext context,
    AppLocalizations l10n,
    Map<String, dynamic>? facilityDoc,
  ) {
    final localeTag = Localizations.localeOf(context).toString();
    final facilityTitle = _resolveBookingFacilityName(
      l10n,
      _facilityId,
      facilityDoc,
    );
    final start =
        _parseBookingDateTime(widget.booking['startTime']) ?? DateTime.now();
    final end =
        _parseBookingDateTime(widget.booking['endTime']) ?? DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFacilityHeaderWithStatus(
          l10n: l10n,
          title: facilityTitle,
          fontSize: 22,
          iconSize: 24,
          badgePadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ),
          badgeFontSize: 13,
          badgeRadius: 10,
        ),
        const SizedBox(height: 16),

        // 2. Requested Time Slot Highlight
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.schedule,
                size: 20,
                color: AppConfig.primaryColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.timeSlot,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatBookingSlot(
                        start,
                        end,
                        localeTag,
                        includeWeekday: true,
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. Applicant & Household Details
        FutureBuilder<_BookingUserAndAddress>(
          future: _userAndAddressFuture,
          builder: (context, userAddrSnap) {
            if (userAddrSnap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 40,
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

            final userDoc = userAddrSnap.data?.userDoc;
            final addressDoc = userAddrSnap.data?.addressDoc;
            final rawName = userDoc?['name']?.toString().trim() ?? '';
            final applicantName = rawName.isNotEmpty ? rawName : _userUid;
            final email = userDoc?['email']?.toString().trim() ?? '';
            final phone = userDoc?['phoneNumber']?.toString().trim() ?? '';
            final addressTitle = _formatAddressTitle(addressDoc);

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.person_outline,
                        size: 18,
                        color: AppConfig.primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${l10n.applicant}: $applicantName',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (addressTitle.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.home_outlined,
                          size: 16,
                          color: Colors.grey.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            addressTitle,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.email_outlined,
                          size: 16,
                          color: Colors.grey.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            email,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.phone_outlined,
                          size: 16,
                          color: Colors.grey.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            phone,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildDocumentationPane(
    BuildContext context,
    AppLocalizations l10n,
    AsyncSnapshot<List<SubmittedBookingAttachment>> attSnapshot,
  ) {
    final attachments =
        attSnapshot.data ?? const <SubmittedBookingAttachment>[];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.folder_shared_outlined,
                size: 20,
                color: AppConfig.primaryColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.bookingAttachmentsSectionTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppConfig.primaryColor,
                  ),
                ),
              ),
              if (attachments.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Text(
                    l10n.bookingAttachmentsCountBadge(attachments.length),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.teal.shade900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Builder(
                builder: (context) {
                  if (attSnapshot.connectionState == ConnectionState.waiting &&
                      attachments.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (attachments.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        l10n.noBookingAttachmentsSubmitted,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: attachments.map((att) {
                      final ext = att.fileType.toLowerCase();
                      final isImage =
                          DocumentTransferHelper.imageExtensions.contains(
                            ext,
                          ) &&
                          att.url.isNotEmpty;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            LayoutBuilder(
                              builder: (context, itemConstraints) {
                                final viewButton = OutlinedButton.icon(
                                  key: ValueKey(
                                    'approval_view_attachment_${_bookingId}_${att.facilityDocId}',
                                  ),
                                  onPressed: () {
                                    DocumentTransferHelper
                                        .openOrDownloadDocument(
                                          context: context,
                                          cacheId:
                                              'batt_${_bookingId}_${att.facilityDocId}',
                                          url: att.url,
                                          fileName: att.fileName,
                                          title: att.title,
                                        );
                                  },
                                  icon: const Icon(
                                    Icons.open_in_new,
                                    size: 16,
                                  ),
                                  label: Text(
                                    l10n.viewBookingAttachmentButton,
                                  ),
                                );

                                final metaRow = Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Icon(
                                        DocumentTransferHelper.iconForExtension(
                                          att.fileType,
                                        ),
                                        color: AppConfig.primaryColor,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                att.title,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              FacilityDocumentsSection.buildModeBadge(
                                                l10n,
                                                att.requirementMode,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${att.fileName} (${DocumentTransferHelper.formatFileSize(att.fileSize)})',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );

                                if (itemConstraints.maxWidth >= 420.0) {
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(child: metaRow),
                                      const SizedBox(width: 8),
                                      viewButton,
                                    ],
                                  );
                                }

                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    metaRow,
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: viewButton,
                                    ),
                                  ],
                                );
                              },
                            ),
                            if (isImage) ...[
                              const SizedBox(height: 10),
                              RotatableImagePreview(
                                imageUrl: att.url,
                                dialogTitle: att.title,
                                height: 220,
                                padding: const EdgeInsets.all(8),
                                borderRadius: 10,
                                thumbnailKey: ValueKey(
                                  'booking_att_thumbnail_${_bookingId}_${att.facilityDocId}',
                                ),
                                rotatedBoxKey: ValueKey(
                                  'booking_att_rotated_box_${_bookingId}_${att.facilityDocId}',
                                ),
                                rotateButtonKey: ValueKey(
                                  'booking_att_rotate_btn_${_bookingId}_${att.facilityDocId}',
                                ),
                                fullscreenButtonKey: ValueKey(
                                  'booking_att_fullscreen_btn_${_bookingId}_${att.facilityDocId}',
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    AppLocalizations l10n,
    double bottomMargin,
    String? presetMessage,
  ) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomMargin),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 12,
        runSpacing: 8,
        children: [
          TextButton(
            key: const ValueKey('booking_detail_reject_button'),
            onPressed: _isProcessing ? null : () => _rejectBooking(_bookingId),
            child: Text(
              l10n.reject,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('booking_detail_approve_button'),
            onPressed: _isProcessing
                ? null
                : () => _approveBooking(_bookingId, presetMessage),
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
                : Text(l10n.approveBookingButton),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasAttachmentsFlag = widget.booking['hasAttachments'] == true;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(
          l10n.bookingDetails,
          style: const TextStyle(fontFamily: AppConfig.fontFamily),
        ),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: StreamBuilder<Map<String, dynamic>?>(
            stream: _facilityStream,
            builder: (context, facSnapshot) {
              final facilityDoc = facSnapshot.data;
              final presetMessage = facilityDoc?['presetApprovalMessage']
                  ?.toString();
              final facilityTemplates = FacilityDocumentTemplate.parseList(
                facilityDoc?['facilityDocuments'],
              );
              final facilityAcceptsAttachments = facilityTemplates.any(
                (doc) => doc.requirementMode.acceptsAttachment,
              );

              return StreamBuilder<List<SubmittedBookingAttachment>>(
                stream: _attachmentsStream,
                builder: (context, attSnapshot) {
                  final attachments =
                      attSnapshot.data ?? const <SubmittedBookingAttachment>[];
                  final shouldShowDocumentation =
                      hasAttachmentsFlag ||
                      facilityAcceptsAttachments ||
                      attachments.isNotEmpty;

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 650.0;

                      if (!shouldShowDocumentation) {
                        if (isWide) {
                          return Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: 680,
                                maxHeight: constraints.maxHeight,
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: SingleChildScrollView(
                                        child: _buildBookingInfo(
                                          context,
                                          l10n,
                                          facilityDoc,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    const Divider(height: 1),
                                    const SizedBox(height: 16),
                                    _buildActionButtons(
                                      l10n,
                                      0,
                                      presetMessage,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: _buildBookingInfo(
                                  context,
                                  l10n,
                                  facilityDoc,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildActionButtons(l10n, 12.0, presetMessage),
                          ],
                        );
                      }

                      if (isWide) {
                        final actionBottomMargin = constraints.maxHeight > 500.0
                            ? constraints.maxHeight * 0.1
                            : 8.0;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 3,
                              child: _buildDocumentationPane(
                                context,
                                l10n,
                                attSnapshot,
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: SingleChildScrollView(
                                      child: _buildBookingInfo(
                                        context,
                                        l10n,
                                        facilityDoc,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _buildActionButtons(
                                    l10n,
                                    actionBottomMargin,
                                    presetMessage,
                                  ),
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
                              child: _buildBookingInfo(
                                context,
                                l10n,
                                facilityDoc,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: _buildDocumentationPane(
                              context,
                              l10n,
                              attSnapshot,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildActionButtons(l10n, 12.0, presetMessage),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BookingSummaryCard extends StatefulWidget {
  final Map<String, dynamic> booking;
  final VoidCallback onTap;

  const _BookingSummaryCard({
    required super.key,
    required this.booking,
    required this.onTap,
  });

  @override
  State<_BookingSummaryCard> createState() => _BookingSummaryCardState();
}

class _BookingSummaryCardState extends State<_BookingSummaryCard> {
  Future<_BookingCardMetadata>? _metadataFuture;

  @override
  void initState() {
    super.initState();
    _initMetadataFuture();
  }

  @override
  void didUpdateWidget(covariant _BookingSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldFacilityId = oldWidget.booking['facilityId']?.toString();
    final newFacilityId = widget.booking['facilityId']?.toString();
    final oldUserUid = oldWidget.booking['userUid']?.toString();
    final newUserUid = widget.booking['userUid']?.toString();
    final oldAddressId = _extractAddressId(
      oldWidget.booking['addressRef'],
      oldWidget.booking['addressId'],
    );
    final newAddressId = _extractAddressId(
      widget.booking['addressRef'],
      widget.booking['addressId'],
    );
    if (oldFacilityId != newFacilityId ||
        oldUserUid != newUserUid ||
        oldAddressId != newAddressId) {
      _initMetadataFuture();
    }
  }

  void _initMetadataFuture() {
    _metadataFuture = _fetchCardMetadata(widget.booking);
  }

  Future<_BookingCardMetadata> _fetchCardMetadata(
    Map<String, dynamic> booking,
  ) async {
    final facilityId = booking['facilityId']?.toString().trim() ?? '';
    final db = DatabaseService();
    final facilityFuture = facilityId.isNotEmpty
        ? db.getDocument('facilities', facilityId)
        : Future<Map<String, dynamic>?>.value(null);
    final userAndAddressFuture = _fetchUserAndAddress(booking);

    final facilityDoc = await facilityFuture;
    final userAndAddress = await userAndAddressFuture;

    return _BookingCardMetadata(
      facilityDoc: facilityDoc,
      userDoc: userAndAddress.userDoc,
      addressDoc: userAndAddress.addressDoc,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final localeTag = Localizations.localeOf(context).toString();
    final bookingId = widget.booking['id']?.toString().trim() ?? '';
    final facilityId = widget.booking['facilityId']?.toString().trim() ?? '';
    final userUid = widget.booking['userUid']?.toString().trim() ?? '';
    final start =
        _parseBookingDateTime(widget.booking['startTime']) ?? DateTime.now();
    final end =
        _parseBookingDateTime(widget.booking['endTime']) ?? DateTime.now();

    final hasAttachments = widget.booking['hasAttachments'] == true;
    final rawCount = widget.booking['attachmentCount'];
    final parsedCount = rawCount is num
        ? rawCount.toInt()
        : int.tryParse(rawCount?.toString() ?? '0') ?? 0;
    final attachmentBadgeCount = parsedCount > 0
        ? parsedCount
        : (hasAttachments ? 1 : 0);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('booking_card_$bookingId'),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: FutureBuilder<_BookingCardMetadata>(
                  future: _metadataFuture,
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

                    final data = snapshot.data;
                    final facilityTitle = _resolveBookingFacilityName(
                      l10n,
                      facilityId,
                      data?.facilityDoc,
                    );
                    final rawName =
                        data?.userDoc?['name']?.toString().trim() ?? '';
                    final applicantName =
                        rawName.isNotEmpty ? rawName : userUid;
                    final addressTitle = _formatAddressTitle(data?.addressDoc);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFacilityHeaderWithStatus(
                          l10n: l10n,
                          title: facilityTitle,
                          fontSize: 17,
                          iconSize: 20,
                          badgePadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          badgeFontSize: 12,
                          badgeRadius: 8,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _buildSummaryPill(
                              icon: Icons.schedule,
                              iconColor: AppConfig.primaryColor,
                              text: _formatBookingSlot(start, end, localeTag),
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.08),
                              borderColor: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.2),
                            ),
                            if (applicantName.isNotEmpty)
                              _buildSummaryPill(
                                icon: Icons.person_outline,
                                iconColor: AppConfig.primaryColor,
                                text: applicantName,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.08),
                                borderColor: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.2),
                              ),
                            if (addressTitle.isNotEmpty)
                              _buildSummaryPill(
                                icon: Icons.home_outlined,
                                iconColor: Colors.blueGrey,
                                text: addressTitle,
                                backgroundColor: Colors.blueGrey.shade50,
                                borderColor: Colors.blueGrey.shade200,
                              ),
                            if (attachmentBadgeCount > 0)
                              _buildSummaryPill(
                                icon: Icons.attach_file,
                                iconColor: Colors.teal,
                                text: l10n.bookingAttachmentsCountBadge(
                                  attachmentBadgeCount,
                                ),
                                backgroundColor: Colors.teal.shade50,
                                borderColor: Colors.teal.shade200,
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

class _ApproveBookingDialog extends StatefulWidget {
  final String? presetMessage;

  const _ApproveBookingDialog({this.presetMessage});

  @override
  State<_ApproveBookingDialog> createState() => _ApproveBookingDialogState();
}

class _ApproveBookingDialogState extends State<_ApproveBookingDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.presetMessage ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.approveBookingTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.approvalInstructionsConfirm),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.presetApprovalMessageLabel,
                hintText: l10n.presetApprovalMessageHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppConfig.primaryColor,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.confirmBooking),
        ),
      ],
    );
  }
}

class _RejectBookingDialog extends StatefulWidget {
  const _RejectBookingDialog();

  @override
  State<_RejectBookingDialog> createState() => _RejectBookingDialogState();
}

class _RejectBookingDialogState extends State<_RejectBookingDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.rejectBookingTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.rejectBookingConfirm),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.rejectionReasonLabel,
                hintText: l10n.rejectionReasonHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.reject),
        ),
      ],
    );
  }
}

class _BookingUserAndAddress {
  final Map<String, dynamic>? userDoc;
  final Map<String, dynamic>? addressDoc;

  const _BookingUserAndAddress({this.userDoc, this.addressDoc});
}

class _BookingCardMetadata {
  final Map<String, dynamic>? facilityDoc;
  final Map<String, dynamic>? userDoc;
  final Map<String, dynamic>? addressDoc;

  const _BookingCardMetadata({
    this.facilityDoc,
    this.userDoc,
    this.addressDoc,
  });
}

String _extractAddressId(dynamic rawRef, dynamic rawId) {
  if (rawId is String && rawId.trim().isNotEmpty) {
    return rawId.trim();
  }
  if (rawRef is DbReference && rawRef.id.isNotEmpty) {
    return rawRef.id;
  }
  if (rawRef is String && rawRef.trim().isNotEmpty) {
    return rawRef.trim().split('/').last;
  }
  return '';
}

Future<_BookingUserAndAddress> _fetchUserAndAddress(
  Map<String, dynamic> booking,
) async {
  final db = DatabaseService();
  final userUid = booking['userUid']?.toString().trim() ?? '';
  final userDoc = userUid.isNotEmpty
      ? await db.getDocument('users', userUid)
      : null;

  var addressId = _extractAddressId(
    booking['addressRef'],
    booking['addressId'],
  );
  if (addressId.isEmpty && userDoc != null) {
    addressId = _extractAddressId(
      userDoc['addressRef'],
      userDoc['addressId'],
    );
  }

  final addressDoc = addressId.isNotEmpty
      ? await db.getDocument('addresses', addressId)
      : null;

  return _BookingUserAndAddress(userDoc: userDoc, addressDoc: addressDoc);
}

DateTime? _parseBookingDateTime(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is int && raw > 0) {
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }
  if (raw is num && raw > 0) {
    return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
  }
  if (raw is String && raw.trim().isNotEmpty) {
    final asInt = int.tryParse(raw.trim());
    if (asInt != null && asInt > 0) {
      return DateTime.fromMillisecondsSinceEpoch(asInt);
    }
    return DateTime.tryParse(raw.trim());
  }
  try {
    final dynamic converted = (raw as dynamic).toDate();
    if (converted is DateTime) return converted;
  } catch (_) {
    // Ignore non-Timestamp dynamic objects.
  }
  return null;
}

String _resolveBookingFacilityName(
  AppLocalizations l10n,
  String facilityId,
  Map<String, dynamic>? facilityDoc,
) {
  final docName = facilityDoc?['name']?.toString().trim() ?? '';
  if (docName.isNotEmpty) return docName;

  switch (facilityId) {
    case 'multipurpose_room':
      return l10n.multipurposeRoom;
    case 'bicycle_1':
      return l10n.bicycle1;
    case 'roof_garden':
      return l10n.roofGarden;
    default:
      return facilityId;
  }
}

String _formatAddressTitle(Map<String, dynamic>? addrData) {
  final street = addrData?['streetName']?.toString().trim() ?? '';
  final number = addrData?['number']?.toString().trim() ?? '';
  if (street.isEmpty) return '';
  return number.isNotEmpty ? '$street #$number' : street;
}

String _formatBookingSlot(
  DateTime start,
  DateTime end,
  String localeTag, {
  bool includeWeekday = false,
}) {
  final datePattern = includeWeekday ? 'EEEE, MMM dd, yyyy' : 'MMM dd, yyyy';
  final datePart = DateFormat(datePattern, localeTag).format(start);
  final startPart = DateFormat('hh:mm a', localeTag).format(start);
  final endPart = DateFormat('hh:mm a', localeTag).format(end);
  return '$datePart • $startPart - $endPart';
}

Widget _buildFacilityHeaderWithStatus({
  required AppLocalizations l10n,
  required String title,
  required double fontSize,
  required double iconSize,
  required EdgeInsetsGeometry badgePadding,
  required double badgeFontSize,
  required double badgeRadius,
}) {
  return SizedBox(
    width: double.infinity,
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_note_outlined,
              size: iconSize,
              color: AppConfig.primaryColor,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  color: AppConfig.primaryColor,
                ),
              ),
            ),
          ],
        ),
        Container(
          padding: badgePadding,
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(badgeRadius),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: Text(
            l10n.pendingReview,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.amber.shade900,
              fontSize: badgeFontSize,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildSummaryPill({
  required IconData icon,
  required Color iconColor,
  required String text,
  required Color backgroundColor,
  required Color borderColor,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: borderColor),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    ),
  );
}

