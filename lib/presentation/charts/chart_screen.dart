import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:candlesticks/candlesticks.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/trading_entities.dart';
import '../../providers/market_provider.dart';
import '../../data/datasources/mock_market_datasource.dart';

class ChartScreen extends ConsumerStatefulWidget {
  final String symbol;
  const ChartScreen({super.key, required this.symbol});

  @override
  ConsumerState<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends ConsumerState<ChartScreen>
    with TickerProviderStateMixin {
  String _selectedTimeframe = '1h';
  String _selectedChartType = 'candlestick';
  late AnimationController _priceAnimController;
  late final TransformationController _transformationController;
  double? _lastPrice;
  Color _priceFlashColor = AppColors.profit;

  final List<String> _timeframes = ['1m', '5m', '15m', '30m', '1h', '4h', '1D', '1W'];
  final List<String> _indicators = ['EMA', 'SMA', 'RSI', 'MACD', 'BB'];
  final Set<String> _activeIndicators = {};

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _priceAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _priceAnimController.dispose();
    super.dispose();
  }

  double _currentScale = 1.0;

  void _zoomIn() {
    setState(() {
      _currentScale = (_currentScale * 1.35).clamp(0.4, 6.0);
      _transformationController.value =
          Matrix4.diagonal3Values(_currentScale, _currentScale, 1.0);
    });
  }

  void _zoomOut() {
    setState(() {
      _currentScale = (_currentScale / 1.35).clamp(0.4, 6.0);
      _transformationController.value =
          Matrix4.diagonal3Values(_currentScale, _currentScale, 1.0);
    });
  }

  void _resetZoom() {
    setState(() {
      _currentScale = 1.0;
      _transformationController.value = Matrix4.identity();
    });
  }

  @override
  Widget build(BuildContext context) {
    final instruments = ref.watch(instrumentsProvider);
    final instrument = instruments.firstWhere(
      (i) => i.symbol == widget.symbol,
      orElse: () => instruments.first,
    );
    final priceAsync = ref.watch(priceStreamProvider(widget.symbol));
    final tf = ref.watch(selectedTimeframeProvider);
    final candles = ref.watch(ohlcProvider(widget.symbol));

    final live = priceAsync.when(
      data: (d) => d,
      loading: () => instrument,
      error: (_, __) => instrument,
    );

    // Flash on price change
    priceAsync.whenData((d) {
      if (_lastPrice != null && d.bid != _lastPrice) {
        _priceFlashColor = d.bid > _lastPrice! ? AppColors.profit : AppColors.loss;
        _priceAnimController.forward().then((_) => _priceAnimController.reverse());
      }
      _lastPrice = d.bid;
    });

    final isPositive = live.isPositiveChange;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            // ── App Bar ─────────────────────────────────────────────────────
            _buildAppBar(context, live, isPositive),

            // ── Price Display ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedBuilder(
                        animation: _priceAnimController,
                        builder: (context, _) {
                          return Text(
                            live.bid.toStringAsFixed(instrument.decimals),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Color.lerp(
                                AppColors.textPrimary,
                                _priceFlashColor,
                                _priceAnimController.value,
                              ),
                              letterSpacing: -0.5,
                            ),
                          );
                        },
                      ),
                      Row(
                        children: [
                          Icon(
                            isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                            size: 14,
                            color: isPositive ? AppColors.profit : AppColors.loss,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${isPositive ? '+' : ''}${live.changeAmount.toStringAsFixed(4)} (${live.change24h.toStringAsFixed(2)}%)',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isPositive ? AppColors.profit : AppColors.loss,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  // OHLC mini display
                  _OhlcMini(candles: candles),
                ],
              ),
            ),

            // ── Timeframe Selector ──────────────────────────────────────────
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _timeframes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final tf = _timeframes[i];
                  final isSelected = _selectedTimeframe == tf;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedTimeframe = tf);
                      ref.read(selectedTimeframeProvider.notifier).state = tf;
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 44,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.brandPrimary : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? AppColors.brandPrimary : AppColors.darkBorder,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          tf,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.black : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // ── Interactive Zoomable Chart ──────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Stack(
                  children: [
                    InteractiveViewer(
                      transformationController: _transformationController,
                      panEnabled: true,
                      scaleEnabled: true,
                      minScale: 0.4,
                      maxScale: 6.0,
                      boundaryMargin: const EdgeInsets.all(200),
                      clipBehavior: Clip.hardEdge,
                      child: _buildChart(candles, instrument, live.bid),
                    ),
                    // Floating Zoom Controls
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.darkCard.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.darkBorder),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.add, color: AppColors.textPrimary, size: 18),
                              onPressed: _zoomIn,
                              tooltip: 'Zoom In',
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              padding: EdgeInsets.zero,
                            ),
                            const Divider(height: 1, color: AppColors.darkDivider),
                            IconButton(
                              icon: const Icon(Icons.remove, color: AppColors.textPrimary, size: 18),
                              onPressed: _zoomOut,
                              tooltip: 'Zoom Out',
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              padding: EdgeInsets.zero,
                            ),
                            const Divider(height: 1, color: AppColors.darkDivider),
                            IconButton(
                              icon: const Icon(Icons.center_focus_strong, color: AppColors.brandPrimary, size: 16),
                              onPressed: _resetZoom,
                              tooltip: 'Reset Zoom',
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Indicators Row ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Text(
                    'Indicators:',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _indicators.map((ind) {
                          final isActive = _activeIndicators.contains(ind);
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GestureDetector(
                              onTap: () => setState(() {
                                if (isActive) {
                                  _activeIndicators.remove(ind);
                                } else {
                                  _activeIndicators.add(ind);
                                }
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? AppColors.brandPrimary.withAlpha(20)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isActive
                                        ? AppColors.brandPrimary
                                        : AppColors.darkBorder,
                                  ),
                                ),
                                child: Text(
                                  ind,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isActive
                                        ? AppColors.brandPrimary
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Trade Buttons ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'BID',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () {},
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: AppColors.lossGradient,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.loss.withAlpha(40),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'SELL',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    live.bid.toStringAsFixed(instrument.decimals),
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      children: [
                        const Text(
                          'SPREAD',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 9,
                            color: AppColors.textMuted,
                          ),
                        ),
                        Text(
                          live.spread.toStringAsFixed(1),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brandSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          'ASK',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () {},
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: AppColors.profitGradient,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.profit.withAlpha(40),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'BUY',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    live.ask.toStringAsFixed(instrument.decimals),
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
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
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, dynamic live, bool isPositive) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary, size: 22),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.darkCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            widget.symbol,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          // Chart type toggle
          Container(
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChartTypeButton(
                  icon: Icons.candlestick_chart_rounded,
                  isActive: _selectedChartType == 'candlestick',
                  onTap: () => setState(() => _selectedChartType = 'candlestick'),
                ),
                _ChartTypeButton(
                  icon: Icons.show_chart_rounded,
                  isActive: _selectedChartType == 'line',
                  onTap: () => setState(() => _selectedChartType = 'line'),
                ),
                _ChartTypeButton(
                  icon: Icons.area_chart_rounded,
                  isActive: _selectedChartType == 'area',
                  onTap: () => setState(() => _selectedChartType = 'area'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(List<OhlcCandle> candles, InstrumentEntity instrument, double livePrice) {
    if (_selectedChartType == 'line' || _selectedChartType == 'area') {
      return _buildLineChart(candles);
    }
    return _buildCandlestickChart(candles, instrument.decimals, livePrice);
  }

  Widget _buildLineChart(List<OhlcCandle> candles) {
    if (candles.isEmpty) return const Center(child: CircularProgressIndicator());

    final spots = candles.asMap().entries.map((e) =>
      FlSpot(e.key.toDouble(), e.value.close),
    ).toList();

    final minY = candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final maxY = candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    final range = maxY - minY;

    final firstClose = candles.first.close;
    final lastClose = candles.last.close;
    final isUp = lastClose >= firstClose;

    return LineChart(
      LineChartData(
        backgroundColor: Colors.transparent,
        gridData: FlGridData(
          show: true,
          drawHorizontalLine: true,
          drawVerticalLine: false,
          horizontalInterval: range / 5,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.chartGrid,
            strokeWidth: 0.5,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 60,
              getTitlesWidget: _rightTitleWidget,
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        minY: minY - range * 0.05,
        maxY: maxY + range * 0.05,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.darkCardElevated,
            tooltipRoundedRadius: 8,
            getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
              s.y.toStringAsFixed(5),
              const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.brandPrimary,
              ),
            )).toList(),
          ),
          handleBuiltInTouches: true,
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: isUp ? AppColors.profit : AppColors.loss,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: _selectedChartType == 'area'
                ? BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: isUp
                          ? [
                              AppColors.profit.withAlpha(60),
                              AppColors.profit.withAlpha(0),
                            ]
                          : [
                              AppColors.loss.withAlpha(60),
                              AppColors.loss.withAlpha(0),
                            ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  )
                : BarAreaData(show: false),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 0),
    );
  }

  Widget _buildCandlestickChart(List<OhlcCandle> candles, int decimals, double livePrice) {
    if (candles.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0ECB81)),
      );
    }

    return _BinanceCandlestickWidget(
      candles: candles,
      decimals: decimals,
      livePrice: livePrice,
    );
  }
}

/// Binance Pro Style Candlestick & Volume Chart Widget
class _BinanceCandlestickWidget extends StatefulWidget {
  final List<OhlcCandle> candles;
  final int decimals;
  final double livePrice;

  const _BinanceCandlestickWidget({
    required this.candles,
    required this.decimals,
    required this.livePrice,
  });

  @override
  State<_BinanceCandlestickWidget> createState() => _BinanceCandlestickWidgetState();
}

class _BinanceCandlestickWidgetState extends State<_BinanceCandlestickWidget> {
  Offset? _touchPos;
  double _scrollOffset = 0.0;
  double _visibleCount = 45.0;
  double _baseScaleCount = 45.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (details) {
        _baseScaleCount = _visibleCount;
      },
      onScaleUpdate: (details) {
        setState(() {
          // 1. Pinch Scale (Zoom In / Zoom Out with 2 fingers or mouse wheel)
          if (details.scale != 1.0) {
            _visibleCount = (_baseScaleCount / details.scale).clamp(15.0, 120.0);
          }

          // 2. Drag / Pan (Slide candles left & right with 1 or 2 fingers)
          if (details.focalPointDelta.dx != 0) {
            _scrollOffset += details.focalPointDelta.dx * 0.2;
            final maxScroll = (widget.candles.length - _visibleCount).clamp(0.0, 500.0);
            _scrollOffset = _scrollOffset.clamp(0.0, maxScroll);
          }

          _touchPos = details.localFocalPoint;
        });
      },
      onScaleEnd: (_) => setState(() => _touchPos = null),
      onTapDown: (d) => setState(() => _touchPos = d.localPosition),
      onTapUp: (_) => setState(() => _touchPos = null),
      child: CustomPaint(
        painter: _BinanceCandlestickPainter(
          candles: widget.candles,
          decimals: widget.decimals,
          livePrice: widget.livePrice,
          touchPos: _touchPos,
          scrollOffset: _scrollOffset.toInt(),
          visibleCount: _visibleCount.toInt(),
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _BinanceCandlestickPainter extends CustomPainter {
  final List<OhlcCandle> candles;
  final int decimals;
  final double livePrice;
  final Offset? touchPos;
  final int scrollOffset;
  final int visibleCount;

  _BinanceCandlestickPainter({
    required this.candles,
    required this.decimals,
    required this.livePrice,
    this.touchPos,
    this.scrollOffset = 0,
    this.visibleCount = 45,
  });

  static const Color binanceGreen = Color(0xFF0ECB81);
  static const Color binanceRed = Color(0xFFF6465D);
  static const Color binanceBg = Color(0xFF0B0E14);
  static const Color gridColor = Color(0xFF1E2329);

  @override
  void paint(Canvas canvas, Size size) {
    final count = visibleCount.clamp(10, candles.length);
    final endIdx = (candles.length - scrollOffset).clamp(count, candles.length);
    final startIdx = (endIdx - count).clamp(0, candles.length);
    final visibleCandles = candles.sublist(startIdx, endIdx);
    final rightMargin = 65.0;
    final chartWidth = size.width - rightMargin;
    final chartHeight = size.height;
    final mainHeight = chartHeight * 0.78;

    final minPrice = visibleCandles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final maxPrice = visibleCandles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    final priceRange = (maxPrice - minPrice).abs() == 0 ? 1.0 : (maxPrice - minPrice);
    final maxVol = visibleCandles.map((c) => c.volume).reduce((a, b) => a > b ? a : b);

    // Draw Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = binanceBg);

    // 1. Draw Price Grid Lines (5 Levels)
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8;

    for (int i = 0; i <= 4; i++) {
      final y = mainHeight * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(chartWidth, y), gridPaint);

      final priceLabel = maxPrice - (priceRange * (i / 4));
      final textSpan = TextSpan(
        text: priceLabel.toStringAsFixed(decimals),
        style: const TextStyle(color: Color(0xFF848E9C), fontSize: 10, fontFamily: 'Inter'),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(chartWidth + 6, y - 6));
    }

    // 2. Draw Candlesticks & Volume Bars
    final candleWidth = chartWidth / visibleCandles.length;
    final bodyWidth = candleWidth * 0.7;

    double toY(double p) => mainHeight - ((p - minPrice) / priceRange) * mainHeight;

    for (int i = 0; i < visibleCandles.length; i++) {
      final c = visibleCandles[i];
      final isBull = c.close >= c.open;
      final color = isBull ? binanceGreen : binanceRed;
      final x = i * candleWidth + candleWidth / 2;

      final highY = toY(c.high);
      final lowY = toY(c.low);
      final openY = toY(c.open);
      final closeY = toY(c.close);

      // Draw Wick
      canvas.drawLine(
        Offset(x, highY),
        Offset(x, lowY),
        Paint()..color = color..strokeWidth = 1.2,
      );

      // Draw Body
      final bodyTop = isBull ? closeY : openY;
      final bodyBottom = isBull ? openY : closeY;
      final bodyH = (bodyBottom - bodyTop).abs().clamp(1.5, mainHeight);

      canvas.drawRect(
        Rect.fromLTWH(x - bodyWidth / 2, bodyTop, bodyWidth, bodyH),
        Paint()..color = color,
      );

      // Draw Volume Bar (Bottom 20%)
      final volH = maxVol > 0 ? (c.volume / maxVol) * (chartHeight * 0.18) : 2.0;
      final volY = chartHeight - volH;
      canvas.drawRect(
        Rect.fromLTWH(x - bodyWidth / 2, volY, bodyWidth, volH),
        Paint()..color = color.withOpacity(0.3),
      );
    }

    // 3. Draw Live Current Price Line & Tag Badge
    final liveY = toY(livePrice).clamp(0.0, mainHeight);
    final isLiveUp = visibleCandles.last.close >= visibleCandles.last.open;
    final liveColor = isLiveUp ? binanceGreen : binanceRed;

    final dashPaint = Paint()
      ..color = liveColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    double startX = 0;
    while (startX < chartWidth) {
      canvas.drawLine(Offset(startX, liveY), Offset(startX + 4, liveY), dashPaint);
      startX += 8;
    }

    final badgeRect = Rect.fromLTWH(chartWidth + 2, liveY - 10, rightMargin - 4, 20);
    canvas.drawRRect(RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)), Paint()..color = liveColor);

    final badgeText = TextSpan(
      text: livePrice.toStringAsFixed(decimals),
      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10, fontFamily: 'Inter'),
    );
    final badgeTp = TextPainter(text: badgeText, textDirection: TextDirection.ltr);
    badgeTp.layout();
    badgeTp.paint(canvas, Offset(chartWidth + 6, liveY - 6));

    // 4. Draw Crosshair on Tap/Touch
    if (touchPos != null && touchPos!.dx <= chartWidth) {
      final chx = touchPos!.dx;
      final chy = touchPos!.dy.clamp(0.0, mainHeight);

      final chPaint = Paint()
        ..color = const Color(0xFF848E9C)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;

      canvas.drawLine(Offset(chx, 0), Offset(chx, chartHeight), chPaint);
      canvas.drawLine(Offset(0, chy), Offset(chartWidth, chy), chPaint);

      final chPrice = maxPrice - (priceRange * (chy / mainHeight));
      final chBadgeRect = Rect.fromLTWH(chartWidth + 2, chy - 9, rightMargin - 4, 18);
      canvas.drawRRect(RRect.fromRectAndRadius(chBadgeRect, const Radius.circular(3)), Paint()..color = const Color(0xFF2B313A));

      final chText = TextSpan(
        text: chPrice.toStringAsFixed(decimals),
        style: const TextStyle(color: Colors.white, fontSize: 9, fontFamily: 'Inter'),
      );
      final chTp = TextPainter(text: chText, textDirection: TextDirection.ltr);
      chTp.layout();
      chTp.paint(canvas, Offset(chartWidth + 6, chy - 5));
    }
  }

  @override
  bool shouldRepaint(_BinanceCandlestickPainter oldDelegate) => true;
}

Widget _rightTitleWidget(double value, TitleMeta meta) {
  return SideTitleWidget(
    axisSide: meta.axisSide,
    child: Text(
      value.toStringAsFixed(4),
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 9,
        color: AppColors.textMuted,
      ),
    ),
  );
}

class _ChartTypeButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _ChartTypeButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isActive ? AppColors.brandPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isActive ? Colors.black : AppColors.textMuted,
        ),
      ),
    );
  }
}

class _OhlcMini extends StatelessWidget {
  final List<OhlcCandle> candles;
  const _OhlcMini({required this.candles});

  @override
  Widget build(BuildContext context) {
    if (candles.isEmpty) return const SizedBox.shrink();
    final last = candles.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _OhlcRow('O', last.open.toStringAsFixed(5)),
        _OhlcRow('H', last.high.toStringAsFixed(5), color: AppColors.profit),
        _OhlcRow('L', last.low.toStringAsFixed(5), color: AppColors.loss),
        _OhlcRow('C', last.close.toStringAsFixed(5)),
      ],
    );
  }

  Widget _OhlcRow(String label, String value, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 10,
            color: AppColors.textMuted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color ?? AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

extension<T> on List<T> {
  List<T> takeLast(int n) => length > n ? sublist(length - n) : this;
}
