import 'package:asianfxapp/data/datasources/market_feed_service.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('commission per lot comes from the server instruments table', () {
    final feed = MarketFeedService();
    expect(feed.commissionPerLot('NOPE/USD'), Decimal.zero, reason: 'unknown symbol: no commission');

    feed.applyServerConfig(null, [
      {'symbol': 'XAU/USD', 'spread_markup_points': 18, 'commission_per_lot': 2},
      {'symbol': 'XAG/USD', 'spread_markup_points': 2, 'commission_per_lot': '2.0000'},
    ]);

    expect(feed.commissionPerLot('XAU/USD'), Decimal.fromInt(2));
    expect(feed.commissionPerLot('XAG/USD'), Decimal.fromInt(2));
    // 0.10 lot -> $0.20, as the server charges (commission_per_lot x lots).
    expect(feed.commissionPerLot('XAU/USD') * Decimal.parse('0.10'), Decimal.parse('0.2'));
    expect(feed.getInstrument('XAU/USD')!.spreadMarkupPips, 18);
  });
}
