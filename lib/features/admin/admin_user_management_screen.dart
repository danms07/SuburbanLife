import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';

class AdminUserManagementScreen extends StatefulWidget {
  const AdminUserManagementScreen({super.key});

  @override
  _AdminUserManagementScreenState createState() => _AdminUserManagementScreenState();
}

class _AdminUserManagementScreenState extends State<AdminUserManagementScreen> {
  bool _isProcessing = false;

  void _promoteToAdmin(Map<String, dynamic> userDoc) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isProcessing = true;
    });

    try {
      await FunctionsService().callFunction('setRole', {
        'uid': userDoc['id'],
        'role': 'admin',
      });

      await DatabaseService().updateDocument('users', userDoc['id'], {'role': 'admin'});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.userPromotedSuccess), backgroundColor: AppConfig.secondaryColor),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _revokeAdmin(Map<String, dynamic> userDoc) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isProcessing = true;
    });

    try {
      // Revert back to resident role
      await FunctionsService().callFunction('setRole', {
        'uid': userDoc['id'],
        'role': 'resident',
      });

      await DatabaseService().updateDocument('users', userDoc['id'], {'role': 'resident'});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.userRevokedSuccess), backgroundColor: Colors.orange),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _changePassword(String targetUid) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.changePasswordTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Define a new secure password for this user.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: l10n.newPasswordLabel,
                border: const OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppConfig.primaryColor, foregroundColor: Colors.white),
            onPressed: () async {
              final pwd = controller.text.trim();
              if (pwd.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password must be at least 6 characters.')),
                );
                return;
              }
              Navigator.pop(context);
              setState(() { _isProcessing = true; });
              try {
                await FunctionsService().callFunction('adminUpdatePassword', {
                  'uid': targetUid,
                  'newPassword': pwd,
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.passwordUpdatedSuccess), backgroundColor: AppConfig.secondaryColor),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                );
              } finally {
                if (mounted) setState(() { _isProcessing = false; });
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(l10n.manageUsersMenu, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: DatabaseService().streamCollection('users'),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data ?? [];

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final name = doc['name'] ?? 'Unknown';
              final email = doc['email'] ?? '';
              final role = doc['role'] ?? 'resident';

              final isAdmin = role == 'admin';

              // Translate Role Tag
              String roleTag = role.toUpperCase();
              if (role == 'resident') roleTag = l10n.roleResident.toUpperCase();
              if (role == 'roommate') roleTag = l10n.roleRoommate.toUpperCase();
              if (role == 'admin') roleTag = l10n.roleAdmin.toUpperCase();
              if (role == 'guard') roleTag = l10n.roleGuard.toUpperCase();

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Header Row: Avatar, Name, and Role/Payment tags
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            backgroundColor: isAdmin ? AppConfig.secondaryColor : AppConfig.primaryColor,
                            child: Icon(
                              isAdmin ? Icons.admin_panel_settings : Icons.person,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: AppConfig.primaryColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        roleTag,
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    Builder(
                                      builder: (context) {
                                        final addressRef = doc['addressRef'] as DbReference?;
                                        if (addressRef == null) {
                                          return Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[200],
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'NO ADDRESS',
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                                            ),
                                          );
                                        }
                                        return FutureBuilder<Map<String, dynamic>?>(
                                          future: DatabaseService().getDocument('addresses', addressRef.id),
                                          builder: (context, addrSnap) {
                                            final addrData = addrSnap.data;
                                            final rawStatus = addrData?['paymentStatus'] as String?;
                                            final status = (rawStatus == null || rawStatus.trim().isEmpty) ? 'restricted' : rawStatus;
                                            return Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: status == 'paid' 
                                                    ? AppConfig.successColor.withOpacity(0.15) 
                                                    : AppConfig.warningColor.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                status.toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: status == 'paid' 
                                                      ? AppConfig.successColor 
                                                      : AppConfig.warningColor,
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 2. Sub-header Row: Email Address (No wrapping overflow)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.email, size: 16, color: Colors.grey),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                email,
                                style: const TextStyle(fontSize: 13, color: Colors.grey),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 24),
                      if (doc['addressRef'] != null) ...[
                        OutlinedButton.icon(
                          onPressed: _isProcessing ? null : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(l10n.resignAddressLabel),
                                content: Text(l10n.resignConfirmText),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('OK', style: TextStyle(color: Colors.redAccent)),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              setState(() {
                                _isProcessing = true;
                              });
                              try {
                                await FunctionsService().callFunction('unbindAddress', {
                                  'uid': doc['id'],
                                });
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Address unlinked successfully.'), backgroundColor: AppConfig.successColor),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _isProcessing = false;
                                  });
                                }
                              }
                            }
                          },
                          icon: const Icon(Icons.link_off, size: 18),
                          label: Text(l10n.resignAddressLabel),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            minimumSize: const Size(double.infinity, 36),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      // 3. Action Bar Row: Clean, fully responsive button alignment
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _changePassword(doc['id']),
                            icon: const Icon(Icons.lock_reset, size: 18),
                            label: const Text('Reset Pwd'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppConfig.primaryColor,
                              side: const BorderSide(color: AppConfig.primaryColor),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _isProcessing
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => isAdmin ? _revokeAdmin(doc) : _promoteToAdmin(doc),
                                    icon: Icon(isAdmin ? Icons.remove_circle_outline : Icons.add_moderator, size: 18),
                                    label: Text(
                                      isAdmin ? l10n.revokeAdminButton : l10n.promoteAdminButton,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isAdmin ? AppConfig.dangerColor : AppConfig.successColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
