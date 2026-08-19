import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';

class AdminFacilitiesScreen extends StatefulWidget {
  const AdminFacilitiesScreen({Key? key}) : super(key: key);

  @override
  _AdminFacilitiesScreenState createState() => _AdminFacilitiesScreenState();
}

class _AdminFacilitiesScreenState extends State<AdminFacilitiesScreen> {
  final _nameController = TextEditingController();
  final _cooldownValueController = TextEditingController(text: '1');
  bool _isUnique = true;
  int _quantity = 1;
  String _cooldownUnit = 'unrestricted';
  bool _isLoading = false;

  void _addFacility() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;
    final cooldownValue = int.tryParse(_cooldownValueController.text.trim()) ?? 1;

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
      });
      await DatabaseService().updateDocument('facilities', docId, {'id': docId});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.facilityAddedSuccess), backgroundColor: AppConfig.secondaryColor),
      );

      _nameController.clear();
      _cooldownValueController.text = '1';
      setState(() {
        _isUnique = true;
        _quantity = 1;
        _cooldownUnit = 'unrestricted';
      });
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
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
    } catch (e) {
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
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.addFacilityTitle,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppConfig.primaryColor),
                    ),
                    const SizedBox(height: 12),
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
                      title: Text(l10n.isUniqueAmenityLabel, style: const TextStyle(fontSize: 14)),
                      value: _isUnique,
                      activeColor: AppConfig.primaryColor,
                      onChanged: (val) {
                        setState(() {
                          _isUnique = val;
                        });
                      },
                    ),
                    if (!_isUnique) ...[
                      const SizedBox(height: 8),
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
                    const SizedBox(height: 12),

                    // Cooldown Unit Dropdown
                    DropdownButtonFormField<String>(
                      value: _cooldownUnit,
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
                      const SizedBox(height: 12),
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
                    const SizedBox(height: 16),
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
                    final qty = doc['quantity'] ?? 1;

                    String subtitleText = isUnique ? 'Unique Amenity' : 'Multi-item (Qty: $qty)';
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
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () => _deleteFacility(doc['id'] as String),
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
