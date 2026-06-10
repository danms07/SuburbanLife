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
  int _cutoffDay = 1;
  int _gracePeriodDays = 10;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() async {
    try {
      final data = await DatabaseService().getDocument('config', 'app_settings');
      if (data != null) {
        setState(() {
          _cutoffDay = data['paymentCutoffDay'] ?? 1;
          _gracePeriodDays = data['gracePeriodDays'] ?? 10;
        });
      }
    } catch (e) {
      debugPrint('Error loading config: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _saveSettings() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isSaving = true;
    });

    try {
      await DatabaseService().setDocument('config', 'app_settings', {
        'paymentCutoffDay': _cutoffDay,
        'gracePeriodDays': _gracePeriodDays,
        'updatedAt': DbFieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsSavedSuccess), backgroundColor: AppConfig.secondaryColor),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
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
              padding: const EdgeInsets.all(24.0),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.settings, size: 60, color: AppConfig.primaryColor),
                      const SizedBox(height: 16),
                      Text(
                        l10n.adminSettingsMenu,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppConfig.primaryColor,
                          fontFamily: AppConfig.fontFamily,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Cutoff Day Slider
                      Text(
                        '${l10n.paymentCutoffDayLabel}: $_cutoffDay',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                      const SizedBox(height: 24),

                      // Grace Period Slider
                      Text(
                        '${l10n.gracePeriodDaysLabel}: $_gracePeriodDays',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                      const SizedBox(height: 40),

                      ElevatedButton(
                        onPressed: _isSaving ? null : _saveSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConfig.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isSaving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text(
                                l10n.confirmAddressButton.replaceAll('Dirección', 'Configuración').replaceAll('Address', 'Settings'),
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
