import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../blocs/blocs.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';

import '../../core/math/money_math.dart';
import '../../domain/entities/chart_entities.dart';
import '../../domain/entities/trading_entities.dart';
import '../../domain/entities/user_entity.dart';
import '../charts/candlestick_chart_canvas.dart';
import 'widgets/order_placement_modal.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  ChartStyle _chartStyle = ChartStyle.candlestick;

  double _chartScale = 1.0;

  @override
  Widget build(BuildContext context) {
    final marketState = context.watch<MarketBloc>().state;
    final activeSymbol = marketState.activeSymbol;
    final instruments = marketState.instruments;
    final selectedInstrument = marketState.selectedInstrument ??
        (instruments.isNotEmpty ? instruments.first : marketState.getInstrument('XAU/USD'));

    final live = selectedInstrument;
    final candles = marketState.candles;
    final currentTf = marketState.selectedTimeframe;
    final engineState = context.watch<TradingEngineBloc>().state;
    final account = engineState.accountState;
    final authUser = context.watch<AuthBloc>().state.user;

    // Palette for the active theme (light / dark).
    final isDark = context.isDarkMode;
    final textPrimary = context.textPrimaryColor;
    final textSecondary = context.textSecondaryColor;
    final cardBg = context.cardBg;
    final border = context.subtleBorderColor;
    final toolBg = isDark ? const Color(0xFF162030) : const Color(0xFFF1F5F9);
    final rowBg = isDark ? const Color(0xFF0F1520) : const Color(0xFFF8FAFC);
    final accent = isDark ? const Color(0xFFFFD600) : const Color(0xFFB7791F);

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Institutional Header & Role Badge ──────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: [
                  // Logo / App Title
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD600),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'MM',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'FXAsian Terminal',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tier-1 Double-Entry Liquidity',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Admin Active Top Banner & Portal Quick-Access ───────────────
            if (authUser?.role == UserRole.admin)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? const [Color(0xFF2A2000), Color(0xFF181300)]
                        : const [Color(0xFFFFF8E1), Color(0xFFFFF1C2)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent, width: 1.2),
                ),
                child: Row(
                  children: [
                    Icon(Icons.admin_panel_settings_rounded, color: accent, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SUPER ADMIN CONSOLE ACTIVE',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: accent,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'Dealing Desk • Spread Control • KYC Approvals',
                            style: TextStyle(
                                fontSize: 10, color: isDark ? const Color(0xFFE5C158) : const Color(0xFF8A6D00)),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => context.push(AppRoutes.admin),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD600),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                      child: const Text('Open Admin Portal'),
                    ),
                  ],
                ),
              ),

            // ── Live Risk & Margin Alert Banner (if Margin Call or Liquidation) ──
            if (engineState.lastAlertMessage != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: account.isStopOutLiquidation
                      ? const Color(0xFFFF4757).withValues(alpha: 0.2)
                      : const Color(0xFFFFB300).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: account.isStopOutLiquidation
                        ? const Color(0xFFFF4757)
                        : const Color(0xFFFFB300),
                  ),
                ),
                child: Text(
                  engineState.lastAlertMessage!,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: account.isStopOutLiquidation
                        ? const Color(0xFFFF4757)
                        : const Color(0xFFFFB300),
                  ),
                ),
              ),

            // ── Instrument Selector Tabs ───────────────────────────────────
            SizedBox(
              height: 38,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: instruments.length,
                itemBuilder: (context, idx) {
                  final inst = instruments[idx];
                  final isSelected = inst.symbol == activeSymbol;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: () {
                        context.read<MarketBloc>().add(MarketSelectSymbolEvent(inst.symbol));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark ? const Color(0xFF1E2838) : const Color(0xFFFFF8E1))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isSelected ? accent : border),
                        ),
                        child: Row(
                          children: [
                            Text(
                              inst.symbol,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? textPrimary : textSecondary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${inst.isPositiveChange ? '+' : ''}${inst.change24h.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: inst.isPositiveChange
                                    ? const Color(0xFF00D68F)
                                    : const Color(0xFFFF4757),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),

            // ── Live price ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border),
                ),
                child: Text(
                  MoneyMath.formatDec(live.midPrice, live.decimals),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Interactive Candlestick Chart Canvas ───────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: CandlestickChartCanvas(
                  candles: candles,
                  timeframe: currentTf,
                  symbol: activeSymbol,
                  style: _chartStyle,
                  priceDecimals: live.decimals,
                  currentPrice: live.midPrice.toDouble(),
                  scale: _chartScale,
                  onScaleChanged: (s) {
                    setState(() {
                      _chartScale = s;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 6),

            // ── Timeframe & Chart Zoom / Style Toolbar (Below Candles) ───────
            SizedBox(
              height: 34,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    ...ChartTimeframe.values.map((tf) {
                      final isSel = tf == currentTf;
                      return GestureDetector(
                        onTap: () {
                          context.read<MarketBloc>().add(MarketSelectTimeframeEvent(tf));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: isSel ? const Color(0xFFFFD600) : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tf.label,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                              color: isSel ? Colors.black : textSecondary,
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(width: 8),

                    // Dedicated Toolbar Zoom In (+) Button
                    InkWell(
                      onTap: () {
                        setState(() {
                          _chartScale = (_chartScale * 1.3).clamp(0.25, 6.0);
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: toolBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_in_rounded, color: accent, size: 14),
                            const SizedBox(width: 2),
                            Text('+', style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),

                    // Dedicated Toolbar Zoom Out (-) Button
                    InkWell(
                      onTap: () {
                        setState(() {
                          _chartScale = (_chartScale / 1.3).clamp(0.25, 6.0);
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: toolBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_out_rounded, color: accent, size: 14),
                            const SizedBox(width: 2),
                            Text('-', style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),

                    // Dedicated Toolbar Reset Zoom (↺) Button
                    InkWell(
                      onTap: () {
                        setState(() {
                          _chartScale = 1.0;
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: toolBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: border),
                        ),
                        child: Icon(Icons.fit_screen_rounded, color: textSecondary, size: 14),
                      ),
                    ),

                    // Chart Style Toggle Button
                    InkWell(
                      onTap: () {
                        setState(() {
                          _chartStyle = _chartStyle == ChartStyle.candlestick
                              ? ChartStyle.line
                              : ChartStyle.candlestick;
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: toolBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: border),
                        ),
                        child: Icon(
                          _chartStyle == ChartStyle.candlestick
                              ? Icons.candlestick_chart_rounded
                              : Icons.show_chart_rounded,
                          color: accent,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Live Active Positions & Pending Orders Drawer on Terminal Screen ──
            if (engineState.openPositions.isNotEmpty || engineState.pendingOrders.isNotEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: toolBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.show_chart_rounded, color: accent, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              engineState.pendingOrders.isNotEmpty
                                  ? 'Trades (${engineState.openPositions.length}) • Pending (${engineState.pendingOrders.length})'
                                  : 'Live Trades (${engineState.openPositions.length})',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: textPrimary,
                              ),
                            ),
                          ],
                        ),
                        if (engineState.openPositions.isNotEmpty)
                          Text(
                            'PnL: ${engineState.totalUnrealizedPnl >= Decimal.zero ? '+' : ''}\$${MoneyMath.formatDec(engineState.totalUnrealizedPnl, 2)}',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: engineState.totalUnrealizedPnl >= Decimal.zero
                                  ? const Color(0xFF00D68F)
                                  : const Color(0xFFFF4757),
                            ),
                          )
                        else
                          Text(
                            'Orders Waiting Fill',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              color: accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...engineState.openPositions.take(3).map((trade) {
                      final isProfitable = trade.unrealizedPnl >= Decimal.zero;
                      return Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: rowBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: trade.isBuy
                                ? const Color(0xFF00D68F).withValues(alpha: 0.3)
                                : const Color(0xFFFF4757).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: trade.isBuy
                                    ? const Color(0xFF00D68F).withValues(alpha: 0.2)
                                    : const Color(0xFFFF4757).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                trade.isBuy ? 'BUY' : 'SELL',
                                style: TextStyle(
                                  color: trade.isBuy
                                      ? const Color(0xFF00D68F)
                                      : const Color(0xFFFF4757),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${trade.symbol} (${trade.lots} lots)',
                              style: TextStyle(
                                color: textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${isProfitable ? '+' : ''}\$${MoneyMath.formatDec(trade.unrealizedPnl, 2)}',
                              style: TextStyle(
                                color: isProfitable ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => context.read<TradingEngineBloc>().closePosition(trade.id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF4757).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFFF4757)),
                                ),
                                child: const Text(
                                  'CLOSE',
                                  style: TextStyle(
                                    color: Color(0xFFFF4757),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    // ── Pending Limit & Stop Orders ──
                    ...engineState.pendingOrders.take(3).map((order) {
                      return Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: rowBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${order.type.name.toUpperCase()} ${order.side.name.toUpperCase()}',
                                style: TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${order.symbol} (${order.lots} lots)',
                              style: TextStyle(
                                color: textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Target: \$${MoneyMath.formatDec(order.targetPrice ?? order.openPrice, 2)}',
                              style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => context.read<TradingEngineBloc>().cancelPendingOrder(order.id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF4757).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFFF4757)),
                                ),
                                child: const Text(
                                  'CANCEL',
                                  style: TextStyle(
                                    color: Color(0xFFFF4757),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),

            // ── Bottom Order Execution Dock ───────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: cardBg,
                border: Border(
                  top: BorderSide(color: border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  // Sell Button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        OrderPlacementModal.show(
                          context,
                          instrument: live,
                          side: OrderSide.sell,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF4757),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text(
                        'SELL',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Buy Button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        OrderPlacementModal.show(
                          context,
                          instrument: live,
                          side: OrderSide.buy,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00D68F),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text(
                        'BUY',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
