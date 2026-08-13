import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({Key? key}) : super(key: key);

  @override
  _AdminSettingsScreenState createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  // App & Payment Settings
  int _cutoffDay = 1;
  int _gracePeriodDays = 10;

  // SMTP Settings
  bool _smtpEnabled = false;
  bool _smtpSecure = false;
  bool _obscurePassword = true;
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: '587');
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _senderEmailController = TextEditingController();
  final TextEditingController _senderNameController = TextEditingController();
  final TextEditingController _testRecipientController = TextEditingController();
  final TextEditingController _customSubjectController = TextEditingController();
  final TextEditingController _customBodyController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
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

  void _loadSettings() async {
    try {
      // 1. Load general app settings
      final appData = await DatabaseService().getDocument('config', 'app_settings');
      if (appData != null) {
        _cutoffDay = appData['paymentCutoffDay'] ?? 1;
        _gracePeriodDays = appData['gracePeriodDays'] ?? 10;
      }

      // 2. Load SMTP settings
      final smtpData = await DatabaseService().getDocument('config', 'smtp_settings');
      if (smtpData != null) {
        _smtpEnabled = smtpData['enabled'] == true;
        _smtpSecure = smtpData['secure'] == true;
        _hostController.text = smtpData['host'] ?? '';
        _portController.text = (smtpData['port'] ?? 587).toString();
        _userController.text = smtpData['user'] ?? '';
        _passController.text = smtpData['pass'] ?? '';
        _senderEmailController.text = smtpData['senderEmail'] ?? '';
        _senderNameController.text = smtpData['senderName'] ?? '';
        _customSubjectController.text = smtpData['customSubject'] ?? '';
        _customBodyController.text = smtpData['customBody'] ?? '';
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _insertPlaceholder(String placeholder) {
    final text = _customBodyController.text;
    final selection = _customBodyController.selection;
    if (selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, placeholder);
      _customBodyController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + placeholder.length),
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

  void _testSmtpConnection() async {
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
    if (recipient.isEmpty || !recipient.contains('@') || !recipient.contains('.')) {
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
      final result = await FunctionsService().callFunction('adminTestSmtpConnection', {
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
      });

      final resMap = result is Map ? Map<String, dynamic>.from(result) : {};
      final isOk = resMap['success'] == true;

      if (mounted) {
        setState(() {
          _isTestSuccess = isOk;
          _testStatusMessage = isOk ? l10n.testSmtpSuccess : (resMap['message'] ?? 'SMTP Error');
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_testStatusMessage!),
            backgroundColor: isOk ? AppConfig.secondaryColor : Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('SMTP connection test error: $e');
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

  void _saveSettings() async {
    final l10n = AppLocalizations.of(context)!;
    final host = _hostController.text.trim();
    final user = _userController.text.trim();
    final pass = _passController.text.trim();

    if (_smtpEnabled) {
      if (host.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.smtpHostRequired), backgroundColor: Colors.orange),
        );
        return;
      }
      if (user.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.smtpUserRequired), backgroundColor: Colors.orange),
        );
        return;
      }
      if (pass.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.smtpPassRequired), backgroundColor: Colors.orange),
        );
        return;
      }
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // 1. Save general app settings
      await DatabaseService().setDocument('config', 'app_settings', {
        'paymentCutoffDay': _cutoffDay,
        'gracePeriodDays': _gracePeriodDays,
        'updatedAt': DbFieldValue.serverTimestamp(),
      });

      // 2. Save SMTP settings
      final portVal = int.tryParse(_portController.text.trim()) ?? (_smtpSecure ? 465 : 587);
      await DatabaseService().setDocument('config', 'smtp_settings', {
        'enabled': _smtpEnabled,
        'host': _hostController.text.trim(),
        'port': portVal,
        'secure': _smtpSecure,
        'user': _userController.text.trim(),
        'pass': _passController.text.trim(),
        'senderEmail': _senderEmailController.text.trim(),
        'senderName': _senderNameController.text.trim(),
        'customSubject': _customSubjectController.text.trim(),
        'customBody': _customBodyController.text.trim(),
        'updatedAt': DbFieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsSavedSuccess), backgroundColor: AppConfig.secondaryColor),
        );
      }
    } catch (e) {
      debugPrint('Error saving settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
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
        title: Text(l10n.adminSettingsMenu, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // SECTION 1: Payment & Grace Period
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
                              const Icon(Icons.payments_outlined, color: AppConfig.primaryColor, size: 26),
                              const SizedBox(width: 10),
                              Text(
                                l10n.paymentSettingsSection,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppConfig.primaryColor,
                                  fontFamily: AppConfig.fontFamily,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Cutoff Day Slider
                          Text(
                            '${l10n.paymentCutoffDayLabel}: $_cutoffDay',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          Slider(
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
                          ),
                          const SizedBox(height: 16),

                          // Grace Period Slider
                          Text(
                            '${l10n.gracePeriodDaysLabel}: $_gracePeriodDays',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          Slider(
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
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // SECTION 2: SMTP Email Service
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
                              const Icon(Icons.mark_email_read_outlined, color: AppConfig.primaryColor, size: 26),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  l10n.smtpSettingsSection,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppConfig.primaryColor,
                                    fontFamily: AppConfig.fontFamily,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.smtpEnabledLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(l10n.smtpEnabledSubtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            value: _smtpEnabled,
                            activeColor: AppConfig.secondaryColor,
                            onChanged: (val) {
                              setState(() {
                                _smtpEnabled = val;
                              });
                            },
                          ),

                          const Divider(height: 24),

                          // SMTP Host
                          TextFormField(
                            controller: _hostController,
                            decoration: InputDecoration(
                              labelText: l10n.smtpHostLabel,
                              hintText: l10n.smtpHostHint,
                              prefixIcon: const Icon(Icons.dns_outlined),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
                                  controller: _portController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: l10n.smtpPortLabel,
                                    hintText: l10n.smtpPortHint,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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

                          // Secure (SSL/TLS) Switch
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.smtpSecureLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            subtitle: Text(l10n.smtpSecureSubtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            value: _smtpSecure,
                            activeColor: AppConfig.primaryColor,
                            onChanged: (val) {
                              setState(() {
                                _smtpSecure = val;
                              });
                            },
                          ),
                          const SizedBox(height: 10),

                          // Username / Auth Email
                          TextFormField(
                            controller: _userController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: l10n.smtpUserLabel,
                              hintText: l10n.smtpUserHint,
                              prefixIcon: const Icon(Icons.person_outline),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Password / API Key
                          TextFormField(
                            controller: _passController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: l10n.smtpPassLabel,
                              hintText: l10n.smtpPassHint,
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Sender Email & Name
                          TextFormField(
                            controller: _senderEmailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: l10n.smtpSenderEmailLabel,
                              hintText: l10n.smtpSenderEmailHint,
                              prefixIcon: const Icon(Icons.alternate_email),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _senderNameController,
                            decoration: InputDecoration(
                              labelText: l10n.smtpSenderNameLabel,
                              hintText: l10n.smtpSenderNameHint,
                              prefixIcon: const Icon(Icons.badge_outlined),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              isDense: true,
                            ),
                          ),

                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 12),

                          // Custom Welcome Message Section
                          Row(
                            children: [
                              const Icon(Icons.edit_note, color: AppConfig.primaryColor, size: 24),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  l10n.customWelcomeEmailSection,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppConfig.primaryColor,
                                    fontFamily: AppConfig.fontFamily,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _resetDefaultTemplate,
                                icon: const Icon(Icons.restore, size: 16),
                                label: Text(l10n.resetDefaultTemplateButton, style: const TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.customWelcomeEmailSubtitle,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 14),

                          // Subject field
                          TextFormField(
                            controller: _customSubjectController,
                            decoration: InputDecoration(
                              labelText: l10n.emailSubjectLabel,
                              hintText: l10n.emailSubjectHint,
                              prefixIcon: const Icon(Icons.title),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Available Placeholders
                          Text(
                            l10n.availablePlaceholdersLabel,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ActionChip(
                                avatar: const Icon(Icons.person, size: 14),
                                label: const Text('%name%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                onPressed: () => _insertPlaceholder('%name%'),
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.email, size: 14),
                                label: const Text('%email%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                onPressed: () => _insertPlaceholder('%email%'),
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.lock, size: 14),
                                label: const Text('%password%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                backgroundColor: Colors.amber.withValues(alpha: 0.2),
                                onPressed: () => _insertPlaceholder('%password%'),
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.home, size: 14),
                                label: const Text('%address%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                onPressed: () => _insertPlaceholder('%address%'),
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.badge, size: 14),
                                label: const Text('%role%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                onPressed: () => _insertPlaceholder('%role%'),
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.apps, size: 14),
                                label: const Text('%appName%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                onPressed: () => _insertPlaceholder('%appName%'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Body field
                          TextFormField(
                            controller: _customBodyController,
                            maxLines: 7,
                            keyboardType: TextInputType.multiline,
                            decoration: InputDecoration(
                              labelText: l10n.emailBodyLabel,
                              hintText: l10n.emailBodyHint,
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),

                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 12),

                          // Interactive Test Connection Section
                          Text(
                            l10n.testSmtpButton,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppConfig.primaryColor),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _testRecipientController,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                    labelText: l10n.testRecipientLabel,
                                    hintText: l10n.testRecipientHint,
                                    prefixIcon: const Icon(Icons.send_outlined),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: _isTestingSmtp ? null : _testSmtpConnection,
                                icon: _isTestingSmtp
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                      )
                                    : const Icon(Icons.network_check),
                                label: Text(l10n.testSmtpButton),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppConfig.primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ],
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
                                  color: _isTestSuccess ? Colors.green : Colors.redAccent,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _isTestSuccess ? Icons.check_circle : Icons.error_outline,
                                    color: _isTestSuccess ? Colors.green : Colors.redAccent,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _testStatusMessage!,
                                      style: TextStyle(
                                        color: _isTestSuccess ? Colors.green.shade800 : Colors.red.shade800,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Save All Settings Button
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConfig.secondaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 3,
                    ),
                    child: _isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(
                            l10n.saveSettingsButton,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: AppConfig.fontFamily),
                          ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}
