import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';

class AdminGuardManagementScreen extends StatefulWidget {
  const AdminGuardManagementScreen({Key? key}) : super(key: key);

  @override
  _AdminGuardManagementScreenState createState() => _AdminGuardManagementScreenState();
}

class _AdminGuardManagementScreenState extends State<AdminGuardManagementScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _processingDeleteUid;

  void _provisionGuard() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a valid name, email, and password (min 6 chars).')),
      );
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isLoading = true;
    });

    try {
      await FunctionsService().callFunction('adminProvisionGuard', {
        'name': name,
        'email': email,
        'password': password,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.guardProvisionedSuccess), backgroundColor: AppConfig.secondaryColor),
      );

      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error provisioning guard: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _removeGuard(String uid) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _processingDeleteUid = uid;
    });

    try {
      await FunctionsService().callFunction('adminDeleteUser', {
        'uid': uid,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.guardRemovedSuccess), backgroundColor: Colors.orange),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error removing guard: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingDeleteUid = null;
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
        title: Text(l10n.provisionGuardTitle, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Provisioning Form
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
                      l10n.provisionGuardTitle,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppConfig.primaryColor),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: l10n.guardNameLabel,
                        prefixIcon: const Icon(Icons.security, color: AppConfig.primaryColor),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: l10n.guardEmailLabel,
                        prefixIcon: const Icon(Icons.email, color: AppConfig.primaryColor),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: l10n.guardPasswordLabel,
                        prefixIcon: const Icon(Icons.lock, color: AppConfig.primaryColor),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _provisionGuard,
                      style: ElevatedButton.styleFrom(backgroundColor: AppConfig.secondaryColor, foregroundColor: Colors.white),
                      child: _isLoading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(l10n.provisionButton),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Real-time Active Guards Stream List
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: DatabaseService().streamCollection('users', filters: [QueryFilter('role', FilterOperator.equal, 'guard')]),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No security guards provisioned yet.', style: TextStyle(color: Colors.grey)));
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final name = doc['name'] ?? 'Unknown Guard';
                    final email = doc['email'] ?? '';
                    final isDeleting = _processingDeleteUid == doc['id'];

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppConfig.primaryColor,
                          child: Icon(Icons.admin_panel_settings, color: Colors.white),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(email),
                        trailing: isDeleting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : IconButton(
                                icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                                tooltip: l10n.removeGuardButton,
                                onPressed: () => _removeGuard(doc['id'] as String),
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
