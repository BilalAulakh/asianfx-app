import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/fx_session.dart';
import '../../domain/entities/chart_entities.dart';

/// Institutional Candlestick Canvas with Interactive Zoom, Drag-Pan, Mouse Wheel, and Touch Pinch
class CandlestickChartCanvas extends StatefulWidget {
  final List<CandleStickModel> candles;
  final ChartStyle style;
  final int priceDecimals;
  final double currentPrice;
  final double scale;
  final ValueChanged<double>? onScaleChanged;
  final ChartTimeframe? timeframe;
  final String? symbol;

  const CandlestickChartCanvas({
    super.key,
    required this.candles,
    this.timeframe,
    this.symbol,
    this.style = ChartStyle.candlestick,
    this.priceDecimals = 2,
    required this.currentPrice,
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
  CandleStickModel? _inspectedCandle;

  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _scale = widget.scale;
    // Tick every second so the candle-close countdown under the price badge stays live
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  /// Time remaining until the current candle closes, TradingView-style, using the
  /// FX session clock (daily rollover 17:00 New York). "Closed" outside trading hours.
  String? _candleCloseCountdown() {
    final tf = widget.timeframe ?? _inferTimeframe();
    if (tf == null) return null;
    final remaining = FxSession.timeToCandleClose(DateTime.now(), tf, symbol: widget.symbol);
    if (remaining == null) return 'Closed';
    return FxSession.formatCountdown(remaining);
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

  @override
  void didUpdateWidget(covariant CandlestickChartCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scale != widget.scale) {
      _scale = widget.scale;
    }
  }

  void _zoomIn() {
    setState(() {
      _scale = (_scale * 1.3).clamp(0.25, 6.0);
      widget.onScaleChanged?.call(_scale);
    });
  }

  void _zoomOut() {
    setState(() {
      _scale = (_scale / 1.3).clamp(0.25, 6.0);
      widget.onScaleChanged?.call(_scale);
    });
  }

  void _resetZoom() {
    setState(() {
      _scale = 1.0;
      _panOffset = 0.0;
      _crosshairPosition = null;
      _inspectedCandle = null;
      widget.onScaleChanged?.call(_scale);
    });
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
              style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF848E9C)),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return MouseRegion(
          cursor: SystemMouseCursors.precise,
          onHover: (event) {
            _handleCrosshair(event.localPosition, width);
          },
          onExit: (_) {
            setState(() {
              _crosshairPosition = null;
              _inspectedCandle = null;
            });
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (pointerSignal) {
              if (pointerSignal is PointerScrollEvent) {
                if (pointerSignal.scrollDelta.dy < 0) {
                  _zoomIn();
                } else if (pointerSignal.scrollDelta.dy > 0) {
                  _zoomOut();
                }
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) {
                _previousScale = _scale;
              },
              onScaleUpdate: (details) {
                setState(() {
                  if (details.scale != 1.0) {
                    _scale = (_previousScale * details.scale).clamp(0.3, 5.0);
                    widget.onScaleChanged?.call(_scale);
                  }
                  _panOffset += details.focalPointDelta.dx;
                  final totalCandles = widget.candles.length;
                  final slotWidth = max(5.0, ((width - 68.0) / 45.0) * _scale);
                  final maxPan = max(0.0, (totalCandles * slotWidth) - (width - 68.0));
                  _panOffset = _panOffset.clamp(-80.0, maxPan + 200.0);
                });
              },
              onDoubleTap: _resetZoom,
              onLongPressStart: (details) {
                _handleCrosshair(details.localPosition, width);
              },
              onLongPressMoveUpdate: (details) {
                _handleCrosshair(details.localPosition, width);
              },
              onLongPressEnd: (_) {
                setState(() {
                  _crosshairPosition = null;
                  _inspectedCandle = null;
                });
              },
              child: Stack(
                children: [
                  // 1. Candlestick Canvas
                  CustomPaint(
                    size: Size(width, height),
                    painter: _InstitutionalChartPainter(
                      candles: widget.candles,
                      style: widget.style,
                      scale: _scale,
                      panOffset: _panOffset,
                      crosshairPosition: _crosshairPosition,
                      priceDecimals: widget.priceDecimals,
                      currentPrice: widget.currentPrice,
                      countdownText: _candleCloseCountdown(),
                      isDark: context.isDarkMode,
                    ),
                  ),

                  // 2. High-Visibility Floating Zoom Overlay (Top Right)
                  Positioned(
                    top: 8,
                    right: 76,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                      decoration: BoxDecoration(
                        color: context.cardBg.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.subtleBorderColor, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: context.isDarkMode ? 0.4 : 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Zoom In (+)
                          _zoomButton(
                            icon: Icons.add_rounded,
                            tooltip: 'Zoom In (Wheel Up)',
                            onTap: _zoomIn,
                          ),
                          const SizedBox(width: 3),
                          // Percentage Pill
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: context.inputBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${(_scale * 100).toInt()}%',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: context.isDarkMode ? const Color(0xFFFFD600) : const Color(0xFFB7791F),
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                          // Zoom Out (-)
                          _zoomButton(
                            icon: Icons.remove_rounded,
                            tooltip: 'Zoom Out (Wheel Down)',
                            onTap: _zoomOut,
                          ),
                          const SizedBox(width: 3),
                          // Reset Zoom (↺)
                          _zoomButton(
                            icon: Icons.fit_screen_rounded,
                            tooltip: 'Reset Zoom (Double Tap)',
                            onTap: _resetZoom,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 3. Crosshair HUD Card
                  if (_inspectedCandle != null)
                    Positioned(
                      top: 8,
                      left: 12,
                      right: 220,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: context.cardBg.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: context.subtleBorderColor),
                        ),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            _hudItem('TIME', DateFormat('yyyy-MM-dd HH:mm').format(_inspectedCandle!.time)),
                            _hudItem('O', _inspectedCandle!.open.toStringAsFixed(widget.priceDecimals)),
                            _hudItem('H', _inspectedCandle!.high.toStringAsFixed(widget.priceDecimals), color: const Color(0xFF00D68F)),
                            _hudItem('L', _inspectedCandle!.low.toStringAsFixed(widget.priceDecimals), color: const Color(0xFFFF4757)),
                            _hudItem('C', _inspectedCandle!.close.toStringAsFixed(widget.priceDecimals)),
                            _hudItem('VOL', _inspectedCandle!.volume.toStringAsFixed(0), color: const Color(0xFFFFD600)),
                          ],
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

  Widget _zoomButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: context.isDarkMode ? const Color(0xFF1E2A3A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 15, color: context.textPrimaryColor),
          ),
        ),
      ),
    );
  }

  Widget _hudItem(String label, String value, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF848E9C),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color ?? context.textPrimaryColor,
          ),
        ),
      ],
    );
  }

  void _handleCrosshair(Offset localPos, double totalWidth) {
    if (widget.candles.isEmpty) return;
    const rightAxis = 68.0;
    const rightMargin = 16.0;
    final chartWidth = totalWidth - rightAxis;
    final totalCandles = widget.candles.length;
    final slotWidth = max(5.0, ((chartWidth - rightMargin) / 45.0) * _scale);

    final distFromRight = (chartWidth - rightMargin + _panOffset) - localPos.dx;
    final indexFromRight = (distFromRight / slotWidth).round();
    final candleIndex = (totalCandles - 1 - indexFromRight).clamp(0, totalCandles - 1);

    setState(() {
      _crosshairPosition = localPos;
      _inspectedCandle = widget.candles[candleIndex];
    });
  }
}

class _InstitutionalChartPainter extends CustomPainter {
  final List<CandleStickModel> candles;
  final ChartStyle style;
  final double scale;
  final double panOffset;
  final Offset? crosshairPosition;
  final int priceDecimals;
  final double currentPrice;
  final String? countdownText;
  final bool isDark;

  _InstitutionalChartPainter({
    this.isDark = true,
    required this.candles,
    required this.style,
    required this.scale,
    required this.panOffset,
    this.crosshairPosition,
    required this.priceDecimals,
    required this.currentPrice,
    this.countdownText,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    const rightPriceAxisWidth = 68.0;
    const rightMargin = 16.0;
    final chartWidth = size.width - rightPriceAxisWidth;
    final chartHeight = size.height - 22.0;

    final totalCandles = candles.length;

    // Dynamically calculate slot width: 45 candles visible across default viewport
    final slotWidth = max(5.0, ((chartWidth - rightMargin) / 45.0) * scale);
    final candleBodyWidth = max(3.0, slotWidth * 0.70);

    // 1. Calculate min and max prices strictly from candles VISIBLE on viewport
    double minPrice = double.infinity;
    double maxPrice = double.negativeInfinity;
    double maxVolume = 0.0;
    int visibleCount = 0;
    bool isLatestCandleVisible = false;

    for (int i = 0; i < totalCandles; i++) {
      final c = candles[i];
      final x = (chartWidth - rightMargin) - ((totalCandles - 1 - i) * slotWidth) + panOffset;

      if (x >= -slotWidth && x <= chartWidth + slotWidth) {
        if (c.low > 0 && c.high > 0) {
          minPrice = min(minPrice, c.low);
          maxPrice = max(maxPrice, c.high);
          maxVolume = max(maxVolume, c.volume);
          visibleCount++;
          if (i == totalCandles - 1) {
            isLatestCandleVisible = true;
          }
        }
      }
    }

    if (visibleCount == 0 || minPrice.isInfinite || minPrice == maxPrice) {
      final fallbackRef = currentPrice > 0 ? currentPrice : candles.last.close;
      minPrice = fallbackRef * 0.985;
      maxPrice = fallbackRef * 1.015;
    }

    if (isLatestCandleVisible && currentPrice > 0) {
      minPrice = min(minPrice, currentPrice);
      maxPrice = max(maxPrice, currentPrice);
    }

    // 18% vertical padding for rock-solid visual stability (prevents sudden jumping)
    final pricePadding = max((maxPrice - minPrice) * 0.18, minPrice * 0.002);
    minPrice -= pricePadding;
    maxPrice += pricePadding;
    final priceRange = max(0.0001, maxPrice - minPrice);

    double getY(double price) {
      final norm = (price - minPrice) / priceRange;
      return chartHeight - (norm * chartHeight);
    }

    // Live price badge geometry (needed up front so axis labels can avoid it)
    final currentY = getY(currentPrice).clamp(0.0, chartHeight);
    final hasCountdown = countdownText != null;
    const priceRowHeight = 18.0;
    const countdownRowHeight = 15.0;
    final badgeHeight = hasCountdown ? priceRowHeight + countdownRowHeight : priceRowHeight;
    final double badgeTop =
        (currentY - priceRowHeight / 2).clamp(0.0, max(0.0, chartHeight - badgeHeight)).toDouble();

    // 2. Draw Grid Lines & Right Price Axis
    final gridPaint = Paint()
      ..color = isDark ? const Color(0xFF1B2332) : const Color(0xFFE2E8F0)
      ..strokeWidth = 0.8;

    const gridLinesCount = 5;
    for (int i = 0; i <= gridLinesCount; i++) {
      final y = chartHeight * (i / gridLinesCount);
      canvas.drawLine(Offset(0, y), Offset(chartWidth, y), gridPaint);

      final priceVal = maxPrice - (priceRange * (i / gridLinesCount));
      final textSpan = TextSpan(
        text: priceVal.toStringAsFixed(priceDecimals),
        style: const TextStyle(
          fontFamily: 'Inter',
          color: Color(0xFF848E9C),
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      );
      final tp = TextPainter(text: textSpan, textDirection: ui.TextDirection.ltr)..layout();
      final labelTop = y - (tp.height / 2);
      // Hide axis labels the live-price badge would overlap (TradingView behaviour)
      final hiddenByBadge = labelTop + tp.height > badgeTop - 2 && labelTop < badgeTop + badgeHeight + 2;
      if (!hiddenByBadge) {
        tp.paint(canvas, Offset(chartWidth + 6, labelTop));
      }
    }

    final bullColor = const Color(0xFF00D68F);
    final bearColor = const Color(0xFFFF4757);

    final bullPaint = Paint()..color = bullColor;
    final bearPaint = Paint()..color = bearColor;

    final wickWidth = max(1.1, min(1.8, slotWidth * 0.09));
    final wickPaintBull = Paint()
      ..color = bullColor
      ..strokeWidth = wickWidth
      ..strokeCap = StrokeCap.square;

    final wickPaintBear = Paint()
      ..color = bearColor
      ..strokeWidth = wickWidth
      ..strokeCap = StrokeCap.square;

    // 3. Draw Candlesticks & Bottom Time Axis
    int lastTimeMarkX = -100;
    final timeMarkInterval = max(80.0, 120.0 / scale);

    if (style == ChartStyle.candlestick) {
      for (int i = 0; i < totalCandles; i++) {
        final c = candles[i];
        final x = (chartWidth - rightMargin) - ((totalCandles - 1 - i) * slotWidth) + panOffset;

        if (x < -slotWidth || x > chartWidth + slotWidth) continue;

        final isBull = c.close >= c.open;

        // Volume histogram bar at bottom
        if (maxVolume > 0 && c.volume > 0) {
          final volHeight = (c.volume / maxVolume) * (chartHeight * 0.16);
          final volRect = Rect.fromLTWH(
            x - (candleBodyWidth / 2),
            chartHeight - volHeight,
            candleBodyWidth,
            volHeight,
          );
          canvas.drawRect(
            volRect,
            Paint()..color = (isBull ? bullColor : bearColor).withValues(alpha: 0.22),
          );
        }

        final openY = getY(c.open);
        final closeY = getY(c.close);
        final highY = getY(c.high);
        final lowY = getY(c.low);

        final bodyTop = min(openY, closeY);
        final bodyBottom = max(openY, closeY);
        final rawHeight = bodyBottom - bodyTop;

        // Upper Wick (clean segment from highY to bodyTop)
        if (highY < bodyTop) {
          canvas.drawLine(
            Offset(x, highY),
            Offset(x, bodyTop),
            isBull ? wickPaintBull : wickPaintBear,
          );
        }

        // Lower Wick (clean segment from bodyBottom to lowY)
        if (lowY > bodyBottom) {
          canvas.drawLine(
            Offset(x, bodyBottom),
            Offset(x, lowY),
            isBull ? wickPaintBull : wickPaintBear,
          );
        }

        // Candle Body
        if (rawHeight < 1.5) {
          // Doji: crisp horizontal bar
          canvas.drawLine(
            Offset(x - (candleBodyWidth / 2), bodyTop),
            Offset(x + (candleBodyWidth / 2), bodyTop),
            Paint()
              ..color = isBull ? bullColor : bearColor
              ..strokeWidth = 1.6
              ..strokeCap = StrokeCap.square,
          );
        } else {
          // Solid clean rectangle
          final bodyRect = Rect.fromLTWH(
            x - (candleBodyWidth / 2),
            bodyTop,
            candleBodyWidth,
            rawHeight,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(bodyRect, const Radius.circular(1.0)),
            isBull ? bullPaint : bearPaint,
          );
        }

        // Time mark on bottom axis
        if (x - lastTimeMarkX > timeMarkInterval && x > 20 && x < chartWidth - 30) {
          lastTimeMarkX = x.toInt();
          final timeStr = _formatAxisTime(c.time);
          final timeSpan = TextSpan(
            text: timeStr,
            style: const TextStyle(
              fontFamily: 'Inter',
              color: Color(0xFF848E9C),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          );
          final timePainter = TextPainter(text: timeSpan, textDirection: ui.TextDirection.ltr)..layout();
          timePainter.paint(canvas, Offset(x - (timePainter.width / 2), chartHeight + 4));
        }
      }
    } else {
      // Line Area Chart
      final linePath = Path();
      final areaPath = Path();

      bool first = true;
      double firstX = 0;
      double lastX = 0;

      for (int i = 0; i < totalCandles; i++) {
        final c = candles[i];
        final x = (chartWidth - rightMargin) - ((totalCandles - 1 - i) * slotWidth) + panOffset;
        final y = getY(c.close);

        if (first) {
          linePath.moveTo(x, y);
          areaPath.moveTo(x, chartHeight);
          areaPath.lineTo(x, y);
          firstX = x;
          first = false;
        } else {
          linePath.lineTo(x, y);
          areaPath.lineTo(x, y);
        }
        lastX = x;

        if (x - lastTimeMarkX > timeMarkInterval && x > 20 && x < chartWidth - 30) {
          lastTimeMarkX = x.toInt();
          final timeStr = _formatAxisTime(c.time);
          final timeSpan = TextSpan(
            text: timeStr,
            style: const TextStyle(
              fontFamily: 'Inter',
              color: Color(0xFF848E9C),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          );
          final timePainter = TextPainter(text: timeSpan, textDirection: ui.TextDirection.ltr)..layout();
          timePainter.paint(canvas, Offset(x - (timePainter.width / 2), chartHeight + 4));
        }
      }

      if (!first) {
        areaPath.lineTo(lastX, chartHeight);
        areaPath.lineTo(firstX, chartHeight);
        areaPath.close();

        final areaGradient = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF00C896).withValues(alpha: 0.35),
            const Color(0xFF00C896).withValues(alpha: 0.0),
          ],
        );

        final areaPaint = Paint()
          ..shader = areaGradient.createShader(Rect.fromLTWH(0, 0, chartWidth, chartHeight));
        canvas.drawPath(areaPath, areaPaint);

        final linePaint = Paint()
          ..color = const Color(0xFF00C896)
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke;
        canvas.drawPath(linePath, linePaint);
      }
    }

    // 4. Draw Current Live Price Line & TradingView-style Badge
    // Line + badge take the live candle's direction colour (green up / red down).
    final liveColor = currentPrice >= candles.last.open ? bullColor : bearColor;

    final dashPaint = Paint()
      ..color = liveColor.withValues(alpha: 0.9)
      ..strokeWidth = 1.0;

    const dashWidth = 2.0;
    const dashSpace = 2.0;
    double startX = 0;
    while (startX < chartWidth) {
      canvas.drawLine(Offset(startX, currentY), Offset(startX + dashWidth, currentY), dashPaint);
      startX += dashWidth + dashSpace;
    }

    // Badge: price row centred on the price line, countdown row underneath
    final badgeLeft = chartWidth + 1;
    final badgeWidth = rightPriceAxisWidth - 2;
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(badgeLeft, badgeTop, badgeWidth, badgeHeight),
      const Radius.circular(3),
    );
    canvas.drawRRect(badgeRect, Paint()..color = liveColor);

    final curPricePainter = TextPainter(
      text: TextSpan(
        text: currentPrice.toStringAsFixed(priceDecimals),
        style: const TextStyle(
          fontFamily: 'Inter',
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          fontFeatures: [ui.FontFeature.tabularFigures()],
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    curPricePainter.paint(
      canvas,
      Offset(
        badgeLeft + (badgeWidth - curPricePainter.width) / 2,
        badgeTop + (priceRowHeight - curPricePainter.height) / 2,
      ),
    );

    if (hasCountdown) {
      final countdownPainter = TextPainter(
        text: TextSpan(
          text: countdownText,
          style: TextStyle(
            fontFamily: 'Inter',
            color: Colors.white.withValues(alpha: 0.88),
            fontSize: 10,
            fontWeight: FontWeight.w500,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      countdownPainter.paint(
        canvas,
        Offset(
          badgeLeft + (badgeWidth - countdownPainter.width) / 2,
          badgeTop + priceRowHeight + (countdownRowHeight - countdownPainter.height) / 2 - 1,
        ),
      );
    }

    // 5. Draw Crosshair if active
    if (crosshairPosition != null) {
      final chPaint = Paint()
        ..color = isDark ? Colors.white60 : Colors.black45
        ..strokeWidth = 0.8;

      canvas.drawLine(
        Offset(0, crosshairPosition!.dy),
        Offset(chartWidth, crosshairPosition!.dy),
        chPaint,
      );
      canvas.drawLine(
        Offset(crosshairPosition!.dx, 0),
        Offset(crosshairPosition!.dx, chartHeight),
        chPaint,
      );
    }
  }

  String _formatAxisTime(DateTime time) {
    if (candles.length > 1) {
      final spanDays = candles.last.time.difference(candles.first.time).inDays.abs();
      if (spanDays > 180) {
        // Multi-month / Multi-year: e.g. "Aug '24", "Jan '25"
        return DateFormat("MMM ''yy").format(time);
      } else if (spanDays > 5) {
        // Multi-day / Multi-week: e.g. "Sep 09", "Aug 24"
        return DateFormat('MMM dd').format(time);
      } else if (spanDays > 1) {
        // Cross-day: e.g. "09/08 14:00"
        return DateFormat('MM/dd HH:mm').format(time);
      }
    }
    return DateFormat('HH:mm').format(time);
  }

  @override
  bool shouldRepaint(covariant _InstitutionalChartPainter oldDelegate) => true;
}
