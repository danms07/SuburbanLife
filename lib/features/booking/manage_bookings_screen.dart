import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../core/services/document_transfer_helper.dart';
import '../../l10n/app_localizations.dart';
import 'booking_screen.dart';
import 'booking_service.dart';
import 'facility_document_models.dart';
import 'widgets/facility_documents_section.dart';

class ManageBookingsScreen extends StatefulWidget {
  const ManageBookingsScreen({Key? key}) : super(key: key);

  @override
  _ManageBookingsScreenState createState() => _ManageBookingsScreenState();
}

class _ManageBookingsScreenState extends State<ManageBookingsScreen> {
  final BookingService _bookingService = BookingService();
  final String? _uid = AuthService().currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final uid = _uid;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(l10n.upcomingBookings, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: uid == null
          ? Center(child: Text(l10n.userNotLoggedIn))
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: DatabaseService().streamCollection('facilities'),
              builder: (context, facSnapshot) {
                final facilitiesMap = <String, String>{};
                final facilityDocsMap = <String, Map<String, dynamic>>{};
                for (final doc in facSnapshot.data ?? const <Map<String, dynamic>>[]) {
                  final id = doc['id']?.toString();
                  final name = doc['name']?.toString();
                  if (id != null && id.isNotEmpty) {
                    facilityDocsMap[id] = doc;
                    if (name != null && name.isNotEmpty) {
                      facilitiesMap[id] = name;
                    }
                  }
                }

                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _bookingService.getUserBookings(uid),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(child: Text(l10n.noBookings));
                    }

                    final bookings = snapshot.data!;

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: bookings.length,
                      itemBuilder: (context, index) {
                        final b = bookings[index];
                        final rawStart = b['startTime'];
                        final rawEnd = b['endTime'];
                        final start = rawStart is DateTime
                            ? rawStart
                            : DateTime.fromMillisecondsSinceEpoch((rawStart as num).toInt());
                        final end = rawEnd is DateTime
                            ? rawEnd
                            : DateTime.fromMillisecondsSinceEpoch((rawEnd as num).toInt());
                        final status = b['status'] ?? 'pending';
                        final facilityId = (b['facilityId'] ?? 'unknown').toString();
                        final displayFacilityName = facilitiesMap[facilityId] ?? _getFacilityName(l10n, facilityId);

                        final rawReason = (b['rejectionReason'] ?? b['notes'])?.toString().trim();
                        final hasRejectionReason = status == 'rejected' && rawReason != null && rawReason.isNotEmpty;

                        final approvalMessage = b['approvalMessage']?.toString().trim();
                        final hasApprovalMessage = (status.toString().startsWith('approved') || status == 'confirmed') &&
                            approvalMessage != null &&
                            approvalMessage.isNotEmpty;

                        final hasAttachments = b['hasAttachments'] == true;
                        final isAttachmentsPurged = b['attachmentsPurgedAt'] != null;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          child: ListTile(
                            title: Text(
                              displayFacilityName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: AppConfig.fontFamily),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${DateFormat('MMM dd, yyyy').format(start)} from ${DateFormat('hh:mm a').format(start)} to ${DateFormat('hh:mm a').format(end)}'),
                                const SizedBox(height: 4),
                                _buildStatusChip(l10n, status.toString()),
                                if (hasAttachments && isAttachmentsPurged) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.auto_delete_outlined,
                                        size: 15,
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          l10n.bookingAttachmentsPurgedNotice,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ] else if (hasAttachments && b['id'] != null) ...[
                                  const SizedBox(height: 8),
                                  _BookingAttachmentsChips(
                                    bookingId: b['id'].toString(),
                                    bookingService: _bookingService,
                                  ),
                                ],
                                if (hasApprovalMessage) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.info_outline, size: 14, color: AppConfig.secondaryColor),
                                            const SizedBox(width: 4),
                                            Text(
                                              l10n.approvalInstructionsCardTitle,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: AppConfig.secondaryColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          approvalMessage,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.green.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (hasRejectionReason) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.info_outline, size: 14, color: Colors.redAccent),
                                            const SizedBox(width: 4),
                                            Text(
                                              l10n.rejectionReasonLabel,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.redAccent,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          rawReason,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.red.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (status == 'rejected')
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: AppConfig.primaryColor),
                                    tooltip: l10n.editRejectedBookingTitle,
                                    onPressed: () {
                                      _showEditDialog(b, facilityDocsMap[facilityId]);
                                    },
                                  ),
                                if (status == 'rejected' || status == 'pending review' || status == 'approved (upcoming)')
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    tooltip: l10n.deleteBooking,
                                    onPressed: () => _confirmCancelBooking(b['id'].toString()),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const BookingScreen()),
          );
        },
      ),
    );
  }

  String _getFacilityName(AppLocalizations l10n, String id) {
    switch (id) {
      case 'multipurpose_room':
        return l10n.multipurposeRoom;
      case 'bicycle_1':
        return l10n.bicycle1;
      case 'roof_garden':
        return l10n.roofGarden;
      default:
        return id;
    }
  }

  String _getTranslatedStatus(AppLocalizations l10n, String status) {
    switch (status) {
      case 'pending review':
        return l10n.pendingReview;
      case 'approved (upcoming)':
        return l10n.approvedUpcoming;
      case 'approved (in use)':
        return l10n.approvedInUse;
      case 'closed':
        return l10n.closed;
      case 'rejected':
        return l10n.rejected;
      default:
        return status;
    }
  }

  Widget _buildStatusChip(AppLocalizations l10n, String status) {
    Color color = Colors.grey;
    switch (status) {
      case 'pending review':
        color = Colors.orange;
        break;
      case 'approved (upcoming)':
        color = Colors.green;
        break;
      case 'approved (in use)':
        color = Colors.blue;
        break;
      case 'closed':
        color = Colors.grey;
        break;
      case 'rejected':
        color = Colors.red;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        _getTranslatedStatus(l10n, status).toUpperCase(),
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> booking, Map<String, dynamic>? facilityDoc) {
    final parentMessenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (_) => _ResubmitBookingDialog(
        booking: booking,
        facilityDoc: facilityDoc,
        bookingService: _bookingService,
        parentMessenger: parentMessenger,
        currentUserUid: _uid ?? '',
      ),
    );
  }

  void _confirmCancelBooking(String bookingId) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.deleteBooking),
        content: Text(l10n.deleteBookingConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(l10n.deleteBooking),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _bookingService.cancelBooking(bookingId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.bookingDeletedSuccess),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('Error cancelling booking: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'ManageBookingsScreen._confirmCancelBooking');
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
}

class _BookingAttachmentsChips extends StatelessWidget {
  final String bookingId;
  final BookingService bookingService;

  const _BookingAttachmentsChips({
    required this.bookingId,
    required this.bookingService,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SubmittedBookingAttachment>>(
      stream: bookingService.streamBookingAttachments(bookingId),
      builder: (context, snapshot) {
        final attachments = snapshot.data ?? const <SubmittedBookingAttachment>[];
        if (attachments.isEmpty) return const SizedBox.shrink();

        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: attachments.map((att) {
            return ActionChip(
              key: ValueKey('manage_booking_att_${bookingId}_${att.facilityDocId}'),
              avatar: Icon(
                DocumentTransferHelper.iconForExtension(att.fileType),
                size: 16,
                color: AppConfig.primaryColor,
              ),
              label: Text(
                att.title,
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: () {
                DocumentTransferHelper.openOrDownloadDocument(
                  context: context,
                  cacheId: 'batt_${bookingId}_${att.facilityDocId}',
                  url: att.url,
                  fileName: att.fileName,
                  title: att.title,
                );
              },
            );
          }).toList(),
        );
      },
    );
  }
}

class _ResubmitBookingDialog extends StatefulWidget {
  final Map<String, dynamic> booking;
  final Map<String, dynamic>? facilityDoc;
  final BookingService bookingService;
  final ScaffoldMessengerState parentMessenger;
  final String currentUserUid;

  const _ResubmitBookingDialog({
    required this.booking,
    required this.facilityDoc,
    required this.bookingService,
    required this.parentMessenger,
    required this.currentUserUid,
  });

  @override
  State<_ResubmitBookingDialog> createState() => _ResubmitBookingDialogState();
}

class _ResubmitBookingDialogState extends State<_ResubmitBookingDialog> {
  late DateTime _selectedDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  final Map<String, DraftBookingAttachment> _draftAttachments = {};
  bool _isLoadingAttachments = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final rawStart = widget.booking['startTime'];
    final rawEnd = widget.booking['endTime'];
    _selectedDate = rawStart is DateTime
        ? rawStart
        : DateTime.fromMillisecondsSinceEpoch((rawStart as num).toInt());
    _startTime = TimeOfDay.fromDateTime(_selectedDate);
    _endTime = TimeOfDay.fromDateTime(
      rawEnd is DateTime ? rawEnd : DateTime.fromMillisecondsSinceEpoch((rawEnd as num).toInt()),
    );

    if (widget.booking['hasAttachments'] == true && widget.booking['id'] != null) {
      _loadExistingAttachments(widget.booking['id'].toString());
    }
  }

  @override
  void dispose() {
    for (final draft in _draftAttachments.values) {
      draft.disposeTempCapture();
    }
    super.dispose();
  }

  Future<void> _loadExistingAttachments(String bookingId) async {
    setState(() {
      _isLoadingAttachments = true;
    });
    try {
      final existing = await widget.bookingService.getBookingAttachments(bookingId);
      if (!mounted) return;
      setState(() {
        for (final att in existing) {
          _draftAttachments[att.facilityDocId] = DraftBookingAttachment.fromSubmitted(att);
        }
      });
    } catch (e) {
      debugPrint('Error loading existing booking attachments: ${e.runtimeType}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAttachments = false;
        });
      }
    }
  }

  Future<void> _handleResubmit() async {
    final l10n = AppLocalizations.of(context)!;
    final startDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _startTime.hour,
      _startTime.minute,
    );
    final endDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _endTime.hour,
      _endTime.minute,
    );

    if (!endDateTime.isAfter(startDateTime)) {
      widget.parentMessenger.showSnackBar(
        SnackBar(
          content: Text(l10n.bookingEndTimeAfterStartError),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final templates = FacilityDocumentTemplate.parseList(widget.facilityDoc?['facilityDocuments']);
    final missingDocs = findMissingMandatoryDocuments(templates, _draftAttachments);
    if (missingDocs.isNotEmpty) {
      final missingTitles = missingDocs.map((m) => m.title).join(', ');
      widget.parentMessenger.showSnackBar(
        SnackBar(
          content: Text(l10n.missingMandatoryDocumentsError(missingTitles)),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final facilityId = widget.booking['facilityId'].toString();
      final bookingId = widget.booking['id'].toString();
      final addressId = widget.booking['addressId']?.toString();
      final hasReturnTemplates = templates.any((t) => t.requirementMode.acceptsAttachment);

      if (hasReturnTemplates) {
        await widget.bookingService.uploadAndCreateBooking(
          facilityId: facilityId,
          userUid: widget.currentUserUid.isNotEmpty
              ? widget.currentUserUid
              : (widget.booking['userUid']?.toString() ?? ''),
          addressId: addressId,
          startTime: startDateTime,
          endTime: endDateTime,
          templates: templates,
          draftsByDocId: _draftAttachments,
          resubmitBookingId: bookingId,
        );
      } else {
        await widget.bookingService.createBooking(
          facilityId,
          startDateTime,
          endDateTime,
          resubmitBookingId: bookingId,
        );
      }

      if (mounted) {
        _draftAttachments.clear();
        Navigator.pop(context);
      }
      widget.parentMessenger.showSnackBar(
        SnackBar(content: Text(l10n.bookingResubmittedSuccess)),
      );
    } catch (e, stack) {
      debugPrint('Error resubmitting booking: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'ManageBookingsScreen.resubmitBooking');
      widget.parentMessenger.showSnackBar(
        SnackBar(
          content: Text(l10n.errorPrefix(e.toString())),
          backgroundColor: Colors.redAccent,
        ),
      );
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final firstDate = _selectedDate.isBefore(now) ? _selectedDate : now;
    final templates = FacilityDocumentTemplate.parseList(widget.facilityDoc?['facilityDocuments']);

    return AlertDialog(
      title: Text(l10n.editRejectedBookingTitle),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((widget.booking['rejectionReason'] != null &&
                      widget.booking['rejectionReason'].toString().trim().isNotEmpty) ||
                  (widget.booking['notes'] != null &&
                      widget.booking['notes'].toString().trim().isNotEmpty)) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline, size: 14, color: Colors.redAccent),
                          const SizedBox(width: 4),
                          Text(
                            l10n.rejectionReasonLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (widget.booking['rejectionReason'] ?? widget.booking['notes']).toString().trim(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              ListTile(
                title: Text('${l10n.date}: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: firstDate,
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedDate = picked;
                    });
                  }
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      title: Text('${l10n.from}: ${_startTime.format(context)}'),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _startTime,
                        );
                        if (picked != null) {
                          setState(() {
                            _startTime = picked;
                          });
                        }
                      },
                    ),
                  ),
                  Expanded(
                    child: ListTile(
                      title: Text('${l10n.to}: ${_endTime.format(context)}'),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _endTime,
                        );
                        if (picked != null) {
                          setState(() {
                            _endTime = picked;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              if (_isLoadingAttachments)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (templates.isNotEmpty) ...[
                const SizedBox(height: 12),
                FacilityDocumentsSection(
                  templates: templates,
                  draftsByDocId: _draftAttachments,
                  enabled: !_isSubmitting,
                  onDraftSelected: (draft) {
                    setState(() {
                      _draftAttachments[draft.facilityDocId] = draft;
                    });
                  },
                  onDraftRemoved: (docId) {
                    setState(() {
                      final removed = _draftAttachments.remove(docId);
                      removed?.disposeTempCapture();
                    });
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _handleResubmit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.resubmitButton),
        ),
      ],
    );
  }
}
