import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';
import '../../domain/entities/user_entity.dart';
import '../../providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _pulseController;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _pulseAnim;
  late Animation<double> _textOpacity;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
      ),
    );

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _logoController.forward();

    _navigateAfterDelay();
  }

  Future<void> _navigateAfterDelay() async {
    await Future.delayed(const Duration(milliseconds: 2800));
    if (!mounted) return;

    final authState = ref.read(authProvider);
    if (authState.status == AuthStatus.loading) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (!mounted) return;
    final finalState = ref.read(authProvider);
    if (finalState.status == AuthStatus.authenticated) {
      if (finalState.user?.role == UserRole.admin) {
        context.go(AppRoutes.admin);
      } else {
        context.go(AppRoutes.dashboard);
      }
    } else {
      context.go(AppRoutes.login);
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF080C14),
              Color(0xFF0A1628),
              Color(0xFF080C14),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Background ambient circles
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brandPrimary.withAlpha(15),
                ),
              ),
            ),
            Positioned(
              bottom: -80,
              left: -80,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brandSecondary.withAlpha(12),
                ),
              ),
            ),

            // Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated Logo
                  AnimatedBuilder(
                    animation: Listenable.merge([_logoController, _pulseController]),
                    builder: (context, _) {
                      return FadeTransition(
                        opacity: _logoOpacity,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: ScaleTransition(
                            scale: _pulseAnim,
                            child: _buildLogo(),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 28),

                  // App Name
                  FadeTransition(
                    opacity: _textOpacity,
                    child: Column(
                      children: [
                        RichText(
                          text: const TextSpan(
                            children: [
                              TextSpan(
                                text: 'FX',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.brandPrimary,
                                  letterSpacing: -1,
                                ),
                              ),
                              TextSpan(
                                text: 'Asian',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -1,
                                ),
                              ),
                              TextSpan(
                                text: 'App',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.brandSecondary,
                                  letterSpacing: -1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Trade the World',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            color: AppColors.textSecondary,
                            letterSpacing: 3,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Loading indicator at bottom
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _textOpacity,
                child: Column(
                  children: [
                    SizedBox(
                      width: 120,
                      child: LinearProgressIndicator(
                        backgroundColor: AppColors.darkBorder,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.brandPrimary,
                        ),
                        borderRadius: BorderRadius.circular(4),
                        minHeight: 3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Powered by FXAsianApp',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: AppColors.textMuted,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: AppColors.primaryGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPrimary.withAlpha(80),
            blurRadius: 40,
            spreadRadius: 8,
          ),
        ],
      ),
      child: const Center(
        child: Text(
          'FX',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 36,
            fontWeight: FontWeight.w900,
            color: Colors.black,
            letterSpacing: -2,
          ),
        ),
      ),
    );
  }
}
