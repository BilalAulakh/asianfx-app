import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../blocs/blocs.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/user_entity.dart';
import '../common/widgets/double_back_to_exit.dart';

/// Bottom-tab shell (Exness layout: Accounts · Trade · Chart · Positions · Profile).
///
/// Android back walks back through the tabs the user visited; on the first tab
/// it asks for a second press before closing the app (it used to close at once).
class AppShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Tabs visited before the current one (most recent last).
  final List<int> _history = [];
  bool _goingBack = false;

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final from = oldWidget.navigationShell.currentIndex;
    final to = widget.navigationShell.currentIndex;
    if (from == to) return;
    if (_goingBack) {
      _goingBack = false;
    } else {
      _history
        ..remove(from)
        ..add(from);
    }
  }

  void _goBranch(int index) {
    final shell = widget.navigationShell;
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  /// Back press inside the shell: previous tab, else the first tab.
  bool _onBack() {
    final current = widget.navigationShell.currentIndex;
    _history.remove(current);
    final target = _history.isNotEmpty ? _history.removeLast() : (current != 0 ? 0 : null);
    if (target == null) return false;
    _goingBack = true;
    widget.navigationShell.goBranch(target);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = widget.navigationShell.currentIndex;
    final authUser = context.watch<AuthBloc>().state.user;
    final isAdmin = authUser?.role == UserRole.admin;
    final isDark = context.isDarkMode;

    return DoubleBackToExit(
      onBack: _onBack,
      child: Scaffold(
        backgroundColor: context.scaffoldBg,
        // Rejected server requests (close / cancel) surface here on every tab,
        // e.g. NO_QUOTE while the market is closed.
        body: BlocListener<TradingEngineBloc, TradingEngineState>(
          listenWhen: (prev, curr) =>
              curr.lastErrorTime != null && curr.lastErrorTime != prev.lastErrorTime,
          listener: (context, state) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.loss,
                behavior: SnackBarBehavior.floating,
                content: Text(
                  state.lastErrorMessage ?? 'Request failed.',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            );
          },
          child: widget.navigationShell,
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            border: Border(top: BorderSide(color: context.borderColor)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 60,
              child: Row(
                children: [
                  _NavItem(
                    icon: Icons.grid_view_outlined,
                    activeIcon: Icons.grid_view_rounded,
                    label: 'Accounts',
                    isActive: currentIndex == 0,
                    onTap: () => _goBranch(0),
                  ),
                  _NavItem(
                    icon: Icons.swap_vert_rounded,
                    activeIcon: Icons.swap_vert_rounded,
                    label: 'Trade',
                    isActive: currentIndex == 1,
                    onTap: () => _goBranch(1),
                  ),
                  _NavItem(
                    icon: Icons.candlestick_chart_outlined,
                    activeIcon: Icons.candlestick_chart_rounded,
                    label: 'Chart',
                    isActive: currentIndex == 2,
                    onTap: () => _goBranch(2),
                  ),
                  _NavItem(
                    icon: Icons.bar_chart_rounded,
                    activeIcon: Icons.bar_chart_rounded,
                    label: 'Positions',
                    isActive: currentIndex == 3,
                    onTap: () => _goBranch(3),
                  ),
                  if (isAdmin)
                    _NavItem(
                      icon: Icons.admin_panel_settings_outlined,
                      activeIcon: Icons.admin_panel_settings_rounded,
                      label: 'Admin',
                      isActive: false,
                      highlight: true,
                      onTap: () => context.push(AppRoutes.admin),
                    )
                  else
                    _NavItem(
                      icon: Icons.account_circle_outlined,
                      activeIcon: Icons.account_circle_rounded,
                      label: 'Profile',
                      isActive: currentIndex == 4,
                      onTap: () => _goBranch(4),
                    ),
                ],
              ),
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
  final bool highlight;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    this.highlight = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight
        ? context.accentColor
        : isActive
            ? context.textPrimaryColor
            : context.textSecondaryColor;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isActive ? activeIcon : icon, size: 24, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
