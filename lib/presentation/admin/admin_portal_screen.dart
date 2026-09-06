import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/math/money_math.dart';
import '../../core/router/app_router.dart';
import '../../domain/entities/dealing_entities.dart';
import '../../domain/entities/ledger_entities.dart';
import '../../domain/entities/trading_entities.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dealing_desk_provider.dart';
import '../../providers/kyc_compliance_provider.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/trading_engine_provider.dart';
import '../../providers/wallet_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminPortalScreen extends ConsumerStatefulWidget {
  const AdminPortalScreen({super.key});

  @override
  ConsumerState<AdminPortalScreen> createState() => _AdminPortalScreenState();
}

class _AdminPortalScreenState extends ConsumerState<AdminPortalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _userSearchQuery = '';
  String _financeFilter = 'ALL'; // ALL, DEPOSIT, WITHDRAWAL

  bool get _isDark => ref.watch(themeProvider);
  Color get _bg => _isDark ? const Color(0xFF0A0E17) : const Color(0xFFF1F5F9);
  Color get _appBarBg => _isDark ? const Color(0xFF151D28) : Colors.white;
  Color get _cardBg => _isDark ? const Color(0xFF151D28) : Colors.white;
  Color get _subCardBg => _isDark ? const Color(0xFF0F141C) : const Color(0xFFF8FAFC);
  Color get _borderColor => _isDark ? const Color(0xFF1C2535) : const Color(0xFFE2E8F0);
  Color get _subtleBorder => _isDark ? const Color(0xFF2B384E) : const Color(0xFFCBD5E1);
  Color get _textPrimary => _isDark ? Colors.white : const Color(0xFF0F172A);
  Color get _textSecondary => _isDark ? const Color(0xFF848E9C) : const Color(0xFF64748B);
  Color get _goldAccent => _isDark ? const Color(0xFFFFD600) : const Color(0xFFD97706);
  Color get _goldText => _isDark ? const Color(0xFFFFD600) : const Color(0xFFB45309);
  Color get _goldBg => _isDark ? const Color(0xFFFFD600).withValues(alpha: 0.2) : const Color(0xFFFEF3C7);
  Color get _goldBorder => _isDark ? const Color(0xFFFFD600).withValues(alpha: 0.4) : const Color(0xFFFDE68A);
  Color get _goldSlider => _isDark ? const Color(0xFFFFD600) : const Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dealerRisk = ref.watch(dealingDeskProvider);
    final admin = ref.watch(adminProvider);
    final adminNotifier = ref.read(adminProvider.notifier);
    final complianceState = ref.watch(kycComplianceProvider);
    final treasuryProof = ref.watch(treasuryAuditProofProvider);
    final isDark = _isDark;
    final pendingFinanceCount = admin.pendingDepositsCount + admin.pendingWithdrawalsCount;
    final pendingKycCount = admin.pendingKycCount + complianceState.pendingApplications.length;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _appBarBg,
        elevation: isDark ? 0 : 1,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        leading: Center(
          child: Icon(Icons.shield_rounded, color: _goldAccent, size: 24),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _goldBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _goldBorder),
              ),
              child: Text(
                'MARKET MAKER DESK',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: _goldText,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Institutional Broker Portal',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // Quick Halt Trading Status
          if (admin.isTradingHalted)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF4757).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFF4757)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFFF4757), size: 14),
                  SizedBox(width: 4),
                  Text('CIRCUIT HALTED', style: TextStyle(color: Color(0xFFFF4757), fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: _goldAccent,
              size: 20,
            ),
            tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            onPressed: () => ref.read(themeProvider.notifier).toggleTheme(),
          ),
          IconButton(
            icon: Icon(Icons.logout_rounded, color: _textSecondary, size: 20),
            tooltip: 'Logout',
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) {
                context.go(AppRoutes.login);
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              color: _appBarBg,
              border: Border(bottom: BorderSide(color: _borderColor)),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: _goldAccent,
              indicatorWeight: 3,
              labelColor: _goldAccent,
              unselectedLabelColor: _textSecondary,
              labelStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 12),
              tabs: [
                const Tab(
                  child: Row(
                    children: [
                      Icon(Icons.tune_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('Dealing Desk (MM)'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined, size: 16),
                      const SizedBox(width: 6),
                      const Text('Finance Desk'),
                      if (pendingFinanceCount > 0) ...[
                        const SizedBox(width: 6),
                        _badge(pendingFinanceCount, const Color(0xFFFFB300)),
                      ],
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    children: [
                      const Icon(Icons.people_outline_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text('Trader CRM (${admin.users.length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    children: [
                      const Icon(Icons.verified_user_outlined, size: 16),
                      const SizedBox(width: 6),
                      const Text('KYC & AML'),
                      if (pendingKycCount > 0) ...[
                        const SizedBox(width: 6),
                        _badge(pendingKycCount, const Color(0xFFFF4757)),
                      ],
                    ],
                  ),
                ),
                const Tab(
                  child: Row(
                    children: [
                      Icon(Icons.speed_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('Risk & Leverage'),
                    ],
                  ),
                ),
                const Tab(
                  child: Row(
                    children: [
                      Icon(Icons.fact_check_outlined, size: 16),
                      SizedBox(width: 6),
                      Text('Treasury & Proof'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 1. Chief Dealer & Market Maker Tab
          _buildDealingDeskTab(dealerRisk, admin, adminNotifier),

          // 2. Finance Desk Tab (Deposits / Withdrawals)
          _buildFinanceDeskTab(admin, adminNotifier),

          // 3. Trader CRM & User Accounts Tab
          _buildTraderCrmTab(admin, adminNotifier),

          // 4. KYC & AML Compliance Tab
          _buildComplianceTab(complianceState, admin, adminNotifier),

          // 5. Risk Engine & Leverage Tab
          _buildRiskEngineTab(admin, adminNotifier),

          // 6. Treasury & Audit Proof Tab
          _buildTreasuryTab(treasuryProof),
        ],
      ),
    );
  }

  static Widget _badge(int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 1. DEALING DESK & MARKET MAKER TAB
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildDealingDeskTab(DealerRiskSummary risk, AdminState admin, AdminNotifier adminNotifier) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Global Exposure & House PnL Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isDark
                    ? const [Color(0xFF1E2838), Color(0xFF101722)]
                    : const [Colors.white, Color(0xFFF8FAFC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _subtleBorder),
              boxShadow: _isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HOUSE B-BOOK PnL (INTERNALIZED)',
                          style: TextStyle(fontSize: 11, color: _textSecondary, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          MoneyMath.formatPnL(risk.aggregateHouseFloatingPnl),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: risk.aggregateHouseFloatingPnl >= Decimal.zero
                                ? const Color(0xFF00D68F)
                                : const Color(0xFFFF4757),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'SPREAD REVENUE EARNED',
                          style: TextStyle(fontSize: 11, color: _textSecondary, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          MoneyMath.formatCurrency(risk.feeRevenueEarned),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _goldAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(color: _subtleBorder, height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _dealerStat('Gross Exposure', '${risk.totalGrossExposureLots.toDouble().toStringAsFixed(2)} Lots'),
                    _dealerStat('Net Exposure', '${risk.totalNetExposureLots.toDouble().toStringAsFixed(2)} Lots'),
                    _dealerStat('Open Positions', '${risk.totalOpenPositions}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Live Instrument Risk & Spread Markup Control',
                style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: _textPrimary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _borderColor),
                ),
                child: const Text('AUTO-REBALANCING ON', style: TextStyle(color: Color(0xFF00D68F), fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Per-Symbol Exposure & Spread Markup Sliders
          ...risk.instrumentExposures.map((exp) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _borderColor),
                boxShadow: _isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        exp.symbol,
                        style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: _textPrimary),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: exp.routing == ExecutionRouting.bBookInternal
                              ? _goldBg
                              : (_isDark ? const Color(0xFF00D68F).withValues(alpha: 0.2) : const Color(0xFFD1FAE5)),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: exp.routing == ExecutionRouting.bBookInternal
                                ? _goldBorder
                                : (_isDark ? const Color(0xFF00D68F).withValues(alpha: 0.3) : const Color(0xFFA7F3D0)),
                          ),
                        ),
                        child: Text(
                          exp.routing == ExecutionRouting.bBookInternal ? 'B-BOOK INTERNAL' : 'A-BOOK STP',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: exp.routing == ExecutionRouting.bBookInternal
                                ? _goldText
                                : (_isDark ? const Color(0xFF00D68F) : const Color(0xFF059669)),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Net: ${exp.netExposureLots >= Decimal.zero ? '+' : ''}${exp.netExposureLots.toDouble().toStringAsFixed(2)} Lots',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: exp.netExposureLots >= Decimal.zero ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text('Long: ${exp.totalLongLots.toDouble().toStringAsFixed(2)}L', style: TextStyle(fontSize: 11, color: _textSecondary)),
                      const SizedBox(width: 12),
                      Text('Short: ${exp.totalShortLots.toDouble().toStringAsFixed(2)}L', style: TextStyle(fontSize: 11, color: _textSecondary)),
                      const Spacer(),
                      Text(
                        'Markup: +${(exp.spreadMarkupPips / 10.0).toStringAsFixed(1)} pips',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _goldText),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: _goldSlider,
                      inactiveTrackColor: _subtleBorder,
                      thumbColor: _goldSlider,
                      overlayColor: _goldSlider.withValues(alpha: 0.2),
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: exp.spreadMarkupPips.toDouble().clamp(0.0, 50.0),
                      min: 0.0,
                      max: 50.0,
                      divisions: 50,
                      onChanged: (val) {
                        ref.read(dealingDeskProvider.notifier).updateSpreadMarkup(
                              exp.symbol,
                              val.toInt(),
                            );
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          ref.read(dealingDeskProvider.notifier).toggleRoutingMode(exp.symbol);
                        },
                        icon: Icon(Icons.swap_horiz, size: 14, color: _textSecondary),
                        label: Text(
                          exp.routing == ExecutionRouting.bBookInternal ? 'Switch to A-Book STP' : 'Switch to B-Book Internal',
                          style: TextStyle(fontSize: 11, color: _textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 2. FINANCE DESK TAB (DEPOSITS & WITHDRAWALS)
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildFinanceDeskTab(AdminState admin, AdminNotifier adminNotifier) {
    final filteredTxs = admin.transactions.where((tx) {
      if (_financeFilter == 'DEPOSIT') return tx.type == 'DEPOSIT';
      if (_financeFilter == 'WITHDRAWAL') return tx.type == 'WITHDRAWAL';
      return true;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Finance Summary Cards
          Row(
            children: [
              Expanded(
                child: _summaryCard('Total Deposited', '\$${admin.totalDeposited.toStringAsFixed(2)}', const Color(0xFF00D68F), Icons.arrow_downward_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryCard('Total Withdrawn', '\$${admin.totalWithdrawn.toStringAsFixed(2)}', const Color(0xFFFF4757), Icons.arrow_upward_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryCard('Pending Action', '${admin.pendingDepositsCount + admin.pendingWithdrawalsCount}', const Color(0xFFFFB300), Icons.pending_actions_rounded),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Filter bar
          Row(
            children: [
              Text(
                'Transaction Requests',
                style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: _textPrimary),
              ),
              const SizedBox(width: 8),
              if (admin.transactions.any((tx) => tx.id.startsWith('TX-948')))
                InkWell(
                  onTap: () {
                    adminNotifier.clearDemoTransactions();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Demo transactions removed! Queue is now clean.'),
                        backgroundColor: _cardBg,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4757).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFFF4757).withValues(alpha: 0.4)),
                    ),
                    child: const Text(
                      'Clear Demo Data',
                      style: TextStyle(color: Color(0xFFFF4757), fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              const Spacer(),
              _filterChip('ALL', 'All'),
              const SizedBox(width: 6),
              _filterChip('DEPOSIT', 'Deposits (${admin.pendingDepositsCount})'),
              const SizedBox(width: 6),
              _filterChip('WITHDRAWAL', 'Withdrawals (${admin.pendingWithdrawalsCount})'),
            ],
          ),
          const SizedBox(height: 12),

          if (filteredTxs.isEmpty)
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _borderColor),
              ),
              child: Center(
                child: Text('No transactions in this queue.', style: TextStyle(color: _textSecondary)),
              ),
            )
          else
            ...filteredTxs.map((tx) {
              final isPending = tx.status == AdminTxStatus.pending;
              final isDeposit = tx.type == 'DEPOSIT';
              final hasProof = tx.proofImageBytes != null || (tx.proofImageName != null && tx.proofImageName!.isNotEmpty);

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isPending
                        ? (isDeposit ? const Color(0xFF00D68F).withValues(alpha: 0.5) : const Color(0xFFFF4757).withValues(alpha: 0.5))
                        : _borderColor,
                  ),
                  boxShadow: _isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
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
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isDeposit ? const Color(0xFF00D68F).withValues(alpha: 0.15) : const Color(0xFFFF4757).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                tx.type,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isDeposit ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              tx.userName,
                              style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.bold, color: _textPrimary),
                            ),
                          ],
                        ),
                        Text(
                          '\$${tx.amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: isDeposit ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Method: ${tx.method}', style: TextStyle(fontSize: 11, color: _textPrimary, fontWeight: FontWeight.w500)),
                    Text('Account / Hash: ${tx.accountOrAddress}', style: TextStyle(fontSize: 11, color: _textSecondary)),
                    Text('Email: ${tx.userEmail} • ${DateFormat('yyyy-MM-dd HH:mm').format(tx.createdAt)}', style: TextStyle(fontSize: 10, color: _textSecondary)),
                    const SizedBox(height: 10),

                    // ── Screenshot Verification Card ─────────────────────────
                    if (hasProof)
                      InkWell(
                        onTap: () => _showProofInspectionDialog(context, tx, adminNotifier),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _subCardBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF00D68F).withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  color: Colors.black12,
                                  child: tx.proofImageBytes != null
                                      ? Image.memory(tx.proofImageBytes!, fit: BoxFit.cover)
                                      : Image.network(
                                          (tx.proofImageName!.startsWith('http://') || tx.proofImageName!.startsWith('https://'))
                                              ? tx.proofImageName!
                                              : Supabase.instance.client.storage.from('reciept-proof').getPublicUrl(tx.proofImageName!),
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.receipt_long_rounded, color: Color(0xFF00D68F), size: 22),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Payment Proof Slip',
                                          style: TextStyle(color: _textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF00D68F).withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            '✓ ATTACHED',
                                            style: TextStyle(color: Color(0xFF00D68F), fontSize: 9, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      tx.proofImageName ?? 'Attached Screenshot Slip',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: _textSecondary, fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00D68F).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.zoom_in_rounded, size: 14, color: Color(0xFF00D68F)),
                                    SizedBox(width: 4),
                                    Text('Inspect', style: TextStyle(color: Color(0xFF00D68F), fontSize: 11, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _subCardBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _borderColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.image_not_supported_outlined, size: 13, color: _textSecondary),
                            const SizedBox(width: 6),
                            Text('No slip attached (Manual / Demo Request)', style: TextStyle(color: _textSecondary, fontSize: 10)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),

                    if (isPending)
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _executeApproval(tx, adminNotifier),
                              icon: const Icon(Icons.check_circle_outline, size: 15),
                              label: const Text('APPROVE & CREDIT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00D68F),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                adminNotifier.rejectTransaction(tx.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('${tx.type} #${tx.id} rejected.'),
                                    backgroundColor: const Color(0xFFFF4757),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.cancel_outlined, size: 15),
                              label: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFFF4757),
                                side: const BorderSide(color: Color(0xFFFF4757)),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: tx.status == AdminTxStatus.approved ? const Color(0xFF00D68F).withValues(alpha: 0.1) : const Color(0xFFFF4757).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tx.status == AdminTxStatus.approved ? '✓ SETTLED / APPROVED' : '✗ REJECTED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: tx.status == AdminTxStatus.approved ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    final isSelected = _financeFilter == key;
    return GestureDetector(
      onTap: () => setState(() => _financeFilter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? _goldSlider : _cardBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? _goldSlider : _borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isSelected ? (_isDark ? Colors.black : Colors.white) : _textSecondary,
          ),
        ),
      ),
    );
  }

  void _showProofInspectionDialog(BuildContext context, AdminTransaction tx, AdminNotifier adminNotifier) {
    final hasBytes = tx.proofImageBytes != null && tx.proofImageBytes!.isNotEmpty;
    final hasName = tx.proofImageName != null && tx.proofImageName!.isNotEmpty;
    final isUrl = hasName && (tx.proofImageName!.startsWith('http://') || tx.proofImageName!.startsWith('https://'));
    final proofUrl = hasName
        ? (isUrl ? tx.proofImageName! : Supabase.instance.client.storage.from('reciept-proof').getPublicUrl(tx.proofImageName!))
        : null;

    final isPending = tx.status == AdminTxStatus.pending;
    final isDeposit = tx.type == 'DEPOSIT';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Dialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _borderColor)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 780),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: _subCardBg,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(bottom: BorderSide(color: _borderColor)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDeposit ? const Color(0xFF00D68F).withValues(alpha: 0.15) : const Color(0xFFFF4757).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tx.type,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: isDeposit ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Payment Proof Verification • #${tx.id}',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Trader: ${tx.userName} (${tx.userEmail})',
                            style: TextStyle(fontSize: 11, color: _textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '\$${tx.amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: isDeposit ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.close, color: _textSecondary, size: 20),
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                    ),
                  ],
                ),
              ),

              // Image inspection area with zoom
              Expanded(
                child: Container(
                  color: _isDark ? const Color(0xFF0A0E17) : const Color(0xFFF1F5F9),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 5.0,
                        child: Center(
                          child: hasBytes
                              ? Image.memory(
                                  tx.proofImageBytes!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) => _imageFallback(),
                                )
                              : (proofUrl != null
                                  ? Image.network(
                                      proofUrl,
                                      fit: BoxFit.contain,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return const Center(
                                          child: CircularProgressIndicator(color: Color(0xFF00D68F), strokeWidth: 2),
                                        );
                                      },
                                      errorBuilder: (context, error, stackTrace) => _imageFallback(),
                                    )
                                  : _imageFallback()),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF2B384E)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.pinch_outlined, size: 14, color: Color(0xFFFFD600)),
                              SizedBox(width: 4),
                              Text(
                                'Pinch / Scroll to Zoom (Up to 5x)',
                                style: TextStyle(color: Color(0xFFFFD600), fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Transaction & Proof Metadata
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _subCardBg,
                  border: Border(top: BorderSide(color: _borderColor)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _miniInfo('Method', tx.method, _textPrimary),
                        ),
                        Expanded(
                          child: _miniInfo('Submitted At', DateFormat('yyyy-MM-dd HH:mm').format(tx.createdAt), _textSecondary),
                        ),
                        Expanded(
                          child: _miniInfo(
                            'Status',
                            tx.status.name.toUpperCase(),
                            tx.status == AdminTxStatus.approved
                                ? const Color(0xFF00D68F)
                                : (tx.status == AdminTxStatus.rejected ? const Color(0xFFFF4757) : const Color(0xFFFFB300)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _cardBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _borderColor),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.link_rounded, size: 14, color: _textSecondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Target Account / Address: ${tx.accountOrAddress}',
                              style: const TextStyle(fontFamily: 'Courier', fontSize: 11, color: Color(0xFFFFD600)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Action buttons (Approve / Reject)
              if (isPending)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                    border: Border(top: BorderSide(color: _borderColor)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            adminNotifier.rejectTransaction(tx.id);
                            Navigator.of(dialogCtx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${tx.type} #${tx.id} rejected.'),
                                backgroundColor: const Color(0xFFFF4757),
                              ),
                            );
                          },
                          icon: const Icon(Icons.cancel_outlined, size: 16),
                          label: const Text('REJECT REQUEST', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF4757),
                            side: const BorderSide(color: Color(0xFFFF4757)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(dialogCtx).pop();
                            _executeApproval(tx, adminNotifier);
                          },
                          icon: const Icon(Icons.check_circle_outline, size: 16),
                          label: const Text('APPROVE & CREDIT BALANCE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00D68F),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageFallback() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.broken_image_outlined, size: 48, color: _textSecondary),
        const SizedBox(height: 8),
        Text('Screenshot preview unavailable', style: TextStyle(color: _textSecondary, fontSize: 13)),
      ],
    );
  }

  void _executeApproval(AdminTransaction tx, AdminNotifier adminNotifier) {
    adminNotifier.approveTransaction(tx.id);

    final amtDec = MoneyMath.toDec(tx.amount);

    if (tx.type == 'DEPOSIT') {
      // 1. Credit trading engine ledger balance
      ref.read(tradingEngineProvider.notifier).depositFunds(tx.userId, amtDec);

      // 2. Credit double-entry ledger provider
      ref.read(ledgerProvider.notifier).deposit(
            userId: tx.userId,
            amount: amtDec,
            method: tx.method,
          );

      // 3. Credit wallet provider balance
      ref.read(walletProvider.notifier).creditDeposit(tx.amount, tx.method);

      // 4. Update Supabase wallets table
      try {
        final newTotal = (ref.read(tradingEngineProvider).accountState.ledgerBalance).toDouble();
        Supabase.instance.client.from('wallets').upsert({
          'user_id': tx.userId,
          'currency': tx.currency,
          'balance': newTotal,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,currency').catchError((err) {
          debugPrint('Supabase wallet update error: $err');
        });
      } catch (e) {
        debugPrint('Supabase wallet update exception: $e');
      }
    } else if (tx.type == 'WITHDRAWAL') {
      // For withdrawal, debit trading engine and wallet if not yet debited
      ref.read(tradingEngineProvider.notifier).withdrawFunds(tx.userId, amtDec);
      ref.read(ledgerProvider.notifier).withdraw(
            userId: tx.userId,
            amount: amtDec,
            destinationAddress: tx.accountOrAddress,
          );
      ref.read(walletProvider.notifier).debitWithdrawal(tx.amount, tx.method);

      try {
        final newTotal = (ref.read(tradingEngineProvider).accountState.ledgerBalance).toDouble();
        Supabase.instance.client.from('wallets').upsert({
          'user_id': tx.userId,
          'currency': tx.currency,
          'balance': newTotal,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,currency').catchError((err) {
          debugPrint('Supabase wallet update error: $err');
        });
      } catch (e) {
        debugPrint('Supabase wallet update exception: $e');
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF00D68F),
        content: Text(
          '✓ ${tx.type} #${tx.id} for \$${tx.amount.toStringAsFixed(2)} approved & funds settled!',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 3. TRADER CRM & USER CONTROL TAB
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildTraderCrmTab(AdminState admin, AdminNotifier adminNotifier) {
    final filteredUsers = admin.users.where((u) {
      if (_userSearchQuery.isEmpty) return true;
      final q = _userSearchQuery.toLowerCase();
      return u.name.toLowerCase().contains(q) || u.email.toLowerCase().contains(q) || u.phone.contains(q);
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search input
          TextField(
            onChanged: (val) => setState(() => _userSearchQuery = val),
            style: TextStyle(color: _textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search trader by name, email, or phone...',
              hintStyle: TextStyle(color: _textSecondary, fontSize: 13),
              prefixIcon: Icon(Icons.search, color: _textSecondary, size: 18),
              filled: true,
              fillColor: _cardBg,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _borderColor)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _borderColor)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _goldAccent)),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Traders List (${filteredUsers.length})', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: _textPrimary)),
              Text('Total Client Funds: \$${admin.totalUserFunds.toStringAsFixed(2)}', style: TextStyle(fontSize: 12, color: _goldAccent, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),

          ...filteredUsers.map((u) {
            final isFrozen = u.status == AdminUserStatus.frozen;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isFrozen ? const Color(0xFFFF4757).withValues(alpha: 0.6) : _borderColor),
                boxShadow: _isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
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
                            radius: 14,
                            backgroundColor: _goldBg,
                            child: Text(u.name.isNotEmpty ? u.name[0] : 'U', style: TextStyle(color: _goldText, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(u.name, style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.bold, color: _textPrimary)),
                              Text(u.email, style: TextStyle(fontSize: 10, color: _textSecondary)),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isFrozen ? const Color(0xFFFF4757).withValues(alpha: 0.2) : const Color(0xFF00D68F).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isFrozen ? 'FROZEN' : 'ACTIVE',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isFrozen ? const Color(0xFFFF4757) : const Color(0xFF00D68F)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _miniInfo('Balance', '\$${u.balance.toStringAsFixed(2)}', const Color(0xFF00D68F)),
                      ),
                      Expanded(
                        child: _miniInfo('Equity', '\$${u.equity.toStringAsFixed(2)}', _textPrimary),
                      ),
                      Expanded(
                        child: _miniInfo('KYC Status', u.isKycVerified ? 'Verified' : 'Unverified', u.isKycVerified ? const Color(0xFF00D68F) : const Color(0xFFFFB300)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Divider(color: _borderColor, height: 1),
                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _showCreditDialog(context, u, adminNotifier),
                        icon: Icon(Icons.add_card, size: 14, color: _goldAccent),
                        label: Text('Adjust Balance / Bonus', style: TextStyle(color: _goldAccent, fontSize: 11)),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () {
                          adminNotifier.toggleUserFreeze(u.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(isFrozen ? '${u.name} has been ACTIVATED' : '${u.name} has been FROZEN'),
                              backgroundColor: isFrozen ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                            ),
                          );
                        },
                        icon: Icon(isFrozen ? Icons.lock_open : Icons.lock_outline, size: 14, color: isFrozen ? const Color(0xFF00D68F) : const Color(0xFFFF4757)),
                        label: Text(
                          isFrozen ? 'Unfreeze Account' : 'Freeze Account',
                          style: TextStyle(color: isFrozen ? const Color(0xFF00D68F) : const Color(0xFFFF4757), fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _showCreditDialog(BuildContext context, AdminTraderUser user, AdminNotifier notifier) {
    final controller = TextEditingController(text: '100');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        title: Text('Adjust Balance: ${user.name}', style: TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current Balance: \$${user.balance.toStringAsFixed(2)}', style: TextStyle(color: _textSecondary, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              style: TextStyle(color: _textPrimary),
              decoration: InputDecoration(
                labelText: 'Amount (e.g. +500 or -200)',
                labelStyle: TextStyle(color: _goldAccent),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: _textSecondary))),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text) ?? 0.0;
              notifier.adjustUserBalance(user.id, val);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Balance adjusted by \$${val.toStringAsFixed(2)} for ${user.name}'), backgroundColor: const Color(0xFF00D68F)),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: _goldSlider, foregroundColor: _isDark ? Colors.black : Colors.white),
            child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 4. KYC & AML COMPLIANCE TAB
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildComplianceTab(ComplianceState state, AdminState admin, AdminNotifier adminNotifier) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Pending KYC Identity Verification Queue',
          style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: _textPrimary),
        ),
        const SizedBox(height: 10),

        if (state.pendingApplications.isEmpty && admin.kycRequests.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
            ),
            child: const Center(
              child: Text(
                '✓ KYC Review Queue is clear. No pending applications.',
                style: TextStyle(color: Color(0xFF00D68F), fontWeight: FontWeight.bold),
              ),
            ),
          )
        else ...[
          ...state.pendingApplications.map((app) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFB300)),
                boxShadow: _isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        app.fullName,
                        style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: _textPrimary),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB300).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'UNDER REVIEW',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFFFB300)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Email: ${app.email} • Country: ${app.country}', style: TextStyle(fontSize: 11, color: _textSecondary)),
                  Text('Doc: ${app.documentType} (#${app.documentNumber})', style: TextStyle(fontSize: 11, color: _textPrimary, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            ref.read(kycComplianceProvider.notifier).approveKyc(app.id);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00D68F),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: const Text('APPROVE & UNLOCK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            ref.read(kycComplianceProvider.notifier).rejectKyc(app.id, 'Unreadable documents');
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF4757),
                            side: const BorderSide(color: Color(0xFFFF4757)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),

          ...admin.kycRequests.map((k) {
            final isPending = k.status == AdminKycStatus.pending;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isPending ? const Color(0xFFFFB300) : _borderColor),
                boxShadow: _isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(k.userName, style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.bold, color: _textPrimary)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isPending ? const Color(0xFFFFB300).withValues(alpha: 0.2) : const Color(0xFF00D68F).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(isPending ? 'PENDING' : 'APPROVED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isPending ? const Color(0xFFFFB300) : const Color(0xFF00D68F))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Email: ${k.userEmail} • Doc: ${k.docType} (${k.docNumber})', style: TextStyle(fontSize: 11, color: _textSecondary)),
                  const SizedBox(height: 10),
                  if (isPending)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => adminNotifier.approveKyc(k.id, k.userId),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00D68F), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 8)),
                            child: const Text('APPROVE KYC', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => adminNotifier.rejectKyc(k.id),
                            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF4757), side: const BorderSide(color: Color(0xFFFF4757)), padding: const EdgeInsets.symmetric(vertical: 8)),
                            child: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            );
          }),
        ],

        const SizedBox(height: 20),
        Text(
          'AML & Sanctions Audit Logs',
          style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: _textPrimary),
        ),
        const SizedBox(height: 10),

        ...state.highRiskAmlAlerts.map((alert) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _borderColor),
            ),
            child: Row(
              children: [
                const Icon(Icons.security, color: Color(0xFFFFD600), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    alert,
                    style: TextStyle(fontSize: 11, color: _textPrimary),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 5. RISK ENGINE & LEVERAGE TAB
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildRiskEngineTab(AdminState admin, AdminNotifier adminNotifier) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Trading Circuit Breaker
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: admin.isTradingHalted ? const Color(0xFFFF4757).withValues(alpha: 0.15) : _cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: admin.isTradingHalted ? const Color(0xFFFF4757) : _borderColor),
              boxShadow: _isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              children: [
                Icon(Icons.power_settings_new_rounded, color: admin.isTradingHalted ? const Color(0xFFFF4757) : const Color(0xFF00D68F), size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        admin.isTradingHalted ? 'TRADING IS GLOBALLY HALTED' : 'Trading Engine Active',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: admin.isTradingHalted ? const Color(0xFFFF4757) : _textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text('Emergency circuit breaker for extreme market volatility', style: TextStyle(fontSize: 11, color: _textSecondary)),
                    ],
                  ),
                ),
                Switch(
                  value: !admin.isTradingHalted,
                  activeThumbColor: const Color(0xFF00D68F),
                  inactiveThumbColor: const Color(0xFFFF4757),
                  onChanged: (_) => adminNotifier.toggleTradingHalt(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Leverage Policy Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _borderColor),
              boxShadow: _isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Global Max Account Leverage', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.bold, color: _textPrimary)),
                const SizedBox(height: 4),
                Text('Maximum leverage ratio available to retail clients', style: TextStyle(fontSize: 11, color: _textSecondary)),
                const SizedBox(height: 12),
                Row(
                  children: [100, 200, 500, 1000].map((lev) {
                    final isSel = admin.maxLeverage == lev;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => adminNotifier.setMaxLeverage(lev),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isSel ? _goldSlider : _subCardBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isSel ? _goldSlider : _borderColor),
                          ),
                          child: Center(
                            child: Text(
                              '1:$lev',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.bold, color: isSel ? (_isDark ? Colors.black : Colors.white) : _textPrimary),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Spread Multiplier Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _borderColor),
              boxShadow: _isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Global Spread Markup Multiplier', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.bold, color: _textPrimary)),
                    Text('${admin.spreadMultiplier.toStringAsFixed(1)}x', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.bold, color: _goldAccent)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Increases all market spreads during high volatility news events', style: TextStyle(fontSize: 11, color: _textSecondary)),
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: _goldSlider,
                    inactiveTrackColor: _borderColor,
                    thumbColor: _goldSlider,
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: admin.spreadMultiplier,
                    min: 1.0,
                    max: 3.0,
                    divisions: 20,
                    onChanged: (val) => adminNotifier.setSpreadMultiplier(val),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Stop-Out Liquidation Rules
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _borderColor),
              boxShadow: _isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Liquidation & Margin Call Parameters', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.bold, color: _textPrimary)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Margin Call Threshold', style: TextStyle(fontSize: 12, color: _textSecondary)),
                    const Text('50% Equity / Margin', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFFB300))),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Stop-Out Auto Liquidation', style: TextStyle(fontSize: 12, color: _textSecondary)),
                    const Text('20% Margin Level', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFF4757))),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Max Single Order Size', style: TextStyle(fontSize: 12, color: _textSecondary)),
                    Text('50.00 Lots', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _textPrimary)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 6. TREASURY & AUDIT PROOF TAB
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildTreasuryTab(TreasuryAuditProof proof) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Zero-Drift Certificate
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: proof.isZeroDriftVerified ? const Color(0xFF00D68F) : const Color(0xFFFF4757)),
              boxShadow: _isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              children: [
                Icon(
                  proof.isZeroDriftVerified ? Icons.verified_rounded : Icons.error_rounded,
                  color: proof.isZeroDriftVerified ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                  size: 32,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        proof.isZeroDriftVerified ? 'DOUBLE-ENTRY BALANCE VERIFIED' : 'BALANCE MISMATCH DETECTED',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: proof.isZeroDriftVerified ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Total Assets (\$${proof.totalAssets.toDouble().toStringAsFixed(2)}) = Total Liabilities (\$${proof.totalLiabilities.toDouble().toStringAsFixed(2)})',
                        style: TextStyle(fontSize: 11, color: _textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Solvency Breakdown
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _borderColor),
              boxShadow: _isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Proof of Reserves & Solvency Audit', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: _textPrimary)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Client Segregated Vaults:', style: TextStyle(fontSize: 12, color: _textSecondary)),
                    Text('\$${proof.totalAssets.toDouble().toStringAsFixed(2)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _textPrimary)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Platform Liabilities:', style: TextStyle(fontSize: 12, color: _textSecondary)),
                    Text('\$${proof.totalLiabilities.toDouble().toStringAsFixed(2)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _textPrimary)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Solvency Reserve Ratio:', style: TextStyle(fontSize: 12, color: _textSecondary)),
                    const Text('100.00% (Fully Backed)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00D68F))),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(color: _borderColor, height: 1),
                const SizedBox(height: 12),
                Text('Audit Merkle Root Hash:', style: TextStyle(fontSize: 10, color: _textSecondary)),
                const SizedBox(height: 2),
                Text(
                  proof.auditHash,
                  style: TextStyle(fontFamily: 'Courier', fontSize: 10, color: _goldAccent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // HELPER WIDGETS
  // ════════════════════════════════════════════════════════════════════════════
  Widget _dealerStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: _textSecondary)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.bold, color: _textPrimary)),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
        boxShadow: _isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(title, style: TextStyle(fontSize: 10, color: _textSecondary)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _miniInfo(String label, String val, Color valColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: _textSecondary)),
        const SizedBox(height: 2),
        Text(val, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: valColor)),
      ],
    );
  }
}
