import 'package:asianfxapp/data/datasources/market_feed_service.dart';
import 'package:asianfxapp/domain/entities/chart_entities.dart';
import 'package:flutter_test/flutter_test.dart';

CandleStickModel _c(DateTime t, double close) =>
    CandleStickModel(time: t, open: close, high: close + 1, low: close - 1, close: close, volume: 1);

void main() {
  final feed = MarketFeedService();

  test('PAXG proxy history is re-based onto live spot and weekend candles are dropped', () {
    // Live spot gold published by the server: mid 4161.80.
    feed.applyServerConfig({'spread_multiplier': 1}, [
      {'symbol': 'XAU/USD', 'spread_markup_points': 16},
    ]);
    feed.applyServerQuote({
      'symbol': 'XAU/USD',
      'bid': '4161.72000000',
      'ask': '4161.88000000',
      'source': 'publisher',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final spot = feed.getInstrument('XAU/USD')!.midPrice.toDouble();

    final raw = [
      _c(DateTime.utc(2026, 10, 2, 12), 4150.0), // Fri, open
      _c(DateTime.utc(2026, 10, 3, 12), 4152.0), // Sat, closed (PAXG still trades)
      _c(DateTime.utc(2026, 10, 4, 12), 4153.0), // Sun midday, closed
      _c(DateTime.utc(2026, 10, 5, 10), 4166.15), // Mon, open — PAXG ~$4 over spot
    ];

    final out = feed.alignMetalHistory('XAU/USD', raw, ChartTimeframe.h1);

    expect(out.length, 2, reason: 'Saturday and Sunday candles removed');
    expect(out.last.close, closeTo(spot, 1e-9), reason: 'last close equals live spot');
    // The whole series shifts by the same basis, so its shape is preserved.
    expect(out.last.close - out.first.close, closeTo(4166.15 - 4150.0, 1e-9));
    expect(out.first.high - out.first.close, closeTo(1, 1e-9));
  });
}
