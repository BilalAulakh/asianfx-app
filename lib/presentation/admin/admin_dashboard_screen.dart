import 'package:flutter/material.dart';
import '../../blocs/blocs.dart';
import '../../core/math/money_math.dart';
import '../../domain/entities/user_entity.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _userSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminCubit>().state;
    final adminNotifier = context.read<AdminCubit>();

    return Scaffold(
      backgroundColor: const Color(0xFF0F141C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E232A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD600).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFFD600), width: 1),
              ),
              child: const Text(
                'ADMIN PORTAL',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFFFD600),
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'FXAsian Control',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: const Color(0xFFFFD600),
          indicatorWeight: 3,
          labelColor: const Color(0xFFFFD600),
          unselectedLabelColor: const Color(0xFF848E9C),
          labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13),
          tabs: [
            const Tab(text: 'Overview'),
            Tab(
              child: Row(
                children: [
                  const Text('Finance'),
                  if (admin.pendingDepositsCount + admin.pendingWithdrawalsCount > 0) ...[
                    const SizedBox(width: 6),
                    _badge(admin.pendingDepositsCount + admin.pendingWithdrawalsCount),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                children: [
                  const Text('KYC'),
                  if (admin.pendingKycCount > 0) ...[
                    const SizedBox(width: 6),
                    _badge(admin.pendingKycCount),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Traders'),
            const Tab(text: 'Risk Controls'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(admin, adminNotifier),
          _buildFinanceTab(admin, adminNotifier),
          _buildKycTab(admin, adminNotifier),
          _buildTradersTab(admin, adminNotifier),
          _buildRiskControlsTab(admin, adminNotifier),
        ],
      ),
    );
  }

  Widget _badge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF6465D),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ── 1. Overview Tab ─────────────────────────────────────────────────────────
  Widget _buildOverviewTab(AdminState admin, AdminNotifier notifier) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Emergency trading alert if halted
          if (admin.isTradingHalted)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF6465D).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF6465D)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFF6465D), size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'TRADING IS CURRENTLY PAUSED BY ADMIN',
                      style: TextStyle(color: Color(0xFFF6465D), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // KPI Grid
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.45,
            children: [
              _kpiCard('Registered Traders', '${admin.totalUsersCount} Users', Icons.people_alt_rounded, const Color(0xFFFFD600)),
              _kpiCard('Total User Funds', '\$${admin.totalUserFunds.toStringAsFixed(2)}', Icons.account_balance_wallet_outlined, const Color(0xFF0ECB81)),
              _kpiCard('Pending Approvals', '${admin.pendingDepositsCount + admin.pendingWithdrawalsCount + admin.pendingKycCount}', Icons.pending_actions_rounded, const Color(0xFFFFB300)),
              _kpiCard('Total Approved In', '\$${admin.totalDeposited.toStringAsFixed(0)}', Icons.arrow_downward_rounded, const Color(0xFF0ECB81)),
            ],
          ),

          const SizedBox(height: 24),

          // Quick Action Shortcuts
          const Text(
            'Quick Actions',
            style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _actionButton(
                  title: 'Review Deposits (${admin.pendingDepositsCount})',
                  color: const Color(0xFF0ECB81),
                  icon: Icons.payments_outlined,
                  onTap: () => _tabController.animateTo(1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  title: 'Verify KYC (${admin.pendingKycCount})',
                  color: const Color(0xFFFFD600),
                  icon: Icons.verified_user_outlined,
                  onTap: () => _tabController.animateTo(2),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Platform Health
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E232A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2B313A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('System & Liquidity Status', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    Icon(Icons.check_circle_rounded, color: Color(0xFF0ECB81), size: 18),
                  ],
                ),
                const SizedBox(height: 12),
                _healthRow('Binance WebSocket Stream', 'Connected (Live)', const Color(0xFF0ECB81)),
                _healthRow('Total Registered Traders', '${admin.users.length} Active', Colors.white),
                _healthRow('Global Spread Multiplier', '${admin.spreadMultiplier}x', const Color(0xFFFFD600)),
                _healthRow('Max Platform Leverage', '1:${admin.maxLeverage}', Colors.white),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E232A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2B313A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Color(0xFF848E9C), fontSize: 11, fontWeight: FontWeight.w500)),
              Icon(icon, color: color, size: 18),
            ],
          ),
          Text(
            value,
            style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({required String title, required Color color, required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E232A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _healthRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF848E9C), fontSize: 12)),
          Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }

  // ── 2. Finance Tab (Deposits & Withdrawals) ─────────────────────────────────
  Widget _buildFinanceTab(AdminState admin, AdminNotifier notifier) {
    final children = <Widget>[
      // Instant Auto-Approval Gateway Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: admin.autoApproveTransactions
                ? const Color(0xFF0ECB81).withValues(alpha: 0.12)
                : const Color(0xFFFFD600).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: admin.autoApproveTransactions ? const Color(0xFF0ECB81) : const Color(0xFFFFD600),
            ),
          ),
          child: Row(
            children: [
              Icon(
                admin.autoApproveTransactions ? Icons.bolt_rounded : Icons.pause_circle_rounded,
                color: admin.autoApproveTransactions ? const Color(0xFF0ECB81) : const Color(0xFFFFD600),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      admin.autoApproveTransactions
                          ? 'INSTANT AUTO-APPROVAL: ACTIVE'
                          : 'MANUAL REVIEW MODE: ACTIVE',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: admin.autoApproveTransactions ? const Color(0xFF0ECB81) : const Color(0xFFFFD600),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      admin.autoApproveTransactions
                          ? 'Deposits & withdrawals are auto-approved & credited immediately to trading equity.'
                          : 'Transactions require manual review and approval before funds are credited.',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF848E9C)),
                    ),
                  ],
                ),
              ),
              Switch(
                value: admin.autoApproveTransactions,
                activeThumbColor: const Color(0xFF0ECB81),
                onChanged: (_) => notifier.toggleAutoApproveTransactions(),
              ),
            ],
          ),
        ),

        // Transactions List
        ...admin.transactions.map((tx) {
          final isDeposit = tx.type == 'DEPOSIT';
          final isPending = tx.status == AdminTxStatus.pending;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E232A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isPending ? const Color(0xFFFFD600).withValues(alpha: 0.5) : const Color(0xFF2B313A),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: Type, Amount & Status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDeposit
                                ? const Color(0xFF0ECB81).withValues(alpha: 0.15)
                                : const Color(0xFFF6465D).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tx.type,
                            style: TextStyle(
                              color: isDeposit ? const Color(0xFF0ECB81) : const Color(0xFFF6465D),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        if (tx.isAutoApproved || tx.status == AdminTxStatus.approved) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0ECB81).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF0ECB81), width: 0.8),
                            ),
                            child: const Text(
                              '⚡ AUTO',
                              style: TextStyle(
                                color: Color(0xFF0ECB81),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          tx.id,
                          style: const TextStyle(color: Color(0xFF848E9C), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Text(
                    '\$${tx.amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Row 2: User details & Payment Method
              Text(
                '${tx.userName} • ${tx.userEmail}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                'Method: ${tx.method}',
                style: const TextStyle(color: Color(0xFF848E9C), fontSize: 12),
              ),
              Text(
                'Ref: ${tx.accountOrAddress}',
                style: const TextStyle(color: Color(0xFF848E9C), fontSize: 12),
              ),

              if (tx.proofImageBytes != null) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (dialogCtx) => Dialog(
                        backgroundColor: const Color(0xFF1E2329),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Payment Proof (${tx.id})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Color(0xFF848E9C), size: 20),
                                    onPressed: () => Navigator.pop(dialogCtx),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxHeight: 400),
                                  child: Image.memory(tx.proofImageBytes!, fit: BoxFit.contain),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF14171A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF0ECB81).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.memory(tx.proofImageBytes!, width: 28, height: 28, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 8),
                        const Text('View Attached Screenshot Proof', style: TextStyle(color: Color(0xFF0ECB81), fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        const Icon(Icons.open_in_new_rounded, color: Color(0xFF0ECB81), size: 14),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),
              const Divider(color: Color(0xFF2B313A), height: 1),
              const SizedBox(height: 12),

              // Action Buttons or Status Badge
              if (isPending)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0ECB81),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Approve', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          // Money moves server-side through the audited admin RPC;
                          // the request is only marked approved once it succeeds.
                          final messenger = ScaffoldMessenger.of(context);
                          final engine = context.read<TradingEngineCubit>();
                          final walletCubit = context.read<WalletCubit>();
                          final walletBloc = context.read<WalletBloc>();
                          final isDeposit = tx.type == 'DEPOSIT';
                          final amt = MoneyMath.toDec(tx.amount);

                          try {
                            await engine.adminAdjustBalance(
                              userId: tx.userId,
                              amount: isDeposit ? amt : -amt,
                              reason: '${tx.type} #${tx.id} approved via admin dashboard',
                              requestId: 'admin-tx-${tx.id}',
                            );
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('${tx.type} #${tx.id} NOT settled: $e'),
                                backgroundColor: const Color(0xFFF6465D),
                              ),
                            );
                            return;
                          }

                          notifier.approveTransaction(tx.id);
                          if (isDeposit) {
                            walletCubit.creditDeposit(tx.amount, tx.method);
                            walletBloc.creditDeposit(tx.amount, tx.method, txId: tx.id);
                          } else {
                            walletCubit.debitWithdrawal(tx.amount, tx.method);
                          }
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('${tx.type} #${tx.id} for \$${tx.amount} APPROVED & CREDITED!'),
                              backgroundColor: const Color(0xFF0ECB81),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF6465D),
                          side: const BorderSide(color: Color(0xFFF6465D)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          notifier.rejectTransaction(tx.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${tx.type} #${tx.id} REJECTED'), backgroundColor: const Color(0xFFF6465D)),
                          );
                        },
                      ),
                    ),
                  ],
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: tx.status == AdminTxStatus.approved ? const Color(0xFF0ECB81).withValues(alpha: 0.15) : const Color(0xFFF6465D).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tx.status == AdminTxStatus.approved ? '✓ APPROVED & CREDITED' : '✗ REJECTED',
                    style: TextStyle(
                      color: tx.status == AdminTxStatus.approved ? const Color(0xFF0ECB81) : const Color(0xFFF6465D),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }

  // ── 3. KYC Tab ──────────────────────────────────────────────────────────────
  Widget _buildKycTab(AdminState admin, AdminNotifier notifier) {
    if (admin.kycRequests.isEmpty) {
      return const Center(child: Text('No KYC submissions', style: TextStyle(color: Color(0xFF848E9C))));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: admin.kycRequests.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final kyc = admin.kycRequests[i];
        final isPending = kyc.status == AdminKycStatus.pending;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E232A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPending ? const Color(0xFFFFD600).withValues(alpha: 0.5) : const Color(0xFF2B313A),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    kyc.userName,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPending ? const Color(0xFFFFD600).withValues(alpha: 0.2) : const Color(0xFF0ECB81).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isPending ? 'PENDING REVIEW' : 'VERIFIED',
                      style: TextStyle(
                        color: isPending ? const Color(0xFFFFD600) : const Color(0xFF0ECB81),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Email: ${kyc.userEmail}', style: const TextStyle(color: Color(0xFF848E9C), fontSize: 12)),
              Text('Document: ${kyc.docType} (${kyc.docNumber})', style: const TextStyle(color: Color(0xFF848E9C), fontSize: 12)),

              const SizedBox(height: 12),
              // Document Preview Placeholder
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F141C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2B313A)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.badge_outlined, color: Color(0xFFFFD600), size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Front & Back ID Verified by OCR Engine',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              if (isPending)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0ECB81),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.verified_rounded, size: 18),
                        label: const Text('Approve KYC', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          notifier.approveKyc(kyc.id, kyc.userId);
                          final currentUser = context.read<AuthCubit>().state.user;
                          if (currentUser != null && currentUser.id == kyc.userId) {
                            context.read<AuthCubit>().updateUserKyc(KycStatus.approved);
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${kyc.userName} KYC Approved! Trader can now place live orders.'), backgroundColor: const Color(0xFF0ECB81)),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF6465D),
                          side: const BorderSide(color: Color(0xFFF6465D)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.cancel_outlined, size: 18),
                        label: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          notifier.rejectKyc(kyc.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${kyc.userName} KYC Rejected'), backgroundColor: const Color(0xFFF6465D)),
                          );
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  // ── 4. Traders Tab ──────────────────────────────────────────────────────────
  Widget _buildTradersTab(AdminState admin, AdminNotifier notifier) {
    final filtered = admin.users.where((u) {
      if (_userSearchQuery.isEmpty) return true;
      return u.name.toLowerCase().contains(_userSearchQuery.toLowerCase()) ||
          u.email.toLowerCase().contains(_userSearchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        // Search Input
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            onChanged: (v) => setState(() => _userSearchQuery = v),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search traders by name, email...',
              hintStyle: const TextStyle(color: Color(0xFF848E9C), fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF848E9C), size: 20),
              filled: true,
              fillColor: const Color(0xFF1E232A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2B313A))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2B313A))),
            ),
          ),
        ),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final user = filtered[i];
              final isFrozen = user.status == AdminUserStatus.frozen;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E232A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isFrozen ? const Color(0xFFF6465D) : const Color(0xFF2B313A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFF2B313A),
                              child: Text(user.name[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(user.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                Text(user.email, style: const TextStyle(color: Color(0xFF848E9C), fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isFrozen ? const Color(0xFFF6465D).withValues(alpha: 0.2) : const Color(0xFF0ECB81).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isFrozen ? 'FROZEN' : 'ACTIVE',
                            style: TextStyle(
                              color: isFrozen ? const Color(0xFFF6465D) : const Color(0xFF0ECB81),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Balance', style: TextStyle(color: Color(0xFF848E9C), fontSize: 11)),
                            Text('\$${user.balance.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('KYC Status', style: TextStyle(color: Color(0xFF848E9C), fontSize: 11)),
                            Text(user.isKycVerified ? 'Verified' : 'Unverified', style: TextStyle(color: user.isKycVerified ? const Color(0xFF0ECB81) : const Color(0xFFF6465D), fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(isFrozen ? Icons.lock_open_rounded : Icons.lock_outline_rounded, color: isFrozen ? const Color(0xFF0ECB81) : const Color(0xFFF6465D)),
                              tooltip: isFrozen ? 'Unfreeze' : 'Freeze Account',
                              onPressed: () => notifier.toggleUserFreeze(user.id),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_card_rounded, color: Color(0xFFFFD600)),
                              tooltip: 'Credit / Debit',
                              onPressed: () => _showCreditModal(context, user, notifier),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showCreditModal(BuildContext context, AdminTraderUser user, AdminNotifier notifier) {
    final controller = TextEditingController(text: '100');
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E232A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Adjust Balance for ${user.name}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Amount (\$USD)',
                labelStyle: TextStyle(color: Color(0xFF848E9C)),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0ECB81), foregroundColor: Colors.black),
                    onPressed: () {
                      final val = double.tryParse(controller.text) ?? 0.0;
                      notifier.adjustUserBalance(user.id, val);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Add Funds (+)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF6465D), foregroundColor: Colors.white),
                    onPressed: () {
                      final val = double.tryParse(controller.text) ?? 0.0;
                      notifier.adjustUserBalance(user.id, -val);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Deduct Funds (-)'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 5. Risk Controls Tab ────────────────────────────────────────────────────
  Widget _buildRiskControlsTab(AdminState admin, AdminNotifier notifier) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Kill Switch
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E232A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: admin.isTradingHalted ? const Color(0xFFF6465D) : const Color(0xFF2B313A)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Global Trading Kill Switch', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      admin.isTradingHalted ? 'All orders paused' : 'Trading engine active',
                      style: TextStyle(color: admin.isTradingHalted ? const Color(0xFFF6465D) : const Color(0xFF0ECB81), fontSize: 12),
                    ),
                  ],
                ),
                Switch(
                  value: admin.isTradingHalted,
                  activeThumbColor: const Color(0xFFF6465D),
                  onChanged: (_) => notifier.toggleTradingHalt(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Spread Multiplier
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E232A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2B313A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Global Spread Multiplier', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('${admin.spreadMultiplier.toStringAsFixed(1)}x', style: const TextStyle(color: Color(0xFFFFD600), fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 8),
                Slider(
                  value: admin.spreadMultiplier,
                  min: 0.5,
                  max: 3.0,
                  divisions: 25,
                  activeColor: const Color(0xFFFFD600),
                  onChanged: (v) => notifier.setSpreadMultiplier(v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Max Platform Leverage
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E232A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2B313A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Maximum Platform Leverage', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [100, 200, 500, 1000].map((lev) {
                    final isSel = admin.maxLeverage == lev;
                    return ChoiceChip(
                      label: Text('1:$lev', style: TextStyle(color: isSel ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
                      selected: isSel,
                      selectedColor: const Color(0xFFFFD600),
                      backgroundColor: const Color(0xFF0F141C),
                      onSelected: (_) => notifier.setMaxLeverage(lev),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
