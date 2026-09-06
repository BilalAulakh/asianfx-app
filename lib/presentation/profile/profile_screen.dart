import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/user_entity.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../admin/admin_portal_screen.dart';
import '../kyc/kyc_flow_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final isDark = ref.watch(themeProvider);

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        backgroundColor: context.headerBg,
        elevation: 0,
        title: Text(
          'Institutional Account & Profile',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: context.textPrimaryColor,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: isDark ? const Color(0xFFFFD600) : const Color(0xFF0F172A),
              size: 22,
            ),
            tooltip: isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme',
            onPressed: () => ref.read(themeProvider.notifier).toggleTheme(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Account Person Details Card ────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.borderColor),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: const Color(0xFFFFD600),
                        child: Text(
                          (user?.fullName.isNotEmpty == true)
                              ? user!.fullName[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.fullName ?? 'Institutional Trader',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: context.textPrimaryColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user?.email ?? 'trader@asianfx.institutional',
                              style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD600).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                user?.roleDisplay.toUpperCase() ?? 'INSTITUTIONAL TRADER',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFFFD600),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: context.borderColor, height: 1),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'KYC Compliance State:',
                        style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const KycFlowScreen()),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: user?.isKycVerified == true
                                ? const Color(0xFF00D68F).withValues(alpha: 0.2)
                                : const Color(0xFFFF4757).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: user?.isKycVerified == true
                                  ? const Color(0xFF00D68F)
                                  : const Color(0xFFFF4757),
                            ),
                          ),
                          child: Text(
                            user?.kycStatusDisplay ?? 'Not Submitted',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: user?.isKycVerified == true
                                  ? const Color(0xFF00D68F)
                                  : const Color(0xFFFF4757),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Theme & Appearance Selector Card ──────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD600).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isDark ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                              color: const Color(0xFFFFD600),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'App Theme & Display',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: context.textPrimaryColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isDark ? 'Currently Dark Theme (Institutional)' : 'Currently Light Theme (Daylight Clean)',
                                style: TextStyle(fontSize: 11, color: context.textSecondaryColor),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Switch.adaptive(
                        value: isDark,
                        activeThumbColor: const Color(0xFFFFD600),
                        activeTrackColor: const Color(0xFFFFD600).withValues(alpha: 0.4),
                        onChanged: (val) {
                          ref.read(themeProvider.notifier).setDark(val);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Side-by-side Dark / Light Option Selectors
                  Row(
                    children: [
                      // Dark Mode Card
                      Expanded(
                        child: InkWell(
                          onTap: () => ref.read(themeProvider.notifier).setDark(true),
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F141C),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? const Color(0xFFFFD600) : const Color(0xFF2B384E),
                                width: isDark ? 2.0 : 1.0,
                              ),
                              boxShadow: isDark
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFFFFD600).withValues(alpha: 0.15),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Icon(Icons.nightlight_round, color: Color(0xFFFFD600), size: 18),
                                    if (isDark)
                                      const Icon(Icons.check_circle, color: Color(0xFFFFD600), size: 16),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Dark Mode',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Institutional Charcoal',
                                  style: TextStyle(color: Color(0xFF848E9C), fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Light Mode Card
                      Expanded(
                        child: InkWell(
                          onTap: () => ref.read(themeProvider.notifier).setDark(false),
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: !isDark ? const Color(0xFF00C896) : const Color(0xFFCBD5E1),
                                width: !isDark ? 2.0 : 1.0,
                              ),
                              boxShadow: !isDark
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF00C896).withValues(alpha: 0.2),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Icon(Icons.wb_sunny_rounded, color: Color(0xFFFF9F43), size: 18),
                                    if (!isDark)
                                      const Icon(Icons.check_circle, color: Color(0xFF00C896), size: 16),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Light Mode',
                                  style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Daylight Clean',
                                  style: TextStyle(color: Color(0xFF64748B), fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Admin & Governance Desk Access Button (Admins Only) ───────
            if (user?.role == UserRole.admin) ...[
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2A2000), Color(0xFF151D28)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFD600), width: 1.2),
                ),
                child: ListTile(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AdminPortalScreen()),
                    );
                  },
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD600).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFFFFD600)),
                  ),
                  title: const Text(
                    'Multi-Desk Admin & Risk Portal',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: const Text(
                    'Super Administrator Controls',
                    style: TextStyle(fontSize: 11, color: Color(0xFF848E9C)),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFFFD600), size: 16),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Security & System Actions ──────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.borderColor),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.verified_user_outlined, color: Color(0xFF00D68F)),
                    title: Text('Two-Factor Authentication (2FA)', style: TextStyle(color: context.textPrimaryColor, fontSize: 13)),
                    trailing: const Text('ENABLED', style: TextStyle(color: Color(0xFF00D68F), fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                  Divider(color: context.borderColor, height: 1),
                  ListTile(
                    leading: Icon(Icons.lock_reset_rounded, color: context.textSecondaryColor),
                    title: Text('Change Security PIN', style: TextStyle(color: context.textPrimaryColor, fontSize: 13)),
                    trailing: Icon(Icons.chevron_right, color: context.textSecondaryColor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Log Out Button
            ElevatedButton.icon(
              onPressed: () {
                ref.read(authProvider.notifier).logout();
                context.go('/login');
              },
              icon: const Icon(Icons.logout_rounded, color: Color(0xFFFF4757), size: 18),
              label: const Text(
                'Logout',
                style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF4757), fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.cardBg,
                side: BorderSide(color: context.subtleBorderColor),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleChip(WidgetRef ref, UserRole? current, UserRole role, String label) {
    final isSelected = current == role;
    return GestureDetector(
      onTap: () {
        ref.read(authProvider.notifier).switchRole(role);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD600) : const Color(0xFF0F141C),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFD600) : const Color(0xFF2B384E),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.black : const Color(0xFF848E9C),
          ),
        ),
      ),
    );
  }
}
