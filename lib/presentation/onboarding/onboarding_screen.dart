import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/router/app_router.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _controller = PageController();
  int _currentPage = 0;

  final _pages = [
    _OnboardingPage(
      icon: Icons.language_rounded,
      gradient: [Color(0xFF00C896), Color(0xFF00B0CC)],
      title: AppStrings.onboarding1Title,
      subtitle: AppStrings.onboarding1Subtitle,
      tags: ['Forex', 'Crypto', 'Gold', 'Stocks'],
    ),
    _OnboardingPage(
      icon: Icons.candlestick_chart_rounded,
      gradient: [Color(0xFFFFB300), Color(0xFFFF8F00)],
      title: AppStrings.onboarding2Title,
      subtitle: AppStrings.onboarding2Subtitle,
      tags: ['Candlestick', 'RSI', 'MACD', 'Bollinger'],
    ),
    _OnboardingPage(
      icon: Icons.security_rounded,
      gradient: [Color(0xFF5C6BC0), Color(0xFF3D5AFE)],
      title: AppStrings.onboarding3Title,
      subtitle: AppStrings.onboarding3Subtitle,
      tags: ['2FA', 'Biometric', 'SSL', 'AES-256'],
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Stack(
        children: [
          // Page View
          PageView.builder(
            controller: _controller,
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, i) => _buildPage(_pages[i], size, i),
          ),

          // Bottom Controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomBar(),
          ),

          // Skip Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 20,
            child: _currentPage < _pages.length - 1
                ? TextButton(
                    onPressed: () => context.go(AppRoutes.login),
                    child: const Text(
                      AppStrings.skip,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        fontFamily: 'Inter',
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(_OnboardingPage page, Size size, int index) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(AppColors.darkBackground, page.gradient[0], 0.08)!,
            AppColors.darkBackground,
          ],
        ),
      ),
      child: Column(
        children: [
          SizedBox(height: size.height * 0.12),

          // Illustration
          Expanded(
            flex: 5,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon container
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.8, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.elasticOut,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(40),
                            gradient: LinearGradient(
                              colors: page.gradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: page.gradient[0].withAlpha(70),
                                blurRadius: 50,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: Icon(
                            page.icon,
                            size: 72,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 48),

                  // Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      page.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        height: 1.2,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Subtitle
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      page.subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        color: AppColors.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Feature Tags
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: page.tags.map((tag) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: page.gradient[0].withAlpha(20),
                        border: Border.all(
                          color: page.gradient[0].withAlpha(50),
                        ),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: page.gradient[0],
                        ),
                      ),
                    )).toList(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final isLast = _currentPage == _pages.length - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, AppColors.darkBackground],
        ),
      ),
      child: Row(
        children: [
          // Page Indicator
          SmoothPageIndicator(
            controller: _controller,
            count: _pages.length,
            effect: ExpandingDotsEffect(
              activeDotColor: AppColors.brandPrimary,
              dotColor: AppColors.darkBorder,
              dotHeight: 8,
              dotWidth: 8,
              expansionFactor: 3,
              spacing: 6,
            ),
          ),
          const Spacer(),

          // Next / Get Started Button
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: FilledButton(
              onPressed: () {
                if (isLast) {
                  context.go(AppRoutes.login);
                } else {
                  _controller.nextPage(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                  );
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: Colors.black,
                minimumSize: Size.zero,
                padding: EdgeInsets.symmetric(
                  horizontal: isLast ? 28 : 20,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isLast ? AppStrings.getStarted : AppStrings.next,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage {
  final IconData icon;
  final List<Color> gradient;
  final String title;
  final String subtitle;
  final List<String> tags;

  const _OnboardingPage({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.subtitle,
    required this.tags,
  });
}
