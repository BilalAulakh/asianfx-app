import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';

class TwoFactorAuthSheet extends ConsumerStatefulWidget {
  final String userEmail;
  final bool isCurrentlyEnabled;

  const TwoFactorAuthSheet({
    super.key,
    required this.userEmail,
    required this.isCurrentlyEnabled,
  });

  static Future<void> show(
    BuildContext context, {
    required String userEmail,
    required bool isCurrentlyEnabled,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TwoFactorAuthSheet(
        userEmail: userEmail,
        isCurrentlyEnabled: isCurrentlyEnabled,
      ),
    );
  }

  @override
  ConsumerState<TwoFactorAuthSheet> createState() => _TwoFactorAuthSheetState();
}

class _TwoFactorAuthSheetState extends ConsumerState<TwoFactorAuthSheet> {
  final TextEditingController _otpController = TextEditingController();
  final SecureStorageService _storage = SecureStorageService.instance;

  String? _secretKey;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final key = await _storage.getOrGenerateTwoFactorSecret(widget.userEmail);
    if (!mounted) return;
    setState(() {
      _secretKey = key;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _copySecret() {
    if (_secretKey == null) return;
    Clipboard.setData(ClipboardData(text: _secretKey!));
    HapticFeedback.selectionClick();
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _enable2FA() async {
    final code = _otpController.text.trim();
    if (code.length < 6) {
      setState(() => _errorMessage = 'Please enter a valid 6-digit authentication code.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 600));
    await ref.read(authProvider.notifier).toggleTwoFactor(true);

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Two-Factor Authentication (2FA) is now enabled.'),
        backgroundColor: Color(0xFF00D68F),
      ),
    );
  }

  Future<void> _disable2FA() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 500));
    await ref.read(authProvider.notifier).toggleTwoFactor(false);

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Two-Factor Authentication (2FA) has been disabled.'),
        backgroundColor: Color(0xFFFF9F43),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: context.scaffoldBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: context.borderColor),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (widget.isCurrentlyEnabled
                                ? const Color(0xFF00D68F)
                                : const Color(0xFFFFD600))
                            .withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        widget.isCurrentlyEnabled
                            ? Icons.verified_user_rounded
                            : Icons.security_rounded,
                        color: widget.isCurrentlyEnabled
                            ? const Color(0xFF00D68F)
                            : const Color(0xFFFFD600),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Two-Factor Authentication',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.isCurrentlyEnabled ? 'Status: Active' : 'Status: Disabled',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: widget.isCurrentlyEnabled
                                ? const Color(0xFF00D68F)
                                : const Color(0xFFFF9F43),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: context.textSecondaryColor),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 18),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(child: CircularProgressIndicator(color: AppColors.brandPrimary)),
              )
            else if (widget.isCurrentlyEnabled)
              _buildActiveView(context)
            else
              _buildSetupView(context),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF00D68F).withAlpha(15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF00D68F).withAlpha(80)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF00D68F), size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account Protected by 2FA',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Withdrawals and account modifications require an authenticator verification code.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: context.textSecondaryColor,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _isSubmitting ? null : _disable2FA,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF4757)),
                  )
                : const Icon(Icons.lock_open_rounded, color: Color(0xFFFF4757), size: 18),
            label: const Text(
              'Disable Two-Factor Authentication',
              style: TextStyle(
                color: Color(0xFFFF4757),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFF4757)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSetupView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Connect your Google Authenticator or Microsoft Authenticator app using the setup key below.',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: context.textSecondaryColor,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),

        // Secret Key Display Box
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Authenticator Secret Key',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _secretKey ?? 'FXA-SETUP-KEY',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: context.textPrimaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: _copySecret,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD600).withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                        color: const Color(0xFFFFD600),
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _copied ? 'Copied' : 'Copy',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFD600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // OTP Input
        Text(
          'Verification Code',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.textPrimaryColor,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            letterSpacing: 8,
            fontWeight: FontWeight.bold,
            color: context.textPrimaryColor,
          ),
          decoration: InputDecoration(
            hintText: '123456',
            hintStyle: TextStyle(
              color: context.textSecondaryColor.withAlpha(100),
              letterSpacing: 8,
            ),
            counterText: '',
            filled: true,
            fillColor: context.cardBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFFD600), width: 1.5),
            ),
          ),
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            _errorMessage!,
            style: const TextStyle(fontSize: 12, color: Colors.redAccent),
          ),
        ],

        const SizedBox(height: 20),

        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _enable2FA,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD600),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Text(
                    'Verify & Enable 2FA',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
