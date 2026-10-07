import 'dart:math';

import '../../domain/entities/chart_entities.dart';
import 'fx_session.dart';

/// Candle helpers for charts built from the broker's own 1-minute candles
/// (public.price_candles_1m).
class CandleMath {
  CandleMath._();

  /// Parses rpc_get_price_candles rows ({t: epoch s, o, h, l, c, n}).
  static List<CandleStickModel> fromServerRows(Object? rows) {
    if (rows is! List) return const [];
    final out = <CandleStickModel>[];
    for (final r in rows) {
      if (r is! Map) continue;
      final t = (r['t'] as num?)?.toInt();
      final o = _num(r['o']), h = _num(r['h']), l = _num(r['l']), c = _num(r['c']);
      if (t == null || o == null || h == null || l == null || c == null || o <= 0) continue;
      out.add(CandleStickModel(
        time: DateTime.fromMillisecondsSinceEpoch(t * 1000),
        open: o,
        high: max(h, max(o, c)),
        low: min(l, min(o, c)),
        close: c,
        volume: (_num(r['n']) ?? 1).toDouble(),
      ));
    }
    return out;
  }

  static double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v');

  /// Folds 1-minute candles (oldest first) into [tf] candles on the FX session
  /// clock (same buckets as the chart and its countdown).
  static List<CandleStickModel> aggregate(List<CandleStickModel> minutes, ChartTimeframe tf) {
    if (tf == ChartTimeframe.m1 || minutes.isEmpty) return List.of(minutes);
    final out = <CandleStickModel>[];
    for (final m in minutes) {
      final start = FxSession.periodStart(m.time, tf);
      if (out.isNotEmpty && out.last.time == start) {
        final last = out.last;
        out[out.length - 1] = last.copyWith(
          high: max(last.high, m.high),
          low: min(last.low, m.low),
          close: m.close,
          volume: last.volume + m.volume,
        );
      } else {
        out.add(CandleStickModel(
          time: start,
          open: m.open,
          high: m.high,
          low: m.low,
          close: m.close,
          volume: m.volume,
        ));
      }
    }
    return out;
  }

  /// Exness-style continuous candles: each candle opens at the previous close
  /// (wicks widened to cover it), so bodies join with no gaps. Candles more than
  /// [maxGap] apart (weekend / market close) keep their own open.
  static List<CandleStickModel> joinGaps(List<CandleStickModel> candles, Duration maxGap) {
    if (candles.length < 2) return candles;
    final out = List<CandleStickModel>.of(candles);
    for (int i = 1; i < out.length; i++) {
      final prev = out[i - 1], c = out[i];
      if (c.time.difference(prev.time) > maxGap || c.open == prev.close) continue;
      final o = prev.close;
      out[i] = c.copyWith(open: o, high: max(c.high, o), low: min(c.low, o));
    }
    return out;
  }

  /// "Nice" axis step (1/2/2.5/5 × 10^n) giving about [targetLines] grid lines.
  static double niceStep(double range, int targetLines) {
    if (range <= 0 || targetLines <= 0) return 1;
    final raw = range / targetLines;
    final mag = pow(10, (log(raw) / ln10).floor()).toDouble();
    for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
      if (raw <= m * mag) return m * mag;
    }
    return 10 * mag;
  }

  /// Older candles from a proxy series (PAXG / futures, already re-based onto
  /// spot) followed by the broker's own candles from their first bucket on.
  static List<CandleStickModel> merge(List<CandleStickModel> proxy, List<CandleStickModel> own) {
    if (own.isEmpty) return proxy;
    final first = own.first.time;
    return [...proxy.where((c) => c.time.isBefore(first)), ...own];
  }
}
