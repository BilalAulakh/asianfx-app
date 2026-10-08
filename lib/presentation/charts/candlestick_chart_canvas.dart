import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/candle_math.dart';
import '../../domain/entities/chart_entities.dart';

/// Exness-style chart palette (sampled from the Exness Trade app).
class ExnessChartColors {
  ExnessChartColors._();

  static const bull = Color(0xFF089981); // green: up candle, Buy / Ask
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
const double _kMaxScale = 5.0;
const double _kMinSlotWidth = 1.2;
// Older history is requested when fewer candles than this are left off-screen.
const int _kPrefetchCandles = 150;

/// Horizontal layout of the chart: where candle `i` sits for a zoom and pan.
/// The pan is measured from the right edge, so prepending older candles never
/// moves what is on screen.
@immutable
class ChartViewport {
  final double plotRight; // x of the newest candle when not panned
  final double slot; // horizontal space per candle
  final int count;
  final double pan;

  const ChartViewport({required this.plotRight, required this.slot, required this.count, required this.pan});

  factory ChartViewport.of(double width, double scale, int count, double pan) {
    final plotRight = width - _kAxisWidth - _kRightMargin;
    return ChartViewport(
      plotRight: plotRight,
      slot: max(_kMinSlotWidth, (plotRight / _kDefaultVisibleCandles) * scale),
      count: count,
      pan: pan,
    );
  }

  double xOf(int i) => plotRight - (count - 1 - i) * slot + pan;

  /// Fractional candle index under [x].
  double indexAt(double x) => count - 1 - (plotRight + pan - x) / slot;

  /// First and last candle index with any part on screen (empty when last < first).
  (int, int) visible(double chartWidth) =>
      (max(0, indexAt(-slot).floor()), min(count - 1, indexAt(chartWidth + slot).ceil()));

  /// Pan limits: the oldest candle may reach the left edge, the newest about
  /// the middle of the screen (empty space for the future, like Exness).
  double clampPan(double p) => p.clamp(-plotRight * 0.5, max(0.0, count * slot - plotRight) + 40.0).toDouble();

  /// Pan keeping the candle under [focalX] in place when the slot width
  /// changes to [newSlot] (zoom around the fingers / mouse, not the right edge).
  double panAfterZoom(double focalX, double newSlot) =>
      focalX - plotRight + (plotRight + pan - focalX) * newSlot / slot;
}

/// Price range that fits the candles on screen (and the live prices while the
/// newest candle is visible), padded 8% like Exness.
@visibleForTesting
(double, double) fitPriceRange(
  List<CandleStickModel> candles,
  int first,
  int last, {
  required double reference,
  List<double> livePrices = const [],
}) {
  double lo = double.infinity, hi = double.negativeInfinity;
  for (int i = first; i <= last; i++) {
    final c = candles[i];
    if (c.low <= 0) continue;
    lo = min(lo, c.low);
    hi = max(hi, c.high);
  }
  if (last == candles.length - 1) {
    for (final p in livePrices) {
      if (p > 0) {
        lo = min(lo, p);
        hi = max(hi, p);
      }
    }
  }
  if (lo.isInfinite || lo >= hi) {
    final ref = lo.isFinite ? lo : reference;
    lo = ref * 0.999;
    hi = ref * 1.001;
  }
  final pad = max((hi - lo) * 0.08, lo * 0.00002);
  return (lo - pad, hi + pad);
}

/// Exness-style candlestick chart: green/red joined candles, round price levels,
/// Bid (red) and Ask (green) tags on the price axis. Pinch zooms around the
/// fingers, drag pans with fling, dragging the price axis stretches the chart
/// vertically, and the price range glides to fit what is on screen. Scrolling
/// back near the oldest candle asks for older history ([onNeedOlderHistory]).
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

  /// Identifies the series (e.g. symbol + timeframe); the view resets when it changes.
  final Object? viewKey;

  /// Called when the user scrolls back close to the oldest loaded candle.
  final VoidCallback? onNeedOlderHistory;

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
    this.viewKey,
    this.onNeedOlderHistory,
  });

  @override
  State<CandlestickChartCanvas> createState() => _CandlestickChartCanvasState();
}

class _CandlestickChartCanvasState extends State<CandlestickChartCanvas> with SingleTickerProviderStateMixin {
  late double _scale;
  double _previousScale = 1.0;
  double _panOffset = 0.0;
  Offset? _crosshairPosition;

  // Price range on screen, gliding towards [_target] (Exness-style stretch / compress).
  double? _lo, _hi;
  (double, double)? _target;
  // Manual vertical stretch from dragging the price axis (1 = auto fit).
  double _yZoom = 1.0;
  bool _draggingAxis = false;

  // Fling after a fast swipe, and the glide back after "fit".
  double _panVelocity = 0;
  bool _fitting = false;

  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastTick = Duration.zero;
  double _width = 0;
  int _olderRequestedAt = -1;

  // joinGaps is O(n); redo it only when the series actually changed.
  List<CandleStickModel>? _joinedFor;
  int _joinedLength = -1;
  CandleStickModel? _joinedLast;
  List<CandleStickModel> _joined = const [];

  @override
  void initState() {
    super.initState();
    _scale = widget.scale;
  }

  @override
  void didUpdateWidget(covariant CandlestickChartCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scale != widget.scale) _scale = widget.scale;
    if (oldWidget.viewKey != widget.viewKey) {
      // New symbol / timeframe: start from the latest candles, range snaps.
      _panOffset = 0;
      _panVelocity = 0;
      _fitting = false;
      _yZoom = 1;
      _lo = _hi = null;
      _olderRequestedAt = -1;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
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
    final src = widget.candles;
    if (identical(src, _joinedFor) && src.length == _joinedLength && identical(src.last, _joinedLast)) {
      return _joined;
    }
    final tf = widget.timeframe ?? _inferTimeframe();
    final maxGap = tf == null ? const Duration(hours: 4) : tf.duration * 3;
    _joinedFor = src;
    _joinedLength = src.length;
    _joinedLast = src.last;
    return _joined = CandleMath.joinGaps(src, maxGap);
  }

  ChartViewport _viewport([double? pan]) => ChartViewport.of(_width, _scale, widget.candles.length, pan ?? _panOffset);

  void _kick() {
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero ? 1 / 60 : ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;
    var moving = false;

    if (_fitting) {
      final k = 1 - exp(-dt * 14);
      _scale += (1.0 - _scale) * k;
      _panOffset += (0.0 - _panOffset) * k;
      _yZoom += (1.0 - _yZoom) * k;
      if ((_scale - 1).abs() < 0.002 && _panOffset.abs() < 0.5 && (_yZoom - 1).abs() < 0.002) {
        _scale = 1;
        _panOffset = 0;
        _yZoom = 1;
        _fitting = false;
        widget.onScaleChanged?.call(_scale);
      } else {
        moving = true;
      }
    } else if (_panVelocity.abs() > 15) {
      final next = _viewport().clampPan(_panOffset + _panVelocity * dt);
      _panVelocity = next == _panOffset + _panVelocity * dt ? _panVelocity * pow(0.05, dt) : 0;
      _panOffset = next;
      moving = true;
    } else {
      _panVelocity = 0;
    }

    final t = _target;
    if (t != null && _lo != null && _hi != null) {
      final k = 1 - exp(-dt * 12);
      _lo = _lo! + (t.$1 - _lo!) * k;
      _hi = _hi! + (t.$2 - _hi!) * k;
      final eps = (t.$2 - t.$1) * 0.0008;
      if ((t.$1 - _lo!).abs() < eps && (t.$2 - _hi!).abs() < eps) {
        _lo = t.$1;
        _hi = t.$2;
      } else {
        moving = true;
      }
    }

    setState(() {});
    if (!moving) _ticker.stop();
  }

  void _zoomTo(double newScale, double focalX) {
    final s = newScale.clamp(_kMinScale, _kMaxScale).toDouble();
    if (s == _scale || _width <= 0) return;
    final before = _viewport();
    final after = ChartViewport.of(_width, s, widget.candles.length, 0);
    setState(() {
      _scale = s;
      _panOffset = after.clampPan(before.panAfterZoom(focalX, after.slot));
    });
    widget.onScaleChanged?.call(_scale);
  }

  void _fitToScreen() {
    setState(() {
      _fitting = true;
      _panVelocity = 0;
      _crosshairPosition = null;
    });
    _kick();
  }

  /// Target range for the candles on screen, stretched by the axis drag.
  (double, double) _computeTarget(List<CandleStickModel> candles, double chartWidth) {
    final (first, last) = _viewport().visible(chartWidth);
    final ref = widget.currentPrice > 0 ? widget.currentPrice : candles.last.close;
    var (lo, hi) = last < first
        ? (ref * 0.999, ref * 1.001)
        : fitPriceRange(
            candles,
            first,
            last,
            reference: ref,
            livePrices: [widget.currentPrice, widget.bid ?? 0, widget.ask ?? 0],
          );
    if (_yZoom != 1) {
      final mid = (lo + hi) / 2, half = (hi - lo) / 2 * _yZoom;
      (lo, hi) = (mid - half, mid + half);
    }
    return (lo, hi);
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
    final showFit = _scale != 1.0 || _panOffset.abs() > 1 || _yZoom != 1.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        _width = width;
        final chartWidth = width - _kAxisWidth;
        final candles = _joinedCandles();
        final viewport = _viewport();

        // Price range glides towards the fit for what is on screen.
        final target = _computeTarget(candles, chartWidth);
        _target = target;
        if (_lo == null || _hi == null) {
          _lo = target.$1;
          _hi = target.$2;
        } else if (_lo != target.$1 || _hi != target.$2) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) _kick();
          });
        }

        // Near the oldest candle: page in older history (once per series length).
        if (widget.onNeedOlderHistory != null &&
            viewport.indexAt(0) < _kPrefetchCandles &&
            _olderRequestedAt != candles.length) {
          _olderRequestedAt = candles.length;
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onNeedOlderHistory?.call();
          });
        }

        // The fit button sits outside the gesture area, so its tap is not held
        // back by the chart's double-tap recognizer.
        return Stack(
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.precise,
              onHover: (event) => setState(() => _crosshairPosition = event.localPosition),
              onExit: (_) => setState(() => _crosshairPosition = null),
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerSignal: (signal) {
                  if (signal is PointerScrollEvent && signal.scrollDelta.dy != 0) {
                    _zoomTo(signal.scrollDelta.dy < 0 ? _scale * 1.15 : _scale / 1.15, signal.localPosition.dx);
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: (d) {
                    _previousScale = _scale;
                    _panVelocity = 0;
                    _fitting = false;
                    // One finger on the price axis: stretch / compress vertically.
                    _draggingAxis = d.pointerCount == 1 && d.localFocalPoint.dx > chartWidth;
                  },
                  onScaleUpdate: (d) {
                    if (_draggingAxis) {
                      setState(() => _yZoom = (_yZoom * exp(d.focalPointDelta.dy * 0.006)).clamp(0.2, 8.0));
                      return;
                    }
                    if (d.pointerCount >= 2 && d.horizontalScale != 1.0) {
                      _zoomTo(_previousScale * d.horizontalScale, d.localFocalPoint.dx);
                    }
                    setState(() => _panOffset = _viewport().clampPan(_panOffset + d.focalPointDelta.dx));
                  },
                  onScaleEnd: (d) {
                    if (_draggingAxis) {
                      _draggingAxis = false;
                      return;
                    }
                    final vx = d.velocity.pixelsPerSecond.dx;
                    if (d.pointerCount == 0 && vx.abs() > 250) {
                      _panVelocity = vx.clamp(-6000.0, 6000.0).toDouble();
                      _kick();
                    }
                  },
                  onDoubleTap: _fitToScreen,
                  onLongPressStart: (d) => setState(() => _crosshairPosition = d.localPosition),
                  onLongPressMoveUpdate: (d) => setState(() => _crosshairPosition = d.localPosition),
                  onLongPressEnd: (_) => setState(() => _crosshairPosition = null),
                  child: CustomPaint(
                    size: Size(width, height),
                    painter: _ExnessChartPainter(
                      candles: candles,
                      viewport: viewport,
                      minPrice: _lo!,
                      maxPrice: _hi!,
                      style: widget.style,
                      crosshairPosition: _crosshairPosition,
                      priceDecimals: widget.priceDecimals,
                      currentPrice: widget.currentPrice,
                      bid: widget.bid,
                      ask: widget.ask,
                      timeframe: widget.timeframe ?? _inferTimeframe(),
                      isDark: isDark,
                    ),
                  ),
                ),
              ),
            ),
            // Round "fit" button (Exness): glide back to the latest candles at 100%.
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
        );
      },
    );
  }
}

class _ExnessChartPainter extends CustomPainter {
  final List<CandleStickModel> candles;
  final ChartViewport viewport;
  final double minPrice;
  final double maxPrice;
  final ChartStyle style;
  final Offset? crosshairPosition;
  final int priceDecimals;
  final double currentPrice;
  final double? bid;
  final double? ask;
  final ChartTimeframe? timeframe;
  final bool isDark;

  _ExnessChartPainter({
    required this.candles,
    required this.viewport,
    required this.minPrice,
    required this.maxPrice,
    required this.style,
    this.crosshairPosition,
    required this.priceDecimals,
    required this.currentPrice,
    this.bid,
    this.ask,
    this.timeframe,
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
    final slotWidth = viewport.slot;
    final bodyWidth = max(1.0, slotWidth * 0.72);
    final (first, last) = viewport.visible(chartWidth);

    final range = max(1e-9, maxPrice - minPrice);
    double yOf(double p) => chartHeight - (p - minPrice) / range * chartHeight;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, chartWidth, size.height));

    // 1. Horizontal grid at round levels (labels drawn after the tags are placed).
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

    // 2. Candles (or line) + time labels pinned to candles (they move with the chart).
    final bullPaint = Paint()..color = _bull;
    final bearPaint = Paint()..color = _bear;
    final wick = max(0.8, min(1.6, slotWidth * 0.08));
    final labelEvery = max(1, (90 / slotWidth).ceil());
    final timeFormat = last >= first ? _timeFormat(candles[first].time, candles[last].time) : DateFormat('HH:mm');

    final line = Path();
    bool lineStarted = false;
    for (int i = first; i <= last; i++) {
      final c = candles[i];
      final x = viewport.xOf(i);

      if (style == ChartStyle.candlestick) {
        final paint = c.close >= c.open ? bullPaint : bearPaint;
        canvas.drawLine(Offset(x, yOf(c.high)), Offset(x, yOf(c.low)), paint..strokeWidth = wick);
        final top = yOf(max(c.open, c.close));
        final bottom = yOf(min(c.open, c.close));
        canvas.drawRect(Rect.fromLTRB(x - bodyWidth / 2, top, x + bodyWidth / 2, max(bottom, top + 1.2)), paint);
      } else {
        final y = yOf(c.close);
        lineStarted ? line.lineTo(x, y) : line.moveTo(x, y);
        lineStarted = true;
      }

      if (i % labelEvery == 0) {
        final tp = _text(timeFormat.format(c.time));
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
    canvas.restore();

    // 3. Ask (green) above Bid (red): dotted lines and axis tags, Exness-style.
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
      if (!covered && top > -tp.height && top < chartHeight) tp.paint(canvas, Offset(chartWidth + 8, top));
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

    // 4. Crosshair with a price tag on the axis.
    final ch = crosshairPosition;
    if (ch != null && ch.dx < chartWidth && ch.dy < chartHeight) {
      final p = Paint()
        ..color = isDark ? Colors.white54 : Colors.black45
        ..strokeWidth = 0.8;
      canvas.drawLine(Offset(0, ch.dy), Offset(chartWidth, ch.dy), p);
      canvas.drawLine(Offset(ch.dx, 0), Offset(ch.dx, chartHeight), p);
      final price = maxPrice - ch.dy / chartHeight * range;
      _axisTag(
        canvas,
        chartWidth,
        ch.dy - _tagH / 2,
        isDark ? Colors.white : Colors.black87,
        price.toStringAsFixed(priceDecimals),
        isDark ? Colors.black : Colors.white,
      );
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

  /// Label format for the span on screen (Exness: "03:35", "07/10, 09:55", "Oct '25").
  DateFormat _timeFormat(DateTime from, DateTime to) {
    final span = to.difference(from).abs();
    if (span > const Duration(days: 300) || timeframe == ChartTimeframe.d1 && span > const Duration(days: 60)) {
      return DateFormat("MMM ''yy");
    }
    if (timeframe == ChartTimeframe.d1 || span > const Duration(days: 20)) return DateFormat('dd/MM');
    if (span > const Duration(hours: 20)) return DateFormat('dd/MM, HH:mm');
    return DateFormat('HH:mm');
  }

  @override
  bool shouldRepaint(covariant _ExnessChartPainter oldDelegate) => true;
}
