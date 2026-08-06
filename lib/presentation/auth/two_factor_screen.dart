import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import '../../core/theme/app_colors.dart';
import '../common/widgets/fx_button.dart';

class TwoFactorScreen extends StatefulWidget {
  const TwoFactorScreen({super.key});

  @override
  State<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends State<TwoFactorScreen> {
  final _totpController = TextEditingController();
  bool _isLoading = false;

  void _verify2fa() async {
    if (_totpController.text.length < 6) return;
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isLoading = false);
    if (mounted) {
      context.go('/shell');
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultPinTheme = PinTheme(
      width: 50,
      height: 56,
      textStyle: const TextStyle(fontSize: 22, color: AppColors.textPrimary, fontWeight: FontWeight.bold),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.security, color: AppColors.brandPrimary, size: 32),
                  SizedBox(width: 12),
                  Text(
                    '2FA Security Check',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Enter the 6-digit code from your Authenticator app (Google Authenticator / Authy)',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 40),
              Center(
                child: Pinput(
                  controller: _totpController,
                  length: 6,
                  defaultPinTheme: defaultPinTheme,
                  onCompleted: (_) => _verify2fa(),
                ),
              ),
              const SizedBox(height: 32),
              FxButton(
                text: 'Authenticate',
                isLoading: _isLoading,
                onPressed: _verify2fa,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
