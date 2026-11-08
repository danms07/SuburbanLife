import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/document_transfer_helper.dart';
import '../../../l10n/app_localizations.dart';
import '../facility_document_models.dart';

/// Renders an amenity's configured documentation templates, allowing the resident
/// to download/view each file and attach completed files (or camera photos) for
/// `mandatory_return` and `optional_return` requirements.
class FacilityDocumentsSection extends StatelessWidget {
  final List<FacilityDocumentTemplate> templates;
  final Map<String, DraftBookingAttachment> draftsByDocId;
  final ValueChanged<DraftBookingAttachment> onDraftSelected;
  final ValueChanged<String> onDraftRemoved;
  final bool enabled;

  const FacilityDocumentsSection({
    super.key,
    required this.templates,
    required this.draftsByDocId,
    required this.onDraftSelected,
    required this.onDraftRemoved,
    this.enabled = true,
  });

  static Widget buildModeBadge(AppLocalizations l10n, FacilityDocRequirementMode mode) {
    final Color baseColor;
    final String label;
    switch (mode) {
      case FacilityDocRequirementMode.mandatoryReturn:
        baseColor = Colors.redAccent;
        label = l10n.facilityDocBadgeMandatory;
        break;
      case FacilityDocRequirementMode.optionalReturn:
        baseColor = Colors.teal;
        label = l10n.facilityDocBadgeOptional;
        break;
      case FacilityDocRequirementMode.informative:
        baseColor = AppConfig.primaryColor;
        label = l10n.facilityDocBadgeInformative;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: baseColor.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: baseColor,
        ),
      ),
    );
  }

  Future<void> _handlePickFile(
    BuildContext context,
    FacilityDocumentTemplate template,
  ) async {
    final picked = await DocumentTransferHelper.pickAllowedDocument(context);
    if (picked == null) return;

    final previous = draftsByDocId[template.docId];
    if (previous != null) {
      await previous.disposeTempCapture();
    }

    onDraftSelected(
      DraftBookingAttachment(
        facilityDocId: template.docId,
        title: template.title,
        requirementMode: template.requirementMode,
        fileName: picked.sanitizedFileName,
        fileType: picked.extension,
        contentType: picked.contentType,
        fileSize: picked.fileSize,
        bytes: picked.bytes,
        tempCameraFile: picked.tempCameraFile,
      ),
    );
  }

  Future<void> _handleCapturePhoto(
    BuildContext context,
    FacilityDocumentTemplate template,
  ) async {
    final captured = await DocumentTransferHelper.captureDocumentPhoto(context);
    if (captured == null) return;

    final previous = draftsByDocId[template.docId];
    if (previous != null) {
      await previous.disposeTempCapture();
    }

    onDraftSelected(
      DraftBookingAttachment(
        facilityDocId: template.docId,
        title: template.title,
        requirementMode: template.requirementMode,
        fileName: captured.sanitizedFileName,
        fileType: captured.extension,
        contentType: captured.contentType,
        fileSize: captured.fileSize,
        bytes: captured.bytes,
        tempCameraFile: captured.tempCameraFile,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context)!;
    final hasReturnSlots = templates.any((t) => t.requirementMode.acceptsAttachment);

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppConfig.primaryColor.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_outlined, color: AppConfig.primaryColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.facilityDocsSectionTitle,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: AppConfig.fontFamily,
                      color: AppConfig.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.bookingDocsInstructionBanner,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 12),
            ...templates.map((template) {
              final draft = draftsByDocId[template.docId];
              final extUpper = template.fileType.toUpperCase();
              final sizeLabel = template.fileSize > 0
                  ? ' • ${DocumentTransferHelper.formatFileSize(template.fileSize)}'
                  : '';

              return Container(
                key: ValueKey('facility_doc_card_${template.docId}'),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: template.requirementMode.isMandatory && draft == null
                        ? Colors.orange.withValues(alpha: 0.6)
                        : Colors.grey.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Icon(
                          DocumentTransferHelper.iconForExtension(template.fileType),
                          size: 18,
                          color: AppConfig.primaryColor,
                        ),
                        Text(
                          template.title,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        buildModeBadge(l10n, template.requirementMode),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${template.fileName}${extUpper.isNotEmpty ? ' ($extUpper$sizeLabel)' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: ValueKey('facility_doc_download_${template.docId}'),
                          onPressed: () {
                            DocumentTransferHelper.openOrDownloadDocument(
                              context: context,
                              cacheId: 'fdoc_${template.docId}',
                              url: template.url,
                              fileName: template.fileName,
                              title: template.title,
                            );
                          },
                          icon: const Icon(Icons.download_outlined, size: 16),
                          label: Text(
                            l10n.downloadFacilityDocumentButton,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (template.requirementMode.acceptsAttachment) ...[
                          ElevatedButton.icon(
                            key: ValueKey('facility_doc_attach_${template.docId}'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConfig.primaryColor,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: enabled ? () => _handlePickFile(context, template) : null,
                            icon: Icon(
                              draft != null ? Icons.swap_horiz : Icons.attach_file,
                              size: 16,
                            ),
                            label: Text(
                              draft != null
                                  ? l10n.replaceAttachedFileButton
                                  : l10n.attachCompletedFileButton,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          if (!kIsWeb)
                            OutlinedButton.icon(
                              key: ValueKey('facility_doc_camera_${template.docId}'),
                              onPressed: enabled ? () => _handleCapturePhoto(context, template) : null,
                              icon: const Icon(Icons.camera_alt_outlined, size: 16),
                              label: Text(
                                l10n.takeDocumentPhotoButton,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ],
                    ),
                    if (draft != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppConfig.secondaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppConfig.secondaryColor.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              size: 16,
                              color: AppConfig.secondaryColor,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${draft.fileName} (${DocumentTransferHelper.formatFileSize(draft.fileSize)})',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (draft.isAlreadyUploaded && draft.existingUrl != null)
                              IconButton(
                                icon: const Icon(Icons.visibility_outlined, size: 18),
                                visualDensity: VisualDensity.compact,
                                tooltip: l10n.viewBookingAttachmentButton,
                                onPressed: () {
                                  DocumentTransferHelper.openOrDownloadDocument(
                                    context: context,
                                    cacheId: 'batt_${template.docId}_${draft.existingUploadedAt ?? 0}',
                                    url: draft.existingUrl!,
                                    fileName: draft.fileName,
                                    title: draft.title,
                                  );
                                },
                              ),
                            IconButton(
                              key: ValueKey('facility_doc_remove_${template.docId}'),
                              icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
                              visualDensity: VisualDensity.compact,
                              tooltip: l10n.removeAttachedFileTooltip,
                              onPressed: enabled ? () => onDraftRemoved(template.docId) : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
            if (hasReturnSlots) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.bookingAttachmentsRetentionHelper,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
