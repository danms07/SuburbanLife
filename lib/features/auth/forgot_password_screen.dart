import 'package:flutter/material.dart';
import 'package:suburban_life/core/config/app_config.dart';
import 'package:suburban_life/features/auth/auth_service.dart';
import 'package:suburban_life/l10n/app_localizations.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _sendResetLink() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final email = _emailController.text.trim();

    if (email.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    final success = await _authService.sendPasswordReset(email);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.resetLinkSent),
          backgroundColor: AppConfig.secondaryColor,
        ),
      );
      navigator.pop();
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.resetLinkFailed),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      body: Column(
        children: [
          // Header matching app design system
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
                    l10n.resetPasswordTitle,
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

          // Responsive Form Area
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 450),
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.resetPasswordInstructions,
                            style: const TextStyle(fontSize: 15, height: 1.4),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          TextField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              labelText: l10n.email,
                              prefixIcon: const Icon(
                                Icons.email,
                                color: AppConfig.primaryColor,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 32),
                          ElevatedButton(
                            onPressed: _isLoading ? null : _sendResetLink,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConfig.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
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
                                : Text(
                                    l10n.sendResetLinkButton,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
