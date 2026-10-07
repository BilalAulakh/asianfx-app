import 'dart:math';

import 'package:asianfxapp/core/utils/candle_math.dart';
import 'package:asianfxapp/domain/entities/chart_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A Wednesday, well inside the trading week, on exact minute boundaries.
  final base = DateTime.utc(2026, 10, 7, 14, 0);
  int s(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  test('server rows -> candles (bad rows skipped, wicks never inside the body)', () {
    final rows = [
      {'t': s(base), 'o': '4100.00', 'h': '4101.50', 'l': '4099.20', 'c': '4100.80', 'n': 20},
      {'t': s(base.add(const Duration(minutes: 1))), 'o': 4100.8, 'h': 4100.0, 'l': 4100.9, 'c': 4100.5, 'n': 18},
      {'t': null, 'o': 1, 'h': 1, 'l': 1, 'c': 1},
      'junk',
    ];
    final c = CandleMath.fromServerRows(rows);
    expect(c, hasLength(2));
    expect(c.first.time, base.toLocal());
    expect((c.first.open, c.first.high, c.first.low, c.first.close), (4100.0, 4101.5, 4099.2, 4100.8));
    expect(c.first.volume, 20);
    expect(c[1].high, 4100.8, reason: 'high raised to the body');
    expect(c[1].low, 4100.5, reason: 'low lowered to the body');
    expect(CandleMath.fromServerRows(null), isEmpty);
  });

  test('five 1-minute candles fold into one 5-minute candle', () {
    final minutes = [
      for (var i = 0; i < 5; i++)
        CandleStickModel(
          time: base.add(Duration(minutes: i)).toLocal(),
          open: 100.0 + i,
          high: 102.0 + i,
          low: 99.0 - i,
          close: 101.0 + i,
          volume: 10,
        ),
    ];
    final m5 = CandleMath.aggregate(minutes, ChartTimeframe.m5);
    expect(m5, hasLength(1));
    final c = m5.single;
    expect((c.open, c.high, c.low, c.close, c.volume), (100.0, 106.0, 95.0, 105.0, 50.0));
    expect(CandleMath.aggregate(minutes, ChartTimeframe.m1), hasLength(5));
  });

  test('proxy history is kept only before the first own candle', () {
    CandleStickModel at(int min, double p) =>
        CandleStickModel(time: base.add(Duration(minutes: min)), open: p, high: p, low: p, close: p);
    final proxy = [at(0, 1), at(1, 1), at(2, 1), at(3, 1)];
    final own = [at(2, 2), at(3, 2), at(4, 2)];
    final merged = CandleMath.merge(proxy, own);
    expect(merged.map((c) => c.close), [1, 1, 2, 2, 2]);
    expect(CandleMath.merge(proxy, const []), proxy);
  });

  test('joinGaps opens each candle at the previous close, except across long gaps', () {
    CandleStickModel at(int m, double o, double c) => CandleStickModel(
        time: base.add(Duration(minutes: m)), open: o, high: max(o, c), low: min(o, c), close: c);
    final joined = CandleMath.joinGaps(
        [at(0, 100, 102), at(1, 103, 104), at(2, 103.5, 101), at(60, 90, 91)], const Duration(minutes: 3));
    expect(joined.map((c) => c.open), [100, 102, 104, 90]);
    expect((joined[2].high, joined[2].low), (104.0, 101.0));
  });

  test('niceStep picks round grid steps', () {
    expect(CandleMath.niceStep(10, 6), 2);
    expect(CandleMath.niceStep(0.9, 6), 0.2);
    expect(CandleMath.niceStep(140, 6), 25);
  });
}
