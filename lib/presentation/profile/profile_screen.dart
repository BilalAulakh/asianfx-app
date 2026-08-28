import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/math/money_math.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/user_entity.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ledger_provider.dart';
import '../admin/admin_portal_screen.dart';
import '../kyc/kyc_flow_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final balance = ref.watch(clientLedgerBalanceProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151D28),
        elevation: 0,
        title: const Text(
          'Institutional Account & Profile',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
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
                color: const Color(0xFF151D28),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF1C2535)),
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
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user?.email ?? 'trader@asianfx.institutional',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF848E9C)),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD600).withOpacity(0.15),
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
                  const Divider(color: Color(0xFF1C2535), height: 1),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'KYC Compliance State:',
                        style: TextStyle(fontSize: 12, color: Color(0xFF848E9C)),
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
                                ? const Color(0xFF00D68F).withOpacity(0.2)
                                : const Color(0xFFFF4757).withOpacity(0.2),
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

            // ── Admin & Governance Desk Access Button ──────────────────────
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
                    color: const Color(0xFFFFD600).withOpacity(0.2),
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
                  'Trader • Admin Controls',
                  style: TextStyle(fontSize: 11, color: Color(0xFF848E9C)),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFFFD600), size: 16),
              ),
            ),
            const SizedBox(height: 16),

            // ── Quick Role Switcher (Preview Simulator) ─────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF151D28),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1C2535)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Multi-Role Switcher',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Switch between Trader and Admin views:',
                    style: TextStyle(fontSize: 11, color: Color(0xFF848E9C)),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _roleChip(ref, user?.role, UserRole.client, 'Trader'),
                      _roleChip(ref, user?.role, UserRole.admin, 'Admin'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Security & System Actions ──────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF151D28),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1C2535)),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.verified_user_outlined, color: Color(0xFF00D68F)),
                    title: const Text('Two-Factor Authentication (2FA)', style: TextStyle(color: Colors.white, fontSize: 13)),
                    trailing: const Text('ENABLED', style: TextStyle(color: Color(0xFF00D68F), fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                  const Divider(color: Color(0xFF1C2535), height: 1),
                  ListTile(
                    leading: const Icon(Icons.lock_reset_rounded, color: Colors.white70),
                    title: const Text('Change Security PIN', style: TextStyle(color: Colors.white, fontSize: 13)),
                    trailing: const Icon(Icons.chevron_right, color: Color(0xFF848E9C)),
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
                'LOG OUT OF INSTITUTIONAL TERMINAL',
                style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF4757)),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF151D28),
                side: const BorderSide(color: Color(0xFF2B384E)),
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
