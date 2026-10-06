import 'package:flutter/material.dart';
import '../../blocs/blocs.dart';
import '../../core/math/money_math.dart';
import '../../domain/entities/chart_entities.dart';
import '../../domain/entities/trading_entities.dart';
import 'candlestick_chart_canvas.dart';
import '../trading/widgets/order_placement_modal.dart';

class ChartScreen extends StatefulWidget {
  final String symbol;
  const ChartScreen({super.key, required this.symbol});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  ChartStyle _chartStyle = ChartStyle.candlestick;
  double _chartScale = 1.0;

  @override
  Widget build(BuildContext context) {
    final marketState = context.watch<MarketBloc>().state;
    final instrument = marketState.getInstrument(widget.symbol);
    final currentTf = marketState.selectedTimeframe;
    final candles = marketState.candles;
    final live = instrument;

    final isPositive = live.isPositiveChange;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151D28),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Text(
              live.symbol,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isPositive
                    ? const Color(0xFF00D68F).withAlpha(40)
                    : const Color(0xFFFF4757).withAlpha(40),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${isPositive ? '+' : ''}${live.change24h.toStringAsFixed(2)}%',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isPositive ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Price & 24h High/Low Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        MoneyMath.formatDec(live.midPrice, live.decimals),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Spread: ${live.spreadPips.toStringAsFixed(1)} pips • 1 Lot = ${MoneyMath.formatDec(live.contractSize, 0)}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF848E9C)),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '24h H: ${MoneyMath.formatDec(live.high24h, live.decimals)}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF00D68F), fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '24h L: ${MoneyMath.formatDec(live.low24h, live.decimals)}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFFFF4757), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Timeframe Selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                            color: isSel ? Colors.black : const Color(0xFF848E9C),
                          ),
                        ),
                      ),
                    );
                  }),
                  const Spacer(),

                  // Toolbar Zoom In (+)
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

                  // Toolbar Zoom Out (-)
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

                  // Toolbar Reset Zoom
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

            // Interactive Candlestick Canvas
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: CandlestickChartCanvas(
                  candles: candles,
                  timeframe: currentTf,
                  symbol: widget.symbol,
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

            // Bottom Order Execution Dock
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
                          const Text('SELL (SHORT)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                          Text(MoneyMath.formatDec(live.bid, live.decimals), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
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
                          const Text('BUY (LONG)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                          Text(MoneyMath.formatDec(live.ask, live.decimals), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
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
}
