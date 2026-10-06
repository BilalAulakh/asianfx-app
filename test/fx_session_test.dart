import 'package:flutter_test/flutter_test.dart';
import 'package:asianfxapp/core/utils/fx_session.dart';
import 'package:asianfxapp/domain/entities/chart_entities.dart';

void main() {
  // TradingView OANDA:XAUUSD screenshot: 09:05:16 UTC, 1D candle closes in 11:54:44
  final tvNow = DateTime.utc(2026, 10, 1, 9, 5, 16);

  test('1D countdown matches TradingView (17:00 New York rollover, EDT)', () {
    final d = FxSession.timeToCandleClose(tvNow, ChartTimeframe.d1, symbol: 'XAU/USD')!;
    expect(FxSession.formatCountdown(d), '11:54:44');
  });

  test('1H countdown runs to the top of the hour', () {
    final d = FxSession.timeToCandleClose(tvNow, ChartTimeframe.h1, symbol: 'XAU/USD')!;
    expect(FxSession.formatCountdown(d), '54:44');
  });

  test('4H candles anchor on 17:00 NY (05:00-09:00 NY = 09:00-13:00 UTC)', () {
    final d = FxSession.timeToCandleClose(tvNow, ChartTimeframe.h4)!;
    expect(FxSession.formatCountdown(d), '03:54:44');
  });

  test('winter (EST) daily rollover is 22:00 UTC', () {
    final d = FxSession.timeToCandleClose(DateTime.utc(2026, 12, 2, 21, 0), ChartTimeframe.d1)!;
    expect(d, const Duration(hours: 1));
  });

  test('weekend and metals daily break show closed', () {
    expect(FxSession.timeToCandleClose(DateTime.utc(2026, 10, 3, 12), ChartTimeframe.h1), isNull); // Sat
    expect(FxSession.timeToCandleClose(DateTime.utc(2026, 10, 1, 21, 30), ChartTimeframe.h1, symbol: 'XAU/USD'), isNull);
    expect(FxSession.timeToCandleClose(DateTime.utc(2026, 10, 1, 21, 30), ChartTimeframe.h1, symbol: 'EUR/USD'), isNotNull);
  });

  test('Friday daily candle closes at 17:00 NY', () {
    final d = FxSession.timeToCandleClose(DateTime.utc(2026, 10, 2, 20, 0), ChartTimeframe.d1)!;
    expect(d, const Duration(hours: 1));
  });

  test('periodStart buckets daily candle at 21:00 UTC rollover', () {
    expect(FxSession.periodStart(tvNow, ChartTimeframe.d1).toUtc(), DateTime.utc(2026, 9, 30, 21));
  });
}
