import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/math/money_math.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/chart_entities.dart';
import '../../domain/entities/trading_entities.dart';
import '../../domain/entities/user_entity.dart';
import '../../providers/auth_provider.dart';
import '../../providers/market_provider.dart';
import '../../providers/trading_engine_provider.dart';
import '../charts/candlestick_chart_canvas.dart';
import 'widgets/order_placement_modal.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  ChartStyle _chartStyle = ChartStyle.candlestick;

  double _chartScale = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCandles();
    });
  }

  void _loadCandles([String? customSymbol, ChartTimeframe? customTf]) {
    final sym = customSymbol ?? ref.read(activeSymbolProvider);
    final tf = customTf ?? ref.read(selectedTimeframeProvider);
    ref.read(marketFeedServiceProvider).fetchCandlesAsync(sym, tf).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeSymbol = ref.watch(activeSymbolProvider);
    final instruments = ref.watch(instrumentsProvider);
    final selectedInstrument = instruments.firstWhere(
      (i) => i.symbol == activeSymbol,
      orElse: () => instruments.first,
    );

    final liveStream = ref.watch(priceStreamProvider(selectedInstrument.symbol));
    final live = liveStream.when(
      data: (i) => i,
      loading: () => selectedInstrument,
      error: (_, __) => selectedInstrument,
    );

    final candles = ref.watch(ohlcProvider(selectedInstrument.symbol));
    final currentTf = ref.watch(selectedTimeframeProvider);
    final engineState = ref.watch(tradingEngineProvider);
    final account = engineState.accountState;
    final authUser = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
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
                          const Text(
                            'FXAsian Terminal',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
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
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),

                  // Quick Role Switcher Pill for Testing
                  PopupMenuButton<UserRole>(
                    onSelected: (role) {
                      ref.read(authProvider.notifier).switchRole(role);
                    },
                    color: const Color(0xFF1E2838),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF162030),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2B384E)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 14,
                            color: authUser?.role == UserRole.admin ||
                                    authUser?.role == UserRole.dealer
                                ? const Color(0xFFFFD600)
                                : const Color(0xFF00D68F),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            authUser?.role.name.toUpperCase() ?? 'CLIENT',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: authUser?.role == UserRole.admin ||
                                      authUser?.role == UserRole.dealer
                                  ? const Color(0xFFFFD600)
                                  : const Color(0xFF00D68F),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 16),
                        ],
                      ),
                    ),
                    itemBuilder: (ctx) => [
                      _roleMenuItem(UserRole.client, 'Trader'),
                      _roleMenuItem(UserRole.admin, 'Admin'),
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
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2A2000), Color(0xFF181300)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFD600), width: 1.2),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFFFFD600), size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SUPER ADMIN CONSOLE ACTIVE',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFFFD600),
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'Dealing Desk • Spread Control • KYC Approvals',
                            style: TextStyle(fontSize: 10, color: Color(0xFFE5C158)),
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
                      ? const Color(0xFFFF4757).withOpacity(0.2)
                      : const Color(0xFFFFB300).withOpacity(0.2),
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
                        ref.read(activeSymbolProvider.notifier).state = inst.symbol;
                        _loadCandles(inst.symbol);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF1E2838) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? const Color(0xFFFFD600) : const Color(0xFF1C2535),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              inst.symbol,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? Colors.white : const Color(0xFF848E9C),
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

            // ── Live Quote Bar (Bid / Ask / High / Low) ─────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF151D28),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1C2535)),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          MoneyMath.formatDec(live.midPrice, live.decimals),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F141C),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Spread: ${live.spreadPips.toStringAsFixed(1)} pips',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFFD600),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Markup: +${live.spreadMarkupPips}p',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10,
                                color: Color(0xFF848E9C),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            const Text('24h H: ', style: TextStyle(fontSize: 10, color: Color(0xFF848E9C))),
                            Text(
                              MoneyMath.formatDec(live.high24h, live.decimals),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Text('24h L: ', style: TextStyle(fontSize: 10, color: Color(0xFF848E9C))),
                            Text(
                              MoneyMath.formatDec(live.low24h, live.decimals),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Timeframe & Chart Zoom / Style Toolbar ───────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ...ChartTimeframe.values.map((tf) {
                    final isSel = tf == currentTf;
                    return GestureDetector(
                      onTap: () {
                        ref.read(selectedTimeframeProvider.notifier).state = tf;
                        _loadCandles(null, tf);
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
                            color: isSel ? Colors.black : const Color(0xFF848E9C),
                          ),
                        ),
                      ),
                    );
                  }),
                  const Spacer(),

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
                        color: const Color(0xFF162030),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF2B384E)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.zoom_in_rounded, color: Color(0xFFFFD600), size: 14),
                          SizedBox(width: 2),
                          Text('+', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
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
                        color: const Color(0xFF162030),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF2B384E)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.zoom_out_rounded, color: Color(0xFFFFD600), size: 14),
                          SizedBox(width: 2),
                          Text('-', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
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
                        color: const Color(0xFF162030),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF2B384E)),
                      ),
                      child: const Icon(Icons.fit_screen_rounded, color: Colors.white70, size: 14),
                    ),
                  ),

                  // Chart Style Toggle Button
                  IconButton(
                    icon: Icon(
                      _chartStyle == ChartStyle.candlestick
                          ? Icons.candlestick_chart_rounded
                          : Icons.show_chart_rounded,
                      color: const Color(0xFFFFD600),
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _chartStyle = _chartStyle == ChartStyle.candlestick
                            ? ChartStyle.line
                            : ChartStyle.candlestick;
                      });
                    },
                  ),
                ],
              ),
            ),

            // ── Interactive Candlestick Chart Canvas ───────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: CandlestickChartCanvas(
                  candles: candles,
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

            // ── Live Active Positions Drawer / Quick Close on Terminal Screen ──
            if (engineState.openPositions.isNotEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF162030),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2B384E)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.show_chart_rounded, color: Color(0xFFFFD600), size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'Live Trades (${engineState.openPositions.length})',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
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
                          color: const Color(0xFF0F1520),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: trade.isBuy
                                ? const Color(0xFF00D68F).withOpacity(0.3)
                                : const Color(0xFFFF4757).withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: trade.isBuy
                                    ? const Color(0xFF00D68F).withOpacity(0.2)
                                    : const Color(0xFFFF4757).withOpacity(0.2),
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
                              style: const TextStyle(
                                color: Colors.white,
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
                              onTap: () => ref.read(tradingEngineProvider.notifier).closePosition(trade.id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF4757).withOpacity(0.2),
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
                  ],
                ),
              ),

            // ── Bottom Order Execution Dock ───────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: Color(0xFF151D28),
                border: Border(
                  top: BorderSide(color: Color(0xFF1C2535), width: 1),
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'SELL (SHORT)',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            MoneyMath.formatDec(live.bid, live.decimals),
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
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
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'BUY (LONG)',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            MoneyMath.formatDec(live.ask, live.decimals),
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
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

  PopupMenuItem<UserRole> _roleMenuItem(UserRole role, String title) {
    return PopupMenuItem<UserRole>(
      value: role,
      child: Text(
        title,
        style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 13),
      ),
    );
  }
}
