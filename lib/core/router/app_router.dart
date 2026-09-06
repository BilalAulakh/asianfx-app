import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/user_entity.dart';
import '../../providers/auth_provider.dart';
import '../../presentation/splash/splash_screen.dart';
import '../../presentation/onboarding/onboarding_screen.dart';
import '../../presentation/auth/login_screen.dart';
import '../../presentation/auth/register_screen.dart';
import '../../presentation/auth/otp_screen.dart';
import '../../presentation/auth/forgot_password_screen.dart';
import '../../presentation/shell/app_shell.dart';
import '../../presentation/trading/terminal_screen.dart';
import '../../presentation/trading/positions_screen.dart';
import '../../presentation/wallet/vault_screen.dart';
import '../../presentation/wallet/double_entry_statement_screen.dart';
import '../../presentation/profile/profile_screen.dart';
import '../../presentation/kyc/kyc_flow_screen.dart';
import '../../presentation/admin/admin_portal_screen.dart';

// Route names
abstract class AppRoutes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const register = '/register';
  static const otp = '/otp';
  static const forgotPassword = '/forgot-password';
  static const shell = '/app';
  static const terminal = '/app/terminal';
  static const dashboard = '/app/vault';
  static const positions = '/app/positions';
  static const vault = '/app/vault';
  static const statement = '/app/statement';
  static const profile = '/app/profile';
  static const kyc = '/app/kyc';
  static const admin = '/app/admin';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final isAuthenticated = authState.status == AuthStatus.authenticated;
      final isAuthRoute = state.matchedLocation == AppRoutes.login ||
          state.matchedLocation == AppRoutes.register ||
          state.matchedLocation == AppRoutes.onboarding;
      final isSplash = state.matchedLocation == AppRoutes.splash;
      final isAdminRoute = state.matchedLocation == AppRoutes.admin;
      final isAdmin = authState.user?.role == UserRole.admin;

      if (isSplash) return null;
      if (authState.status == AuthStatus.loading) return null;

      if (!isAuthenticated && !isAuthRoute) return AppRoutes.login;
      if (isAuthenticated && isAuthRoute) {
        return isAdmin ? AppRoutes.admin : AppRoutes.vault;
      }

      // Strict protection: Non-admin users cannot access admin desk
      if (isAdminRoute && !isAdmin) {
        return AppRoutes.vault;
      }

      // Strict protection: Admin users ONLY access Admin Portal and are isolated from client trader terminal
      if (isAuthenticated && isAdmin && !isAdminRoute) {
        return AppRoutes.admin;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const LoginScreen(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.register,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const RegisterScreen(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.otp,
        builder: (context, state) => OtpScreen(
          email: state.extra as String? ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),

      // Admin & KYC Full Routes
      GoRoute(
        path: AppRoutes.admin,
        builder: (context, state) => const AdminPortalScreen(),
      ),
      GoRoute(
        path: AppRoutes.kyc,
        builder: (context, state) => const KycFlowScreen(),
      ),

      GoRoute(
        path: AppRoutes.statement,
        builder: (context, state) => const DoubleEntryStatementScreen(),
      ),

      // Institutional 4 Branch Navigation Shell
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          // 1. Trading Terminal
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.terminal,
                builder: (context, state) => const TerminalScreen(),
              ),
            ],
          ),
          // 2. Positions & Portfolio
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.positions,
                builder: (context, state) => const PositionsScreen(),
              ),
            ],
          ),
          // 3. Client Vault & Wallet
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.vault,
                builder: (context, state) => const VaultScreen(),
              ),
            ],
          ),
          // 4. Profile & KYC
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFFFFD600)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.vault),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD600),
                foregroundColor: Colors.black,
              ),
              child: const Text('Go to Vault'),
            ),
          ],
        ),
      ),
    ),
  );
});

Widget _fadeSlideTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  return SlideTransition(
    position: Tween<Offset>(
      begin: const Offset(0.05, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: FadeTransition(opacity: animation, child: child),
  );
}
