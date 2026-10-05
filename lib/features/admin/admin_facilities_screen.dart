import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';

class AdminFacilitiesScreen extends StatefulWidget {
  const AdminFacilitiesScreen({super.key});

  @override
  State<AdminFacilitiesScreen> createState() => _AdminFacilitiesScreenState();
}

class _AdminFacilitiesScreenState extends State<AdminFacilitiesScreen> {
  final _nameController = TextEditingController();
  final _cooldownValueController = TextEditingController(text: '1');
  final _anticipationValueController = TextEditingController(text: '1');
  final _presetApprovalMessageController = TextEditingController();

  bool _isUnique = true;
  int _quantity = 1;
  String _cooldownUnit = 'unrestricted';
  String _anticipationUnit = 'unrestricted';
  TimeOfDay _openingTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _closingTime = const TimeOfDay(hour: 21, minute: 0);
  bool _isLoading = false;

  String _formatTimeOfDay(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay _parseTimeOfDay(String? s, {TimeOfDay fallback = const TimeOfDay(hour: 8, minute: 0)}) {
    if (s == null || !s.contains(':')) return fallback;
    final parts = s.split(':');
    final h = int.tryParse(parts[0]) ?? fallback.hour;
    final m = int.tryParse(parts[1]) ?? fallback.minute;
    return TimeOfDay(hour: h, minute: m);
  }

  void _addFacility() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;
    final cooldownValue = int.tryParse(_cooldownValueController.text.trim()) ?? 1;
    final anticipationValue = int.tryParse(_anticipationValueController.text.trim()) ?? 1;

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
        'cooldownUnit': _cooldownUnit,
        'cooldownValue': _cooldownUnit == 'unrestricted' ? 0 : cooldownValue,
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
      _anticipationValueController.text = '1';
      _presetApprovalMessageController.clear();
      setState(() {
        _isUnique = true;
        _quantity = 1;
        _cooldownUnit = 'unrestricted';
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

  void _editFacility(Map<String, dynamic> doc) async {
    final l10n = AppLocalizations.of(context)!;
    final facilityId = doc['id'] as String;
    final nameController = TextEditingController(text: doc['name']?.toString() ?? '');
    final initialCooldownValue = (doc['cooldownValue'] as num?)?.toInt() ?? 1;
    final cooldownValueController = TextEditingController(
      text: initialCooldownValue > 0 ? initialCooldownValue.toString() : '1',
    );
    final initialAnticipationValue = (doc['anticipationValue'] as num?)?.toInt() ?? 1;
    final anticipationValueController = TextEditingController(
      text: initialAnticipationValue > 0 ? initialAnticipationValue.toString() : '1',
    );
    final presetApprovalController = TextEditingController(
      text: doc['presetApprovalMessage']?.toString() ?? '',
    );

    bool isUnique = doc['isUnique'] == true;
    int quantity = (doc['quantity'] as num?)?.toInt() ?? 1;
    String cooldownUnit = doc['cooldownUnit']?.toString() ?? 'unrestricted';
    String anticipationUnit = doc['anticipationUnit']?.toString() ?? 'unrestricted';
    TimeOfDay editOpening = _parseTimeOfDay(doc['openingTime']?.toString(), fallback: const TimeOfDay(hour: 8, minute: 0));
    TimeOfDay editClosing = _parseTimeOfDay(doc['closingTime']?.toString(), fallback: const TimeOfDay(hour: 21, minute: 0));

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(l10n.editFacilityTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: l10n.facilityNameLabel,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: Text(l10n.isUniqueAmenityLabel),
                      value: isUnique,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setDialogState(() {
                          isUnique = val;
                          if (val) quantity = 1;
                        });
                      },
                    ),
                    if (!isUnique) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(l10n.quantityLabel),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: quantity > 1
                                ? () {
                                    setDialogState(() {
                                      quantity--;
                                    });
                                  }
                                : null,
                          ),
                          Text('$quantity', style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () {
                              setDialogState(() {
                                quantity++;
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
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
                            label: Text(editOpening.format(context)),
                            onPressed: () async {
                              final picked = await showTimePicker(context: context, initialTime: editOpening);
                              if (picked != null) {
                                setDialogState(() => editOpening = picked);
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
                            label: Text(editClosing.format(context)),
                            onPressed: () async {
                              final picked = await showTimePicker(context: context, initialTime: editClosing);
                              if (picked != null) {
                                setDialogState(() => editClosing = picked);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Cooldown Unit Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: cooldownUnit,
                      decoration: InputDecoration(
                        labelText: l10n.cooldownUnitLabel,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem(value: 'unrestricted', child: Text(l10n.cooldownUnrestricted)),
                        DropdownMenuItem(value: 'days', child: Text(l10n.cooldownDays)),
                        DropdownMenuItem(value: 'months', child: Text(l10n.cooldownMonths)),
                        DropdownMenuItem(value: 'years', child: Text(l10n.cooldownYears)),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            cooldownUnit = val;
                          });
                        }
                      },
                    ),
                    if (cooldownUnit != 'unrestricted') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: cooldownValueController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: l10n.cooldownValueLabel,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // Anticipation Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: anticipationUnit,
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
                          setDialogState(() {
                            anticipationUnit = val;
                          });
                        }
                      },
                    ),
                    if (anticipationUnit != 'unrestricted') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: anticipationValueController,
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
                      controller: presetApprovalController,
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(l10n.cancel),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final openM = editOpening.hour * 60 + editOpening.minute;
                    final closeM = editClosing.hour * 60 + editClosing.minute;
                    if (closeM <= openM) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.closingTimeBeforeOpeningTime), backgroundColor: Colors.redAccent),
                      );
                      return;
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  child: Text(l10n.save),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) return;

    final updatedName = nameController.text.trim();
    if (updatedName.isEmpty) return;

    final newCooldownVal = int.tryParse(cooldownValueController.text.trim()) ?? 1;
    final newAnticipationVal = int.tryParse(anticipationValueController.text.trim()) ?? 1;

    setState(() {
      _isLoading = true;
    });

    try {
      await DatabaseService().updateDocument('facilities', facilityId, {
        'name': updatedName,
        'isUnique': isUnique,
        'quantity': isUnique ? 1 : quantity,
        'cooldownUnit': cooldownUnit,
        'cooldownValue': cooldownUnit == 'unrestricted' ? 0 : newCooldownVal,
        'anticipationUnit': anticipationUnit,
        'anticipationValue': anticipationUnit == 'unrestricted' ? 0 : newAnticipationVal,
        'openingTime': _formatTimeOfDay(editOpening),
        'closingTime': _formatTimeOfDay(editClosing),
        'presetApprovalMessage': presetApprovalController.text.trim(),
      });

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
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
                  Padding(
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
                                onPressed: _quantity > 1 ? () => setState(() { _quantity--; }) : null,
                              ),
                              Text('$_quantity', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () => setState(() { _quantity++; }),
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

                        // Cooldown Unit Dropdown
                        DropdownButtonFormField<String>(
                          initialValue: _cooldownUnit,
                          decoration: InputDecoration(
                            labelText: l10n.cooldownUnitLabel,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            DropdownMenuItem(value: 'unrestricted', child: Text(l10n.cooldownUnrestricted)),
                            DropdownMenuItem(value: 'days', child: Text(l10n.cooldownDays)),
                            DropdownMenuItem(value: 'months', child: Text(l10n.cooldownMonths)),
                            DropdownMenuItem(value: 'years', child: Text(l10n.cooldownYears)),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _cooldownUnit = value;
                              });
                            }
                          },
                        ),
                        if (_cooldownUnit != 'unrestricted') ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: _cooldownValueController,
                            decoration: InputDecoration(
                              labelText: l10n.cooldownValueLabel,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ],
                        const SizedBox(height: 10),

                        // Anticipation Unit Dropdown
                        DropdownButtonFormField<String>(
                          initialValue: _anticipationUnit,
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
                          style: ElevatedButton.styleFrom(backgroundColor: AppConfig.secondaryColor, foregroundColor: Colors.white),
                          child: _isLoading
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text(l10n.create),
                        ),
                      ],
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
                    final name = doc['name'] ?? doc['id'];
                    final isUnique = doc['isUnique'] == true;
                    final cooldownUnit = doc['cooldownUnit'] ?? 'unrestricted';
                    final cooldownValue = doc['cooldownValue'] ?? 0;
                    final anticipationUnit = doc['anticipationUnit'] ?? 'unrestricted';
                    final anticipationValue = doc['anticipationValue'] ?? 0;
                    final openTime = doc['openingTime'] ?? '00:00';
                    final closeTime = doc['closingTime'] ?? '23:59';
                    final qty = doc['quantity'] ?? 1;

                    String subtitleText = isUnique ? 'Unique' : 'Multi-item (Qty: $qty)';
                    if (openTime != '00:00' || closeTime != '23:59') {
                      subtitleText += ' | Hours: $openTime - $closeTime';
                    } else {
                      subtitleText += ' | Hours: 24/7';
                    }

                    if (anticipationUnit != 'unrestricted') {
                      subtitleText += ' | Notice: $anticipationValue $anticipationUnit';
                    }

                    if (cooldownUnit != 'unrestricted') {
                      String unitLabel = cooldownUnit;
                      if (cooldownUnit == 'days') unitLabel = l10n.cooldownDays.toLowerCase();
                      if (cooldownUnit == 'months') unitLabel = l10n.cooldownMonths.toLowerCase();
                      if (cooldownUnit == 'years') unitLabel = l10n.cooldownYears.toLowerCase();
                      subtitleText += ' | Limit: 1 per $cooldownValue $unitLabel';
                    } else {
                      subtitleText += ' | Limit: Unrestricted';
                    }

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
