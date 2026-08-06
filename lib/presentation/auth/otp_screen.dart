import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';
import '../common/widgets/fx_button.dart';

class OtpScreen extends StatefulWidget {
  final String email;
  const OtpScreen({super.key, required this.email});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  String _otp = '';
  bool _isVerifying = false;
  int _resendSeconds = 30;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  void _startResendTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _resendSeconds > 0) {
        setState(() => _resendSeconds--);
        _startResendTimer();
      }
    });
  }

  Future<void> _verify() async {
    if (_otp.length < 6) return;
    setState(() => _isVerifying = true);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() => _isVerifying = false);
    context.go(AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    final defaultPinTheme = PinTheme(
      width: 52,
      height: 56,
      textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
      ),
    );

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
                onTap: () => context.pop(),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: AppColors.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.darkBorder)),
                  child: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary, size: 20),
                ),
              ),
              const SizedBox(height: 40),
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: AppColors.brandPrimary.withAlpha(50), blurRadius: 24)]),
                child: const Icon(Icons.mark_email_unread_outlined, color: Colors.black, size: 30),
              ),
              const SizedBox(height: 24),
              const Text('Verify Your Email', style: TextStyle(fontFamily: 'Inter', fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  text: 'We sent a 6-digit code to\n',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.textSecondary, height: 1.5),
                  children: [TextSpan(text: widget.email.isNotEmpty ? widget.email : 'your email', style: const TextStyle(color: AppColors.brandPrimary, fontWeight: FontWeight.w600))],
                ),
              ),
              const SizedBox(height: 40),
              Center(
                child: Pinput(
                  length: 6,
                  defaultPinTheme: defaultPinTheme,
                  focusedPinTheme: defaultPinTheme.copyWith(
                    decoration: defaultPinTheme.decoration!.copyWith(border: Border.all(color: AppColors.brandPrimary, width: 2)),
                  ),
                  submittedPinTheme: defaultPinTheme.copyWith(
                    decoration: defaultPinTheme.decoration!.copyWith(color: AppColors.brandPrimary.withAlpha(15), border: Border.all(color: AppColors.brandPrimary)),
                  ),
                  separatorBuilder: (index) => const SizedBox(width: 10),
                  onCompleted: (v) { setState(() => _otp = v); _verify(); },
                  onChanged: (v) => setState(() => _otp = v),
                ),
              ),
              const SizedBox(height: 40),
              FxButton(label: 'Verify', isLoading: _isVerifying, onPressed: _otp.length == 6 ? _verify : null),
              const SizedBox(height: 20),
              Center(
                child: _resendSeconds > 0
                    ? Text('Resend code in ${_resendSeconds}s', style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.textSecondary))
                    : TextButton(
                        onPressed: () { setState(() => _resendSeconds = 30); _startResendTimer(); },
                        child: const Text('Resend Code', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.brandPrimary)),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
