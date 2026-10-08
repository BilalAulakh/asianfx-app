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
import '../common/widgets/balance_pill.dart';
import '../common/widgets/symbol_badge.dart';
import 'widgets/order_placement_modal.dart';

const _green = ExnessChartColors.bull;
const _red = ExnessChartColors.bear;

/// Exness-style trading screen: balance pill, symbol picker over a full-height
/// chart, timeframe / chart-type chips, and big Sell / Buy buttons with the
/// spread between them.
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  ChartStyle _chartStyle = ChartStyle.candlestick;

  double _chartScale = 1.0;

  /// Exness timeframe label: "1 m", "5 m", "1 H", "1 D".
  static String _tfLabel(ChartTimeframe tf) {
    final l = tf.label;
    final unit = l.substring(l.length - 1);
    return '${l.substring(0, l.length - 1)} ${unit == 'M' ? 'm' : unit}';
  }

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

    final isDark = context.isDarkMode;
    final textPrimary = context.textPrimaryColor;
    final textSecondary = context.textSecondaryColor;
    final bg = isDark ? ExnessChartColors.darkBg : context.scaffoldBg;
    final chipBg = isDark ? const Color(0xFF232B33) : const Color(0xFFEFF2F5);
    final rowBg = isDark ? const Color(0xFF1A2229) : const Color(0xFFF8FAFC);
    final accent = isDark ? const Color(0xFFFFDE02) : const Color(0xFFB7791F);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header: balance pill (Exness) ─────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  const SizedBox(width: 40),
                  const Spacer(),
                  const BalancePill(),
                  const Spacer(),
                  SizedBox(
                    width: 40,
                    child: authUser?.role == UserRole.admin
                        ? IconButton(
                            tooltip: 'Admin Portal',
                            onPressed: () => context.push(AppRoutes.admin),
                            icon: Icon(Icons.admin_panel_settings_rounded, color: accent),
                          )
                        : null,
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
                      ? _red.withValues(alpha: 0.2)
                      : const Color(0xFFFFB300).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: account.isStopOutLiquidation ? _red : const Color(0xFFFFB300),
                  ),
                ),
                child: Text(
                  engineState.lastAlertMessage!,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: account.isStopOutLiquidation ? _red : const Color(0xFFFFB300),
                  ),
                ),
              ),

            // ── Chart with the symbol picker on top ───────────────────────
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    top: 36,
                    child: CandlestickChartCanvas(
                      candles: candles,
                      timeframe: currentTf,
                      viewKey: '$activeSymbol/${currentTf.name}',
                      onNeedOlderHistory: () => context.read<MarketBloc>().add(MarketLoadOlderCandlesEvent()),
                      style: _chartStyle,
                      priceDecimals: live.displayDecimals,
                      currentPrice: live.midPrice.toDouble(),
                      bid: live.bid.toDouble(),
                      ask: live.ask.toDouble(),
                      scale: _chartScale,
                      onScaleChanged: (s) => setState(() => _chartScale = s),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 4,
                    child: InkWell(
                      onTap: () => _showSymbolPicker(context, instruments, activeSymbol),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SymbolBadge(symbol: live.symbol),
                            const SizedBox(width: 8),
                            Text(
                              live.symbol,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                              ),
                            ),
                            Icon(Icons.keyboard_arrow_down_rounded, color: textSecondary, size: 22),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Timeframe & chart-type chips (Exness) ─────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Row(
                children: [
                  _ToolChip(
                    color: chipBg,
                    onTap: () => _showTimeframePicker(context, currentTf),
                    child: Text(
                      _tfLabel(currentTf),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ToolChip(
                    color: chipBg,
                    onTap: () => setState(() {
                      _chartStyle =
                          _chartStyle == ChartStyle.candlestick ? ChartStyle.line : ChartStyle.candlestick;
                    }),
                    child: Icon(
                      _chartStyle == ChartStyle.candlestick
                          ? Icons.candlestick_chart_outlined
                          : Icons.show_chart_rounded,
                      size: 18,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // ── Open trades & pending orders ──────────────────────────────
            if (engineState.openPositions.isNotEmpty || engineState.pendingOrders.isNotEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: rowBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          engineState.pendingOrders.isNotEmpty
                              ? 'Open (${engineState.openPositions.length}) • Pending (${engineState.pendingOrders.length})'
                              : 'Open (${engineState.openPositions.length})',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        if (engineState.openPositions.isNotEmpty)
                          Text(
                            '${engineState.totalUnrealizedPnl >= Decimal.zero ? '+' : ''}${MoneyMath.formatDec(engineState.totalUnrealizedPnl, 2)} USD',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: engineState.totalUnrealizedPnl >= Decimal.zero
                                  ? const Color(0xFF00C27A)
                                  : _red,
                            ),
                          ),
                      ],
                    ),
                    ...engineState.openPositions.take(3).map((trade) {
                      final isProfitable = trade.unrealizedPnl >= Decimal.zero;
                      return _TradeRow(
                        sideLabel: trade.isBuy ? 'Buy' : 'Sell',
                        sideColor: trade.isBuy ? _green : _red,
                        title: '${trade.symbol} • ${trade.lots} lot',
                        value: '${isProfitable ? '+' : ''}${MoneyMath.formatDec(trade.unrealizedPnl, 2)} USD',
                        valueColor: isProfitable ? const Color(0xFF00C27A) : _red,
                        actionLabel: 'Close',
                        onAction: () => context.read<TradingEngineBloc>().closePosition(trade.id),
                        textColor: textPrimary,
                      );
                    }),
                    ...engineState.pendingOrders.take(3).map((order) {
                      return _TradeRow(
                        sideLabel: '${order.type.name} ${order.side.name}',
                        sideColor: accent,
                        title: '${order.symbol} • ${order.lots} lot',
                        value: '@ ${MoneyMath.formatDec(order.targetPrice ?? order.openPrice, 2)}',
                        valueColor: textSecondary,
                        actionLabel: 'Cancel',
                        onAction: () => context.read<TradingEngineBloc>().cancelPendingOrder(order.id),
                        textColor: textPrimary,
                      );
                    }),
                  ],
                ),
              ),

            // ── Sell / Buy with the spread between them (Exness) ──────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _PriceButton(
                          label: 'Sell',
                          price: MoneyMath.formatDec(live.bid, live.displayDecimals),
                          color: _red,
                          onTap: () => OrderPlacementModal.show(context, instrument: live, side: OrderSide.sell),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _PriceButton(
                          label: 'Buy',
                          price: MoneyMath.formatDec(live.ask, live.displayDecimals),
                          color: _green,
                          onTap: () => OrderPlacementModal.show(context, instrument: live, side: OrderSide.buy),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    bottom: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        MoneyMath.formatDec(live.spread, live.decimals),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: textSecondary,
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

  void _showTimeframePicker(BuildContext context, ChartTimeframe current) {
    final isDark = context.isDarkMode;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C242B) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                current.description,
                style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: sheetContext.textSecondaryColor),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: ChartTimeframe.values.map((tf) {
                  final sel = tf == current;
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      context.read<MarketBloc>().add(MarketSelectTimeframeEvent(tf));
                      Navigator.pop(sheetContext);
                    },
                    child: Container(
                      width: 60,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sel
                            ? (isDark ? const Color(0xFF4A535B) : const Color(0xFFD5DAE0))
                            : (isDark ? const Color(0xFF2A333B) : const Color(0xFFEFF2F5)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _tfLabel(tf).replaceAll(' ', ''),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          color: sheetContext.textPrimaryColor,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSymbolPicker(BuildContext context, List<InstrumentEntity> instruments, String activeSymbol) {
    final isDark = context.isDarkMode;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1C242B) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scroll) => ListView.builder(
          controller: scroll,
          padding: const EdgeInsets.symmetric(vertical: 10),
          itemCount: instruments.length,
          itemBuilder: (_, i) {
            final inst = instruments[i];
            final up = inst.isPositiveChange;
            return ListTile(
              selected: inst.symbol == activeSymbol,
              selectedTileColor: isDark ? const Color(0xFF232B33) : const Color(0xFFF1F4F7),
              leading: SymbolBadge(symbol: inst.symbol, size: 30),
              title: Text(
                inst.symbol,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: sheetContext.textPrimaryColor,
                ),
              ),
              subtitle: Text(
                inst.name,
                style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: sheetContext.textSecondaryColor),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    MoneyMath.formatDec(inst.bid, inst.displayDecimals),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: sheetContext.textPrimaryColor,
                    ),
                  ),
                  Text(
                    '${up ? '↑' : '↓'} ${inst.change24h.abs().toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: up ? const Color(0xFF00C27A) : _red,
                    ),
                  ),
                ],
              ),
              onTap: () {
                context.read<MarketBloc>().add(MarketSelectSymbolEvent(inst.symbol));
                Navigator.pop(sheetContext);
              },
            );
          },
        ),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  final Widget child;

  const _ToolChip({required this.color, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 34,
          constraints: const BoxConstraints(minWidth: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

/// Exness Sell / Buy button: small label over the bold price.
class _PriceButton extends StatelessWidget {
  final String label;
  final String price;
  final Color color;
  final VoidCallback onTap;

  const _PriceButton({required this.label, required this.price, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Text(
                label,
                style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white),
              ),
              const SizedBox(height: 1),
              Text(
                price,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TradeRow extends StatelessWidget {
  final String sideLabel;
  final Color sideColor;
  final String title;
  final String value;
  final Color valueColor;
  final String actionLabel;
  final VoidCallback onAction;
  final Color textColor;

  const _TradeRow({
    required this.sideLabel,
    required this.sideColor,
    required this.title,
    required this.value,
    required this.valueColor,
    required this.actionLabel,
    required this.onAction,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Text(
            sideLabel,
            style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: sideColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: textColor),
            ),
          ),
          Text(
            value,
            style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: valueColor),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: _red.withValues(alpha: 0.7)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                actionLabel,
                style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: _red),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
