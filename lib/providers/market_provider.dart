import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/datasources/market_feed_service.dart';
import '../domain/entities/trading_entities.dart';
import '../domain/entities/chart_entities.dart';

final marketFeedServiceProvider = Provider<MarketFeedService>((ref) {
  return MarketFeedService();
});

/// List of all tradable instruments
final instrumentsProvider = Provider<List<InstrumentEntity>>((ref) {
  final service = ref.watch(marketFeedServiceProvider);
  return service.getAllInstruments();
});

/// Real-time live price stream for a specific symbol
final priceStreamProvider =
    StreamProvider.family<InstrumentEntity, String>((ref, symbol) {
  final service = ref.watch(marketFeedServiceProvider);
  return service.tickStream.where((inst) => inst.symbol == symbol);
});

/// Active Selected Timeframe
final selectedTimeframeProvider =
    StateProvider<ChartTimeframe>((ref) => ChartTimeframe.h1);

/// OHLC Candlesticks for a specific symbol
final ohlcProvider =
    Provider.family<List<CandleStickModel>, String>((ref, symbol) {
  final service = ref.watch(marketFeedServiceProvider);
  final tf = ref.watch(selectedTimeframeProvider);
  return service.getCandles(symbol, tf);
});

/// Selected active symbol for Trading & Terminal
final activeSymbolProvider = StateProvider<String>((ref) => 'XAU/USD');
