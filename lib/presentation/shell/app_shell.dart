import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/market_provider.dart';

class AppShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin {
  late AnimationController _tradeButtonController;

  @override
  void initState() {
    super.initState();
    _tradeButtonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _tradeButtonController.dispose();
    super.dispose();
  }

  void _goBranch(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = widget.navigationShell.currentIndex;
    final wallet = ref.watch(walletProvider);
    final totalPl = ref.watch(openTradesProvider.select((t) =>
        t.where((trade) => trade.isOpen).fold(0.0, (s, t) => s + t.floatingPl)));

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: widget.navigationShell,

      // ── Bottom Navigation ────────────────────────────────────────────────────
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.darkSurface,
          border: Border(
            top: BorderSide(color: AppColors.darkBorder, width: 0.5),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 66,
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  isActive: currentIndex == 0,
                  onTap: () => _goBranch(0),
                ),
                _NavItem(
                  icon: Icons.bar_chart_rounded,
                  label: 'Markets',
                  isActive: currentIndex == 1,
                  onTap: () => _goBranch(1),
                ),
                // Center Trade Button
                Expanded(
                  child: GestureDetector(
                    onTap: () => _goBranch(2),
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _tradeButtonController,
                        builder: (context, child) {
                          return Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppColors.primaryGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.brandPrimary.withAlpha(
                                    (60 + _tradeButtonController.value * 40).round(),
                                  ),
                                  blurRadius: 16 + _tradeButtonController.value * 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Icon(
                              currentIndex == 2
                                  ? Icons.swap_horiz_rounded
                                  : Icons.add_rounded,
                              color: Colors.black,
                              size: 28,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                _NavItem(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Wallet',
                  isActive: currentIndex == 3,
                  onTap: () => _goBranch(3),
                ),
                _NavItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  isActive: currentIndex == 4,
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
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isActive ? AppColors.brandPrimary.withAlpha(20) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 22,
                color: isActive ? AppColors.brandPrimary : AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? AppColors.brandPrimary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
