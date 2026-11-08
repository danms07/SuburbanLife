import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../booking/booking_service.dart';

class AdminFacilitiesScreen extends StatefulWidget {
  final bool isEmbedded;

  const AdminFacilitiesScreen({super.key, this.isEmbedded = false});

  @override
  State<AdminFacilitiesScreen> createState() => _AdminFacilitiesScreenState();
}

class _AdminFacilitiesScreenState extends State<AdminFacilitiesScreen> {
  final _nameController = TextEditingController();
  final _cooldownValueController = TextEditingController(text: '1');
  final _quotaLimitController = TextEditingController(text: '1');
  final _anticipationValueController = TextEditingController(text: '1');
  final _presetApprovalMessageController = TextEditingController();

  bool _isUnique = true;
  int _quantity = 1;
  String _restrictionType = 'unrestricted'; // 'unrestricted' | 'cooldown' | 'quota'
  String _cooldownUnit = 'days'; // 'hours' | 'days' | 'months' | 'years'
  String _quotaPeriod = 'monthly'; // 'daily' | 'monthly' | 'yearly'
  String _anticipationUnit = 'unrestricted';
  TimeOfDay _openingTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _closingTime = const TimeOfDay(hour: 21, minute: 0);
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _cooldownValueController.dispose();
    _quotaLimitController.dispose();
    _anticipationValueController.dispose();
    _presetApprovalMessageController.dispose();
    super.dispose();
  }

  static String _formatTimeOfDay(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay _parseTimeOfDay(
    String? s, {
    TimeOfDay fallback = const TimeOfDay(hour: 8, minute: 0),
  }) {
    if (s == null || !s.contains(':')) return fallback;
    final parts = s.split(':');
    final h = int.tryParse(parts[0]) ?? fallback.hour;
    final m = int.tryParse(parts[1]) ?? fallback.minute;
    return TimeOfDay(hour: h, minute: m);
  }

  static String _localizedCooldownUnit(AppLocalizations l10n, String unit) {
    switch (unit) {
      case 'hours':
        return l10n.cooldownHours.toLowerCase();
      case 'days':
        return l10n.cooldownDays.toLowerCase();
      case 'months':
        return l10n.cooldownMonths.toLowerCase();
      case 'years':
        return l10n.cooldownYears.toLowerCase();
      default:
        return unit;
    }
  }

  static String _localizedQuotaPeriod(AppLocalizations l10n, String period) {
    switch (period) {
      case 'daily':
        return l10n.quotaDaily.toLowerCase();
      case 'monthly':
        return l10n.quotaMonthly.toLowerCase();
      case 'yearly':
        return l10n.quotaYearly.toLowerCase();
      default:
        return period;
    }
  }

  static String _localizedAnticipationUnit(AppLocalizations l10n, String unit) {
    switch (unit) {
      case 'hours':
        return l10n.anticipationHours.toLowerCase();
      case 'days':
        return l10n.anticipationDays.toLowerCase();
      case 'weeks':
        return l10n.anticipationWeeks.toLowerCase();
      default:
        return unit;
    }
  }

  static int _parsePositiveInt(String raw, {int fallback = 1}) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed < 1) return fallback;
    return parsed;
  }

  void _addFacility() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;
    final cooldownValue = _parsePositiveInt(_cooldownValueController.text);
    final quotaLimit = _parsePositiveInt(_quotaLimitController.text);
    final anticipationValue = _parsePositiveInt(_anticipationValueController.text);

    final openMinutes = _openingTime.hour * 60 + _openingTime.minute;
    final closeMinutes = _closingTime.hour * 60 + _closingTime.minute;
    if (closeMinutes <= openMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.closingTimeBeforeOpeningTime), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final docId = await DatabaseService().addDocument('facilities', {
        'name': name,
        'isUnique': _isUnique,
        'quantity': _isUnique ? 1 : _quantity,
        'restrictionType': _restrictionType,
        'cooldownUnit': _restrictionType == 'cooldown' ? _cooldownUnit : 'unrestricted',
        'cooldownValue': _restrictionType == 'cooldown' ? cooldownValue : 0,
        'quotaPeriod': _restrictionType == 'quota' ? _quotaPeriod : 'unrestricted',
        'quotaLimit': _restrictionType == 'quota' ? quotaLimit : 0,
        'anticipationUnit': _anticipationUnit,
        'anticipationValue': _anticipationUnit == 'unrestricted' ? 0 : anticipationValue,
        'openingTime': _formatTimeOfDay(_openingTime),
        'closingTime': _formatTimeOfDay(_closingTime),
        'presetApprovalMessage': _presetApprovalMessageController.text.trim(),
      });
      await DatabaseService().updateDocument('facilities', docId, {'id': docId});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.facilityAddedSuccess), backgroundColor: AppConfig.secondaryColor),
        );
      }

      _nameController.clear();
      _cooldownValueController.text = '1';
      _quotaLimitController.text = '1';
      _anticipationValueController.text = '1';
      _presetApprovalMessageController.clear();
      setState(() {
        _isUnique = true;
        _quantity = 1;
        _restrictionType = 'unrestricted';
        _cooldownUnit = 'days';
        _quotaPeriod = 'monthly';
        _anticipationUnit = 'unrestricted';
        _openingTime = const TimeOfDay(hour: 8, minute: 0);
        _closingTime = const TimeOfDay(hour: 21, minute: 0);
      });
    } catch (e, stack) {
      debugPrint('Error creating facility: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminFacilitiesScreen._createFacility');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorPrefix(e.toString())), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  static Widget _buildRestrictionFields({
    required AppLocalizations l10n,
    required String restrictionType,
    required String cooldownUnit,
    required TextEditingController cooldownValueController,
    required String quotaPeriod,
    required TextEditingController quotaLimitController,
    required ValueChanged<String> onRestrictionTypeChanged,
    required ValueChanged<String> onCooldownUnitChanged,
    required ValueChanged<String> onQuotaPeriodChanged,
    required String keyPrefix,
  }) {
    final safeCooldownUnit =
        const ['hours', 'days', 'months', 'years'].contains(cooldownUnit) ? cooldownUnit : 'days';
    final safeQuotaPeriod =
        const ['daily', 'monthly', 'yearly'].contains(quotaPeriod) ? quotaPeriod : 'monthly';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('${keyPrefix}_restriction_type_$restrictionType'),
          initialValue: restrictionType,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.bookingRestrictionTypeLabel,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            DropdownMenuItem(value: 'unrestricted', child: Text(l10n.restrictionUnrestricted)),
            DropdownMenuItem(value: 'cooldown', child: Text(l10n.restrictionCooldown)),
            DropdownMenuItem(value: 'quota', child: Text(l10n.restrictionQuota)),
          ],
          onChanged: (val) {
            if (val != null) onRestrictionTypeChanged(val);
          },
        ),
        if (restrictionType == 'cooldown') ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey('${keyPrefix}_cooldown_value_field'),
                  controller: cooldownValueController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.cooldownValueLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('${keyPrefix}_cooldown_unit_$safeCooldownUnit'),
                  initialValue: safeCooldownUnit,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.cooldownUnitLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(value: 'hours', child: Text(l10n.cooldownHours)),
                    DropdownMenuItem(value: 'days', child: Text(l10n.cooldownDays)),
                    DropdownMenuItem(value: 'months', child: Text(l10n.cooldownMonths)),
                    DropdownMenuItem(value: 'years', child: Text(l10n.cooldownYears)),
                  ],
                  onChanged: (val) {
                    if (val != null) onCooldownUnitChanged(val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: cooldownValueController,
            builder: (context, value, _) {
              final parsed = _parsePositiveInt(value.text);
              return Text(
                l10n.cooldownRulePreview(parsed, _localizedCooldownUnit(l10n, safeCooldownUnit)),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              );
            },
          ),
        ],
        if (restrictionType == 'quota') ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('${keyPrefix}_quota_period_$safeQuotaPeriod'),
                  initialValue: safeQuotaPeriod,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.quotaPeriodLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(value: 'daily', child: Text(l10n.quotaDaily)),
                    DropdownMenuItem(value: 'monthly', child: Text(l10n.quotaMonthly)),
                    DropdownMenuItem(value: 'yearly', child: Text(l10n.quotaYearly)),
                  ],
                  onChanged: (val) {
                    if (val != null) onQuotaPeriodChanged(val);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: ValueKey('${keyPrefix}_quota_limit_field'),
                  controller: quotaLimitController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.quotaLimitLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: quotaLimitController,
            builder: (context, value, _) {
              final parsed = _parsePositiveInt(value.text);
              return Text(
                l10n.quotaRulePreview(parsed, _localizedQuotaPeriod(l10n, safeQuotaPeriod)),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  void _editFacility(Map<String, dynamic> doc) async {
    final l10n = AppLocalizations.of(context)!;
    final facilityId = doc['id'] as String;

    final updatedPayload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditFacilityDialog(doc: doc),
    );

    if (updatedPayload == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await DatabaseService().updateDocument('facilities', facilityId, updatedPayload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.facilityUpdatedSuccess), backgroundColor: AppConfig.secondaryColor),
        );
      }
    } catch (e, stack) {
      debugPrint('Error updating facility: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminFacilitiesScreen._editFacility');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorPrefix(e.toString())), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _deleteFacility(String id) async {
    try {
      await DatabaseService().deleteDocument('facilities', id);
    } catch (e, stack) {
      debugPrint('Error deleting facility: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminFacilitiesScreen._deleteFacility');
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorDeletingFacility(e.toString())), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  String _buildFacilitySubtitle(AppLocalizations l10n, Map<String, dynamic> doc) {
    final isUnique = doc['isUnique'] == true;
    final qty = (doc['quantity'] as num?)?.toInt() ?? 1;
    final openTime = (doc['openingTime'] ?? '00:00').toString();
    final closeTime = (doc['closingTime'] ?? '23:59').toString();
    final anticipationUnit = (doc['anticipationUnit'] ?? 'unrestricted').toString();
    final anticipationValue = (doc['anticipationValue'] as num?)?.toInt() ?? 0;
    final restriction = BookingService.resolveRestriction(doc);

    final parts = <String>[
      isUnique ? l10n.facilityCapacityUnique : l10n.facilityCapacityMulti(qty),
      l10n.facilitySubtitleHours(
        (openTime != '00:00' || closeTime != '23:59') ? '$openTime - $closeTime' : '24/7',
      ),
    ];

    if (anticipationUnit != 'unrestricted' && anticipationValue > 0) {
      parts.add(
        l10n.facilitySubtitleNotice(
          anticipationValue,
          _localizedAnticipationUnit(l10n, anticipationUnit),
        ),
      );
    }

    if (restriction.isCooldown) {
      parts.add(
        l10n.facilityLimitCooldown(
          restriction.cooldownValue,
          _localizedCooldownUnit(l10n, restriction.cooldownUnit),
        ),
      );
    } else if (restriction.isQuota) {
      parts.add(
        l10n.facilityLimitQuota(
          restriction.quotaLimit,
          _localizedQuotaPeriod(l10n, restriction.quotaPeriod),
        ),
      );
    } else {
      parts.add(l10n.facilityLimitUnrestricted);
    }

    return parts.join(' | ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: Text(l10n.manageFacilitiesMenu, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
              backgroundColor: AppConfig.primaryColor,
              foregroundColor: Colors.white,
            ),
      body: Column(
        children: [
          // Form to Add New Facility
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ExpansionTile(
                title: Text(
                  l10n.addFacilityTitle,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppConfig.primaryColor),
                ),
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: l10n.facilityNameLabel,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SwitchListTile(
                            title: Text(l10n.isUniqueAmenityLabel, style: const TextStyle(fontSize: 14)),
                            value: _isUnique,
                            activeThumbColor: AppConfig.primaryColor,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (val) {
                              setState(() {
                                _isUnique = val;
                              });
                            },
                          ),
                          if (!_isUnique) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(l10n.quantityLabel),
                                const SizedBox(width: 16),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: _quantity > 1
                                      ? () => setState(() {
                                            _quantity--;
                                          })
                                      : null,
                                ),
                                Text('$_quantity', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () => setState(() {
                                    _quantity++;
                                  }),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 10),

                          // Operating Hours
                          Text(
                            '${l10n.openingTimeLabel} & ${l10n.closingTimeLabel}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.access_time, size: 16),
                                  label: Text(_openingTime.format(context)),
                                  onPressed: () async {
                                    final picked = await showTimePicker(context: context, initialTime: _openingTime);
                                    if (picked != null) {
                                      setState(() => _openingTime = picked);
                                    }
                                  },
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Text('-'),
                              ),
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.access_time_filled, size: 16),
                                  label: Text(_closingTime.format(context)),
                                  onPressed: () async {
                                    final picked = await showTimePicker(context: context, initialTime: _closingTime);
                                    if (picked != null) {
                                      setState(() => _closingTime = picked);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Restriction Policy (Unrestricted | Cooldown | Quota)
                          _buildRestrictionFields(
                            l10n: l10n,
                            restrictionType: _restrictionType,
                            cooldownUnit: _cooldownUnit,
                            cooldownValueController: _cooldownValueController,
                            quotaPeriod: _quotaPeriod,
                            quotaLimitController: _quotaLimitController,
                            onRestrictionTypeChanged: (value) {
                              setState(() {
                                _restrictionType = value;
                              });
                            },
                            onCooldownUnitChanged: (value) {
                              setState(() {
                                _cooldownUnit = value;
                              });
                            },
                            onQuotaPeriodChanged: (value) {
                              setState(() {
                                _quotaPeriod = value;
                              });
                            },
                            keyPrefix: 'add',
                          ),
                          const SizedBox(height: 10),

                          // Anticipation Unit Dropdown
                          DropdownButtonFormField<String>(
                            key: ValueKey('add_anticipation_$_anticipationUnit'),
                            initialValue: _anticipationUnit,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: l10n.anticipationUnitLabel,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: [
                              DropdownMenuItem(value: 'unrestricted', child: Text(l10n.anticipationUnrestricted)),
                              DropdownMenuItem(value: 'hours', child: Text(l10n.anticipationHours)),
                              DropdownMenuItem(value: 'days', child: Text(l10n.anticipationDays)),
                              DropdownMenuItem(value: 'weeks', child: Text(l10n.anticipationWeeks)),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _anticipationUnit = value;
                                });
                              }
                            },
                          ),
                          if (_anticipationUnit != 'unrestricted') ...[
                            const SizedBox(height: 10),
                            TextField(
                              controller: _anticipationValueController,
                              decoration: InputDecoration(
                                labelText: l10n.anticipationValueLabel,
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ],
                          const SizedBox(height: 10),

                          TextField(
                            controller: _presetApprovalMessageController,
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: l10n.presetApprovalMessageLabel,
                              hintText: l10n.presetApprovalMessageHint,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 14),

                          ElevatedButton(
                            onPressed: _isLoading ? null : _addFacility,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConfig.secondaryColor,
                              foregroundColor: Colors.white,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : Text(l10n.create),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Existing Facilities List
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: DatabaseService().streamCollection('facilities'),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data ?? [];
                if (docs.isEmpty) {
                  return Center(child: Text(l10n.noAmenitiesRegistered, style: const TextStyle(color: Colors.grey)));
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final name = (doc['name'] ?? doc['id']).toString();
                    final subtitleText = _buildFacilitySubtitle(l10n, doc);

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: ListTile(
                        leading: const Icon(Icons.category, color: AppConfig.primaryColor),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(subtitleText),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: AppConfig.primaryColor),
                              onPressed: () => _editFacility(doc),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              onPressed: () => _deleteFacility(doc['id'] as String),
                            ),
                          ],
                        ),
                      ),
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

class _EditFacilityDialog extends StatefulWidget {
  final Map<String, dynamic> doc;

  const _EditFacilityDialog({required this.doc});

  @override
  State<_EditFacilityDialog> createState() => _EditFacilityDialogState();
}

class _EditFacilityDialogState extends State<_EditFacilityDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _cooldownValueController;
  late final TextEditingController _quotaLimitController;
  late final TextEditingController _anticipationValueController;
  late final TextEditingController _presetApprovalController;

  late bool _isUnique;
  late int _quantity;
  late String _restrictionType;
  late String _cooldownUnit;
  late String _quotaPeriod;
  late String _anticipationUnit;
  late TimeOfDay _editOpening;
  late TimeOfDay _editClosing;

  @override
  void initState() {
    super.initState();
    final doc = widget.doc;
    final resolved = BookingService.resolveRestriction(doc);

    _nameController = TextEditingController(text: doc['name']?.toString() ?? '');
    _cooldownValueController = TextEditingController(
      text: resolved.cooldownValue > 0 ? resolved.cooldownValue.toString() : '1',
    );
    _quotaLimitController = TextEditingController(
      text: resolved.quotaLimit > 0 ? resolved.quotaLimit.toString() : '1',
    );
    final initialAnticipationValue = (doc['anticipationValue'] as num?)?.toInt() ?? 1;
    _anticipationValueController = TextEditingController(
      text: initialAnticipationValue > 0 ? initialAnticipationValue.toString() : '1',
    );
    _presetApprovalController = TextEditingController(
      text: doc['presetApprovalMessage']?.toString() ?? '',
    );

    _isUnique = doc['isUnique'] == true;
    _quantity = (doc['quantity'] as num?)?.toInt() ?? 1;
    _restrictionType = resolved.restrictionType;
    _cooldownUnit = resolved.isCooldown ? resolved.cooldownUnit : 'days';
    _quotaPeriod = resolved.isQuota ? resolved.quotaPeriod : 'monthly';
    _anticipationUnit = doc['anticipationUnit']?.toString() ?? 'unrestricted';
    _editOpening = _AdminFacilitiesScreenState._parseTimeOfDay(
      doc['openingTime']?.toString(),
      fallback: const TimeOfDay(hour: 8, minute: 0),
    );
    _editClosing = _AdminFacilitiesScreenState._parseTimeOfDay(
      doc['closingTime']?.toString(),
      fallback: const TimeOfDay(hour: 21, minute: 0),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cooldownValueController.dispose();
    _quotaLimitController.dispose();
    _anticipationValueController.dispose();
    _presetApprovalController.dispose();
    super.dispose();
  }

  void _handleSave() {
    final l10n = AppLocalizations.of(context)!;
    final openM = _editOpening.hour * 60 + _editOpening.minute;
    final closeM = _editClosing.hour * 60 + _editClosing.minute;
    if (closeM <= openM) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.closingTimeBeforeOpeningTime),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final updatedName = _nameController.text.trim();
    if (updatedName.isEmpty) {
      Navigator.pop(context);
      return;
    }

    final newCooldownVal = _AdminFacilitiesScreenState._parsePositiveInt(_cooldownValueController.text);
    final newQuotaLimit = _AdminFacilitiesScreenState._parsePositiveInt(_quotaLimitController.text);
    final newAnticipationVal = _AdminFacilitiesScreenState._parsePositiveInt(_anticipationValueController.text);
    final updatedPresetMsg = _presetApprovalController.text.trim();

    Navigator.pop<Map<String, dynamic>>(context, {
      'name': updatedName,
      'isUnique': _isUnique,
      'quantity': _isUnique ? 1 : _quantity,
      'restrictionType': _restrictionType,
      'cooldownUnit': _restrictionType == 'cooldown' ? _cooldownUnit : 'unrestricted',
      'cooldownValue': _restrictionType == 'cooldown' ? newCooldownVal : 0,
      'quotaPeriod': _restrictionType == 'quota' ? _quotaPeriod : 'unrestricted',
      'quotaLimit': _restrictionType == 'quota' ? newQuotaLimit : 0,
      'anticipationUnit': _anticipationUnit,
      'anticipationValue': _anticipationUnit == 'unrestricted' ? 0 : newAnticipationVal,
      'openingTime': _AdminFacilitiesScreenState._formatTimeOfDay(_editOpening),
      'closingTime': _AdminFacilitiesScreenState._formatTimeOfDay(_editClosing),
      'presetApprovalMessage': updatedPresetMsg,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.editFacilityTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l10n.facilityNameLabel,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: Text(l10n.isUniqueAmenityLabel),
                value: _isUnique,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) {
                  setState(() {
                    _isUnique = val;
                    if (val) _quantity = 1;
                  });
                },
              ),
              if (!_isUnique) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(l10n.quantityLabel),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _quantity > 1
                          ? () {
                              setState(() {
                                _quantity--;
                              });
                            }
                          : null,
                    ),
                    Text('$_quantity', style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () {
                        setState(() {
                          _quantity++;
                        });
                      },
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Text(
                '${l10n.openingTimeLabel} & ${l10n.closingTimeLabel}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time, size: 16),
                      label: Text(_editOpening.format(context)),
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: _editOpening);
                        if (picked != null) {
                          setState(() => _editOpening = picked);
                        }
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('-'),
                  ),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time_filled, size: 16),
                      label: Text(_editClosing.format(context)),
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: _editClosing);
                        if (picked != null) {
                          setState(() => _editClosing = picked);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _AdminFacilitiesScreenState._buildRestrictionFields(
                l10n: l10n,
                restrictionType: _restrictionType,
                cooldownUnit: _cooldownUnit,
                cooldownValueController: _cooldownValueController,
                quotaPeriod: _quotaPeriod,
                quotaLimitController: _quotaLimitController,
                onRestrictionTypeChanged: (val) {
                  setState(() {
                    _restrictionType = val;
                  });
                },
                onCooldownUnitChanged: (val) {
                  setState(() {
                    _cooldownUnit = val;
                  });
                },
                onQuotaPeriodChanged: (val) {
                  setState(() {
                    _quotaPeriod = val;
                  });
                },
                keyPrefix: 'edit',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('edit_anticipation_$_anticipationUnit'),
                initialValue: _anticipationUnit,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.anticipationUnitLabel,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(value: 'unrestricted', child: Text(l10n.anticipationUnrestricted)),
                  DropdownMenuItem(value: 'hours', child: Text(l10n.anticipationHours)),
                  DropdownMenuItem(value: 'days', child: Text(l10n.anticipationDays)),
                  DropdownMenuItem(value: 'weeks', child: Text(l10n.anticipationWeeks)),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _anticipationUnit = val;
                    });
                  }
                },
              ),
              if (_anticipationUnit != 'unrestricted') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _anticipationValueController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.anticipationValueLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _presetApprovalController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: l10n.presetApprovalMessageLabel,
                  hintText: l10n.presetApprovalMessageHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppConfig.primaryColor,
            foregroundColor: Colors.white,
          ),
          onPressed: _handleSave,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

