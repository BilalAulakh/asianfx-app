import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import '../../domain/entities/user_entity.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = navigationShell.currentIndex;
    final authUser = ref.watch(authProvider).user;
    final isAdmin = authUser?.role == UserRole.admin;
    final isDark = ref.watch(themeProvider);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0E17) : const Color(0xFFF4F6F9),
      body: navigationShell,

      // ── Institutional Bottom Navigation Items ───────────────────────
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF151D28) : Colors.white,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
          border: Border(
            top: BorderSide(
              color: isAdmin
                  ? const Color(0xFFFFD600).withValues(alpha: 0.5)
                  : (isDark ? const Color(0xFF1C2535) : const Color(0xFFE2E8F0)),
              width: isAdmin ? 1.5 : 1.0,
            ),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.account_balance_wallet_outlined,
                  activeIcon: Icons.account_balance_wallet_rounded,
                  label: 'Wallet',
                  isActive: currentIndex == 0,
                  isDark: isDark,
                  onTap: () => _goBranch(0),
                ),
                _NavItem(
                  icon: Icons.trending_up_rounded,
                  activeIcon: Icons.trending_up_rounded,
                  label: 'Markets',
                  isActive: currentIndex == 1,
                  isDark: isDark,
                  onTap: () => _goBranch(1),
                ),
                _NavItem(
                  icon: Icons.candlestick_chart_outlined,
                  activeIcon: Icons.candlestick_chart_rounded,
                  label: 'Terminal',
                  isActive: currentIndex == 2,
                  isDark: isDark,
                  onTap: () => _goBranch(2),
                ),
                _NavItem(
                  icon: Icons.pie_chart_outline_rounded,
                  activeIcon: Icons.pie_chart_rounded,
                  label: 'Positions',
                  isActive: currentIndex == 3,
                  isDark: isDark,
                  onTap: () => _goBranch(3),
                ),
                if (isAdmin)
                  _NavItem(
                    icon: Icons.admin_panel_settings_outlined,
                    activeIcon: Icons.admin_panel_settings_rounded,
                    label: 'Admin Desk',
                    isActive: false,
                    isSpecialAdmin: true,
                    isDark: isDark,
                    onTap: () => context.push(AppRoutes.admin),
                  )
                else
                  _NavItem(
                    icon: Icons.person_outline_rounded,
                    activeIcon: Icons.person_rounded,
                    label: 'Profile',
                    isActive: currentIndex == 4,
                    isDark: isDark,
                    onTap: () => _goBranch(4),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final bool isSpecialAdmin;
  final bool isDark;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    this.isSpecialAdmin = false,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isSpecialAdmin
        ? const Color(0xFFFFD600)
        : (isDark ? const Color(0xFFFFD600) : const Color(0xFF00C896));
    final inactiveColor = isSpecialAdmin
        ? const Color(0xFFFFD600)
        : (isDark ? const Color(0xFF848E9C) : const Color(0xFF64748B));

    return Expanded(
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSpecialAdmin)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD600).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFFD600).withValues(alpha: 0.5)),
                ),
                child: Icon(activeIcon, size: 18, color: const Color(0xFFFFD600)),
              )
            else
              Icon(
                isActive ? activeIcon : icon,
                size: 22,
                color: isActive ? activeColor : inactiveColor,
              ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                fontWeight: (isActive || isSpecialAdmin) ? FontWeight.bold : FontWeight.w500,
                color: (isActive || isSpecialAdmin) ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

