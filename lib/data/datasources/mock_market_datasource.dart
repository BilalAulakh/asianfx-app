import 'dart:async';
import 'dart:math';
import '../../domain/entities/trading_entities.dart';

/// Mock Market Data Source
/// Simulates real-time price feeds — replace with live provider (Polygon, TwelveData, Binance)
class MockMarketDataSource {
  MockMarketDataSource._();
  static final MockMarketDataSource instance = MockMarketDataSource._();

  final _random = Random();
  final Map<String, StreamController<InstrumentEntity>> _streams = {};
  final Map<String, Timer> _timers = {};
  final Map<String, InstrumentEntity> _currentPrices = {};

  // ── Initial Data ─────────────────────────────────────────────────────────────
  List<InstrumentEntity> getInitialInstruments() {
    return [
      // Forex
      _makeInstrument('EURUSD', 'Euro / US Dollar', 'forex', 1.08532, 5),
      _makeInstrument('GBPUSD', 'Pound / US Dollar', 'forex', 1.26741, 5),
      _makeInstrument('USDJPY', 'US Dollar / Japanese Yen', 'forex', 149.832, 3),
      _makeInstrument('USDCHF', 'US Dollar / Swiss Franc', 'forex', 0.89142, 5),
      _makeInstrument('AUDUSD', 'Australian Dollar / US Dollar', 'forex', 0.64891, 5),
      _makeInstrument('USDCAD', 'US Dollar / Canadian Dollar', 'forex', 1.36254, 5),
      _makeInstrument('NZDUSD', 'New Zealand Dollar / US Dollar', 'forex', 0.59321, 5),
      _makeInstrument('EURGBP', 'Euro / Pound Sterling', 'forex', 0.85643, 5),
      _makeInstrument('EURJPY', 'Euro / Japanese Yen', 'forex', 162.451, 3),
      _makeInstrument('GBPJPY', 'Pound / Japanese Yen', 'forex', 189.632, 3),

      // Crypto
      _makeInstrument('BTCUSD', 'Bitcoin / US Dollar', 'crypto', 67842.50, 2),
      _makeInstrument('ETHUSD', 'Ethereum / US Dollar', 'crypto', 3521.80, 2),
      _makeInstrument('XRPUSD', 'Ripple / US Dollar', 'crypto', 0.5832, 4),
      _makeInstrument('BNBUSD', 'Binance Coin / US Dollar', 'crypto', 412.30, 2),
      _makeInstrument('SOLUSD', 'Solana / US Dollar', 'crypto', 148.75, 2),
      _makeInstrument('ADAUSD', 'Cardano / US Dollar', 'crypto', 0.4521, 4),

      // Gold & Silver
      _makeInstrument('XAUUSD', 'Gold / US Dollar', 'gold', 2341.50, 2),
      _makeInstrument('XAGUSD', 'Silver / US Dollar', 'gold', 27.842, 3),

      // Indices
      _makeInstrument('US30', 'Dow Jones Industrial', 'indices', 39421.50, 2),
      _makeInstrument('US500', 'S&P 500', 'indices', 5342.80, 2),
      _makeInstrument('NASDAQ', 'NASDAQ Composite', 'indices', 18721.30, 2),
      _makeInstrument('UK100', 'FTSE 100', 'indices', 8124.60, 2),
      _makeInstrument('GER40', 'DAX 40', 'indices', 18234.90, 2),

      // Commodities
      _makeInstrument('USOIL', 'Crude Oil (WTI)', 'commodities', 78.42, 2),
      _makeInstrument('NGAS', 'Natural Gas', 'commodities', 2.841, 3),

      // Stocks
      _makeInstrument('AAPL', 'Apple Inc.', 'stocks', 189.42, 2),
      _makeInstrument('TSLA', 'Tesla, Inc.', 'stocks', 248.70, 2),
      _makeInstrument('NVDA', 'NVIDIA Corporation', 'stocks', 121.35, 2),
      _makeInstrument('AMZN', 'Amazon.com, Inc.', 'stocks', 185.60, 2),
      _makeInstrument('MSFT', 'Microsoft Corporation', 'stocks', 415.20, 2),
    ];
  }

  InstrumentEntity _makeInstrument(
    String symbol,
    String name,
    String category,
    double basePrice,
    int decimals,
  ) {
    final change = (_random.nextDouble() - 0.5) * 2; // -1% to +1%
    final spread = basePrice * 0.0001 * (category == 'forex' ? 1 : 2);
    final instrument = InstrumentEntity(
      symbol: symbol,
      name: name,
      category: category,
      bid: basePrice,
      ask: basePrice + spread,
      spread: spread,
      change24h: change,
      changeAmount: basePrice * change / 100,
      high24h: basePrice * 1.005,
      low24h: basePrice * 0.995,
      volume24h: _random.nextDouble() * 1000000,
      decimals: decimals,
    );
    _currentPrices[symbol] = instrument;
    return instrument;
  }

  // ── Real-time Streaming ──────────────────────────────────────────────────────
  Stream<InstrumentEntity> streamPrice(String symbol) {
    if (!_streams.containsKey(symbol)) {
      _streams[symbol] = StreamController<InstrumentEntity>.broadcast();
      _startPriceTick(symbol);
    }
    return _streams[symbol]!.stream;
  }

  void _startPriceTick(String symbol) {
    _timers[symbol] = Timer.periodic(
      Duration(milliseconds: 800 + _random.nextInt(1200)),
      (_) {
        final current = _currentPrices[symbol];
        if (current == null) return;

        // Simulate price movement with random walk
        final volatility = current.bid * 0.0003;
        final delta = (_random.nextDouble() - 0.5) * volatility;
        final newBid = current.bid + delta;
        final spread = current.spread;
        final newAsk = newBid + spread;

        final updated = current.copyWith(
          bid: newBid,
          ask: newAsk,
          change24h: current.change24h + (_random.nextDouble() - 0.5) * 0.01,
        );
        _currentPrices[symbol] = updated;
        _streams[symbol]?.add(updated);
      },
    );
  }

  InstrumentEntity? getCurrentPrice(String symbol) => _currentPrices[symbol];

  List<OhlcCandle> getOhlcData(String symbol, String timeframe) {
    final base = _currentPrices[symbol]?.bid ?? 1.0;
    final candles = <OhlcCandle>[];
    var price = base;
    final now = DateTime.now();

    final tfMinutes = _timeframeToMinutes(timeframe);

    for (int i = 200; i >= 0; i--) {
      final open = price;
      final move = (_random.nextDouble() - 0.5) * base * 0.002;
      final close = open + move;
      final range = base * 0.003;
      candles.add(OhlcCandle(
        time: now.subtract(Duration(minutes: i * tfMinutes)),
        open: open,
        high: [open, close].reduce((a, b) => a > b ? a : b) + _random.nextDouble() * range,
        low: [open, close].reduce((a, b) => a < b ? a : b) - _random.nextDouble() * range,
        close: close,
        volume: _random.nextDouble() * 10000,
      ));
      price = close;
    }
    return candles;
  }

  int _timeframeToMinutes(String tf) {
    switch (tf) {
      case '1m': return 1;
      case '5m': return 5;
      case '15m': return 15;
      case '30m': return 30;
      case '1h': return 60;
      case '4h': return 240;
      case '1D': return 1440;
      case '1W': return 10080;
      default: return 60;
    }
  }

  void dispose() {
    for (final t in _timers.values) t.cancel();
    for (final s in _streams.values) s.close();
    _timers.clear();
    _streams.clear();
  }
}

class OhlcCandle {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const OhlcCandle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  bool get isBullish => close >= open;
}
