import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import 'package:suburban_life/core/config/app_config.dart';
import 'package:suburban_life/features/auth/auth_service.dart';
import 'package:suburban_life/features/auth/ownership_proof_screen.dart';
import 'package:suburban_life/l10n/app_localizations.dart';

class SignupScreen extends StatefulWidget {
  final bool isAdditionalClaim;

  const SignupScreen({super.key, this.isAdditionalClaim = false});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  late int _step; // 1: Account Details, 2: Address Selection
  bool _isLoading = false;
  bool _obscurePassword = true;
  List<Map<String, dynamic>> _unclaimedAddresses = [];
  
  String? _selectedStreet;
  Map<String, dynamic>? _selectedAddress;

  @override
  void initState() {
    super.initState();
    _step = widget.isAdditionalClaim ? 2 : 1;
    if (_step == 2) {
      _loadUnclaimedAddresses();
    }
  }

  void _loadUnclaimedAddresses() async {
    setState(() {
      _isLoading = true;
    });
    final addresses = await _fetchUnclaimedAddresses();
    setState(() {
      _unclaimedAddresses = addresses;
      _isLoading = false;
    });
  }

  bool _isPasswordValid(String password) {
    if (password.length < 8) return false;
    if (!password.contains(RegExp(r'[A-Z]'))) return false;
    if (!password.contains(RegExp(r'[a-z]'))) return false;
    if (!password.contains(RegExp(r'[0-9]'))) return false;
    return true;
  }

  void _createAccount() async {
    final l10n = AppLocalizations.of(context)!;
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) return;

    if (!_isPasswordValid(password)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.passwordComplexityRequirements),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final user = await _authService.signUp(email, password, name: name);

    if (user != null) {
      final addresses = await _fetchUnclaimedAddresses();
      setState(() {
        _unclaimedAddresses = addresses;
        _step = 2;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.signUpSuccess)),
      );
    } else {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.signUpFailed)),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _fetchUnclaimedAddresses() async {
    try {
      // 1. Fetch all addresses that have a residentUid set
      final addressesList = await DatabaseService().getCollection('addresses');
      final List<Map<String, dynamic>> unclaimed = [];
      for (var data in addressesList) {
        final residentUid = data['residentUid'];
        // Address is unclaimed if residentUid is null or empty
        if (residentUid == null || residentUid.toString().trim().isEmpty) {
          unclaimed.add(data);
        }
      }
      return unclaimed;
    } catch (e) {
      debugPrint('Error fetching addresses: $e');
      return [];
    }
  }

  List<String> get _availableStreets {
    final Set<String> streets = {};
    for (var doc in _unclaimedAddresses) {
      final street = doc['streetName']?.toString();
      if (street != null && street.isNotEmpty) {
        streets.add(street);
      }
    }
    final list = streets.toList();
    list.sort();
    return list;
  }

  List<Map<String, dynamic>> get _availableNumbersForStreet {
    if (_selectedStreet == null) return [];
    final list = _unclaimedAddresses.where((doc) {
      return doc['streetName']?.toString() == _selectedStreet;
    }).toList();
    
    list.sort((a, b) {
      final numA = a['number'] ?? 0;
      final numB = b['number'] ?? 0;
      if (numA is int && numB is int) return numA.compareTo(numB);
      return numA.toString().compareTo(numB.toString());
    });
    return list;
  }

  void _confirmSelectedAddress() {
    if (_selectedAddress == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OwnershipProofScreen(
          addressRef: DatabaseService().createReference('addresses', _selectedAddress!['id']),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Column(
        children: [
          // Premium Header Matching Home Screen Look and Feel
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top + 16,
              left: 20,
              right: 20,
              bottom: 30,
            ),
            decoration: const BoxDecoration(
              color: AppConfig.primaryColor,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _step == 1 ? l10n.signUpTitle : l10n.selectAddressTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      fontFamily: AppConfig.fontFamily,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Form / Content Area
          Expanded(
            child: _step == 1 ? _buildAccountForm(l10n) : _buildAddressSelection(l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountForm(AppLocalizations l10n) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width > 900
                ? MediaQuery.of(context).size.width / 3
                : 450,
          ),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: l10n.fullName,
                    prefixIcon: const Icon(Icons.person, color: AppConfig.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: l10n.email,
                    prefixIcon: const Icon(Icons.email, color: AppConfig.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: l10n.password,
                    helperText: l10n.passwordComplexityHelper,
                    helperMaxLines: 2,
                    prefixIcon: const Icon(Icons.lock, color: AppConfig.primaryColor),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: AppConfig.primaryColor,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  obscureText: _obscurePassword,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _createAccount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          l10n.signUpButton,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _buildAddressSelection(AppLocalizations l10n) {
    final streets = _availableStreets;
    final numbers = _availableNumbersForStreet;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width > 900
                ? MediaQuery.of(context).size.width / 3
                : 450,
          ),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppConfig.primaryColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppConfig.primaryColor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppConfig.primaryColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.addressClaimInstructions,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                            height: 1.4,
                            fontFamily: AppConfig.fontFamily,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (streets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      l10n.noUnclaimedAddresses,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                else ...[
                  // Spinner 1: Street Name
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: l10n.selectStreetLabel,
                      prefixIcon: const Icon(Icons.signpost, color: AppConfig.primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    initialValue: _selectedStreet,
                    items: streets.map((street) {
                      return DropdownMenuItem<String>(
                        value: street,
                        child: Text(street),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedStreet = value;
                        _selectedAddress = null; // Reset number selection
                      });
                    },
                  ),
                  const SizedBox(height: 20),

                  // Spinner 2: Street Number
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: l10n.selectNumberLabel,
                      prefixIcon: const Icon(Icons.home, color: AppConfig.primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    initialValue: _selectedAddress?['id'] as String?,
                    items: numbers.map((doc) {
                      final numVal = doc['number'] ?? '';
                      return DropdownMenuItem<String>(
                        value: doc['id'] as String,
                        child: Text(numVal.toString()),
                      );
                    }).toList(),
                    onChanged: _selectedStreet == null
                        ? null
                        : (value) {
                            setState(() {
                                _selectedAddress = numbers.firstWhere((doc) => doc['id'] == value);
                            });
                          },
                  ),
                  const SizedBox(height: 32),

                  // Confirm Button Routes to Proof Screen
                  ElevatedButton(
                    onPressed: _selectedAddress == null ? null : _confirmSelectedAddress,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConfig.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      l10n.confirmAddressButton,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}
