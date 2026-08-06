import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/formatters.dart';
import '../../providers/auth_provider.dart';
import '../../providers/market_provider.dart';
import '../../domain/entities/trading_entities.dart';
import '../common/widgets/fx_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = ref.watch(authProvider).user;
    final wallet = ref.watch(walletProvider);
    final openTrades = ref.watch(openTradesProvider);
    final instruments = ref.watch(instrumentsProvider);

    final openOnly = openTrades.where((t) => t.isOpen).toList();
    final totalPl = openOnly.fold(0.0, (s, t) => s + t.floatingPl);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _buildAppBar(context, user?.fullName ?? 'Trader'),
          ),

          SliverToBoxAdapter(
            child: Column(
              children: [
                // ── Account Summary Card ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: _AccountSummaryCard(wallet: wallet, totalPl: totalPl),
                ),

                // ── Stats Row ─────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _StatsRow(wallet: wallet),
                ),
                const SizedBox(height: 24),

                // ── Market Overview ──────────────────────────────────────────
                _SectionHeader(
                  title: AppStrings.marketOverview,
                  onViewAll: () => context.go('/app/markets'),
                ),
                const SizedBox(height: 12),
                _MarketTickerList(instruments: instruments.take(6).toList()),
                const SizedBox(height: 24),

                // ── Open Positions ─────────────────────────────────────────────
                _SectionHeader(
                  title: AppStrings.openPositions,
                  badge: openOnly.length,
                  onViewAll: () => context.go('/app/trade'),
                ),
                const SizedBox(height: 12),
                openOnly.isEmpty
                    ? _EmptyState(
                        icon: Icons.show_chart_rounded,
                        message: AppStrings.noPositions,
                        subtitle: 'Start trading to see your open positions here.',
                      )
                    : _OpenPositionsList(trades: openOnly),
                const SizedBox(height: 24),

                // ── News / Alerts ─────────────────────────────────────────────
                _SectionHeader(title: 'Market News'),
                const SizedBox(height: 12),
                const _NewsSection(),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, String name) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 20,
        right: 20,
        bottom: 16,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A1628), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          // Avatar + Greeting
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getGreeting(),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name.split(' ').first,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const Spacer(),

          // Notification Bell
          Stack(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.darkBorder),
                ),
                child: const Icon(
                  Icons.notifications_outlined,
                  color: AppColors.textPrimary,
                  size: 20,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.loss,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(width: 10),

          // Profile Avatar
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: AppColors.primaryGradient,
            ),
            child: const Center(
              child: Text(
                'AR',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return '🌅 Good morning,';
    if (hour < 17) return '☀️ Good afternoon,';
    return '🌙 Good evening,';
  }
}

// ── Account Summary Card ────────────────────────────────────────────────────
class _AccountSummaryCard extends StatelessWidget {
  final WalletEntity wallet;
  final double totalPl;

  const _AccountSummaryCard({required this.wallet, required this.totalPl});

  @override
  Widget build(BuildContext context) {
    final isProfit = totalPl >= 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1E35), Color(0xFF0A1628)],
        ),
        border: Border.all(color: AppColors.darkBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPrimary.withAlpha(15),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Account Type Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.brandPrimary.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.brandPrimary.withAlpha(50)),
                ),
                child: const Text(
                  'LIVE ACCOUNT',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandPrimary,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.profit.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.profit,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Markets Open',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.profit,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Balance
          const Text(
            'Total Balance',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                AppFormatters.currency(wallet.balance),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -1,
                ),
              ),
              const Spacer(),
              // Floating P/L Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isProfit
                      ? AppColors.profit.withAlpha(20)
                      : AppColors.loss.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isProfit
                        ? AppColors.profit.withAlpha(50)
                        : AppColors.loss.withAlpha(50),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Floating P/L',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        color: isProfit ? AppColors.profit : AppColors.loss,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppFormatters.plAmount(totalPl),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isProfit ? AppColors.profit : AppColors.loss,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Equity Divider
          Container(height: 1, color: AppColors.darkBorder),
          const SizedBox(height: 16),

          // Equity
          Row(
            children: [
              _StatItem(label: 'Equity', value: AppFormatters.currency(wallet.equity)),
              const SizedBox(width: 1),
              _StatItem(label: 'Margin', value: AppFormatters.currency(wallet.margin)),
              const SizedBox(width: 1),
              _StatItem(
                label: 'Free Margin',
                value: AppFormatters.currency(wallet.freeMargin),
                valueColor: AppColors.brandPrimary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatItem({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats Row ────────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final WalletEntity wallet;
  const _StatsRow({required this.wallet});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MiniStatCard(
          icon: Icons.trending_up_rounded,
          iconColor: AppColors.profit,
          label: 'Daily P/L',
          value: '+\$124.50',
          isPositive: true,
        ),
        const SizedBox(width: 12),
        _MiniStatCard(
          icon: Icons.calendar_month_rounded,
          iconColor: AppColors.brandSecondary,
          label: 'Monthly P/L',
          value: '+\$1,847.20',
          isPositive: true,
        ),
        const SizedBox(width: 12),
        _MiniStatCard(
          icon: Icons.show_chart_rounded,
          iconColor: AppColors.info,
          label: 'Open Trades',
          value: '3',
          isPositive: null,
        ),
      ],
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool? isPositive;

  const _MiniStatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.isPositive,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isPositive == null
                    ? AppColors.textPrimary
                    : isPositive!
                        ? AppColors.profit
                        : AppColors.loss,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section Header ───────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final int? badge;
  final VoidCallback? onViewAll;

  const _SectionHeader({required this.title, this.badge, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (badge != null && badge! > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.brandPrimary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$badge',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (onViewAll != null)
            TextButton(
              onPressed: onViewAll,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
              ),
              child: const Text(
                'View All →',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppColors.brandPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Market Ticker List ────────────────────────────────────────────────────────
class _MarketTickerList extends ConsumerWidget {
  final List<InstrumentEntity> instruments;
  const _MarketTickerList({required this.instruments});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: instruments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final inst = instruments[i];
          return _TickerCard(instrument: inst);
        },
      ),
    );
  }
}

class _TickerCard extends ConsumerWidget {
  final InstrumentEntity instrument;
  const _TickerCard({required this.instrument});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch live price stream
    final priceStream = ref.watch(priceStreamProvider(instrument.symbol));
    final live = priceStream.when(
      data: (d) => d,
      loading: () => instrument,
      error: (_, __) => instrument,
    );

    final isPositive = live.isPositiveChange;

    return GestureDetector(
      onTap: () => context.push('/app/markets/chart/${instrument.symbol}'),
      child: Container(
        width: 130,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isPositive
                        ? AppColors.profit.withAlpha(20)
                        : AppColors.loss.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      instrument.symbol.substring(0, 2),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: isPositive ? AppColors.profit : AppColors.loss,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isPositive ? AppColors.profit.withAlpha(20) : AppColors.loss.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${isPositive ? '+' : ''}${live.change24h.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: isPositive ? AppColors.profit : AppColors.loss,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              instrument.symbol,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              live.bid.toStringAsFixed(instrument.decimals),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isPositive ? AppColors.profit : AppColors.loss,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Open Positions List ────────────────────────────────────────────────────
class _OpenPositionsList extends StatelessWidget {
  final List<TradeEntity> trades;
  const _OpenPositionsList({required this.trades});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: trades.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _PositionCard(trade: trades[i]),
    );
  }
}

class _PositionCard extends StatelessWidget {
  final TradeEntity trade;
  const _PositionCard({required this.trade});

  @override
  Widget build(BuildContext context) {
    final isBuy = trade.side == OrderSide.buy;
    final isProfit = trade.floatingPl >= 0;
    final duration = DateTime.now().difference(trade.openTime);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          // Side Indicator
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isBuy ? AppColors.profit.withAlpha(20) : AppColors.loss.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                isBuy ? 'B' : 'S',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isBuy ? AppColors.profit : AppColors.loss,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Symbol + Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      trade.symbol,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isBuy
                            ? AppColors.profit.withAlpha(20)
                            : AppColors.loss.withAlpha(20),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isBuy ? 'BUY' : 'SELL',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: isBuy ? AppColors.profit : AppColors.loss,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${trade.lotSize} lots @ ${trade.openPrice.toStringAsFixed(5)}  ·  ${AppFormatters.duration(duration)}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // P/L
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                AppFormatters.plAmount(trade.floatingPl),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isProfit ? AppColors.profit : AppColors.loss,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${isProfit ? '+' : ''}${(trade.floatingPl / (trade.lotSize * trade.openPrice / 10)).toStringAsFixed(1)} pips',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── News Section ────────────────────────────────────────────────────────────
class _NewsSection extends StatelessWidget {
  const _NewsSection();

  final List<Map<String, String>> _news = const [
    {
      'title': 'Fed Holds Rates Steady — Dollar Index Rallies',
      'source': 'Reuters',
      'time': '2h ago',
      'tag': 'Macro',
      'color': '0xFF3D91FF',
    },
    {
      'title': 'Gold Hits 3-Month High Amid Inflation Concerns',
      'source': 'Bloomberg',
      'time': '4h ago',
      'tag': 'Gold',
      'color': '0xFFFFB300',
    },
    {
      'title': 'Bitcoin Consolidates Above \$67K Ahead of ETF Decision',
      'source': 'CoinDesk',
      'time': '6h ago',
      'tag': 'Crypto',
      'color': '0xFF5C6BC0',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _news.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final item = _news[i];
        final color = Color(int.parse(item['color']!));
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item['tag']!,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['title']!,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          item['source']!,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: const BoxDecoration(
                            color: AppColors.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item['time']!,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Empty State ────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.brandPrimary.withAlpha(15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: AppColors.brandPrimary, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
