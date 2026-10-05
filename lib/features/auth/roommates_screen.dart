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
    } catch (e, stack) {
      debugPrint('Error adding roommate: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'RoommatesScreen._addRoommate');
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _RoommateQrScannerSheet(
          onScan: (code) {
            _addRoommate(code);
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchRoommatesDetails(
    List<dynamic> uids,
  ) async {
    final Map<String, Map<String, dynamic>> detailsMap = {};

    for (dynamic uid in uids) {
      final uidStr = uid.toString().trim();
      if (uidStr.isEmpty) continue;
      try {
        final docData = await DatabaseService().getDocument('users', uidStr);
        if (docData != null) {
          docData['uid'] = docData['uid'] ?? uidStr;
          docData['id'] = docData['id'] ?? uidStr;
          detailsMap[uidStr] = docData;
        } else {
          detailsMap[uidStr] = {
            'uid': uidStr,
            'id': uidStr,
            'name': uidStr,
            'email': '',
          };
        }
      } catch (e) {
        debugPrint('Error fetching roommate details for $uidStr: $e');
        detailsMap[uidStr] = {
          'uid': uidStr,
          'id': uidStr,
          'name': uidStr,
          'email': '',
        };
      }
    }

    return detailsMap.values.toList();
  }

  Widget _buildInstructionStep({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppConfig.primaryColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: AppConfig.primaryColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 12.5,
                color: Colors.black87,
                height: 1.35,
                fontFamily: AppConfig.fontFamily,
              ),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: description),
              ],
            ),
          ),
        ),
      ],
    );
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
                      padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
                      child: Card(
                        elevation: 0,
                        color: AppConfig.primaryColor.withValues(alpha: 0.05),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppConfig.primaryColor.withValues(alpha: 0.2)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.info_outline, color: AppConfig.primaryColor, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      l10n.howToAddFamilyMemberTitle,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: AppConfig.primaryColor,
                                        fontFamily: AppConfig.fontFamily,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _buildInstructionStep(
                                icon: Icons.person_add_outlined,
                                title: l10n.familyOnboardingStep1Title,
                                description: l10n.familyOnboardingStep1Desc,
                              ),
                              const SizedBox(height: 8),
                              _buildInstructionStep(
                                icon: Icons.qr_code,
                                title: l10n.familyOnboardingStep2Title,
                                description: l10n.familyOnboardingStep2Desc,
                              ),
                              const SizedBox(height: 8),
                              _buildInstructionStep(
                                icon: Icons.qr_code_scanner,
                                title: l10n.familyOnboardingStep3Title,
                                description: l10n.familyOnboardingStep3Desc,
                              ),
                            ],
                          ),
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
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: _fetchRoommatesDetails(familyMembers),
                        builder: (context, detailsSnapshot) {
                          if (detailsSnapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final roommates = detailsSnapshot.data ?? [];
                          if (roommates.isEmpty) {
                            return Center(child: Text(l10n.noRoommates));
                          }
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
                                          (r['name'] != null && r['name'].toString().isNotEmpty)
                                              ? r['name']
                                              : (r['email'] ?? r['uid'] ?? 'Roommate'),
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        subtitle: Text(
                                          (r['email'] != null && r['email'].toString().isNotEmpty)
                                              ? r['email']
                                              : (r['uid'] ?? ''),
                                        ),
                                        trailing: IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                            color: Colors.redAccent,
                                          ),
                                          onPressed: _isLoading
                                              ? null
                                              : () async {
                                                  final targetUid = r['uid'] ?? r['id'];
                                                  if (targetUid == null) return;
                                                  setState(() {
                                                    _isLoading = true;
                                                  });
                                                  try {
                                                    await FunctionsService().callFunction(
                                                      'removeRoommate',
                                                      {'roommateUid': targetUid},
                                                    );
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(
                                                          content: Text(l10n.roommateRemovedSuccess),
                                                          backgroundColor: AppConfig.secondaryColor,
                                                        ),
                                                      );
                                                    }
                                                  } catch (e, stack) {
                                                    debugPrint('Error removing roommate: $e');
                                                    Backend.crashlytics.recordError(e, stack, reason: 'RoommatesScreen.removeRoommate');
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

class _RoommateQrScannerSheet extends StatefulWidget {
  final ValueChanged<String> onScan;

  const _RoommateQrScannerSheet({
    required this.onScan,
  });

  @override
  State<_RoommateQrScannerSheet> createState() => _RoommateQrScannerSheetState();
}

class _RoommateQrScannerSheetState extends State<_RoommateQrScannerSheet> {
  late final MobileScannerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
      returnImage: false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: ValueListenableBuilder<MobileScannerState>(
                      valueListenable: _controller,
                      builder: (context, state, child) {
                        return Icon(
                          state.cameraDirection == CameraFacing.front
                              ? Icons.camera_front
                              : Icons.camera_rear,
                          color: AppConfig.primaryColor,
                        );
                      },
                    ),
                    tooltip: l10n.switchCamera,
                    onPressed: () => _controller.switchCamera(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: (capture) {
                      final barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty) {
                        final code = (barcodes.first.rawValue ?? barcodes.first.displayValue)?.trim();
                        if (code != null && code.isNotEmpty) {
                          Navigator.pop(context);
                          widget.onScan(code);
                        }
                      }
                    },
                  ),
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: FloatingActionButton.small(
                      heroTag: 'roommate_switch_camera_fab',
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white,
                      tooltip: l10n.switchCamera,
                      onPressed: () => _controller.switchCamera(),
                      child: ValueListenableBuilder<MobileScannerState>(
                        valueListenable: _controller,
                        builder: (context, state, child) {
                          return Icon(
                            state.cameraDirection == CameraFacing.front
                                ? Icons.camera_front
                                : Icons.camera_rear,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
