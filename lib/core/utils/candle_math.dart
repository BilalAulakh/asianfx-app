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

  /// Older candles from a proxy series (PAXG / futures, already re-based onto
  /// spot) followed by the broker's own candles from their first bucket on.
  static List<CandleStickModel> merge(List<CandleStickModel> proxy, List<CandleStickModel> own) {
    if (own.isEmpty) return proxy;
    final first = own.first.time;
    return [...proxy.where((c) => c.time.isBefore(first)), ...own];
  }
}
