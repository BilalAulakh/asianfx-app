import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../blocs/blocs.dart';
import '../../core/policy/kyc_policy.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/kyc_entities.dart';
import '../../domain/entities/user_entity.dart';
import '../admin/admin_portal_screen.dart';
import '../kyc/kyc_flow_screen.dart';
import 'widgets/change_security_pin_sheet.dart';
import 'widgets/two_factor_auth_sheet.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    final isDark = context.watch<ThemeCubit>().state;
    final kycState = context.watch<KycCubit>().state;
    final kycStatus = kycState.activeProfile?.status ?? KycPolicy.mapFromUser(user);
    final kycColor = KycPolicy.getStatusColor(kycStatus);

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        backgroundColor: context.headerBg,
        elevation: 0,
        title: Text(
          'Account & Profile',
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
            onPressed: () => context.read<ThemeCubit>().toggleTheme(),
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
                              user?.fullName ?? 'Trader',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: context.textPrimaryColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user?.email ?? 'trader@asianfx.com',
                              style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
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
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: kycColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: kycColor),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                kycStatus.code,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: kycColor,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.chevron_right, size: 14, color: kycColor),
                            ],
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
                                isDark ? 'Currently Dark Theme' : 'Currently Light Theme (Daylight Clean)',
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
                          context.read<ThemeCubit>().setDark(val);
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
                          onTap: () => context.read<ThemeCubit>().setDark(true),
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
                                  'Charcoal Dark',
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
                          onTap: () => context.read<ThemeCubit>().setDark(false),
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
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const KycFlowScreen()),
                      );
                    },
                    leading: Icon(
                      kycStatus == KycVerificationStatus.approved
                          ? Icons.verified_user_rounded
                          : Icons.badge_outlined,
                      color: kycColor,
                    ),
                    title: Text(
                      'Identity & Address Verification (KYC)',
                      style: TextStyle(
                        color: context.textPrimaryColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      KycPolicy.getStatusExplanation(kycStatus),
                      style: TextStyle(fontSize: 11, color: context.textSecondaryColor),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: kycColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: kycColor),
                      ),
                      child: Text(
                        kycStatus.code,
                        style: TextStyle(
                          color: kycColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  Divider(color: context.borderColor, height: 1),
                  ListTile(
                    onTap: () {
                      final email = user?.email ?? 'trader@asianfx.com';
                      TwoFactorAuthSheet.show(
                        context,
                        userEmail: email,
                        isCurrentlyEnabled: user?.isTwoFactorEnabled ?? false,
                      );
                    },
                    leading: Icon(
                      user?.isTwoFactorEnabled == true
                          ? Icons.verified_user_rounded
                          : Icons.security_outlined,
                      color: user?.isTwoFactorEnabled == true
                          ? const Color(0xFF00D68F)
                          : const Color(0xFFFF9F43),
                    ),
                    title: Text(
                      'Two-Factor Authentication (2FA)',
                      style: TextStyle(
                        color: context.textPrimaryColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      user?.isTwoFactorEnabled == true
                          ? 'Protected with Authenticator'
                          : 'Tap to enable extra account defense',
                      style: TextStyle(fontSize: 11, color: context.textSecondaryColor),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (user?.isTwoFactorEnabled == true
                                ? const Color(0xFF00D68F)
                                : const Color(0xFFFF9F43))
                            .withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: user?.isTwoFactorEnabled == true
                              ? const Color(0xFF00D68F)
                              : const Color(0xFFFF9F43),
                        ),
                      ),
                      child: Text(
                        user?.isTwoFactorEnabled == true ? 'ENABLED' : 'DISABLED',
                        style: TextStyle(
                          color: user?.isTwoFactorEnabled == true
                              ? const Color(0xFF00D68F)
                              : const Color(0xFFFF9F43),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  Divider(color: context.borderColor, height: 1),
                  ListTile(
                    onTap: () {
                      final email = user?.email ?? 'trader@asianfx.com';
                      ChangeSecurityPinSheet.show(context, email);
                    },
                    leading: const Icon(Icons.lock_reset_rounded, color: Color(0xFFFFD600)),
                    title: Text(
                      'Change Security PIN',
                      style: TextStyle(
                        color: context.textPrimaryColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Manage 4-digit security code',
                      style: TextStyle(fontSize: 11, color: context.textSecondaryColor),
                    ),
                    trailing: Icon(Icons.chevron_right, color: context.textSecondaryColor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Log Out Button
            ElevatedButton.icon(
              onPressed: () {
                context.read<AuthBloc>().logout();
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
}
