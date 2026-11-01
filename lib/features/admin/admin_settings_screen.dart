import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';

class AdminSettingsScreen extends StatefulWidget {
  final bool isEmbedded;

  const AdminSettingsScreen({super.key, this.isEmbedded = false});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  // App & Payment Settings (auto-saved to config/app_settings)
  int _cutoffDay = 1;
  int _gracePeriodDays = 10;
  String _timeZone = 'America/Mexico_City';
  bool _scanOnExitEnabled = false;
  List<String> _paymentRejectionReasons = [];

  // SMTP Settings (switches auto-saved; server fields & email template manually saved)
  bool _smtpEnabled = false;
  bool _smtpSecure = false;
  bool _obscurePassword = true;
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '587',
  );
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _senderEmailController = TextEditingController();
  final TextEditingController _senderNameController = TextEditingController();
  final TextEditingController _testRecipientController =
      TextEditingController();
  final TextEditingController _customSubjectController =
      TextEditingController();
  final TextEditingController _customBodyController = TextEditingController();

  // Last persisted SMTP text values so real-time switch saves or independent card saves
  // never overwrite unsaved edits in the other manual section.
  String _savedHost = '';
  int _savedPort = 587;
  String _savedUser = '';
  String _savedPass = '';
  String _savedSenderEmail = '';
  String _savedSenderName = '';
  String _savedCustomSubject = '';
  String _savedCustomBody = '';

  final Set<String> _expandedCards = <String>{};

  bool _isLoading = true;
  int _activeAutoSaves = 0;
  bool _hasAutoSavedOnce = false;
  bool _isSavingSmtpConfig = false;
  bool _isSavingEmailTemplate = false;
  bool _isTestingSmtp = false;
  String? _testStatusMessage;
  bool _isTestSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _userController.dispose();
    _passController.dispose();
    _senderEmailController.dispose();
    _senderNameController.dispose();
    _testRecipientController.dispose();
    _customSubjectController.dispose();
    _customBodyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      // 1. Load general app settings
      final appData = await DatabaseService().getDocument(
        'config',
        'app_settings',
      );
      if (appData != null) {
        _cutoffDay = appData['paymentCutoffDay'] ?? 1;
        _gracePeriodDays = appData['gracePeriodDays'] ?? 10;
        _timeZone = appData['timeZone'] ?? 'America/Mexico_City';
        _scanOnExitEnabled = appData['scanOnExitEnabled'] == true;
        if (appData['paymentRejectionReasons'] is List) {
          _paymentRejectionReasons = List<String>.from(
            appData['paymentRejectionReasons'],
          );
        }
      }

      // 2. Load SMTP settings
      final smtpData = await DatabaseService().getDocument(
        'config',
        'smtp_settings',
      );
      if (smtpData != null) {
        _smtpEnabled = smtpData['enabled'] == true;
        _smtpSecure = smtpData['secure'] == true;
        _savedHost = (smtpData['host'] ?? '').toString();
        _savedPort = smtpData['port'] is int
            ? smtpData['port'] as int
            : (int.tryParse((smtpData['port'] ?? '587').toString()) ?? 587);
        _savedUser = (smtpData['user'] ?? '').toString();
        _savedPass = (smtpData['pass'] ?? '').toString();
        _savedSenderEmail = (smtpData['senderEmail'] ?? '').toString();
        _savedSenderName = (smtpData['senderName'] ?? '').toString();
        _savedCustomSubject = (smtpData['customSubject'] ?? '').toString();
        _savedCustomBody = (smtpData['customBody'] ?? '').toString();

        _hostController.text = _savedHost;
        _portController.text = _savedPort.toString();
        _userController.text = _savedUser;
        _passController.text = _savedPass;
        _senderEmailController.text = _savedSenderEmail;
        _senderNameController.text = _savedSenderName;
        _customSubjectController.text = _savedCustomSubject;
        _customBodyController.text = _savedCustomBody;
      }
    } catch (e, stack) {
      debugPrint('Error loading settings: $e');
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'AdminSettingsScreen._loadSettings',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _autoSaveAppSettings() async {
    if (mounted) {
      setState(() {
        _activeAutoSaves++;
      });
    }
    try {
      await DatabaseService().setDocument('config', 'app_settings', {
        'paymentCutoffDay': _cutoffDay,
        'gracePeriodDays': _gracePeriodDays,
        'timeZone': _timeZone,
        'scanOnExitEnabled': _scanOnExitEnabled,
        'paymentRejectionReasons': List<String>.from(_paymentRejectionReasons),
        'updatedAt': DbFieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() {
          _hasAutoSavedOnce = true;
        });
      }
    } catch (e, stack) {
      debugPrint('Error auto-saving app_settings: $e');
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'AdminSettingsScreen._autoSaveAppSettings',
      );
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
          _activeAutoSaves = (_activeAutoSaves - 1).clamp(0, 999);
        });
      }
    }
  }

  Future<void> _writeSmtpDocument() async {
    await DatabaseService().setDocument('config', 'smtp_settings', {
      'enabled': _smtpEnabled,
      'host': _savedHost,
      'port': _savedPort,
      'secure': _smtpSecure,
      'user': _savedUser,
      'pass': _savedPass,
      'senderEmail': _savedSenderEmail,
      'senderName': _savedSenderName,
      'customSubject': _savedCustomSubject,
      'customBody': _savedCustomBody,
      'updatedAt': DbFieldValue.serverTimestamp(),
    });
  }

  Future<void> _autoSaveSmtpSwitches() async {
    if (mounted) {
      setState(() {
        _activeAutoSaves++;
      });
    }
    try {
      await _writeSmtpDocument();
      if (mounted) {
        setState(() {
          _hasAutoSavedOnce = true;
        });
      }
    } catch (e, stack) {
      debugPrint('Error auto-saving smtp switch state: $e');
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'AdminSettingsScreen._autoSaveSmtpSwitches',
      );
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
          _activeAutoSaves = (_activeAutoSaves - 1).clamp(0, 999);
        });
      }
    }
  }

  Future<void> _saveSmtpServerConfig() async {
    final l10n = AppLocalizations.of(context)!;
    final host = _hostController.text.trim();
    final user = _userController.text.trim();
    final pass = _passController.text.trim();

    if (_smtpEnabled) {
      if (host.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.smtpHostRequired),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (user.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.smtpUserRequired),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (pass.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.smtpPassRequired),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    setState(() {
      _isSavingSmtpConfig = true;
    });

    try {
      final portVal =
          int.tryParse(_portController.text.trim()) ??
          (_smtpSecure ? 465 : 587);
      _savedHost = host;
      _savedPort = portVal;
      _savedUser = user;
      _savedPass = pass;
      _savedSenderEmail = _senderEmailController.text.trim();
      _savedSenderName = _senderNameController.text.trim();

      await _writeSmtpDocument();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.settingsSavedSuccess),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('Error saving SMTP server settings: $e');
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'AdminSettingsScreen._saveSmtpServerConfig',
      );
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
          _isSavingSmtpConfig = false;
        });
      }
    }
  }

  Future<void> _saveEmailTemplate() async {
    final l10n = AppLocalizations.of(context)!;

    setState(() {
      _isSavingEmailTemplate = true;
    });

    try {
      _savedCustomSubject = _customSubjectController.text.trim();
      _savedCustomBody = _customBodyController.text.trim();

      await _writeSmtpDocument();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.settingsSavedSuccess),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('Error saving custom email template: $e');
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'AdminSettingsScreen._saveEmailTemplate',
      );
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
          _isSavingEmailTemplate = false;
        });
      }
    }
  }

  void _insertPlaceholder(String placeholder) {
    final text = _customBodyController.text;
    final selection = _customBodyController.selection;
    if (selection.start >= 0) {
      final newText = text.replaceRange(
        selection.start,
        selection.end,
        placeholder,
      );
      _customBodyController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + placeholder.length,
        ),
      );
    } else {
      _customBodyController.text = '$text$placeholder';
    }
  }

  void _resetDefaultTemplate() {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _customSubjectController.text = l10n.defaultWelcomeSubject;
      _customBodyController.text = l10n.defaultWelcomeBody;
    });
  }

  Future<void> _addRejectionReason() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final added = await showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text(l10n.addRejectionReason),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: l10n.rejectionReasonSelect,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConfig.primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  Navigator.of(dialogCtx).pop(text);
                }
              },
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );

    if (added != null && added.isNotEmpty && mounted) {
      bool changed = false;
      setState(() {
        if (!_paymentRejectionReasons.contains(added)) {
          _paymentRejectionReasons.add(added);
          changed = true;
        }
      });
      if (changed) {
        await _autoSaveAppSettings();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.rejectionReasonAdded),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
      }
    }
  }

  Future<void> _removeRejectionReason(int index) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _paymentRejectionReasons.removeAt(index);
    });
    await _autoSaveAppSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.rejectionReasonDeleted),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _testSmtpConnection() async {
    final l10n = AppLocalizations.of(context)!;
    final host = _hostController.text.trim();
    final user = _userController.text.trim();
    final pass = _passController.text.trim();
    final recipient = _testRecipientController.text.trim();

    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.smtpHostRequired),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (user.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.smtpUserRequired),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.smtpPassRequired),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (recipient.isEmpty ||
        !recipient.contains('@') ||
        !recipient.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.smtpTestRecipientRequired),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isTestingSmtp = true;
      _testStatusMessage = null;
    });

    try {
      final portVal = int.tryParse(_portController.text.trim()) ?? 587;
      final result = await FunctionsService().callFunction(
        'adminTestSmtpConnection',
        {
          'host': host,
          'port': portVal,
          'secure': _smtpSecure,
          'user': user,
          'pass': pass,
          'senderEmail': _senderEmailController.text.trim(),
          'senderName': _senderNameController.text.trim(),
          'customSubject': _customSubjectController.text.trim(),
          'customBody': _customBodyController.text.trim(),
          'testRecipient': recipient,
        },
      );

      final resMap = result is Map ? Map<String, dynamic>.from(result) : {};
      final isOk = resMap['success'] == true;

      if (mounted) {
        setState(() {
          _isTestSuccess = isOk;
          _testStatusMessage = isOk
              ? l10n.testSmtpSuccess
              : (resMap['message'] ?? 'SMTP Error');
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_testStatusMessage!),
            backgroundColor: isOk
                ? AppConfig.secondaryColor
                : Colors.redAccent,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('SMTP connection test error: $e');
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'AdminSettingsScreen._testSmtpConnection',
      );
      if (mounted) {
        setState(() {
          _isTestSuccess = false;
          _testStatusMessage = l10n.testSmtpFailure(e.toString());
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_testStatusMessage!),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTestingSmtp = false;
        });
      }
    }
  }

  Widget _buildCollapsibleSettingsCard({
    required BuildContext context,
    required String cardId,
    required Key cardKey,
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    final isExpanded = _expandedCards.contains(cardId);

    return Card(
      elevation: 2.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: cardKey,
          initiallyExpanded: isExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          leading: Icon(icon, color: AppConfig.primaryColor, size: 26),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppConfig.primaryColor,
              fontFamily: AppConfig.fontFamily,
            ),
          ),
          subtitle: subtitle != null
              ? Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade600,
                    fontFamily: AppConfig.fontFamily,
                  ),
                )
              : null,
          iconColor: AppConfig.primaryColor,
          collapsedIconColor: Colors.grey[700],
          onExpansionChanged: (expanded) {
            setState(() {
              if (expanded) {
                _expandedCards.add(cardId);
              } else {
                _expandedCards.remove(cardId);
              }
            });
          },
          children: [
            const Divider(height: 1),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bool isAutoSaving = _activeAutoSaves > 0;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: Text(
                l10n.adminSettingsMenu,
                style: const TextStyle(fontFamily: AppConfig.fontFamily),
              ),
              backgroundColor: AppConfig.primaryColor,
              foregroundColor: Colors.white,
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Auto-save Status Banner
                      Container(
                        key: const ValueKey('settings_autosave_banner'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppConfig.primaryColor.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppConfig.primaryColor.withValues(
                              alpha: 0.18,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isAutoSaving
                                  ? Icons.sync
                                  : Icons.cloud_done_outlined,
                              size: 18,
                              color: AppConfig.primaryColor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                l10n.settingsAutoSaveHint,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppConfig.textColor,
                                  fontFamily: AppConfig.fontFamily,
                                ),
                              ),
                            ),
                            if (isAutoSaving || _hasAutoSavedOnce) ...[
                              const SizedBox(width: 8),
                              Container(
                                key: const ValueKey('settings_autosave_status'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isAutoSaving
                                      ? AppConfig.primaryColor.withValues(
                                          alpha: 0.12,
                                        )
                                      : AppConfig.secondaryColor.withValues(
                                          alpha: 0.16,
                                        ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isAutoSaving)
                                      const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppConfig.primaryColor,
                                        ),
                                      )
                                    else
                                      const Icon(
                                        Icons.check_circle,
                                        size: 14,
                                        color: AppConfig.secondaryColor,
                                      ),
                                    const SizedBox(width: 5),
                                    Text(
                                      isAutoSaving
                                          ? l10n.settingsAutoSavingLabel
                                          : l10n.settingsAutoSavedLabel,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isAutoSaving
                                            ? AppConfig.primaryColor
                                            : Colors.green.shade800,
                                        fontFamily: AppConfig.fontFamily,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // CARD 1: Payment & Grace Period (Auto-saved)
                      _buildCollapsibleSettingsCard(
                        context: context,
                        cardId: 'payment',
                        cardKey: const ValueKey('settings_card_payment'),
                        icon: Icons.payments_outlined,
                        title: l10n.paymentSettingsSection,
                        subtitle:
                            '${l10n.paymentCutoffDayLabel}: $_cutoffDay · ${l10n.gracePeriodDaysLabel}: $_gracePeriodDays · $_timeZone',
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${l10n.paymentCutoffDayLabel}: $_cutoffDay',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Slider(
                            key: const ValueKey('cutoff_day_slider'),
                            value: _cutoffDay.toDouble(),
                            min: 1,
                            max: 28,
                            divisions: 27,
                            label: '$_cutoffDay',
                            activeColor: AppConfig.primaryColor,
                            onChanged: (val) {
                              setState(() {
                                _cutoffDay = val.toInt();
                              });
                            },
                            onChangeEnd: (_) => _autoSaveAppSettings(),
                          ),
                          const SizedBox(height: 16),

                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${l10n.gracePeriodDaysLabel}: $_gracePeriodDays',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Slider(
                            key: const ValueKey('grace_period_slider'),
                            value: _gracePeriodDays.toDouble(),
                            min: 0,
                            max: 30,
                            divisions: 30,
                            label: '$_gracePeriodDays',
                            activeColor: AppConfig.primaryColor,
                            onChanged: (val) {
                              setState(() {
                                _gracePeriodDays = val.toInt();
                              });
                            },
                            onChangeEnd: (_) => _autoSaveAppSettings(),
                          ),
                          const SizedBox(height: 16),

                          DropdownButtonFormField<String>(
                            key: const ValueKey('timezone_dropdown'),
                            isExpanded: true,
                            initialValue: _timeZone,
                            decoration: InputDecoration(
                              labelText: l10n.timezoneLabel,
                              helperText: l10n.timezoneHelperText,
                              prefixIcon: const Icon(
                                Icons.schedule,
                                color: AppConfig.primaryColor,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              isDense: true,
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 'America/Mexico_City',
                                child: Text(
                                  l10n.timezoneCstLabel,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'America/Cancun',
                                child: Text(
                                  l10n.timezoneEstLabel,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'America/Tijuana',
                                child: Text(
                                  l10n.timezonePstLabel,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'America/Hermosillo',
                                child: Text(
                                  l10n.timezoneMstLabel,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'UTC',
                                child: Text(
                                  l10n.timezoneUtcLabel,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null && val != _timeZone) {
                                setState(() {
                                  _timeZone = val;
                                });
                                _autoSaveAppSettings();
                              }
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // CARD 2: Access Control & QR Exit Scanning (Auto-saved in real time)
                      _buildCollapsibleSettingsCard(
                        context: context,
                        cardId: 'access_control',
                        cardKey: const ValueKey('settings_card_access_control'),
                        icon: Icons.qr_code_scanner,
                        title: l10n.accessControlSettingsSection,
                        subtitle: l10n.scanOnExitTitle,
                        children: [
                          SwitchListTile(
                            key: const ValueKey('scan_on_exit_switch'),
                            contentPadding: EdgeInsets.zero,
                            activeTrackColor: AppConfig.primaryColor,
                            title: Text(
                              l10n.scanOnExitTitle,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              l10n.scanOnExitSubtitle,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            value: _scanOnExitEnabled,
                            onChanged: (val) {
                              setState(() {
                                _scanOnExitEnabled = val;
                              });
                              _autoSaveAppSettings();
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // CARD 3: Payment Rejection Reasons (Auto-saved)
                      _buildCollapsibleSettingsCard(
                        context: context,
                        cardId: 'rejection_reasons',
                        cardKey: const ValueKey(
                          'settings_card_rejection_reasons',
                        ),
                        icon: Icons.rule_folder_outlined,
                        title: l10n.manageRejectionReasons,
                        subtitle: l10n.rejectionReasonSelect,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.rejectionReasonSelect,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              IconButton(
                                key: const ValueKey(
                                  'add_rejection_reason_button',
                                ),
                                icon: const Icon(
                                  Icons.add_circle,
                                  color: AppConfig.primaryColor,
                                ),
                                tooltip: l10n.addRejectionReason,
                                onPressed: _addRejectionReason,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_paymentRejectionReasons.isEmpty)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8.0,
                                ),
                                child: Text(
                                  l10n.noCustomRejectionReasonsHint,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _paymentRejectionReasons.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final reason = _paymentRejectionReasons[index];
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.label_outline,
                                    size: 20,
                                    color: AppConfig.primaryColor,
                                  ),
                                  title: Text(
                                    reason,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        _removeRejectionReason(index),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // CARD 4: SMTP Email Service (Switches auto-save in real time; server config requires manual save)
                      _buildCollapsibleSettingsCard(
                        context: context,
                        cardId: 'smtp',
                        cardKey: const ValueKey('settings_card_smtp'),
                        icon: Icons.mark_email_read_outlined,
                        title: l10n.smtpSettingsSection,
                        subtitle: _savedHost.isNotEmpty
                            ? '$_savedHost:$_savedPort'
                            : l10n.smtpEnabledSubtitle,
                        children: [
                          SwitchListTile(
                            key: const ValueKey('smtp_enabled_switch'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              l10n.smtpEnabledLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              l10n.smtpEnabledSubtitle,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            value: _smtpEnabled,
                            activeThumbColor: AppConfig.secondaryColor,
                            onChanged: (val) {
                              setState(() {
                                _smtpEnabled = val;
                              });
                              _autoSaveSmtpSwitches();
                            },
                          ),

                          const Divider(height: 24),

                          // SMTP Host
                          TextFormField(
                            key: const ValueKey('smtp_host_field'),
                            controller: _hostController,
                            decoration: InputDecoration(
                              labelText: l10n.smtpHostLabel,
                              hintText: l10n.smtpHostHint,
                              prefixIcon: const Icon(Icons.dns_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Port & Presets
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 110,
                                child: TextFormField(
                                  key: const ValueKey('smtp_port_field'),
                                  controller: _portController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: l10n.smtpPortLabel,
                                    hintText: l10n.smtpPortHint,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Wrap(
                                  spacing: 6,
                                  children: [
                                    ActionChip(
                                      label: const Text('587 (TLS)'),
                                      onPressed: () {
                                        setState(() {
                                          _portController.text = '587';
                                          _smtpSecure = false;
                                        });
                                      },
                                    ),
                                    ActionChip(
                                      label: const Text('465 (SSL)'),
                                      onPressed: () {
                                        setState(() {
                                          _portController.text = '465';
                                          _smtpSecure = true;
                                        });
                                      },
                                    ),
                                    ActionChip(
                                      label: const Text('25'),
                                      onPressed: () {
                                        setState(() {
                                          _portController.text = '25';
                                          _smtpSecure = false;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Secure (SSL/TLS) Switch (Auto-saved in real time)
                          SwitchListTile(
                            key: const ValueKey('smtp_secure_switch'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              l10n.smtpSecureLabel,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              l10n.smtpSecureSubtitle,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            value: _smtpSecure,
                            activeThumbColor: AppConfig.primaryColor,
                            onChanged: (val) {
                              setState(() {
                                _smtpSecure = val;
                              });
                              _autoSaveSmtpSwitches();
                            },
                          ),
                          const SizedBox(height: 10),

                          // Username / Auth Email
                          TextFormField(
                            key: const ValueKey('smtp_user_field'),
                            controller: _userController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: l10n.smtpUserLabel,
                              hintText: l10n.smtpUserHint,
                              prefixIcon: const Icon(Icons.person_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Password / API Key
                          TextFormField(
                            key: const ValueKey('smtp_pass_field'),
                            controller: _passController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: l10n.smtpPassLabel,
                              hintText: l10n.smtpPassHint,
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Sender Email & Name
                          TextFormField(
                            key: const ValueKey('smtp_sender_email_field'),
                            controller: _senderEmailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: l10n.smtpSenderEmailLabel,
                              hintText: l10n.smtpSenderEmailHint,
                              prefixIcon: const Icon(Icons.alternate_email),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 14),

                          TextFormField(
                            key: const ValueKey('smtp_sender_name_field'),
                            controller: _senderNameController,
                            decoration: InputDecoration(
                              labelText: l10n.smtpSenderNameLabel,
                              hintText: l10n.smtpSenderNameHint,
                              prefixIcon: const Icon(Icons.badge_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              isDense: true,
                            ),
                          ),

                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 12),

                          // Interactive Test Connection Section
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              l10n.testSmtpButton,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppConfig.primaryColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          LayoutBuilder(
                            builder: (context, smtpConstraints) {
                              final recipientField = TextFormField(
                                controller: _testRecipientController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  labelText: l10n.testRecipientLabel,
                                  hintText: l10n.testRecipientHint,
                                  prefixIcon: const Icon(Icons.send_outlined),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  isDense: true,
                                ),
                              );
                              final testButton = ElevatedButton.icon(
                                onPressed: _isTestingSmtp
                                    ? null
                                    : _testSmtpConnection,
                                icon: _isTestingSmtp
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.network_check),
                                label: Text(l10n.testSmtpButton),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppConfig.primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                    horizontal: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              );

                              if (smtpConstraints.maxWidth >= 560) {
                                return Row(
                                  children: [
                                    Expanded(child: recipientField),
                                    const SizedBox(width: 10),
                                    testButton,
                                  ],
                                );
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  recipientField,
                                  const SizedBox(height: 10),
                                  testButton,
                                ],
                              );
                            },
                          ),

                          if (_testStatusMessage != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _isTestSuccess
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _isTestSuccess
                                      ? Colors.green
                                      : Colors.redAccent,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _isTestSuccess
                                        ? Icons.check_circle
                                        : Icons.error_outline,
                                    color: _isTestSuccess
                                        ? Colors.green
                                        : Colors.redAccent,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _testStatusMessage!,
                                      style: TextStyle(
                                        color: _isTestSuccess
                                            ? Colors.green.shade800
                                            : Colors.red.shade800,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              key: const ValueKey('save_smtp_config_button'),
                              onPressed: _isSavingSmtpConfig
                                  ? null
                                  : _saveSmtpServerConfig,
                              icon: _isSavingSmtpConfig
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(
                                l10n.saveSmtpConfigButton,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: AppConfig.fontFamily,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppConfig.secondaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // CARD 5: Custom Welcome Email Template (Manual save)
                      _buildCollapsibleSettingsCard(
                        context: context,
                        cardId: 'email_template',
                        cardKey: const ValueKey('settings_card_email_template'),
                        icon: Icons.edit_note,
                        title: l10n.customWelcomeEmailSection,
                        subtitle: l10n.customWelcomeEmailSubtitle,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.customWelcomeEmailSubtitle,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _resetDefaultTemplate,
                                icon: const Icon(Icons.restore, size: 16),
                                label: Text(
                                  l10n.resetDefaultTemplateButton,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Subject field
                          TextFormField(
                            key: const ValueKey('email_template_subject_field'),
                            controller: _customSubjectController,
                            decoration: InputDecoration(
                              labelText: l10n.emailSubjectLabel,
                              hintText: l10n.emailSubjectHint,
                              prefixIcon: const Icon(Icons.title),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Available Placeholders
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              l10n.availablePlaceholdersLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ActionChip(
                                  avatar: const Icon(Icons.person, size: 14),
                                  label: const Text(
                                    '%name%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () => _insertPlaceholder('%name%'),
                                ),
                                ActionChip(
                                  avatar: const Icon(Icons.email, size: 14),
                                  label: const Text(
                                    '%email%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () =>
                                      _insertPlaceholder('%email%'),
                                ),
                                ActionChip(
                                  avatar: const Icon(Icons.lock, size: 14),
                                  label: const Text(
                                    '%password%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  backgroundColor: Colors.amber.withValues(
                                    alpha: 0.2,
                                  ),
                                  onPressed: () =>
                                      _insertPlaceholder('%password%'),
                                ),
                                ActionChip(
                                  avatar: const Icon(Icons.home, size: 14),
                                  label: const Text(
                                    '%address%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () =>
                                      _insertPlaceholder('%address%'),
                                ),
                                ActionChip(
                                  avatar: const Icon(Icons.badge, size: 14),
                                  label: const Text(
                                    '%role%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () => _insertPlaceholder('%role%'),
                                ),
                                ActionChip(
                                  avatar: const Icon(Icons.apps, size: 14),
                                  label: const Text(
                                    '%appName%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () =>
                                      _insertPlaceholder('%appName%'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Body field
                          TextFormField(
                            key: const ValueKey('email_template_body_field'),
                            controller: _customBodyController,
                            maxLines: 7,
                            keyboardType: TextInputType.multiline,
                            decoration: InputDecoration(
                              labelText: l10n.emailBodyLabel,
                              hintText: l10n.emailBodyHint,
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              key: const ValueKey('save_email_template_button'),
                              onPressed: _isSavingEmailTemplate
                                  ? null
                                  : _saveEmailTemplate,
                              icon: _isSavingEmailTemplate
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(
                                l10n.saveEmailTemplateButton,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: AppConfig.fontFamily,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppConfig.secondaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
