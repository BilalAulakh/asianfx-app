import 'package:asianfxapp/blocs/market_bloc.dart';
import 'package:asianfxapp/data/datasources/market_feed_service.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a burst of ticks becomes ONE state update holding every latest quote', () async {
    final feed = MarketFeedService();
    final bloc = MarketBloc(feedService: feed);
    await Future<void>.delayed(Duration.zero); // initialise + subscribe

    final gold = feed.getInstrument('XAU/USD')!;
    final euro = feed.getInstrument('EUR/USD')!;
    final states = <MarketState>[];
    final sub = bloc.stream.listen(states.add);

    // 5 ticks inside one batch window: gold twice, euro three times.
    for (final bid in ['4200.10', '4200.50']) {
      feed.emitTick(gold.copyWith(rawBid: Decimal.parse(bid), rawAsk: Decimal.parse(bid)));
    }
    for (final bid in ['1.1001', '1.1002', '1.1003']) {
      feed.emitTick(euro.copyWith(rawBid: Decimal.parse(bid), rawAsk: Decimal.parse(bid)));
    }
    await Future<void>.delayed(MarketBloc.tickBatchWindow + const Duration(milliseconds: 100));

    final tickStates = states.where((s) => s.liveQuotes.containsKey('EUR/USD')).toList();
    expect(tickStates, hasLength(1), reason: 'five ticks -> one rebuild');
    final s = tickStates.single;
    expect(s.liveQuotes['XAU/USD']!.rawBid, Decimal.parse('4200.50'), reason: 'latest gold quote');
    expect(s.liveQuotes['EUR/USD']!.rawBid, Decimal.parse('1.1003'), reason: 'latest euro quote');
    expect(s.instruments.firstWhere((i) => i.symbol == 'EUR/USD').rawBid, Decimal.parse('1.1003'));

    await sub.cancel();
    await bloc.close();
  });
}
