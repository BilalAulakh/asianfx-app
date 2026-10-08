import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../blocs/auth_bloc.dart';
import '../../core/router/app_router.dart';
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
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  int _step = 0; // 0: Request Code, 1: Enter Code & New Password, 2: Success
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  /// Supabase allows one reset e-mail per address per 60 seconds.
  static const _resendAfter = 60;
  int _resendIn = 0;
  Timer? _resendTimer;

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = _resendAfter);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _resendCode() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final authBloc = context.read<AuthBloc>();
    final sent = await authBloc.requestPasswordReset(_emailController.text.trim());
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (!sent) _errorMessage = authBloc.state.error ?? 'Could not send a new code. Please try again.';
    });
    if (sent) {
      _startResendCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code has been sent to your email.')),
      );
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendResetCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = 'Please enter a valid email address.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authBloc = context.read<AuthBloc>();
    final sent = await authBloc.requestPasswordReset(email);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (sent) {
        _step = 1;
        _codeController.clear();
      } else {
        _errorMessage = authBloc.state.error ?? 'Could not request password reset. Please try again.';
      }
    });
    if (sent) _startResendCooldown();
  }

  /// The code is verified by Supabase (OtpType.recovery). There is no local
  /// fallback: a code the server does not accept never changes a password.
  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    final enteredCode = _codeController.text.trim();
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (enteredCode.isEmpty) {
      setState(() => _errorMessage = 'Please enter the verification code from your email.');
      return;
    }
    if (newPassword.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters long.');
      return;
    }
    if (newPassword != confirmPassword) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authBloc = context.read<AuthBloc>();
    final success = await authBloc.completePasswordRecovery(
      email: email,
      code: enteredCode,
      newPassword: newPassword,
    );
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (success) {
        _step = 2;
      } else {
        _errorMessage = authBloc.state.error ?? 'Failed to reset password. Please try again.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),

              // Back button
              if (_step < 2)
                GestureDetector(
                  onTap: () {
                    if (_step == 1) {
                      setState(() {
                        _step = 0;
                        _errorMessage = null;
                      });
                    } else {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go(AppRoutes.login);
                      }
                    }
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.darkCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.darkBorder),
                    ),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textPrimary,
                      size: 20,
                    ),
                  ),
                ),

              const SizedBox(height: 32),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildCurrentStepView(),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_step) {
      case 0:
        return _buildStep0Email();
      case 1:
        return _buildStep1CodeAndNewPassword();
      case 2:
      default:
        return _buildStep2Success();
    }
  }

  Widget _buildStep0Email() {
    return Column(
      key: const ValueKey('step_0'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.brandSecondary.withAlpha(20),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.brandSecondary.withAlpha(60)),
          ),
          child: const Icon(
            Icons.lock_reset_rounded,
            color: AppColors.brandSecondary,
            size: 32,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Forgot Password?',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Enter your registered account email and we'll send you a verification code to reset your password.",
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),

        FxTextField(
          controller: _emailController,
          label: 'Email Address',
          hint: 'trader@example.com',
          keyboardType: TextInputType.emailAddress,
          prefixIcon: Icons.email_outlined,
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          Text(
            _errorMessage!,
            style: const TextStyle(fontSize: 13, color: Colors.redAccent),
          ),
        ],

        const SizedBox(height: 28),
        FxButton(
          label: 'Send Verification Code',
          isLoading: _isLoading,
          onPressed: _sendResetCode,
        ),
      ],
    );
  }

  Widget _buildStep1CodeAndNewPassword() {
    return Column(
      key: const ValueKey('step_1'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFFFFDE02).withAlpha(20),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFFDE02).withAlpha(60)),
          ),
          child: const Icon(
            Icons.password_rounded,
            color: Color(0xFFFFDE02),
            size: 32,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Set New Password',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the verification code and your new password for ${_emailController.text}.',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),

        // Verification Code Notice Box
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFDE02).withAlpha(15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFDE02).withAlpha(60)),
          ),
          child: Row(
            children: [
              const Icon(Icons.mark_email_read_rounded, color: Color(0xFFFFDE02), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'We sent a verification code to ${_emailController.text.trim()}. '
                  'Enter it below to choose a new password.',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Code Input
        FxTextField(
          controller: _codeController,
          label: 'Verification Code',
          hint: 'Code from the email',
          keyboardType: TextInputType.number,
          prefixIcon: Icons.security_rounded,
        ),
        const SizedBox(height: 16),

        // New Password
        FxTextField(
          controller: _newPasswordController,
          label: 'New Password',
          hint: '••••••••',
          obscureText: _obscureNew,
          prefixIcon: Icons.lock_outline_rounded,
          suffixIcon: IconButton(
            icon: Icon(
              _obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: AppColors.textSecondary,
              size: 20,
            ),
            onPressed: () => setState(() => _obscureNew = !_obscureNew),
          ),
        ),
        const SizedBox(height: 16),

        // Confirm New Password
        FxTextField(
          controller: _confirmPasswordController,
          label: 'Confirm New Password',
          hint: '••••••••',
          obscureText: _obscureConfirm,
          prefixIcon: Icons.lock_outline_rounded,
          suffixIcon: IconButton(
            icon: Icon(
              _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: AppColors.textSecondary,
              size: 20,
            ),
            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
          ),
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          Text(
            _errorMessage!,
            style: const TextStyle(fontSize: 13, color: Colors.redAccent),
          ),
        ],

        const SizedBox(height: 28),
        FxButton(
          label: 'Confirm & Reset Password',
          isLoading: _isLoading,
          onPressed: _resetPassword,
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: _isLoading || _resendIn > 0 ? null : _resendCode,
            child: Text(
              _resendIn > 0 ? "Didn't get the code? Resend in ${_resendIn}s" : "Didn't get the code? Resend",
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _resendIn > 0 ? AppColors.textSecondary : AppColors.brandPrimary,
              ),
            ),
          ),
        ),
        const Center(
          child: Text(
            'Also check your Spam / Junk folder.',
            style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2Success() {
    return Column(
      key: const ValueKey('step_2'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF16C784).withAlpha(30),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF16C784), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF16C784).withAlpha(60),
                blurRadius: 28,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF16C784),
            size: 42,
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Password Reset Complete',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            text: 'Your password has been successfully updated for\n',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
            children: [
              TextSpan(
                text: _emailController.text,
                style: const TextStyle(
                  color: AppColors.brandPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 36),
        FxButton(
          label: 'Back to Login',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.login);
            }
          },
        ),
      ],
    );
  }
}
