import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../blocs/blocs.dart';
import '../../core/math/money_math.dart';
import '../../core/router/app_router.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../domain/entities/ledger_entities.dart';
import '../../domain/entities/trading_entities.dart';
import '../../core/policy/kyc_policy.dart';
import '../../domain/entities/kyc_entities.dart';
import '../../domain/entities/user_entity.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminPortalScreen extends StatefulWidget {
  const AdminPortalScreen({super.key});

  @override
  State<AdminPortalScreen> createState() => _AdminPortalScreenState();
}

class _AdminPortalScreenState extends State<AdminPortalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _userSearchQuery = '';
  String _financeFilter = 'ALL'; // ALL, DEPOSIT, WITHDRAWAL
  KycVerificationStatus? _selectedKycStatusFilter;
  String _adminKycSearchQuery = '';
  String _adminKycCountryFilter = 'All';

  bool get _isDark => context.watch<ThemeCubit>().state;
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
    final dealerRisk = context.watch<DealingDeskCubit>().state;
    final admin = context.watch<AdminCubit>().state;
    final adminNotifier = context.read<AdminCubit>();
    final complianceState = context.watch<KycCubit>().state;
    final treasuryProof = context.watch<LedgerCubit>().state.auditProof ??
        LedgerRepository.instance.generateTreasuryProof();
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: _goldBg,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: _goldBorder),
              ),
              child: Text(
                'MM DESK',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  color: _goldText,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Broker Portal',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
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
            onPressed: () => context.read<ThemeCubit>().toggleTheme(),
          ),
          IconButton(
            icon: Icon(Icons.logout_rounded, color: _textSecondary, size: 20),
            tooltip: 'Logout',
            onPressed: () async {
              await context.read<AuthBloc>().logout();
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HOUSE B-BOOK PnL',
                            style: TextStyle(fontSize: 10, color: _textSecondary, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
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
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'SPREAD REVENUE',
                            style: TextStyle(fontSize: 10, color: _textSecondary, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              MoneyMath.formatCurrency(risk.feeRevenueEarned),
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: _goldAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
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
          const SizedBox(height: 16),

          // ── Broker Account & User KPIs ──────────────────────────────────────
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.6,
            children: [
              _overviewKpiCard(
                title: 'REGISTERED TRADERS',
                value: '${admin.totalUsersCount}',
                subtitle: '${admin.activeUsersCount} Active Accounts',
                icon: Icons.people_alt_rounded,
                color: _goldAccent,
                onTap: () => _tabController.animateTo(2),
              ),
              _overviewKpiCard(
                title: 'CLIENT DEPOSITS',
                value: '\$${admin.totalUserFunds.toStringAsFixed(2)}',
                subtitle: 'Total User Balances',
                icon: Icons.account_balance_wallet_rounded,
                color: const Color(0xFF00D68F),
                onTap: () => _tabController.animateTo(2),
              ),
              _overviewKpiCard(
                title: 'KYC COMPLIANCE',
                value: '${admin.verifiedUsersCount} / ${admin.totalUsersCount}',
                subtitle: 'Verified Traders',
                icon: Icons.verified_user_rounded,
                color: const Color(0xFF3861FB),
                onTap: () => _tabController.animateTo(3),
              ),
              _overviewKpiCard(
                title: 'PENDING FINANCE',
                value: '${admin.pendingDepositsCount + admin.pendingWithdrawalsCount}',
                subtitle: 'Deposit / Withdrawal',
                icon: Icons.receipt_long_rounded,
                color: const Color(0xFFFFB300),
                onTap: () => _tabController.animateTo(1),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: Text(
                  'Instrument Risk & Markup',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.bold, color: _textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D68F).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF00D68F).withValues(alpha: 0.35)),
                ),
                child: const Text('AUTO-REBALANCE', style: TextStyle(color: Color(0xFF00D68F), fontSize: 9.5, fontWeight: FontWeight.bold)),
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
                        context.read<DealingDeskCubit>().updateSpreadMarkup(
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
                          context.read<DealingDeskCubit>().toggleRoutingMode(exp.symbol);
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
                    Row(
                      children: [
                        Text('Method: ${tx.method}', style: TextStyle(fontSize: 11, color: _textPrimary, fontWeight: FontWeight.w500)),
                        const Spacer(),
                        Text(DateFormat('yyyy-MM-dd HH:mm').format(tx.createdAt), style: TextStyle(fontSize: 10, color: _textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _subCardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2B384E)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.tag_rounded, size: 14, color: Color(0xFF00D68F)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'TxID: ${tx.txHash ?? tx.accountOrAddress}',
                              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w600, color: Color(0xFFFFD600)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: tx.txHash ?? tx.accountOrAddress));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: Color(0xFF00D68F),
                                  duration: Duration(seconds: 1),
                                  content: Text('TxID copied!'),
                                ),
                              );
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(Icons.copy, size: 14, color: Color(0xFF00D68F)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Email: ${tx.userEmail}', style: TextStyle(fontSize: 10, color: _textSecondary)),
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

    final allUsers = context.read<AdminCubit>().state.users;
    AdminTraderUser? traderUser;
    for (final u in allUsers) {
      if (u.id == tx.userId) {
        traderUser = u;
        break;
      }
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Dialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _borderColor)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 780),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Sleek Responsive Header ─────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
                  decoration: BoxDecoration(
                    color: _subCardBg,
                    border: Border(bottom: BorderSide(color: _borderColor)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDeposit
                                  ? const Color(0xFF00D68F).withValues(alpha: 0.15)
                                  : const Color(0xFFFF4757).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isDeposit
                                    ? const Color(0xFF00D68F).withValues(alpha: 0.4)
                                    : const Color(0xFFFF4757).withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              tx.type,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                color: isDeposit ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '#${tx.id}',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '\$${tx.amount.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: isDeposit ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            icon: Icon(Icons.close_rounded, color: _textSecondary, size: 20),
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.person_outline_rounded, size: 14, color: _textSecondary),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${tx.userName}  •  ${tx.userEmail}',
                              style: TextStyle(fontSize: 11, color: _textSecondary, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── TxID & Blockchain Toolbar (Clean Card Format) ───────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0E17),
                    border: Border(bottom: BorderSide(color: _borderColor)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.tag_rounded, size: 14, color: Color(0xFF00D68F)),
                          const SizedBox(width: 4),
                          Text(
                            'TxID Hash / Account:',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _textSecondary),
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: tx.txHash ?? tx.accountOrAddress));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: Color(0xFF00D68F),
                                  duration: Duration(seconds: 2),
                                  content: Text('TxID copied to clipboard!'),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00D68F).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFF00D68F).withValues(alpha: 0.3)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.copy_rounded, size: 11, color: Color(0xFF00D68F)),
                                  SizedBox(width: 3),
                                  Text('Copy', style: TextStyle(fontSize: 10, color: Color(0xFF00D68F), fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () {
                              final currentHash = tx.txHash ?? tx.accountOrAddress;
                              Clipboard.setData(ClipboardData(text: 'https://tronscan.org/#/transaction/$currentHash'));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: const Color(0xFFFFD600),
                                  duration: const Duration(seconds: 2),
                                  content: Text('Tronscan URL copied: https://tronscan.org/#/transaction/$currentHash'),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD600).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFFFD600).withValues(alpha: 0.3)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.open_in_new_rounded, size: 11, color: Color(0xFFFFD600)),
                                  SizedBox(width: 3),
                                  Text('Tronscan', style: TextStyle(fontSize: 10, color: Color(0xFFFFD600), fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      SelectableText(
                        tx.txHash ?? tx.accountOrAddress,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Color(0xFFFFD600),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Image Inspection Area with Zoom ─────────────────────────────
                Expanded(
                  child: Container(
                    color: _isDark ? const Color(0xFF06090F) : const Color(0xFFF1F5F9),
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
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF2B384E)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.pinch_outlined, size: 12, color: Color(0xFFFFD600)),
                                SizedBox(width: 4),
                                Text(
                                  'Pinch / Scroll to Zoom (Up to 5x)',
                                  style: TextStyle(color: Color(0xFFFFD600), fontSize: 9.5, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Transaction & Proof Metadata ────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _subCardBg,
                    border: Border(top: BorderSide(color: _borderColor)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                      if (traderUser != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _miniInfo('Trader Live Balance', '\$${traderUser.balance.toStringAsFixed(2)}', const Color(0xFF00D68F)),
                            ),
                            Expanded(
                              child: _miniInfo('Trader Live Equity', '\$${traderUser.equity.toStringAsFixed(2)}', _textPrimary),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // ── Action Buttons (Approve / Reject) ───────────────────────────
                if (isPending)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _cardBg,
                      border: Border(top: BorderSide(color: _borderColor)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
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
                            icon: const Icon(Icons.cancel_outlined, size: 15),
                            label: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFFF4757),
                              side: const BorderSide(color: Color(0xFFFF4757), width: 1.2),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 6,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(dialogCtx).pop();
                              _executeApproval(tx, adminNotifier);
                            },
                            icon: const Icon(Icons.check_circle_rounded, size: 16),
                            label: const Text('APPROVE & CREDIT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00D68F),
                              foregroundColor: Colors.black,
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      context.read<TradingEngineCubit>().depositFunds(tx.userId, amtDec);

      // 2. Credit double-entry ledger provider
      context.read<LedgerCubit>().deposit(
            userId: tx.userId,
            amount: amtDec,
            method: tx.method,
          );

      // 3. Credit wallet provider balance
      context.read<WalletCubit>().creditDeposit(tx.amount, tx.method);
      context.read<WalletBloc>().creditDeposit(tx.amount, tx.method, txId: tx.id);

      // 4. Update Supabase wallets table
      try {
        Supabase.instance.client
            .from('wallets')
            .select('balance')
            .eq('user_id', tx.userId)
            .maybeSingle()
            .then((existingWallet) {
          final currentBal = (existingWallet?['balance'] as num?)?.toDouble() ?? 0.0;
          final cleanBal = (currentBal == 10000.0 || currentBal == 25000.0) ? 0.0 : currentBal;
          final newTotal = cleanBal + tx.amount;
          Supabase.instance.client.from('wallets').upsert({
            'user_id': tx.userId,
            'currency': tx.currency,
            'balance': newTotal,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'user_id,currency').catchError((err) {
            debugPrint('Supabase wallet update error: $err');
          });
        }).catchError((err) {
          debugPrint('Supabase wallet select error: $err');
        });
      } catch (e) {
        debugPrint('Supabase wallet update exception: $e');
      }
    } else if (tx.type == 'WITHDRAWAL') {
      // For withdrawal, debit trading engine and wallet if not yet debited
      context.read<TradingEngineCubit>().withdrawFunds(tx.userId, amtDec);
      context.read<LedgerCubit>().withdraw(
            userId: tx.userId,
            amount: amtDec,
            destinationAddress: tx.accountOrAddress,
          );
      context.read<WalletCubit>().debitWithdrawal(tx.amount, tx.method);

      try {
        Supabase.instance.client
            .from('wallets')
            .select('balance')
            .eq('user_id', tx.userId)
            .maybeSingle()
            .then((existingWallet) {
          final currentBal = (existingWallet?['balance'] as num?)?.toDouble() ?? 0.0;
          final cleanBal = (currentBal == 10000.0 || currentBal == 25000.0) ? 0.0 : currentBal;
          final newTotal = (cleanBal - tx.amount).clamp(0.0, 1000000000.0);
          Supabase.instance.client.from('wallets').upsert({
            'user_id': tx.userId,
            'currency': tx.currency,
            'balance': newTotal,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'user_id,currency').catchError((err) {
            debugPrint('Supabase wallet update error: $err');
          });
        }).catchError((err) {
          debugPrint('Supabase wallet select error: $err');
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
          // CRM Metrics Summary Strip
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _borderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TOTAL TRADERS', style: TextStyle(fontSize: 9.5, color: _textSecondary, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('${admin.totalUsersCount}', style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w900, color: _goldAccent)),
                    ],
                  ),
                ),
                Container(width: 1, height: 30, color: _borderColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ACTIVE ACCOUNTS', style: TextStyle(fontSize: 9.5, color: _textSecondary, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('${admin.activeUsersCount}', style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF00D68F))),
                    ],
                  ),
                ),
                Container(width: 1, height: 30, color: _borderColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('KYC VERIFIED', style: TextStyle(fontSize: 9.5, color: _textSecondary, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('${admin.verifiedUsersCount}', style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF3861FB))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

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
              Text('Traders List (${filteredUsers.length} shown)', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: _textPrimary)),
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
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: _goldBg,
                        child: Text(
                          u.name.isNotEmpty ? u.name[0].toUpperCase() : 'U',
                          style: TextStyle(color: _goldText, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              u.name,
                              style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.bold, color: _textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              u.email,
                              style: TextStyle(fontSize: 10.5, color: _textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: isFrozen ? const Color(0xFFFF4757).withValues(alpha: 0.2) : const Color(0xFF00D68F).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isFrozen ? const Color(0xFFFF4757).withValues(alpha: 0.4) : const Color(0xFF00D68F).withValues(alpha: 0.4),
                          ),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _showCreditDialog(context, u, adminNotifier),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_card, size: 13, color: _goldAccent),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'Adjust Balance / Bonus',
                                    style: TextStyle(color: _goldAccent, fontSize: 11, fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          adminNotifier.toggleUserFreeze(u.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(isFrozen ? '${u.name} has been ACTIVATED' : '${u.name} has been FROZEN'),
                              backgroundColor: isFrozen ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(isFrozen ? Icons.lock_open : Icons.lock_outline, size: 13, color: isFrozen ? const Color(0xFF00D68F) : const Color(0xFFFF4757)),
                              const SizedBox(width: 4),
                              Text(
                                isFrozen ? 'Unfreeze' : 'Freeze Account',
                                style: TextStyle(color: isFrozen ? const Color(0xFF00D68F) : const Color(0xFFFF4757), fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
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
  // 4. KYC & AML COMPLIANCE TAB (Comprehensive Verification Portal)
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildComplianceTab(ComplianceState state, AdminState admin, AdminNotifier adminNotifier) {
    final profiles = state.adminProfiles;

    // Filter modern profiles according to active filters
    final filteredProfiles = profiles.where((p) {
      if (_selectedKycStatusFilter != null && p.status != _selectedKycStatusFilter) return false;
      if (_adminKycCountryFilter != 'All' &&
          p.countryOfResidence.toLowerCase() != _adminKycCountryFilter.toLowerCase()) {
        return false;
      }
      if (_adminKycSearchQuery.trim().isNotEmpty) {
        final q = _adminKycSearchQuery.toLowerCase().trim();
        final match = p.fullName.toLowerCase().contains(q) ||
            p.userId.toLowerCase().contains(q) ||
            p.id.toLowerCase().contains(q) ||
            p.city.toLowerCase().contains(q);
        if (!match) return false;
      }
      return true;
    }).toList();

    // Counts
    final pendingCount = profiles.where((p) => p.status == KycVerificationStatus.pendingReview).length +
        state.pendingApplications.length +
        admin.kycRequests.where((k) => k.status == AdminKycStatus.pending).length;
    final approvedCount = profiles.where((p) => p.status == KycVerificationStatus.approved).length;
    final resubmissionCount = profiles.where((p) => p.status == KycVerificationStatus.resubmissionRequired).length;
    final rejectedCount = profiles.where((p) => p.status == KycVerificationStatus.rejected).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Top KPI Cards ────────────────────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              SizedBox(width: 95, child: _kycKpiMiniCard('Total Queue', '${profiles.length + state.pendingApplications.length}', const Color(0xFF3B82F6))),
              const SizedBox(width: 8),
              SizedBox(width: 90, child: _kycKpiMiniCard('Pending', '$pendingCount', const Color(0xFFFFC700))),
              const SizedBox(width: 8),
              SizedBox(width: 105, child: _kycKpiMiniCard('Resubmit Req.', '$resubmissionCount', const Color(0xFFFF9800))),
              const SizedBox(width: 8),
              SizedBox(width: 90, child: _kycKpiMiniCard('Approved', '$approvedCount', const Color(0xFF0ECB81))),
              const SizedBox(width: 8),
              SizedBox(width: 90, child: _kycKpiMiniCard('Rejected', '$rejectedCount', const Color(0xFFFF4757))),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Filter Chips ─────────────────────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _kycFilterChip('All Statuses', _selectedKycStatusFilter == null, () {
                setState(() => _selectedKycStatusFilter = null);
              }),
              const SizedBox(width: 8),
              _kycFilterChip('Pending Review', _selectedKycStatusFilter == KycVerificationStatus.pendingReview, () {
                setState(() => _selectedKycStatusFilter = KycVerificationStatus.pendingReview);
              }, count: pendingCount),
              const SizedBox(width: 8),
              _kycFilterChip('Resubmission Required', _selectedKycStatusFilter == KycVerificationStatus.resubmissionRequired, () {
                setState(() => _selectedKycStatusFilter = KycVerificationStatus.resubmissionRequired);
              }, count: resubmissionCount),
              const SizedBox(width: 8),
              _kycFilterChip('Approved', _selectedKycStatusFilter == KycVerificationStatus.approved, () {
                setState(() => _selectedKycStatusFilter = KycVerificationStatus.approved);
              }, count: approvedCount),
              const SizedBox(width: 8),
              _kycFilterChip('Rejected', _selectedKycStatusFilter == KycVerificationStatus.rejected, () {
                setState(() => _selectedKycStatusFilter = KycVerificationStatus.rejected);
              }, count: rejectedCount),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Search & Country Filter Row ──────────────────────────────────────
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 480;
            final searchField = TextField(
              onChanged: (v) => setState(() => _adminKycSearchQuery = v),
              style: TextStyle(color: _textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search by Trader name, email, or KYC ID...',
                hintStyle: TextStyle(color: _textSecondary, fontSize: 12),
                prefixIcon: Icon(Icons.search_rounded, size: 18, color: _textSecondary),
                fillColor: _cardBg,
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _borderColor)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _borderColor)),
              ),
            );

            final countryDropdown = DropdownButtonFormField<String>(
              value: _adminKycCountryFilter,
              dropdownColor: _cardBg,
              style: TextStyle(color: _textPrimary, fontSize: 12),
              decoration: InputDecoration(
                fillColor: _cardBg,
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _borderColor)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _borderColor)),
              ),
              items: ['All', 'Pakistan', 'United Arab Emirates', 'Saudi Arabia', 'United Kingdom', 'Other']
                  .map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _adminKycCountryFilter = v);
              },
            );

            if (isNarrow) {
              return Column(
                children: [
                  searchField,
                  const SizedBox(height: 8),
                  countryDropdown,
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 3, child: searchField),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: countryDropdown),
              ],
            );
          },
        ),
        const SizedBox(height: 16),

        // ── Modern Profile Cards ─────────────────────────────────────────────
        if (filteredProfiles.isNotEmpty) ...[
          ...filteredProfiles.map((p) => _buildModernKycProfileCard(p, adminNotifier)),
        ],

        // ── Legacy Pending Applications (Backward Compatible) ────────────────
        if (state.pendingApplications.isNotEmpty) ...[
          ...state.pendingApplications.map((app) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFB300)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(app.fullName, style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.bold, color: _textPrimary)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFFFB300).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                        child: const Text('LEGACY PENDING', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFFFB300))),
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
                          onPressed: () => context.read<KycCubit>().approveKyc(app.id),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00D68F), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 8)),
                          child: const Text('APPROVE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.read<KycCubit>().rejectKyc(app.id, 'Unreadable documents'),
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

        // Empty State
        if (filteredProfiles.isEmpty && state.pendingApplications.isEmpty && admin.kycRequests.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _borderColor),
            ),
            child: Column(
              children: [
                const Icon(Icons.verified_user_outlined, size: 48, color: Color(0xFF0ECB81)),
                const SizedBox(height: 12),
                Text('No KYC Requests Matching Filter', style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text('All trader verification submissions have been reviewed.', style: TextStyle(color: _textSecondary, fontSize: 12)),
              ],
            ),
          ),

        const SizedBox(height: 24),
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

  Widget _kycKpiMiniCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: _textSecondary, fontSize: 9, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _kycFilterChip(String label, bool isSelected, VoidCallback onTap, {int? count}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD600) : _cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? const Color(0xFFFFD600) : _borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : _textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            if (count != null && count > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black : const Color(0xFF263143),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? const Color(0xFFFFD600) : Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModernKycProfileCard(KycProfileEntity profile, AdminNotifier adminNotifier) {
    final statusColor = KycPolicy.getStatusColor(profile.status);
    final isPending = profile.status == KycVerificationStatus.pendingReview;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isPending ? const Color(0xFFFFC700).withValues(alpha: 0.6) : _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF1E2838),
                child: Text(
                  profile.firstName.isNotEmpty ? profile.firstName[0].toUpperCase() : 'T',
                  style: const TextStyle(color: Color(0xFFFFD600), fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _textPrimary),
                    ),
                    Text(
                      '${profile.id} • ${profile.countryOfResidence}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: _textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor),
                ),
                child: Text(
                  profile.status.code,
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Details grid
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _subCardBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _miniDetail('Identity (POI)', '${profile.identityDocType.displayName} (#${profile.documentNumber ?? "Attached"})'),
                _miniDetail('Address (POA)', profile.addressDocType.displayName),
                _miniDetail('Submitted', profile.submittedAt != null ? '${profile.submittedAt!.day}/${profile.submittedAt!.month} ${profile.submittedAt!.hour}:${profile.submittedAt!.minute.toString().padLeft(2, '0')}' : 'Draft'),
              ],
            ),
          ),

          if (profile.resubmissionNotes != null && profile.resubmissionNotes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Feedback: ${profile.resubmissionNotes}',
                style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 11),
              ),
            ),
          ],

          if (profile.rejectionReason != null && profile.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF4757).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Rejection Reason: ${profile.rejectionReason}',
                style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 11),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Action buttons
          Row(
            children: [
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () => _showKycInspectionModal(profile, adminNotifier),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E2838),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.preview_rounded, size: 16),
                  label: const Text('INSPECT & REVIEW', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ),
              if (isPending) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _showApproveDialog(profile, adminNotifier),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0ECB81),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('APPROVE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showRejectDialog(profile, adminNotifier),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF4757),
                      side: const BorderSide(color: Color(0xFFFF4757)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniDetail(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: _textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  // ── Inspection Modal ───────────────────────────────────────────────────────

  void _showKycInspectionModal(KycProfileEntity profile, AdminNotifier adminNotifier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (sheetCtx, scrollController) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: ListView(
                controller: scrollController,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('KYC Compliance Inspection', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _textPrimary)),
                          Text('Profile ID: ${profile.id}', style: TextStyle(fontSize: 11, color: _textSecondary)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // 1. User Information
                  Text('1. APPLICANT PERSONAL INFORMATION', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _goldAccent)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: _subCardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: _borderColor)),
                    child: Column(
                      children: [
                        _inspectionRow('Legal Name', profile.fullName),
                        const Divider(height: 12),
                        _inspectionRow('User ID', profile.userId),
                        const Divider(height: 12),
                        _inspectionRow('Date of Birth', profile.dateOfBirth != null ? '${profile.dateOfBirth!.day}/${profile.dateOfBirth!.month}/${profile.dateOfBirth!.year}' : 'N/A'),
                        const Divider(height: 12),
                        _inspectionRow('Nationality', profile.nationality),
                        const Divider(height: 12),
                        _inspectionRow('Country of Residence', profile.countryOfResidence),
                        const Divider(height: 12),
                        _inspectionRow('Residential Address', '${profile.address}, ${profile.city}, ${profile.state} ${profile.postalCode}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 2. Identity Document (POI)
                  Text('2. PROOF OF IDENTITY (POI)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _goldAccent)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: _subCardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: _borderColor)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _inspectionRow('Document Type', profile.identityDocType.displayName),
                        const Divider(height: 12),
                        _inspectionRow('Document Number', profile.documentNumber ?? 'Not specified'),
                        const SizedBox(height: 14),
                        Text('Document Photos:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _textSecondary)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (profile.poiFrontDoc != null)
                              Expanded(
                                child: _adminDocumentThumbnail(
                                  label: 'Front Side',
                                  doc: profile.poiFrontDoc!,
                                ),
                              ),
                            if (profile.poiBackDoc != null) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: _adminDocumentThumbnail(
                                  label: 'Back Side',
                                  doc: profile.poiBackDoc!,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. Proof of Address (POA)
                  Text('3. PROOF OF ADDRESS (POA)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _goldAccent)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: _subCardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: _borderColor)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _inspectionRow('Document Type', profile.addressDocType.displayName),
                        const SizedBox(height: 14),
                        if (profile.poaDoc != null)
                          _adminDocumentThumbnail(
                            label: 'Proof of Address Document',
                            doc: profile.poaDoc!,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Admin Action Buttons
                  LayoutBuilder(
                    builder: (modalCtx, constraints) {
                      final isNarrow = constraints.maxWidth < 480;
                      final approveBtn = ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _showApproveDialog(profile, adminNotifier);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0ECB81),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.check_circle_rounded, size: 16),
                        label: const Text('APPROVE KYC', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      );

                      final resubmitBtn = ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _showResubmissionDialog(profile, adminNotifier);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9800),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.replay_rounded, size: 16),
                        label: const Text('RESUBMIT REQ.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      );

                      final rejectBtn = OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _showRejectDialog(profile, adminNotifier);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFF4757),
                          side: const BorderSide(color: Color(0xFFFF4757)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.cancel_rounded, size: 16),
                        label: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      );

                      if (isNarrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            approveBtn,
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: resubmitBtn),
                                const SizedBox(width: 8),
                                Expanded(child: rejectBtn),
                              ],
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: approveBtn),
                          const SizedBox(width: 10),
                          Expanded(child: resubmitBtn),
                          const SizedBox(width: 10),
                          Expanded(child: rejectBtn),
                        ],
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _inspectionRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: _textSecondary)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _adminDocumentThumbnail({required String label, required KycDocumentEntity doc}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _textPrimary)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _showImagePreviewDialog(label, doc.fileBytes, doc.originalFileName),
            child: Container(
              height: 100,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF1E2838),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Center(
                child: Icon(Icons.zoom_in_rounded, color: Color(0xFFFFD600), size: 32),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('${doc.originalFileName} • ${(doc.fileSize / 1024).toStringAsFixed(1)} KB', style: TextStyle(fontSize: 10, color: _textSecondary)),
        ],
      ),
    );
  }

  void _showImagePreviewDialog(String title, Uint8List? bytes, String? name) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF121824),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => Navigator.of(ctx).pop()),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                height: 250,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F141C),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.description_rounded, size: 56, color: Color(0xFF0ECB81)),
                      SizedBox(height: 8),
                      Text('Secure Document Verified', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showApproveDialog(KycProfileEntity profile, AdminNotifier adminNotifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121824),
        title: const Text('Approve KYC Application?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Approving ${profile.fullName} will unlock Level 2 privileges (unrestricted deposits, STP withdrawals, and live orders).',
          style: const TextStyle(color: Color(0xFF848E9C), fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<KycCubit>().adminApproveProfile(
                    kycId: profile.id,
                    reviewerEmail: 'admin@asianfx.com',
                  );
              // Sync user session if active
              final currentUser = context.read<AuthBloc>().state.user;
              if (currentUser != null && currentUser.id == profile.userId) {
                context.read<AuthBloc>().updateUserKyc(KycStatus.approved, kycTier: 2);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('✓ ${profile.fullName} KYC Approved!'), backgroundColor: const Color(0xFF0ECB81)),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0ECB81), foregroundColor: Colors.black),
            child: const Text('Approve KYC', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(KycProfileEntity profile, AdminNotifier adminNotifier) {
    final reasons = [
      'Document expired',
      'Document unreadable or blurry',
      'Information mismatch with identity record',
      'Invalid or fraudulent document',
      'Address document older than 90 days',
      'Additional verification required',
    ];
    String selectedReason = reasons.first;
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF121824),
          title: const Text('Reject KYC Application', style: TextStyle(color: Color(0xFFFF4757), fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select mandatory compliance reason:', style: TextStyle(color: Color(0xFF848E9C), fontSize: 12)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedReason,
                dropdownColor: const Color(0xFF1E2838),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                items: reasons.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 12)))).toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedReason = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(
                  hintText: 'Additional remarks for compliance record...',
                  hintStyle: TextStyle(color: Color(0xFF55657E), fontSize: 12),
                  fillColor: Color(0xFF0F141C),
                  filled: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                final fullReason = noteController.text.trim().isNotEmpty
                    ? '$selectedReason - ${noteController.text.trim()}'
                    : selectedReason;

                context.read<KycCubit>().adminRejectProfile(
                      kycId: profile.id,
                      reviewerEmail: 'admin@asianfx.com',
                      reason: fullReason,
                    );

                final currentUser = context.read<AuthBloc>().state.user;
                if (currentUser != null && currentUser.id == profile.userId) {
                  context.read<AuthBloc>().updateUserKyc(KycStatus.rejected, rejectionReason: fullReason);
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${profile.fullName} KYC Rejected: $fullReason'), backgroundColor: const Color(0xFFFF4757)),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4757), foregroundColor: Colors.white),
              child: const Text('Reject KYC', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showResubmissionDialog(KycProfileEntity profile, AdminNotifier adminNotifier) {
    final noteController = TextEditingController(text: 'Proof of address document is unclear. Please upload a recent utility bill or bank statement.');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121824),
        title: const Text('Request Document Resubmission', style: TextStyle(color: Color(0xFFFF9800), fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Specify what document or detail the trader must correct:',
              style: TextStyle(color: Color(0xFF848E9C), fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Enter specific resubmission instructions...',
                fillColor: Color(0xFF0F141C),
                filled: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final notes = noteController.text.trim();
              if (notes.isEmpty) return;

              context.read<KycCubit>().adminRequestProfileResubmission(
                    kycId: profile.id,
                    reviewerEmail: 'admin@asianfx.com',
                    notes: notes,
                  );

              final currentUser = context.read<AuthBloc>().state.user;
              if (currentUser != null && currentUser.id == profile.userId) {
                context.read<AuthBloc>().updateUserKyc(KycStatus.restricted);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Resubmission requested from ${profile.fullName}'), backgroundColor: const Color(0xFFFF9800)),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9800), foregroundColor: Colors.black),
            child: const Text('Send Request', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
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
          Text(label, style: TextStyle(fontSize: 10, color: _textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.bold, color: _textPrimary)),
          ),
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
          Text(title, style: TextStyle(fontSize: 10, color: _textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          ),
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

  Widget _overviewKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                if (onTap != null)
                  Icon(Icons.arrow_forward_ios_rounded, color: _textSecondary, size: 10),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: _textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  title,
                  style: TextStyle(fontSize: 9.5, color: _textSecondary, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 8.5, color: color, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
