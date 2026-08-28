import 'dart:async';
import 'dart:math';
import 'package:decimal/decimal.dart';
import '../../core/constants/app_constants.dart';
import '../../core/math/money_math.dart';
import '../../domain/entities/trading_entities.dart';

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
}

/// Mock Market Data Source for legacy compatibility
class MockMarketDataSource {
  MockMarketDataSource._();
  static final MockMarketDataSource instance = MockMarketDataSource._();

  final _random = Random();
  final Map<String, StreamController<InstrumentEntity>> _streams = {};
  final Map<String, Timer> _timers = {};
  final Map<String, InstrumentEntity> _currentPrices = {};

  List<InstrumentEntity> getInitialInstruments() {
    return [
      _makeInstrument('EUR/USD', 'Euro / US Dollar', 'forex', 1.08532, 4, AppConstants.contractSizeForex),
      _makeInstrument('BTC/USD', 'Bitcoin / US Dollar', 'crypto', 96420.00, 2, AppConstants.contractSizeCrypto),
      _makeInstrument('ETH/USD', 'Ethereum / US Dollar', 'crypto', 2745.80, 2, AppConstants.contractSizeCrypto),
      _makeInstrument('XAU/USD', 'Gold / US Dollar', 'metals', 2864.50, 2, AppConstants.contractSizeGold),
      _makeInstrument('XAG/USD', 'Silver / US Dollar', 'metals', 32.40, 2, AppConstants.contractSizeSilver),
    ];
  }

  InstrumentEntity _makeInstrument(
    String symbol,
    String name,
    String category,
    double basePrice,
    int decimals,
    Decimal contractSize,
  ) {
    final change = (_random.nextDouble() - 0.5) * 2;
    final spread = basePrice * 0.0001 * (category == 'forex' ? 1 : 2);
    final rawBidDec = MoneyMath.toDec(basePrice);
    final rawAskDec = MoneyMath.toDec(basePrice + spread);

    final instrument = InstrumentEntity(
      symbol: symbol,
      name: name,
      category: category,
      rawBid: rawBidDec,
      rawAsk: rawAskDec,
      contractSize: contractSize,
      change24h: change,
      high24h: MoneyMath.toDec(basePrice * 1.005),
      low24h: MoneyMath.toDec(basePrice * 0.995),
      volume24h: MoneyMath.toDec(_random.nextDouble() * 1000000),
      decimals: decimals,
    );
    _currentPrices[symbol] = instrument;
    return instrument;
  }

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

        final volatility = current.rawBid.toDouble() * 0.0003;
        final delta = (_random.nextDouble() - 0.5) * volatility;
        final newBid = current.rawBid.toDouble() + delta;
        final spread = current.spread.toDouble();
        final newAsk = newBid + spread;

        final updated = current.copyWith(
          rawBid: MoneyMath.toDec(newBid),
          rawAsk: MoneyMath.toDec(newAsk),
          change24h: current.change24h + (_random.nextDouble() - 0.5) * 0.01,
        );
        _currentPrices[symbol] = updated;
        _streams[symbol]?.add(updated);
      },
    );
  }

  InstrumentEntity? getCurrentPrice(String symbol) => _currentPrices[symbol];

  List<OhlcCandle> getOhlcData(String symbol, String timeframe) {
    final base = _currentPrices[symbol]?.rawBid.toDouble() ?? 100.0;
    final candles = <OhlcCandle>[];
    var price = base;
    final now = DateTime.now();

    final tfMinutes = _timeframeToMinutes(timeframe);

    for (int i = 100; i >= 0; i--) {
      final open = price;
      final move = (_random.nextDouble() - 0.5) * base * 0.002;
      final close = open + move;
      final range = base * 0.003;
      candles.add(OhlcCandle(
        time: now.subtract(Duration(minutes: i * tfMinutes)),
        open: open,
        high: max(open, close) + _random.nextDouble() * range * 0.5,
        low: min(open, close) - _random.nextDouble() * range * 0.5,
        close: close,
        volume: 50 + _random.nextDouble() * 200,
      ));
      price = close;
    }
    return candles;
  }

  int _timeframeToMinutes(String tf) {
    switch (tf) {
      case '1m':
        return 1;
      case '5m':
        return 5;
      case '15m':
        return 15;
      case '30m':
        return 30;
      case '1h':
        return 60;
      case '4h':
        return 240;
      case '1D':
        return 1440;
      default:
        return 60;
    }
  }
}
