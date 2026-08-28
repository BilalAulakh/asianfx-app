import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/trading_entities.dart';
import '../../providers/auth_provider.dart';
import '../../providers/market_provider.dart';
import '../../providers/trading_provider.dart';
import '../../providers/trading_engine_provider.dart';
import '../../providers/wallet_provider.dart';
import '../kyc/kyc_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with AutomaticKeepAliveClientMixin {
  int _selectedOrderTab = 0; // 0: Open, 1: Pending, 2: Closed

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final instruments = ref.watch(instrumentsProvider);
    final wallet = ref.watch(walletProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F141C),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── App Bar ──────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Accounts',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Column(
                children: [
                  // ── Yellow KYC Banner ───────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
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
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF332F1A),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.person_outline_rounded,
                                  color: Color(0xFFFFD600),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Add your profile information',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Takes about 3-5 minutes',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 12,
                                        color: Color(0xFF848E9C),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {},
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Color(0xFF3B414D)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  child: const Text('Learn more', style: TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const KycScreen()),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFFD600),
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  child: const Text('Complete', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Standard Account Card ──────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E232A),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF2B313A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Standard',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF848E9C),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '# 256797955',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 13,
                                      color: Colors.white.withOpacity(0.5),
                                    ),
                                  ),
                                ],
                              ),
                              const Icon(Icons.settings_outlined, color: Color(0xFF848E9C), size: 20),
                            ],
                          ),

                          const SizedBox(height: 10),

                          Row(
                            children: [
                              _chip('Real'),
                              const SizedBox(width: 6),
                              _chip('MT5'),
                              const SizedBox(width: 6),
                              _chip('Standard'),
                            ],
                          ),

                          const SizedBox(height: 16),

                          Text(
                            '${wallet.balance.toStringAsFixed(2)} USD',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),

                          const SizedBox(height: 20),

                          // 4 Action Circle Buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _actionButton(
                                icon: Icons.candlestick_chart_rounded,
                                label: 'Trade',
                                isPrimary: true,
                                onTap: () => context.go('/app/trade'),
                              ),
                              _actionButton(
                                icon: Icons.arrow_downward_rounded,
                                label: 'Deposit',
                                onTap: () => context.go('/app/wallet'),
                              ),
                              _actionButton(
                                icon: Icons.arrow_upward_rounded,
                                label: 'Withdraw',
                                onTap: () => context.go('/app/wallet'),
                              ),
                              _actionButton(
                                icon: Icons.swap_horiz_rounded,
                                label: 'Transfer',
                                onTap: () => context.go('/app/wallet'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Welcome Banner Carousel ──────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E232A).withOpacity(0.6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF2B313A)),
                      ),
                      child: const Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Welcome to Exness',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Happy to have you on board.',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    color: Color(0xFF848E9C),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.schedule_rounded, color: Color(0xFF2EBD85), size: 36),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Orders Section ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                _orderTab(0, 'Open'),
                                const SizedBox(width: 16),
                                _orderTab(1, 'Pending'),
                                const SizedBox(width: 16),
                                _orderTab(2, 'Closed'),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.swap_vert_rounded, color: Color(0xFF848E9C)),
                              onPressed: () {},
                            ),
                          ],
                        ),
                        const Divider(color: Color(0xFF2B313A), height: 1),

                        const SizedBox(height: 16),

                        // ── Tab 0: OPEN ORDERS ──
                        if (_selectedOrderTab == 0) ...[
                          Consumer(
                            builder: (context, ref, _) {
                              final engine = ref.watch(tradingEngineProvider);
                              final openTrades = engine.openPositions;

                              if (openTrades.isEmpty) {
                                return Column(
                                  children: [
                                    const Text(
                                      'No open orders. Find your next trade:',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 13,
                                        color: Color(0xFF848E9C),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    SizedBox(
                                      height: 90,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: instruments.take(5).length,
                                        itemBuilder: (context, idx) {
                                          final inst = instruments[idx];
                                          return Padding(
                                            padding: const EdgeInsets.only(right: 12),
                                            child: GestureDetector(
                                              onTap: () => context.push('/app/markets/chart/${inst.symbol}'),
                                              child: Container(
                                                width: 150,
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF1E232A),
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(color: const Color(0xFF2B313A)),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Text(
                                                      inst.symbol,
                                                      style: const TextStyle(
                                                        fontFamily: 'Inter',
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 13,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Text(
                                                          inst.bid.toStringAsFixed(inst.decimals),
                                                          style: const TextStyle(
                                                            fontFamily: 'Inter',
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w600,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                        Text(
                                                          '${inst.changePercent >= 0 ? '+' : ''}${inst.changePercent.toStringAsFixed(2)}%',
                                                          style: TextStyle(
                                                            fontFamily: 'Inter',
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.w600,
                                                            color: inst.changePercent >= 0
                                                                ? const Color(0xFF0ECB81)
                                                                : const Color(0xFFF6465D),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              }

                              return ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: openTrades.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, i) {
                                  final trade = openTrades[i];
                                  final isBuy = trade.side == OrderSide.buy;
                                  final isProfit = trade.floatingPl >= 0;

                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E232A),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: const Color(0xFF2B313A)),
                                    ),
                                    child: Row(
                                      children: [
                                        // Left Side (Side badge + Symbol + Open Price)
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: isBuy
                                                      ? const Color(0xFF0ECB81).withOpacity(0.15)
                                                      : const Color(0xFFF6465D).withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  isBuy ? 'BUY' : 'SELL',
                                                  style: TextStyle(
                                                    fontFamily: 'Inter',
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: isBuy ? const Color(0xFF0ECB81) : const Color(0xFFF6465D),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      '${trade.symbol} • ${trade.lotSize.toStringAsFixed(2)}L',
                                                      style: const TextStyle(
                                                        fontFamily: 'Inter',
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.white,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '@ \$${trade.openPrice.toStringAsFixed(trade.symbol.contains('BTC') ? 2 : 4)}',
                                                      style: const TextStyle(
                                                        fontFamily: 'Inter',
                                                        fontSize: 11,
                                                        color: Color(0xFF848E9C),
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        const SizedBox(width: 8),

                                        // Right Side (Floating P&L + Close Button)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  '${isProfit ? '+' : ''}\$${trade.floatingPl.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    fontFamily: 'Inter',
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: isProfit ? const Color(0xFF0ECB81) : const Color(0xFFF6465D),
                                                  ),
                                                ),
                                                const SizedBox(height: 1),
                                                const Text(
                                                  'Floating P&L',
                                                  style: TextStyle(color: Color(0xFF848E9C), fontSize: 9),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 4),
                                            IconButton(
                                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                              padding: EdgeInsets.zero,
                                              icon: const Icon(Icons.close_rounded, color: Color(0xFFF6465D), size: 18),
                                              tooltip: 'Close Position',
                                              onPressed: () {
                                                ref.read(tradingEngineProvider.notifier).closePosition(trade.id);
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Closed ${trade.symbol} position!'),
                                                    backgroundColor: const Color(0xFF1E232A),
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ]
                        // ── Tab 1: PENDING ORDERS ──
                        else if (_selectedOrderTab == 1) ...[
                          Consumer(
                            builder: (context, ref, _) {
                              final engine = ref.watch(tradingEngineProvider);
                              final pending = engine.pendingOrders;

                              if (pending.isEmpty) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 24),
                                    child: Text(
                                      'No pending limit/stop orders',
                                      style: TextStyle(color: Color(0xFF848E9C), fontSize: 13),
                                    ),
                                  ),
                                );
                              }

                              return ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: pending.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, i) {
                                  final order = pending[i];
                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E232A),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFF2B313A)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${order.isBuy ? "BUY" : "SELL"} ${order.symbol} @ \$${order.targetPrice?.toStringAsFixed(2)}',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.cancel_outlined, color: Color(0xFFF6465D), size: 18),
                                          onPressed: () => ref.read(tradingEngineProvider.notifier).cancelPendingOrder(order.id),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ]
                        // ── Tab 2: CLOSED TRADES ──
                        else ...[
                          Consumer(
                            builder: (context, ref, _) {
                              final engine = ref.watch(tradingEngineProvider);
                              final history = engine.closedTrades;

                              if (history.isEmpty) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 24),
                                    child: Text('No closed trades yet', style: TextStyle(color: Color(0xFF848E9C))),
                                  ),
                                );
                              }

                              return ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: history.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, i) {
                                  final trade = history[i];
                                  final isBuy = trade.side == OrderSide.buy;
                                  final isProfit = trade.realizedPnl >= Decimal.zero;

                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E232A),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFF2B313A)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${isBuy ? "BUY" : "SELL"} ${trade.symbol} • ${trade.lotSize.toStringAsFixed(2)} Lots',
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                            Text(
                                              'Closed @ \$${(trade.closePrice ?? trade.openPrice).toStringAsFixed(trade.symbol.contains('BTC') ? 2 : 4)}',
                                              style: const TextStyle(color: Color(0xFF848E9C), fontSize: 11),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          '${isProfit ? '+' : ''}\$${trade.realizedPnl.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: isProfit ? const Color(0xFF0ECB81) : const Color(0xFFF6465D),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF2B313A),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: Color(0xFF848E9C),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isPrimary ? const Color(0xFFFFD600) : const Color(0xFF2B313A),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isPrimary ? Colors.black : Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderTab(int index, String label) {
    final isSelected = _selectedOrderTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedOrderTab = index),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : const Color(0xFF848E9C),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 2,
            width: 40,
            color: isSelected ? const Color(0xFFFFD600) : Colors.transparent,
          ),
        ],
      ),
    );
  }
}
