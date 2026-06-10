import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';

class RoommatesScreen extends StatefulWidget {
  const RoommatesScreen({Key? key}) : super(key: key);

  @override
  _RoommatesScreenState createState() => _RoommatesScreenState();
}

class _RoommatesScreenState extends State<RoommatesScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  void _addRoommate() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await FunctionsService().callFunction('addRoommate', {'email': email});
      
      _emailController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Roommate added successfully.'), backgroundColor: AppConfig.secondaryColor),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRoommatesDetails(List<dynamic> uids) async {
    List<Map<String, dynamic>> details = [];
    for (String uid in uids) {
      final docData = await DatabaseService().getDocument('users', uid);
      if (docData != null) {
        details.add(docData);
      }
    }
    return details;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final user = AuthService().currentUser;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(l10n.familyGroupGrid, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: user == null
          ? const Center(child: Text('User not logged in'))
          : StreamBuilder<Map<String, dynamic>?>(
              stream: DatabaseService().streamDocument('users', user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final userData = snapshot.data;
                final familyMembers = userData?['familyMembers'] as List<dynamic>? ?? [];

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppConfig.primaryColor.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppConfig.primaryColor.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: AppConfig.primaryColor),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                l10n.roommateOnboardingInstructions,
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
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _emailController,
                              decoration: InputDecoration(
                                labelText: l10n.enterEmail,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: _isLoading ? null : _addRoommate,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConfig.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                            ),
                            child: _isLoading
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.person_add),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: familyMembers.isEmpty
                          ? Center(child: Text(l10n.noRoommates))
                          : FutureBuilder<List<Map<String, dynamic>>>(
                              future: _fetchRoommatesDetails(familyMembers),
                              builder: (context, detailsSnapshot) {
                                if (detailsSnapshot.connectionState == ConnectionState.waiting) {
                                  return const Center(child: CircularProgressIndicator());
                                }
                                final roommates = detailsSnapshot.data ?? [];
                                return ListView.builder(
                                  padding: const EdgeInsets.all(20),
                                  itemCount: roommates.length,
                                  itemBuilder: (context, index) {
                                    final r = roommates[index];
                                    return Card(
                                      margin: const EdgeInsets.symmetric(vertical: 8),
                                      child: ListTile(
                                        leading: const CircleAvatar(
                                          backgroundColor: AppConfig.primaryColor,
                                          child: Icon(Icons.person, color: Colors.white),
                                        ),
                                        title: Text(r['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                                        subtitle: Text(r['email'] ?? ''),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                                          onPressed: _isLoading
                                              ? null
                                              : () async {
                                                  setState(() {
                                                    _isLoading = true;
                                                  });
                                                  try {
                                                    await FunctionsService().callFunction('removeRoommate', {'roommateUid': r['uid']});
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(
                                                          content: Text(l10n.roommateRemovedSuccess),
                                                          backgroundColor: AppConfig.secondaryColor,
                                                        ),
                                                      );
                                                    }
                                                  } catch (e) {
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(
                                                          content: Text('Error: $e'),
                                                          backgroundColor: Colors.redAccent,
                                                        ),
                                                      );
                                                    }
                                                  } finally {
                                                    if (mounted) {
                                                      setState(() {
                                                        _isLoading = false;
                                                      });
                                                    }
                                                  }
                                                },
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
