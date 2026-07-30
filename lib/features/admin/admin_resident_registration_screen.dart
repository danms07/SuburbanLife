import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';

import 'admin_bulk_user_import_screen.dart';

class AdminResidentRegistrationScreen extends StatefulWidget {
  const AdminResidentRegistrationScreen({Key? key}) : super(key: key);

  @override
  _AdminResidentRegistrationScreenState createState() => _AdminResidentRegistrationScreenState();
}

class _AdminResidentRegistrationScreenState extends State<AdminResidentRegistrationScreen> {
  String _selectedRole = 'resident';
  Map<String, dynamic>? _selectedUser;
  Map<String, dynamic>? _selectedAddress;
  bool _isLoading = false;

  void _registerUser() async {
    if (_selectedUser == null || _selectedAddress == null) return;

    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isLoading = true;
    });

    try {
      final currentResidentUid = _selectedAddress!['residentUid'];
      final isAddressClaimed = currentResidentUid != null && currentResidentUid.toString().trim().isNotEmpty;
      final targetUid = _selectedUser!['id'] as String;
      final addressId = _selectedAddress!['id'] as String;

      if (_selectedRole == 'resident') {
        // Check for collision: Resident cannot be registered to an already claimed address
        if (isAddressClaimed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.addressAlreadyClaimedError), backgroundColor: Colors.redAccent),
          );
          setState(() { _isLoading = false; });
          return;
        }

        // Assign role via Cloud Function
        await FunctionsService().callFunction('setRole', {
          'uid': targetUid,
          'role': 'resident',
        });

        // Link address to resident and set paymentStatus to paid on address
        await DatabaseService().updateDocument('addresses', addressId, {
          'residentUid': targetUid,
          'paymentStatus': 'paid',
        });
        await DatabaseService().updateDocument('users', targetUid, {
          'addressRef': DatabaseService().createReference('addresses', addressId),
        });

      } else if (_selectedRole == 'roommate') {
        // Roommate gatekeeping: Address must ALREADY be linked to a primary resident
        if (!isAddressClaimed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.roommateRequiresResidentError), backgroundColor: Colors.redAccent),
          );
          setState(() { _isLoading = false; });
          return;
        }

        // Assign role via Cloud Function
        await FunctionsService().callFunction('setRole', {
          'uid': targetUid,
          'role': 'roommate',
        });

        // Link address (roommate inherits payment status from address)
        await DatabaseService().updateDocument('users', targetUid, {
          'addressRef': DatabaseService().createReference('addresses', addressId),
        });

        await DatabaseService().updateDocument('users', currentResidentUid, {
          'familyMembers': DbFieldValue.arrayUnion([targetUid]),
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.userRegisteredSuccess), backgroundColor: AppConfig.secondaryColor),
      );

      setState(() {
        _selectedUser = null;
        _selectedAddress = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(l10n.registerResidentTitle, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: l10n.bulkUserImportMenu,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminBulkUserImportScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.registerResidentMenu,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppConfig.primaryColor,
                    fontFamily: AppConfig.fontFamily,
                  ),
                ),
                const SizedBox(height: 20),

                // Role Selection Toggle
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text(l10n.roleResident),
                        value: 'resident',
                        groupValue: _selectedRole,
                        activeColor: AppConfig.primaryColor,
                        onChanged: (val) {
                          if (val != null) setState(() { _selectedRole = val; });
                        },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text(l10n.roleRoommate),
                        value: 'roommate',
                        groupValue: _selectedRole,
                        activeColor: AppConfig.primaryColor,
                        onChanged: (val) {
                          if (val != null) setState(() { _selectedRole = val; });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Target User Selection
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: DatabaseService().streamCollection('users', filters: [QueryFilter('addressRef', FilterOperator.isNull, true)]),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final users = snapshot.data ?? [];
                    return DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: l10n.selectResidentLabel,
                        prefixIcon: const Icon(Icons.person, color: AppConfig.primaryColor),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      value: (_selectedUser != null && users.any((u) => u['id'] == _selectedUser!['id'])) ? _selectedUser!['id'] as String? : null,
                      items: users.map((doc) {
                        return DropdownMenuItem<String>(
                          value: doc['id'] as String,
                          child: Text('${doc['name']} (${doc['email']})'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedUser = users.firstWhere((u) => u['id'] == val);
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 20),

                // Target Address Selection
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: DatabaseService().streamCollection('addresses'),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final addresses = snapshot.data ?? [];
                    
                    // Sort addresses logically by street and number
                    final sortedAddresses = List<Map<String, dynamic>>.from(addresses)..sort((a, b) {
                      final streetA = a['streetName']?.toString() ?? '';
                      final streetB = b['streetName']?.toString() ?? '';
                      final cmp = streetA.compareTo(streetB);
                      if (cmp != 0) return cmp;
                      final numA = a['number'] ?? 0;
                      final numB = b['number'] ?? 0;
                      if (numA is int && numB is int) return numA.compareTo(numB);
                      return numA.toString().compareTo(numB.toString());
                    });

                    return DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: l10n.selectAddressTitle,
                        prefixIcon: const Icon(Icons.home, color: AppConfig.primaryColor),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      value: (_selectedAddress != null && sortedAddresses.any((a) => a['id'] == _selectedAddress!['id'])) ? _selectedAddress!['id'] as String? : null,
                      items: sortedAddresses.map((doc) {
                        final isClaimed = doc['residentUid'] != null && doc['residentUid'].toString().trim().isNotEmpty;
                        final statusTag = isClaimed ? ' [Linked]' : ' [Available]';
                        return DropdownMenuItem<String>(
                          value: doc['id'] as String,
                          child: Text('${doc['streetName']} ${doc['number']}$statusTag'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedAddress = sortedAddresses.firstWhere((a) => a['id'] == val);
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 32),

                // Submit Button
                ElevatedButton(
                  onPressed: _isLoading || _selectedUser == null || _selectedAddress == null ? null : _registerUser,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          l10n.create,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
