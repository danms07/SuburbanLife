import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';

class AdminCreateUserScreen extends StatefulWidget {
  final String initialRole;

  const AdminCreateUserScreen({
    Key? key,
    this.initialRole = 'resident',
  }) : super(key: key);

  @override
  _AdminCreateUserScreenState createState() => _AdminCreateUserScreenState();
}

class _AdminCreateUserScreenState extends State<AdminCreateUserScreen> {
  final _formKey = GlobalKey<FormState>();

  late String _selectedRole;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isCreating = false;

  // Address selection for resident
  String? _selectedStreetName;
  Map<String, dynamic>? _selectedAddress;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.initialRole;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _generateRandomPassword() {
    const uppers = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const lowers = 'abcdefghijkmnpqrstuvwxyz';
    const digits = '23456789';
    const symbols = r'!@#$%&*+';
    final rand = Random.secure();
    final required = [
      uppers[rand.nextInt(uppers.length)],
      lowers[rand.nextInt(lowers.length)],
      digits[rand.nextInt(digits.length)],
      symbols[rand.nextInt(symbols.length)],
    ];
    final allChars = uppers + lowers + digits + symbols;
    final remaining = List.generate(8, (_) => allChars[rand.nextInt(allChars.length)]);
    final combined = required + remaining;
    combined.shuffle(rand);
    final generated = combined.join();
    setState(() {
      _passwordController.text = generated;
      _obscurePassword = false;
    });
  }

  void _createUser() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;

    if (_selectedRole == 'resident' && _selectedAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.addressMustBeSelected),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final payload = {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'password': _passwordController.text.trim(),
        'role': _selectedRole,
        if (_selectedRole == 'resident' && _selectedAddress != null) ...{
          'addressId': _selectedAddress!['id'],
          'streetName': _selectedAddress!['streetName'],
          'number': _selectedAddress!['number'],
        },
      };

      final result = await FunctionsService().callFunction('adminCreateUser', payload);
      final resMap = result is Map ? Map<String, dynamic>.from(result) : {};

      if (mounted) {
        final emailSent = resMap['emailSent'] == true;
        final successMsg = emailSent
            ? '${l10n.userCreatedSuccess} (${l10n.emailSentStatus})'
            : l10n.userCreatedSuccess;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMsg),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );

        setState(() {
          _nameController.clear();
          _emailController.clear();
          _passwordController.clear();
          _selectedStreetName = null;
          _selectedAddress = null;
        });
      }
    } catch (e) {
      debugPrint('Error creating user: $e');
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
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
          _isCreating = false;
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
        title: Text(l10n.createUserTitle, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // CARD 1: User Type Selector
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.manage_accounts, color: AppConfig.primaryColor, size: 24),
                          const SizedBox(width: 10),
                          Text(
                            l10n.userTypeLabel,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppConfig.primaryColor,
                              fontFamily: AppConfig.fontFamily,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: l10n.userTypeLabel,
                          prefixIcon: Icon(
                            _selectedRole == 'admin'
                                ? Icons.admin_panel_settings
                                : _selectedRole == 'guard'
                                    ? Icons.security
                                    : Icons.person,
                            color: AppConfig.primaryColor,
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                        initialValue: _selectedRole,
                        items: [
                          DropdownMenuItem<String>(
                            value: 'resident',
                            child: Row(
                              children: [
                                const Icon(Icons.home, size: 20, color: Colors.blue),
                                const SizedBox(width: 8),
                                Text(l10n.roleResident),
                              ],
                            ),
                          ),
                          DropdownMenuItem<String>(
                            value: 'guard',
                            child: Row(
                              children: [
                                const Icon(Icons.security, size: 20, color: Colors.blueGrey),
                                const SizedBox(width: 8),
                                Text(l10n.roleGuard),
                              ],
                            ),
                          ),
                          DropdownMenuItem<String>(
                            value: 'admin',
                            child: Row(
                              children: [
                                const Icon(Icons.admin_panel_settings, size: 20, color: Colors.orange),
                                const SizedBox(width: 8),
                                Text(l10n.roleAdmin),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedRole = val;
                              _selectedStreetName = null;
                              _selectedAddress = null;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // CARD 2: Personal & Authentication Details
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.badge_outlined, color: AppConfig.primaryColor, size: 24),
                          const SizedBox(width: 10),
                          Text(
                            l10n.userManagementMenu,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppConfig.primaryColor,
                              fontFamily: AppConfig.fontFamily,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Full Name
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: l10n.fullNameLabel,
                          hintText: l10n.fullNameHint,
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return l10n.fullNameHint;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Email Address
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: l10n.emailAddressLabel,
                          hintText: l10n.emailAddressHint,
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty || !value.contains('@')) {
                            return l10n.emailAddressHint;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Password with Generator and Toggle
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: l10n.passwordLabel,
                          hintText: l10n.passwordHint,
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.auto_fix_high, color: AppConfig.primaryColor),
                                tooltip: l10n.generatePasswordButton,
                                onPressed: _generateRandomPassword,
                              ),
                              IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ],
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().length < 8) {
                            return l10n.passwordComplexityRequirements;
                          }
                          final pass = value.trim();
                          if (!pass.contains(RegExp(r'[A-Z]')) ||
                              !pass.contains(RegExp(r'[a-z]')) ||
                              !pass.contains(RegExp(r'[0-9]'))) {
                            return l10n.passwordComplexityRequirements;
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // CARD 3: Dynamic Role Context & Address Form
              if (_selectedRole == 'resident') ...[
                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.home_work_outlined, color: AppConfig.primaryColor, size: 24),
                            const SizedBox(width: 10),
                            Text(
                              l10n.selectAddressLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppConfig.primaryColor,
                                fontFamily: AppConfig.fontFamily,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        StreamBuilder<List<Map<String, dynamic>>>(
                          stream: DatabaseService().streamCollection('addresses'),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: Padding(
                                padding: EdgeInsets.all(12.0),
                                child: CircularProgressIndicator(),
                              ));
                            }

                            final allAddresses = snapshot.data ?? [];
                            // Filter out "Admin office" addresses from residential list
                            final residentialAddresses = allAddresses.where((doc) {
                              final street = (doc['streetName'] ?? '').toString().toLowerCase();
                              return street != 'admin office' && street != 'oficina de administración';
                            }).toList();

                            final streetNames = residentialAddresses
                                .map((doc) => doc['streetName']?.toString() ?? '')
                                .where((street) => street.isNotEmpty)
                                .toSet()
                                .toList()
                              ..sort();

                            final filteredNumbers = _selectedStreetName != null
                                ? (residentialAddresses.where((doc) {
                                    return doc['streetName']?.toString() == _selectedStreetName;
                                  }).toList()
                                    ..sort((a, b) {
                                      final numA = a['number'] ?? 0;
                                      final numB = b['number'] ?? 0;
                                      if (numA is int && numB is int) return numA.compareTo(numB);
                                      return numA.toString().compareTo(numB.toString());
                                    }))
                                : <Map<String, dynamic>>[];

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Street Dropdown
                                DropdownButtonFormField<String>(
                                  decoration: InputDecoration(
                                    labelText: l10n.selectStreetLabel,
                                    prefixIcon: const Icon(Icons.map_outlined),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    isDense: true,
                                  ),
                                  initialValue: streetNames.contains(_selectedStreetName) ? _selectedStreetName : null,
                                  items: streetNames.map((street) {
                                    return DropdownMenuItem<String>(
                                      value: street,
                                      child: Text(street),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedStreetName = val;
                                      _selectedAddress = null;
                                    });
                                  },
                                ),
                                const SizedBox(height: 14),

                                // Number Dropdown
                                DropdownButtonFormField<String>(
                                  decoration: InputDecoration(
                                    labelText: l10n.selectNumberLabel,
                                    prefixIcon: const Icon(Icons.home_outlined),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    isDense: true,
                                  ),
                                  initialValue: (_selectedAddress != null && filteredNumbers.any((a) => a['id'] == _selectedAddress!['id']))
                                      ? _selectedAddress!['id'] as String?
                                      : null,
                                  items: filteredNumbers.map((doc) {
                                    final isClaimed = doc['residentUid'] != null && doc['residentUid'].toString().trim().isNotEmpty;
                                    final statusTag = isClaimed ? ' [Claimed]' : ' [Available]';
                                    return DropdownMenuItem<String>(
                                      value: doc['id'] as String,
                                      enabled: !isClaimed,
                                      child: Text(
                                        '#${doc['number']}$statusTag',
                                        style: TextStyle(
                                          color: isClaimed ? Colors.grey : Colors.black87,
                                          fontWeight: isClaimed ? FontWeight.normal : FontWeight.bold,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      final chosen = filteredNumbers.firstWhere((a) => a['id'] == val);
                                      setState(() {
                                        _selectedAddress = chosen;
                                      });
                                    }
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (_selectedRole == 'guard') ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blueGrey.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.security, color: Colors.blueGrey, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.guardInfoBanner,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blueGrey.shade900,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (_selectedRole == 'admin') ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.admin_panel_settings, color: Colors.orange, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.adminInfoBanner,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange.shade900,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Submit Button
              ElevatedButton(
                onPressed: _isCreating ? null : _createUser,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConfig.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 3,
                ),
                child: _isCreating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        l10n.createUserButton,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: AppConfig.fontFamily,
                        ),
                      ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
