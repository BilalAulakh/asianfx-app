import 'dart:math';

import 'package:asianfxapp/domain/entities/chart_entities.dart';
import 'package:asianfxapp/presentation/charts/candlestick_chart_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<CandleStickModel> _series(int n, {double start = 4100}) {
  final t0 = DateTime(2026, 10, 7, 8);
  var p = start;
  return List.generate(n, (i) {
    final o = p;
    final c = o + sin(i / 5) * 2;
    p = c;
    return CandleStickModel(
      time: t0.add(Duration(minutes: 5 * i)),
      open: o,
      high: max(o, c) + 0.5,
      low: min(o, c) - 0.5,
      close: c,
    );
  });
}

void main() {
  group('ChartViewport', () {
    test('zoom keeps the candle under the fingers in place', () {
      final v = ChartViewport.of(400, 1.0, 500, 120);
      const focalX = 150.0;
      final before = v.indexAt(focalX);
      final zoomed = ChartViewport.of(400, 2.5, 500, 0);
      final after = ChartViewport(
        plotRight: zoomed.plotRight,
        slot: zoomed.slot,
        count: 500,
        pan: v.panAfterZoom(focalX, zoomed.slot),
      );
      expect(after.indexAt(focalX), closeTo(before, 1e-9));
    });

    test('visible range covers only what is on screen', () {
      final v = ChartViewport.of(400, 1.0, 5000, 0);
      final (first, last) = v.visible(400 - 64);
      expect(last, 4999);
      expect(last - first, lessThan(40)); // ~30 candles at 100%
    });

    test('pan is clamped: oldest candle at most to the left edge', () {
      final v = ChartViewport.of(400, 1.0, 100, 0);
      expect(v.clampPan(1e9), lessThan(100 * v.slot));
      expect(v.clampPan(-1e9), -v.plotRight * 0.5);
    });
  });

  test('fitPriceRange pads the visible highs / lows and includes live prices', () {
    final c = _series(50);
    final (lo, hi) = fitPriceRange(c, 0, 49, reference: 4100, livePrices: [5000]);
    expect(hi, greaterThan(5000));
    final (lo2, hi2) = fitPriceRange(c, 0, 10, reference: 4100, livePrices: [5000]);
    expect(hi2, lessThan(5000)); // live price ignored: newest candle not on screen
    expect(lo, lessThanOrEqualTo(lo2));
  });

  group('chart widget', () {
    Future<void> pumpChart(WidgetTester tester, List<CandleStickModel> candles, {VoidCallback? onOlder}) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CandlestickChartCanvas(
            candles: candles,
            timeframe: ChartTimeframe.m5,
            currentPrice: candles.last.close,
            viewKey: 'XAU/m5',
            onNeedOlderHistory: onOlder,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('scrolling back near the oldest candle asks for older history', (tester) async {
      var asked = 0;
      await pumpChart(tester, _series(400), onOlder: () => asked++);
      expect(asked, 0);

      // Drag far to the right (back in time) in a few strokes.
      for (var i = 0; i < 14; i++) {
        await tester.dragFrom(const Offset(40, 300), const Offset(300, 0));
        await tester.pumpAndSettle();
      }
      expect(asked, 1); // once per series length, not on every frame
    });

    testWidgets('fit button appears after panning and glides back', (tester) async {
      await pumpChart(tester, _series(400));
      expect(find.byIcon(Icons.close_fullscreen_rounded), findsNothing);

      await tester.dragFrom(const Offset(40, 300), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close_fullscreen_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_fullscreen_rounded));
      await tester.pump(const Duration(milliseconds: 16));
      // Still gliding after one frame (animated, not a jump)...
      expect(find.byIcon(Icons.close_fullscreen_rounded), findsOneWidget);
      await tester.pumpAndSettle();
      // ...and back at the latest candles afterwards.
      expect(find.byIcon(Icons.close_fullscreen_rounded), findsNothing);
    });
  });
}
