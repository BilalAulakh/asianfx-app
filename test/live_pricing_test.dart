import 'package:asianfxapp/core/constants/feature_flags.dart';
import 'package:asianfxapp/data/datasources/market_feed_service.dart';
import 'package:asianfxapp/data/datasources/supabase_trade_service.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final feed = MarketFeedService();

  test('production builds are not in demo mode', () {
    // Synthetic ticks / candles exist only behind --dart-define=ASIANFX_DEMO_MODE=true.
    expect(kDemoMode, isFalse);
  });

  group('live mode: only real prices', () {
    test('seed placeholders are stale until a real price arrives', () {
      // No Supabase session in tests, so no server quote has been applied yet.
      expect(feed.isStale('EUR/GBP'), isTrue);
      expect(feed.lastLiveAt('EUR/GBP'), isNull);
    });

    test('no synthetic candle history is generated in live mode', () {
      expect(feed.getCandles('NZD/CHF'), isEmpty);
    });

    test('a published quote is displayed exactly as the server will fill it', () {
      feed.applyServerConfig({'quote_max_age_seconds': 60, 'spread_multiplier': 1}, [
        {'symbol': 'EUR/GBP', 'spread_markup_points': 15},
      ]);
      final now = DateTime.now().toUtc();
      feed.applyServerQuote({
        'symbol': 'EUR/GBP',
        'bid': '0.85740000',
        'ask': '0.85755000',
        'source': 'publisher',
        'updated_at': now.toIso8601String(),
      });

      final inst = feed.getInstrument('EUR/GBP')!;
      expect(inst.bid, Decimal.parse('0.8574'));
      expect(inst.ask, Decimal.parse('0.85755'));
      expect(feed.isStale('EUR/GBP'), isFalse);

      // After quote_max_age_seconds without a new quote it becomes stale again.
      expect(feed.isStale('EUR/GBP', now.add(const Duration(seconds: 61))), isTrue);
    });

    test('client-sourced or older rows never move the displayed price', () {
      final before = feed.getInstrument('EUR/GBP')!;
      feed.applyServerQuote({
        'symbol': 'EUR/GBP',
        'bid': '0.90000000',
        'ask': '0.90010000',
        'source': 'client',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      feed.applyServerQuote({
        'symbol': 'EUR/GBP',
        'bid': '0.80000000',
        'ask': '0.80010000',
        'source': 'publisher',
        'updated_at': DateTime.utc(2020).toIso8601String(),
      });
      final after = feed.getInstrument('EUR/GBP')!;
      expect(after.bid, before.bid);
      expect(after.ask, before.ask);
    });

    test('markup comes from the instruments table x the global multiplier', () {
      feed.applyServerConfig({'spread_multiplier': '2.0'}, [
        {'symbol': 'GBP/CHF', 'spread_markup_points': 18},
      ]);
      expect(feed.getSpreadMarkup('GBP/CHF'), 18);
      expect(feed.getInstrument('GBP/CHF')!.spreadMarkupPips, 36);

      feed.applyServerConfig({'spread_multiplier': 1}, const []);
      expect(feed.getInstrument('GBP/CHF')!.spreadMarkupPips, 18);
    });
  });

  group('server rejections are shown in plain language', () {
    test('NO_QUOTE / MARKET_CLOSED', () {
      for (final code in ['NO_QUOTE', 'MARKET_CLOSED']) {
        final e = TradeServiceException(code, 'no live price for XAU/USD');
        expect(e.toString(), contains('market is closed'));
      }
    });

    test('KYC_REQUIRED', () {
      expect(const TradeServiceException('KYC_REQUIRED', 'x').toString(), contains('KYC'));
    });

    test('other codes keep the server message', () {
      expect(const TradeServiceException('INSUFFICIENT_MARGIN', 'need 10, have 5').toString(),
          'need 10, have 5');
    });
  });
}
