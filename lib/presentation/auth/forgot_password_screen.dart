import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../common/widgets/fx_button.dart';
import '../common/widgets/fx_text_field.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendReset() async {
    if (_emailController.text.isEmpty || !_emailController.text.contains('@')) return;
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() { _isLoading = false; _emailSent = true; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: AppColors.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.darkBorder)),
                  child: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary, size: 20),
                ),
              ),
              const SizedBox(height: 40),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _emailSent ? _buildSuccess() : _buildForm(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(color: AppColors.brandSecondary.withAlpha(20), borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.lock_reset_rounded, color: AppColors.brandSecondary, size: 32),
        ),
        const SizedBox(height: 24),
        const Text('Forgot Password?', style: TextStyle(fontFamily: 'Inter', fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        const Text("No worries! Enter your email and we'll send you a reset link.", style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.textSecondary, height: 1.5)),
        const SizedBox(height: 32),
        FxTextField(controller: _emailController, label: 'Email Address', hint: 'you@example.com', keyboardType: TextInputType.emailAddress, prefixIcon: Icons.email_outlined),
        const SizedBox(height: 24),
        FxButton(label: 'Send Reset Link', isLoading: _isLoading, onPressed: _sendReset),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      key: const ValueKey('success'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(gradient: AppColors.profitGradient, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: AppColors.profit.withAlpha(50), blurRadius: 30)]),
          child: const Icon(Icons.mark_email_read_outlined, color: Colors.white, size: 38),
        ),
        const SizedBox(height: 28),
        const Text('Check Your Email', style: TextStyle(fontFamily: 'Inter', fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            text: 'A reset link was sent to\n',
            style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.textSecondary, height: 1.6),
            children: [TextSpan(text: _emailController.text, style: const TextStyle(color: AppColors.brandPrimary, fontWeight: FontWeight.w600))],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        FxButton(label: 'Back to Login', onPressed: () => Navigator.pop(context)),
      ],
    );
  }
}
