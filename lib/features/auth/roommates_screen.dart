import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';

class RoommatesScreen extends StatefulWidget {
  const RoommatesScreen({super.key});

  @override
  State<RoommatesScreen> createState() => _RoommatesScreenState();
}

class _RoommatesScreenState extends State<RoommatesScreen> {
  final TextEditingController _inputController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _addRoommate([String? rawInput]) async {
    final l10n = AppLocalizations.of(context)!;
    String input = (rawInput ?? _inputController.text).trim();
    if (input.isEmpty) return;

    // Clean prefix if string came from QR code
    if (input.startsWith('roommate_uid:')) {
      input = input.substring('roommate_uid:'.length).trim();
    } else if (input.startsWith('roommate:')) {
      input = input.substring('roommate:'.length).trim();
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final Map<String, dynamic> params = {};
      if (input.contains('@')) {
        params['email'] = input;
      } else {
        params['roommateUid'] = input;
      }

      await FunctionsService().callFunction('addRoommate', params);

      _inputController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.roommateAddedSuccess),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error adding roommate: $e');
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
          _isLoading = false;
        });
      }
    }
  }

  void _openQrScanner() {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.7,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.roommateQrScannerTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: AppConfig.fontFamily,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: MobileScanner(
                    controller: MobileScannerController(
                      detectionSpeed: DetectionSpeed.noDuplicates,
                    ),
                    onDetect: (capture) {
                      final barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty) {
                        final code = barcodes.first.rawValue ?? '';
                        if (code.isNotEmpty) {
                          Navigator.pop(ctx);
                          _addRoommate(code);
                        }
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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
          ? Center(child: Text(l10n.userNotLoggedIn))
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
                      child: Column(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isLoading ? null : _openQrScanner,
                            icon: const Icon(Icons.qr_code_scanner),
                            label: Text(l10n.scanRoommateQrButton),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConfig.primaryColor,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _inputController,
                                  decoration: InputDecoration(
                                    labelText: l10n.enterEmailOrUidLabel,
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.content_paste),
                                      tooltip: l10n.pasteFromClipboard,
                                      onPressed: () async {
                                        final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
                                        if (clipboardData?.text != null && clipboardData!.text!.isNotEmpty) {
                                          setState(() {
                                            _inputController.text = clipboardData.text!.trim();
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: _isLoading ? null : () => _addRoommate(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppConfig.primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.person_add),
                              ),
                            ],
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
                                        title: Text(
                                          r['name'] ?? 'Unknown',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        subtitle: Text(r['email'] ?? r['uid'] ?? ''),
                                        trailing: IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                            color: Colors.redAccent,
                                          ),
                                          onPressed: _isLoading
                                              ? null
                                              : () async {
                                                  setState(() {
                                                    _isLoading = true;
                                                  });
                                                  try {
                                                    await FunctionsService().callFunction(
                                                      'removeRoommate',
                                                      {'roommateUid': r['uid']},
                                                    );
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(
                                                          content: Text(l10n.roommateRemovedSuccess),
                                                          backgroundColor: AppConfig.secondaryColor,
                                                        ),
                                                      );
                                                    }
                                                  } catch (e) {
                                                    debugPrint('Error removing roommate: $e');
                                                    if (mounted) {
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
