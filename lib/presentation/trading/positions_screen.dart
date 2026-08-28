import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/math/money_math.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/trading_entities.dart';
import '../../providers/trading_engine_provider.dart';
import '../../providers/ledger_provider.dart';

class PositionsScreen extends ConsumerStatefulWidget {
  const PositionsScreen({super.key});

  @override
  ConsumerState<PositionsScreen> createState() => _PositionsScreenState();
}

class _PositionsScreenState extends ConsumerState<PositionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engineState = ref.watch(tradingEngineProvider);
    final account = engineState.accountState;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151D28),
        elevation: 0,
        title: const Text(
          'Positions & Portfolio',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFFD600),
          indicatorWeight: 3,
          labelColor: const Color(0xFFFFD600),
          unselectedLabelColor: const Color(0xFF848E9C),
          labelStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 13),
          tabs: [
            Tab(text: 'Open (${engineState.openPositions.length})'),
            Tab(text: 'Pending (${engineState.pendingOrders.length})'),
            Tab(text: 'History (${engineState.closedTrades.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Risk & Financial Account Overview Card ────────────────────────
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF162030), Color(0xFF0F1622)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: account.isMarginCall ? AppColors.loss : const Color(0xFF222F44),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TOTAL EQUITY',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF848E9C),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          MoneyMath.formatCurrency(account.equity),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'UNREALIZED PnL',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF848E9C),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          MoneyMath.formatPnL(account.unrealizedPnl),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: account.unrealizedPnl >= Decimal.zero
                                ? const Color(0xFF00D68F)
                                : const Color(0xFFFF4757),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: Color(0xFF222F44), height: 1),
                const SizedBox(height: 12),

                // 4-Quadrant Account Metrics
                Row(
                  children: [
                    _metricCell('Ledger Balance', MoneyMath.formatCurrency(account.ledgerBalance)),
                    _metricCell('Free Margin', MoneyMath.formatCurrency(account.freeMargin)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _metricCell('Used Margin', MoneyMath.formatCurrency(account.usedMargin)),
                    _metricCell(
                      'Margin Level',
                      account.usedMargin > Decimal.zero
                          ? '${account.marginLevelPercent.toDouble().toStringAsFixed(1)}%'
                          : 'Safe (100%)',
                      highlightColor: account.isMarginCall
                          ? AppColors.loss
                          : const Color(0xFF00D68F),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Tab Views ───────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 1. Open Positions
                _buildOpenPositionsList(engineState.openPositions),

                // 2. Pending Orders
                _buildPendingOrdersList(engineState.pendingOrders),

                // 3. Closed Trades History
                _buildHistoryList(engineState.closedTrades),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpenPositionsList(List<TradeEntity> positions) {
    if (positions.isEmpty) {
      return const Center(
        child: Text(
          'No open trading positions.',
          style: TextStyle(fontFamily: 'Inter', color: Color(0xFF848E9C)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: positions.length,
      itemBuilder: (context, idx) {
        final pos = positions[idx];
        final isProfit = pos.unrealizedPnl >= Decimal.zero;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF151D28),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1C2535)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Symbol, Side Badge, Lots, Floating PnL
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: pos.isBuy
                          ? const Color(0xFF00D68F).withOpacity(0.15)
                          : const Color(0xFFFF4757).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      pos.isBuy ? 'BUY' : 'SELL',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: pos.isBuy ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${pos.symbol} • ${pos.lots.toDouble().toStringAsFixed(2)} Lots',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    MoneyMath.formatPnL(pos.unrealizedPnl),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: isProfit ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Price Details (Entry -> Current Price)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Entry: ${MoneyMath.formatDec(pos.openPrice, 2)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF848E9C)),
                  ),
                  const Icon(Icons.arrow_forward, size: 14, color: Color(0xFF848E9C)),
                  Text(
                    'Current: ${MoneyMath.formatDec(pos.currentPrice, 2)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    'Margin: ${MoneyMath.formatCurrency(pos.requiredMargin)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFFFFD600)),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Close Position Button
              OutlinedButton(
                onPressed: () async {
                  await ref.read(tradingEngineProvider.notifier).closePosition(pos.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF1E2838),
                        content: Text(
                          'Position ${pos.symbol} Closed. PnL booked to Double-Entry Ledger.',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF4757),
                  side: const BorderSide(color: Color(0xFFFF4757)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  'CLOSE POSITION & SETTLE LEDGER',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPendingOrdersList(List<TradeEntity> orders) {
    if (orders.isEmpty) {
      return const Center(
        child: Text(
          'No pending limit or stop orders.',
          style: TextStyle(fontFamily: 'Inter', color: Color(0xFF848E9C)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: orders.length,
      itemBuilder: (context, idx) {
        final ord = orders[idx];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF151D28),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1C2535)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${ord.type.name.toUpperCase()} ${ord.side.name.toUpperCase()} • ${ord.symbol}',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Target: ${MoneyMath.formatDec(ord.targetPrice ?? ord.openPrice, 2)} • Lots: ${ord.lots.toDouble().toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF848E9C)),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.cancel_outlined, color: Color(0xFFFF4757)),
                onPressed: () {
                  ref.read(tradingEngineProvider.notifier).cancelPendingOrder(ord.id);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryList(List<TradeEntity> trades) {
    if (trades.isEmpty) {
      return const Center(
        child: Text(
          'No closed trades recorded yet.',
          style: TextStyle(fontFamily: 'Inter', color: Color(0xFF848E9C)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: trades.length,
      itemBuilder: (context, idx) {
        final t = trades[idx];
        final isProfit = t.realizedPnl >= Decimal.zero;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF151D28),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1C2535)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: t.isBuy
                      ? const Color(0xFF00D68F).withOpacity(0.15)
                      : const Color(0xFFFF4757).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  t.isBuy ? 'BUY' : 'SELL',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: t.isBuy ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${t.symbol} • ${t.lots.toDouble().toStringAsFixed(2)} Lots',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Closed: ${t.closePrice != null ? MoneyMath.formatDec(t.closePrice!, 2) : '-'} • Reason: ${t.closeReason ?? 'manual'}',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF848E9C)),
                    ),
                  ],
                ),
              ),
              Text(
                MoneyMath.formatPnL(t.realizedPnl),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: isProfit ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _metricCell(String label, String value, {Color? highlightColor}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              color: Color(0xFF848E9C),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: highlightColor ?? Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
