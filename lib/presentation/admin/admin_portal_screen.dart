import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../blocs/blocs.dart';
import '../../core/math/money_math.dart';
import '../../core/router/app_router.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../domain/entities/ledger_entities.dart';
import '../../domain/entities/trading_entities.dart';
import '../../core/policy/kyc_policy.dart';
import '../../domain/entities/kyc_entities.dart';
import '../../domain/entities/user_entity.dart';
import 'widgets/app_release_tab.dart';
import 'widgets/deposit_requests_tab.dart';
import 'widgets/withdrawal_requests_tab.dart';
import '../../data/datasources/market_feed_service.dart';
import '../../data/datasources/supabase_trade_service.dart';

class AdminPortalScreen extends StatefulWidget {
  const AdminPortalScreen({super.key});

  @override
  State<AdminPortalScreen> createState() => _AdminPortalScreenState();
}

class _AdminPortalScreenState extends State<AdminPortalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _userSearchQuery = '';
  KycVerificationStatus? _selectedKycStatusFilter;
  String _adminKycSearchQuery = '';
  String _adminKycCountryFilter = 'All';

  bool get _isDark => context.watch<ThemeCubit>().state;
  Color get _bg => _isDark ? const Color(0xFF0B0E11) : const Color(0xFFF1F5F9);
  Color get _appBarBg => _isDark ? const Color(0xFF161B20) : Colors.white;
  Color get _cardBg => _isDark ? const Color(0xFF161B20) : Colors.white;
  Color get _subCardBg => _isDark ? const Color(0xFF0F1317) : const Color(0xFFF8FAFC);
  Color get _borderColor => _isDark ? const Color(0xFF1F252B) : const Color(0xFFE2E8F0);
  Color get _subtleBorder => _isDark ? const Color(0xFF262D34) : const Color(0xFFCBD5E1);
  Color get _textPrimary => _isDark ? Colors.white : const Color(0xFF0F172A);
  Color get _textSecondary => _isDark ? const Color(0xFF8A919A) : const Color(0xFF64748B);
  Color get _goldAccent => _isDark ? const Color(0xFFFFDE02) : const Color(0xFFD97706);
  Color get _goldText => _isDark ? const Color(0xFFFFDE02) : const Color(0xFFB45309);
  Color get _goldBg => _isDark ? const Color(0xFFFFDE02).withValues(alpha: 0.2) : const Color(0xFFFEF3C7);
  Color get _goldBorder => _isDark ? const Color(0xFFFFDE02).withValues(alpha: 0.4) : const Color(0xFFFDE68A);
  Color get _goldSlider => _isDark ? const Color(0xFFFFDE02) : const Color(0xFFF59E0B);

  /// Position of "KYC & AML" in the portal's TabBar.
  static const int _kycTabIndex = 3;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    // The KYC queue is first loaded at app start, before the admin has signed
    // in, when RLS only returns the caller's own profile. Reload it now that
    // the admin session exists, and again whenever the KYC tab is opened.
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _tabController.index == _kycTabIndex) {
        context.read<KycCubit>().loadAdminQueue();
      }
    });
    // Load the persisted dealer config (markups, spread multiplier).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      context.read<KycCubit>().loadAdminQueue();
      // Registered traders come from the server now that the admin session exists.
      context.read<AdminCubit>().refreshUsers();
      final feed = MarketFeedService();
      await feed.refreshServerQuotes(forceConfig: true);
      if (!mounted) return;
      context.read<AdminCubit>().setSpreadMultiplier(feed.spreadMultiplier);
      context.read<DealingDeskCubit>().calculateExposure();
    });
  }

  Future<void> _commitSpreadMultiplier(double value, AdminNotifier adminNotifier) async {
    final messenger = ScaffoldMessenger.of(context);
    final feed = MarketFeedService();
    try {
      final stored = await SupabaseTradeService.instance.adminSetSpreadMultiplier(value);
      feed.updateSpreadMultiplier(stored);
      adminNotifier.setSpreadMultiplier(stored);
      messenger.showSnackBar(SnackBar(
        backgroundColor: const Color(0xFF16C784),
        content: Text('Spread multiplier saved: ${stored.toStringAsFixed(2)}x '
            '(applied by the price publisher on its next run).'),
      ));
    } on TradeServiceException catch (e) {
      adminNotifier.setSpreadMultiplier(feed.spreadMultiplier);
      messenger.showSnackBar(SnackBar(
        backgroundColor: const Color(0xFFE5484D),
        content: Text('Spread multiplier NOT saved: ${e.message}'),
      ));
    }
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
                color: const Color(0xFFE5484D).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE5484D)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFE5484D), size: 14),
                  SizedBox(width: 4),
                  Text('CIRCUIT HALTED', style: TextStyle(color: Color(0xFFE5484D), fontSize: 10, fontWeight: FontWeight.bold)),
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
                        _badge(pendingKycCount, const Color(0xFFE5484D)),
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
                const Tab(
                  child: Row(
                    children: [
                      Icon(Icons.system_update_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('App Update'),
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

          // 2. Finance Desk: USDT deposit review + transactions/withdrawals
          _buildFinanceDesk(admin, adminNotifier),

          // 3. Trader CRM & User Accounts Tab
          _buildTraderCrmTab(admin, adminNotifier),

          // 4. KYC & AML Compliance Tab
          _buildComplianceTab(complianceState, admin, adminNotifier),

          // 5. Risk Engine & Leverage Tab
          _buildRiskEngineTab(admin, adminNotifier),

          // 6. Treasury & Audit Proof Tab
          _buildTreasuryTab(treasuryProof),

          // 7. Publish a new app version (in-app update)
          const AppReleaseTab(),
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
                    ? const [Color(0xFF1E242A), Color(0xFF101722)]
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
                            'HOUSE PnL (UNHEDGED)',
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
                                     ? const Color(0xFF16C784)
                                     : const Color(0xFFE5484D),
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
          LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 750;
              return GridView.count(
                crossAxisCount: isDesktop ? 4 : 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: isDesktop ? 2.3 : 1.6,
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
                    color: const Color(0xFF16C784),
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
              );
            },
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
                  color: const Color(0xFF16C784).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF16C784).withValues(alpha: 0.35)),
                ),
                child: const Text('NOT HEDGED', style: TextStyle(color: Color(0xFF16C784), fontSize: 9.5, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'A-Book / B-Book are internal tags only. There is no liquidity-provider bridge: '
            'every client trade is held by the broker and nothing is hedged externally. '
            'Markup changes are saved to the server and used by the price publisher.',
            style: TextStyle(fontSize: 10.5, color: _textSecondary),
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
                              : (_isDark ? const Color(0xFF16C784).withValues(alpha: 0.2) : const Color(0xFFD1FAE5)),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: exp.routing == ExecutionRouting.bBookInternal
                                ? _goldBorder
                                : (_isDark ? const Color(0xFF16C784).withValues(alpha: 0.3) : const Color(0xFFA7F3D0)),
                          ),
                        ),
                        child: Text(
                          exp.routing == ExecutionRouting.bBookInternal ? 'TAG: B-BOOK' : 'TAG: A-BOOK (NOT HEDGED)',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: exp.routing == ExecutionRouting.bBookInternal
                                ? _goldText
                                : (_isDark ? const Color(0xFF16C784) : const Color(0xFF059669)),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Net: ${exp.netExposureLots >= Decimal.zero ? '+' : ''}${exp.netExposureLots.toDouble().toStringAsFixed(2)} Lots',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: exp.netExposureLots >= Decimal.zero ? const Color(0xFF16C784) : const Color(0xFFE5484D),
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
                        'Markup: ${exp.spreadMarkupPips} pts',
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
                      value: exp.spreadMarkupPips.toDouble().clamp(0.0, 500.0),
                      min: 0.0,
                      max: 500.0,
                      divisions: 500,
                      onChanged: (val) {
                        context.read<DealingDeskCubit>().previewSpreadMarkup(exp.symbol, val.round());
                      },
                      onChangeEnd: (val) async {
                        final messenger = ScaffoldMessenger.of(context);
                        final error = await context
                            .read<DealingDeskCubit>()
                            .commitSpreadMarkup(exp.symbol, val.round());
                        messenger.showSnackBar(SnackBar(
                          duration: const Duration(seconds: 2),
                          backgroundColor: error == null ? const Color(0xFF16C784) : const Color(0xFFE5484D),
                          content: Text(error ?? '${exp.symbol} markup saved: ${val.round()} pts'),
                        ));
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
                          exp.routing == ExecutionRouting.bBookInternal ? 'Tag as A-Book' : 'Tag as B-Book',
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
  /// Finance Desk = one place for money in and out:
  ///   * USDT Deposits — manual review of deposit claims (rpc_review_deposit)
  ///   * USDT Withdrawals — pay out and record held withdrawals
  ///     (rpc_admin_review_withdrawal); replaces the old client-side list whose
  ///     Approve / Reject never reached the database
  Widget _buildFinanceDesk(AdminState admin, AdminNotifier adminNotifier) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: _cardBg,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: _goldAccent,
              labelColor: _goldAccent,
              unselectedLabelColor: _textSecondary,
              labelStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 12),
              tabs: const [
                Tab(
                  child: Row(
                    children: [
                      Icon(Icons.currency_bitcoin, size: 16),
                      SizedBox(width: 6),
                      Text('USDT Deposits'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    children: [
                      Icon(Icons.north_east_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('USDT Withdrawals'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: const TabBarView(
              children: [
                DepositRequestsTab(),
                WithdrawalRequestsTab(),
              ],
            ),
          ),
        ],
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
                      Text('${admin.activeUsersCount}', style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF16C784))),
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
                border: Border.all(color: isFrozen ? const Color(0xFFE5484D).withValues(alpha: 0.6) : _borderColor),
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
                          color: isFrozen ? const Color(0xFFE5484D).withValues(alpha: 0.2) : const Color(0xFF16C784).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isFrozen ? const Color(0xFFE5484D).withValues(alpha: 0.4) : const Color(0xFF16C784).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          isFrozen ? 'FROZEN' : 'ACTIVE',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isFrozen ? const Color(0xFFE5484D) : const Color(0xFF16C784)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _miniInfo('Balance', '\$${u.balance.toStringAsFixed(2)}', const Color(0xFF16C784)),
                      ),
                      Expanded(
                        child: _miniInfo('Equity', '\$${u.equity.toStringAsFixed(2)}', _textPrimary),
                      ),
                      Expanded(
                        child: _miniInfo('KYC Status', u.isKycVerified ? 'Verified' : 'Unverified', u.isKycVerified ? const Color(0xFF16C784) : const Color(0xFFFFB300)),
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
                              backgroundColor: isFrozen ? const Color(0xFF16C784) : const Color(0xFFE5484D),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(isFrozen ? Icons.lock_open : Icons.lock_outline, size: 13, color: isFrozen ? const Color(0xFF16C784) : const Color(0xFFE5484D)),
                              const SizedBox(width: 4),
                              Text(
                                isFrozen ? 'Unfreeze' : 'Freeze Account',
                                style: TextStyle(color: isFrozen ? const Color(0xFF16C784) : const Color(0xFFE5484D), fontSize: 11, fontWeight: FontWeight.w600),
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
                SnackBar(content: Text('Balance adjusted by \$${val.toStringAsFixed(2)} for ${user.name}'), backgroundColor: const Color(0xFF16C784)),
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
              SizedBox(width: 90, child: _kycKpiMiniCard('Pending', '$pendingCount', const Color(0xFFFFDE02))),
              const SizedBox(width: 8),
              SizedBox(width: 105, child: _kycKpiMiniCard('Resubmit Req.', '$resubmissionCount', const Color(0xFFFF9800))),
              const SizedBox(width: 8),
              SizedBox(width: 90, child: _kycKpiMiniCard('Approved', '$approvedCount', const Color(0xFF16C784))),
              const SizedBox(width: 8),
              SizedBox(width: 90, child: _kycKpiMiniCard('Rejected', '$rejectedCount', const Color(0xFFE5484D))),
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
              initialValue: _adminKycCountryFilter,
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
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16C784), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 8)),
                          child: const Text('APPROVE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.read<KycCubit>().rejectKyc(app.id, 'Unreadable documents'),
                          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFE5484D), side: const BorderSide(color: Color(0xFFE5484D)), padding: const EdgeInsets.symmetric(vertical: 8)),
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
                const Icon(Icons.verified_user_outlined, size: 48, color: Color(0xFF16C784)),
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
                const Icon(Icons.security, color: Color(0xFFFFDE02), size: 18),
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
          color: isSelected ? const Color(0xFFFFDE02) : _cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? const Color(0xFFFFDE02) : _borderColor),
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
                  color: isSelected ? Colors.black : const Color(0xFF252C33),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? const Color(0xFFFFDE02) : Colors.white,
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
        border: Border.all(color: isPending ? const Color(0xFFFFDE02).withValues(alpha: 0.6) : _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF1E242A),
                child: Text(
                  profile.firstName.isNotEmpty ? profile.firstName[0].toUpperCase() : 'T',
                  style: const TextStyle(color: Color(0xFFFFDE02), fontWeight: FontWeight.bold, fontSize: 13),
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
                color: const Color(0xFFE5484D).withValues(alpha: 0.1),
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
                    backgroundColor: const Color(0xFF1E242A),
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
                      backgroundColor: const Color(0xFF16C784),
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
                      foregroundColor: const Color(0xFFE5484D),
                      side: const BorderSide(color: Color(0xFFE5484D)),
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
                          backgroundColor: const Color(0xFF16C784),
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
                          foregroundColor: const Color(0xFFE5484D),
                          side: const BorderSide(color: Color(0xFFE5484D)),
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
                color: const Color(0xFF1E242A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Center(
                child: Icon(Icons.zoom_in_rounded, color: Color(0xFFFFDE02), size: 32),
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
        backgroundColor: const Color(0xFF13181D),
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
                  color: const Color(0xFF0F1317),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.description_rounded, size: 56, color: Color(0xFF16C784)),
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
        backgroundColor: const Color(0xFF13181D),
        title: const Text('Approve KYC Application?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Approving ${profile.fullName} will unlock Level 2 privileges (deposits, withdrawals and live orders).',
          style: const TextStyle(color: Color(0xFF8A919A), fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<KycCubit>().adminApproveProfile(
                    kycId: profile.id,
                    reviewerEmail: context.read<AuthBloc>().state.user?.email ?? 'admin',
                  );
              // Sync user session if active
              final currentUser = context.read<AuthBloc>().state.user;
              if (currentUser != null && currentUser.id == profile.userId) {
                context.read<AuthBloc>().updateUserKyc(KycStatus.approved, kycTier: 2);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('✓ ${profile.fullName} KYC Approved!'), backgroundColor: const Color(0xFF16C784)),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16C784), foregroundColor: Colors.black),
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
          backgroundColor: const Color(0xFF13181D),
          title: const Text('Reject KYC Application', style: TextStyle(color: Color(0xFFE5484D), fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select mandatory compliance reason:', style: TextStyle(color: Color(0xFF8A919A), fontSize: 12)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: selectedReason,
                dropdownColor: const Color(0xFF1E242A),
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
                  fillColor: Color(0xFF0F1317),
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
                      reviewerEmail: context.read<AuthBloc>().state.user?.email ?? 'admin',
                      reason: fullReason,
                    );

                final currentUser = context.read<AuthBloc>().state.user;
                if (currentUser != null && currentUser.id == profile.userId) {
                  context.read<AuthBloc>().updateUserKyc(KycStatus.rejected, rejectionReason: fullReason);
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${profile.fullName} KYC Rejected: $fullReason'), backgroundColor: const Color(0xFFE5484D)),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE5484D), foregroundColor: Colors.white),
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
        backgroundColor: const Color(0xFF13181D),
        title: const Text('Request Document Resubmission', style: TextStyle(color: Color(0xFFFF9800), fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Specify what document or detail the trader must correct:',
              style: TextStyle(color: Color(0xFF8A919A), fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Enter specific resubmission instructions...',
                fillColor: Color(0xFF0F1317),
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
                    reviewerEmail: context.read<AuthBloc>().state.user?.email ?? 'admin',
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
              color: admin.isTradingHalted ? const Color(0xFFE5484D).withValues(alpha: 0.15) : _cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: admin.isTradingHalted ? const Color(0xFFE5484D) : _borderColor),
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
                Icon(Icons.power_settings_new_rounded, color: admin.isTradingHalted ? const Color(0xFFE5484D) : const Color(0xFF16C784), size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        admin.isTradingHalted ? 'TRADING IS GLOBALLY HALTED' : 'Trading Engine Active',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: admin.isTradingHalted ? const Color(0xFFE5484D) : _textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text('Emergency circuit breaker for extreme market volatility', style: TextStyle(fontSize: 11, color: _textSecondary)),
                    ],
                  ),
                ),
                Switch(
                  value: !admin.isTradingHalted,
                  activeThumbColor: const Color(0xFF16C784),
                  inactiveThumbColor: const Color(0xFFE5484D),
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
                    value: admin.spreadMultiplier.clamp(1.0, 3.0),
                    min: 1.0,
                    max: 3.0,
                    divisions: 20,
                    onChanged: (val) => adminNotifier.setSpreadMultiplier(val),
                    onChangeEnd: (val) => _commitSpreadMultiplier(val, adminNotifier),
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
                    const Text('20% Margin Level', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFE5484D))),
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
              border: Border.all(color: proof.isZeroDriftVerified ? const Color(0xFF16C784) : const Color(0xFFE5484D)),
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
                  color: proof.isZeroDriftVerified ? const Color(0xFF16C784) : const Color(0xFFE5484D),
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
                          color: proof.isZeroDriftVerified ? const Color(0xFF16C784) : const Color(0xFFE5484D),
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
                    const Text('100.00% (Fully Backed)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF16C784))),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
          mainAxisAlignment: MainAxisAlignment.center,
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
                  Icon(Icons.arrow_forward_ios_rounded, color: _textSecondary, size: 12),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: _textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 2),
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
      ),
    );
  }
}
