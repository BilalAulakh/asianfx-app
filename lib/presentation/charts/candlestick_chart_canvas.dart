import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/candle_math.dart';
import '../../domain/entities/chart_entities.dart';

/// Exness-style chart palette (sampled from the Exness Trade app).
class ExnessChartColors {
  ExnessChartColors._();

  static const bull = Color(0xFF2390F3); // blue: up candle, Buy / Ask
  static const bear = Color(0xFFDB363D); // red: down candle, Sell / Bid
  static const darkBg = Color(0xFF141B21);
  static const darkGrid = Color(0xFF232B33);
  static const lightGrid = Color(0xFFE6E9ED);
  static const axisText = Color(0xFF7F8790);
}

/// Candles visible across the default viewport (Exness shows ~30 on a phone).
const double _kDefaultVisibleCandles = 30.0;
const double _kAxisWidth = 64.0;
const double _kTimeAxisHeight = 22.0;
const double _kRightMargin = 14.0;
// Pinch out to ~300 hair-thin candles, like Exness.
const double _kMinScale = 0.1;
const double _kMinSlotWidth = 1.2;

/// Exness-style candlestick chart: blue/red joined candles, round price levels,
/// Bid (red) and Ask (blue) tags on the price axis, pinch / wheel zoom, drag pan
/// and a round "fit" button to snap back to the latest candles.
class CandlestickChartCanvas extends StatefulWidget {
  final List<CandleStickModel> candles;
  final ChartStyle style;
  final int priceDecimals;
  final double currentPrice;
  final double? bid;
  final double? ask;
  final double scale;
  final ValueChanged<double>? onScaleChanged;
  final ChartTimeframe? timeframe;

  const CandlestickChartCanvas({
    super.key,
    required this.candles,
    this.timeframe,
    this.style = ChartStyle.candlestick,
    this.priceDecimals = 2,
    required this.currentPrice,
    this.bid,
    this.ask,
    this.scale = 1.0,
    this.onScaleChanged,
  });

  @override
  State<CandlestickChartCanvas> createState() => _CandlestickChartCanvasState();
}

class _CandlestickChartCanvasState extends State<CandlestickChartCanvas> {
  late double _scale;
  double _previousScale = 1.0;
  double _panOffset = 0.0;
  Offset? _crosshairPosition;

  @override
  void initState() {
    super.initState();
    _scale = widget.scale;
  }

  @override
  void didUpdateWidget(covariant CandlestickChartCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scale != widget.scale) {
      _scale = widget.scale;
    }
  }

  ChartTimeframe? _inferTimeframe() {
    final candles = widget.candles;
    if (candles.length < 2) return null;
    final gap = candles.last.time.difference(candles[candles.length - 2].time).abs();
    for (final tf in ChartTimeframe.values) {
      if (tf.duration == gap) return tf;
    }
    return null;
  }

  /// Candles joined body-to-body (open = previous close) like Exness.
  List<CandleStickModel> _joinedCandles() {
    final tf = widget.timeframe ?? _inferTimeframe();
    final maxGap = tf == null ? const Duration(hours: 4) : tf.duration * 3;
    return CandleMath.joinGaps(widget.candles, maxGap);
  }

  void _setScale(double s) {
    setState(() => _scale = s.clamp(_kMinScale, 5.0));
    widget.onScaleChanged?.call(_scale);
  }

  void _fitToScreen() {
    setState(() {
      _scale = 1.0;
      _panOffset = 0.0;
      _crosshairPosition = null;
    });
    widget.onScaleChanged?.call(_scale);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.candles.isEmpty) {
      // Live mode never fabricates history: wait for real candles.
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandPrimary),
            ),
            SizedBox(height: 10),
            Text(
              'Waiting for live chart data…',
              style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: ExnessChartColors.axisText),
            ),
          ],
        ),
      );
    }

    final isDark = context.isDarkMode;
    final showFit = _scale != 1.0 || _panOffset.abs() > 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return MouseRegion(
          cursor: SystemMouseCursors.precise,
          onHover: (event) => setState(() => _crosshairPosition = event.localPosition),
          onExit: (_) => setState(() => _crosshairPosition = null),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (signal) {
              if (signal is PointerScrollEvent && signal.scrollDelta.dy != 0) {
                _setScale(signal.scrollDelta.dy < 0 ? _scale * 1.2 : _scale / 1.2);
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) => _previousScale = _scale,
              onScaleUpdate: (details) {
                if (details.scale != 1.0) _setScale(_previousScale * details.scale);
                setState(() {
                  _panOffset += details.focalPointDelta.dx;
                  final plotWidth = width - _kAxisWidth - _kRightMargin;
                  final slotWidth = max(_kMinSlotWidth, (plotWidth / _kDefaultVisibleCandles) * _scale);
                  final maxPan = max(0.0, widget.candles.length * slotWidth - plotWidth);
                  _panOffset = _panOffset.clamp(-plotWidth * 0.5, maxPan + 40.0);
                });
              },
              onDoubleTap: _fitToScreen,
              onLongPressStart: (d) => setState(() => _crosshairPosition = d.localPosition),
              onLongPressMoveUpdate: (d) => setState(() => _crosshairPosition = d.localPosition),
              onLongPressEnd: (_) => setState(() => _crosshairPosition = null),
              child: Stack(
                children: [
                  CustomPaint(
                    size: Size(width, height),
                    painter: _ExnessChartPainter(
                      candles: _joinedCandles(),
                      style: widget.style,
                      scale: _scale,
                      panOffset: _panOffset,
                      crosshairPosition: _crosshairPosition,
                      priceDecimals: widget.priceDecimals,
                      currentPrice: widget.currentPrice,
                      bid: widget.bid,
                      ask: widget.ask,
                      isDark: isDark,
                    ),
                  ),
                  // Round "fit" button (Exness): back to the latest candles at 100%.
                  if (showFit)
                    Positioned(
                      right: _kAxisWidth + 10,
                      bottom: _kTimeAxisHeight + 12,
                      child: Material(
                        color: isDark ? const Color(0xFF1F272E) : Colors.white,
                        shape: CircleBorder(
                          side: BorderSide(color: isDark ? const Color(0xFF2E373F) : const Color(0xFFD5DAE0)),
                        ),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _fitToScreen,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.close_fullscreen_rounded,
                              size: 16,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ExnessChartPainter extends CustomPainter {
  final List<CandleStickModel> candles;
  final ChartStyle style;
  final double scale;
  final double panOffset;
  final Offset? crosshairPosition;
  final int priceDecimals;
  final double currentPrice;
  final double? bid;
  final double? ask;
  final bool isDark;

  _ExnessChartPainter({
    required this.candles,
    required this.style,
    required this.scale,
    required this.panOffset,
    this.crosshairPosition,
    required this.priceDecimals,
    required this.currentPrice,
    this.bid,
    this.ask,
    this.isDark = true,
  });

  static const _bull = ExnessChartColors.bull;
  static const _bear = ExnessChartColors.bear;
  static const _tagH = 18.0;

  TextPainter _text(String s, {Color color = ExnessChartColors.axisText, double size = 10, FontWeight? weight}) =>
      TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            fontFamily: 'Inter',
            color: color,
            fontSize: size,
            fontWeight: weight ?? FontWeight.w500,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    final chartWidth = size.width - _kAxisWidth;
    final chartHeight = size.height - _kTimeAxisHeight;
    final plotRight = chartWidth - _kRightMargin;
    final total = candles.length;

    final slotWidth = max(_kMinSlotWidth, (plotRight / _kDefaultVisibleCandles) * scale);
    final bodyWidth = max(1.0, slotWidth * 0.72);
    double xOf(int i) => plotRight - (total - 1 - i) * slotWidth + panOffset;
    bool onScreen(double x) => x >= -slotWidth && x <= chartWidth + slotWidth;

    // 1. Price range from the visible candles only (tight Exness fit).
    double lo = double.infinity, hi = double.negativeInfinity;
    bool latestVisible = false;
    for (int i = 0; i < total; i++) {
      final c = candles[i];
      if (!onScreen(xOf(i)) || c.low <= 0) continue;
      lo = min(lo, c.low);
      hi = max(hi, c.high);
      if (i == total - 1) latestVisible = true;
    }
    final ref = currentPrice > 0 ? currentPrice : candles.last.close;
    if (lo.isInfinite || lo == hi) {
      lo = ref * 0.999;
      hi = ref * 1.001;
    }
    if (latestVisible) {
      for (final p in [currentPrice, bid ?? 0, ask ?? 0]) {
        if (p > 0) {
          lo = min(lo, p);
          hi = max(hi, p);
        }
      }
    }
    final pad = max((hi - lo) * 0.08, lo * 0.00002);
    final minPrice = lo - pad, maxPrice = hi + pad;
    final range = max(1e-9, maxPrice - minPrice);
    double yOf(double p) => chartHeight - (p - minPrice) / range * chartHeight;

    // 2. Horizontal grid at round levels (labels drawn after the tags are placed).
    final gridPaint = Paint()
      ..color = isDark ? ExnessChartColors.darkGrid : ExnessChartColors.lightGrid
      ..strokeWidth = 1;
    final step = CandleMath.niceStep(range, 5);
    final labels = <double, TextPainter>{};
    for (double p = (minPrice / step).ceil() * step; p <= maxPrice; p += step) {
      final y = yOf(p);
      canvas.drawLine(Offset(0, y), Offset(chartWidth, y), gridPaint);
      labels[y] = _text(p.toStringAsFixed(priceDecimals));
    }

    // 3. Candles (or line) + bottom time axis.
    final bullPaint = Paint()..color = _bull;
    final bearPaint = Paint()..color = _bear;
    final wick = max(0.8, min(1.6, slotWidth * 0.08));
    double lastTimeX = -1e9;
    final timeGap = max(70.0, 110.0 / scale);

    final line = Path();
    bool lineStarted = false;
    for (int i = 0; i < total; i++) {
      final c = candles[i];
      final x = xOf(i);
      if (!onScreen(x)) continue;

      if (style == ChartStyle.candlestick) {
        final paint = c.close >= c.open ? bullPaint : bearPaint;
        canvas.drawLine(Offset(x, yOf(c.high)), Offset(x, yOf(c.low)), paint..strokeWidth = wick);
        final top = yOf(max(c.open, c.close));
        final bottom = yOf(min(c.open, c.close));
        canvas.drawRect(
          Rect.fromLTRB(x - bodyWidth / 2, top, x + bodyWidth / 2, max(bottom, top + 1.2)),
          paint,
        );
      } else {
        final y = yOf(c.close);
        lineStarted ? line.lineTo(x, y) : line.moveTo(x, y);
        lineStarted = true;
      }

      if (x - lastTimeX > timeGap && x > 16 && x < chartWidth - 24) {
        lastTimeX = x;
        final tp = _text(_formatAxisTime(c.time));
        tp.paint(canvas, Offset(x - tp.width / 2, chartHeight + 6));
      }
    }
    if (lineStarted) {
      canvas.drawPath(
        line,
        Paint()
          ..color = _bull
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke,
      );
    }

    // 4. Ask (blue) above Bid (red): dotted lines and axis tags, Exness-style.
    final tags = <(double, Color)>[];
    if (ask != null && ask! > 0) tags.add((ask!, _bull));
    if (bid != null && bid! > 0) tags.add((bid!, _bear));
    if (tags.isEmpty) tags.add((currentPrice, currentPrice >= candles.last.open ? _bull : _bear));

    // Tag tops: centred on their price, stacked so they never overlap.
    final tops = <double>[];
    for (final (p, _) in tags) {
      var top = (yOf(p) - _tagH / 2).clamp(0.0, chartHeight - _tagH).toDouble();
      if (tops.isNotEmpty) top = max(top, tops.last + _tagH);
      tops.add(top);
    }
    final overflow = tops.last - (chartHeight - _tagH);
    if (overflow > 0) {
      for (int i = 0; i < tops.length; i++) {
        tops[i] -= overflow;
      }
    }

    // Axis labels hidden where a tag covers them.
    labels.forEach((y, tp) {
      final top = y - tp.height / 2;
      final covered = tops.any((t) => top + tp.height > t - 1 && top < t + _tagH + 1);
      if (!covered) tp.paint(canvas, Offset(chartWidth + 8, top));
    });

    for (int i = 0; i < tags.length; i++) {
      final (price, color) = tags[i];
      final y = yOf(price).clamp(0.0, chartHeight).toDouble();
      final dash = Paint()
        ..color = color.withValues(alpha: 0.85)
        ..strokeWidth = 1;
      for (double x = 0; x < chartWidth; x += 5) {
        canvas.drawLine(Offset(x, y), Offset(min(x + 2, chartWidth), y), dash);
      }
      _axisTag(canvas, chartWidth, tops[i], color, price.toStringAsFixed(priceDecimals), Colors.white);
    }

    // 5. Crosshair with a price tag on the axis.
    final ch = crosshairPosition;
    if (ch != null && ch.dx < chartWidth && ch.dy < chartHeight) {
      final p = Paint()
        ..color = isDark ? Colors.white54 : Colors.black45
        ..strokeWidth = 0.8;
      canvas.drawLine(Offset(0, ch.dy), Offset(chartWidth, ch.dy), p);
      canvas.drawLine(Offset(ch.dx, 0), Offset(ch.dx, chartHeight), p);
      final price = maxPrice - ch.dy / chartHeight * range;
      _axisTag(canvas, chartWidth, ch.dy - _tagH / 2, isDark ? Colors.white : Colors.black87,
          price.toStringAsFixed(priceDecimals), isDark ? Colors.black : Colors.white);
    }
  }

  void _axisTag(Canvas canvas, double chartWidth, double top, Color bg, String text, Color fg) {
    const w = _kAxisWidth - 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(chartWidth + 2, top, w, _tagH), const Radius.circular(3)),
      Paint()..color = bg,
    );
    final tp = _text(text, color: fg, size: 10.5, weight: FontWeight.w600);
    tp.paint(canvas, Offset(chartWidth + 2 + (w - tp.width) / 2, top + (_tagH - tp.height) / 2));
  }

  String _formatAxisTime(DateTime time) {
    if (candles.length > 1) {
      final spanDays = candles.last.time.difference(candles.first.time).inDays.abs();
      if (spanDays > 180) return DateFormat("MMM ''yy").format(time);
      if (spanDays > 5) return DateFormat('dd/MM').format(time);
      if (spanDays > 1) return DateFormat('dd/MM, HH:mm').format(time);
    }
    return DateFormat('HH:mm').format(time);
  }

  @override
  bool shouldRepaint(covariant _ExnessChartPainter oldDelegate) => true;
}
