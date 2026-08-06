import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';
import '../../providers/auth_provider.dart';
import '../common/widgets/fx_button.dart';
import '../common/widgets/fx_text_field.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  bool _agreeToTerms = false;
  int _step = 0;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreeToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please agree to the terms.'), backgroundColor: AppColors.warning));
      return;
    }
    setState(() => _isLoading = true);
    final success = await ref.read(authProvider.notifier).register(
      fullName: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      phone: _phoneController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (success) context.go(AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
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
                  const SizedBox(height: 28),
                  const Text('Create Account', style: TextStyle(fontFamily: 'Inter', fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5)),
                  const SizedBox(height: 6),
                  const Text('Join FXAsianApp and start trading globally', style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.textSecondary)),
                  const SizedBox(height: 32),

                  // Step indicator
                  Row(
                    children: [
                      _StepDot(label: 'Personal', isActive: _step == 0, isDone: _step > 0),
                      Expanded(child: Container(height: 2, color: _step > 0 ? AppColors.brandPrimary : AppColors.darkBorder)),
                      _StepDot(label: 'Security', isActive: _step == 1, isDone: false),
                    ],
                  ),
                  const SizedBox(height: 28),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _step == 0 ? _buildStep1() : _buildStep2(),
                  ),

                  const SizedBox(height: 20),

                  if (_step == 1) ...[
                    GestureDetector(
                      onTap: () => setState(() => _agreeToTerms = !_agreeToTerms),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 20, height: 20,
                            decoration: BoxDecoration(
                              color: _agreeToTerms ? AppColors.brandPrimary : Colors.transparent,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: _agreeToTerms ? AppColors.brandPrimary : AppColors.darkBorder),
                            ),
                            child: _agreeToTerms ? const Icon(Icons.check_rounded, size: 14, color: Colors.black) : null,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text.rich(TextSpan(
                              text: 'I agree to the ',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.textSecondary),
                              children: [
                                TextSpan(text: 'Terms of Service', style: TextStyle(color: AppColors.brandPrimary, fontWeight: FontWeight.w600)),
                                TextSpan(text: ' and '),
                                TextSpan(text: 'Privacy Policy', style: TextStyle(color: AppColors.brandPrimary, fontWeight: FontWeight.w600)),
                              ],
                            )),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  FxButton(
                    label: _step == 0 ? 'Continue' : 'Create Account',
                    isLoading: _isLoading,
                    onPressed: () {
                      if (_step == 0) {
                        if (_nameController.text.isNotEmpty && _emailController.text.contains('@')) {
                          setState(() { _step = 1; });
                        }
                      } else {
                        _handleRegister();
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Already have an account?', style: TextStyle(color: AppColors.textSecondary, fontSize: 14, fontFamily: 'Inter')),
                        TextButton(
                          onPressed: () => context.pop(),
                          style: TextButton.styleFrom(padding: const EdgeInsets.only(left: 6), minimumSize: Size.zero),
                          child: const Text('Sign In', style: TextStyle(color: AppColors.brandPrimary, fontWeight: FontWeight.w700, fontSize: 14, fontFamily: 'Inter')),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      key: const ValueKey('step1'),
      children: [
        FxTextField(controller: _nameController, label: 'Full Name', hint: 'Alex Rahman', prefixIcon: Icons.person_outline_rounded, validator: (v) => v == null || v.isEmpty ? 'Required' : null),
        const SizedBox(height: 16),
        FxTextField(controller: _emailController, label: 'Email Address', hint: 'you@example.com', keyboardType: TextInputType.emailAddress, prefixIcon: Icons.email_outlined, validator: (v) => v == null || !v.contains('@') ? 'Invalid email' : null),
        const SizedBox(height: 16),
        FxTextField(controller: _phoneController, label: 'Phone Number (Optional)', hint: '+92 300 0000000', keyboardType: TextInputType.phone, prefixIcon: Icons.phone_outlined),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      key: const ValueKey('step2'),
      children: [
        FxTextField(
          controller: _passwordController, label: 'Password', hint: 'Min. 8 characters',
          obscureText: _obscurePassword, prefixIcon: Icons.lock_outline_rounded,
          suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.textSecondary, size: 20), onPressed: () => setState(() => _obscurePassword = !_obscurePassword)),
          validator: (v) => v == null || v.length < 8 ? 'Minimum 8 characters' : null,
        ),
        const SizedBox(height: 16),
        FxTextField(
          controller: _confirmController, label: 'Confirm Password', hint: 'Repeat password',
          obscureText: _obscureConfirm, prefixIcon: Icons.lock_outline_rounded,
          suffixIcon: IconButton(icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.textSecondary, size: 20), onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm)),
          validator: (v) => v != _passwordController.text ? 'Passwords do not match' : null,
        ),
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isDone;
  const _StepDot({required this.label, required this.isActive, required this.isDone});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 28, height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone ? AppColors.brandPrimary : isActive ? AppColors.brandPrimary.withAlpha(20) : Colors.transparent,
            border: Border.all(color: isActive || isDone ? AppColors.brandPrimary : AppColors.darkBorder, width: 2),
          ),
          child: Center(
            child: isDone ? const Icon(Icons.check_rounded, size: 14, color: Colors.black) : Icon(Icons.circle, size: 8, color: isActive ? AppColors.brandPrimary : AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: isActive ? AppColors.brandPrimary : AppColors.textMuted, fontWeight: isActive ? FontWeight.w600 : FontWeight.w400)),
      ],
    );
  }
}
