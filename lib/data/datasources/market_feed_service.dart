import 'dart:async';
import 'dart:math';
import 'package:decimal/decimal.dart';
import '../../core/constants/app_constants.dart';
import '../../core/math/money_math.dart';
import '../../domain/entities/trading_entities.dart';
import '../../domain/entities/chart_entities.dart';
import 'binance_market_datasource.dart';

class MarketFeedService {
  static final MarketFeedService _instance = MarketFeedService._internal();
  factory MarketFeedService() => _instance;

  final BinanceMarketDataSource _binanceSource = BinanceMarketDataSource.instance;
  final StreamController<InstrumentEntity> _tickController = StreamController<InstrumentEntity>.broadcast();
  Stream<InstrumentEntity> get tickStream => _tickController.stream;

  StreamSubscription? _binanceTickSub;
  StreamSubscription? _binanceKlineSub;

  final Map<String, List<CandleStickModel>> _candleHistory = {};
  final Map<String, InstrumentEntity> _instruments = {};

  // Dealer Spread Markup Map (Symbol -> pips)
  final Map<String, int> _spreadMarkupMap = {
    'XAU/USD': 15,
    'BTC/USD': 40,
    'ETH/USD': 25,
    'EUR/USD': 12,
    'XAG/USD': 18,
    'SOL/USD': 20,
    'XRP/USD': 10,
    'BNB/USD': 20,
    'ADA/USD': 10,
  };

  MarketFeedService._internal() {
    _initializeFeed();
  }

  void _initializeFeed() {
    // 1. Initial baseline instruments
    _instruments['XAU/USD'] = InstrumentEntity(
      symbol: 'XAU/USD',
      name: 'Gold vs US Dollar',
      category: 'metals',
      rawBid: MoneyMath.toDec(4479.50),
      rawAsk: MoneyMath.toDec(4479.90),
      spreadMarkupPips: _spreadMarkupMap['XAU/USD'] ?? 15,
      decimals: 2,
      contractSize: AppConstants.contractSizeGold,
      change24h: 1.45,
      high24h: MoneyMath.toDec(4517.76),
      low24h: MoneyMath.toDec(4351.92),
      volume24h: MoneyMath.toDec(184200),
      isFavorite: true,
    );

    _instruments['BTC/USD'] = InstrumentEntity(
      symbol: 'BTC/USD',
      name: 'Bitcoin vs US Dollar',
      category: 'crypto',
      rawBid: MoneyMath.toDec(96420.00),
      rawAsk: MoneyMath.toDec(96435.00),
      spreadMarkupPips: _spreadMarkupMap['BTC/USD'] ?? 40,
      decimals: 2,
      contractSize: AppConstants.contractSizeCrypto,
      change24h: 3.82,
      high24h: MoneyMath.toDec(98200.00),
      low24h: MoneyMath.toDec(94500.00),
      volume24h: MoneyMath.toDec(54120),
      isFavorite: true,
    );

    _instruments['ETH/USD'] = InstrumentEntity(
      symbol: 'ETH/USD',
      name: 'Ethereum vs US Dollar',
      category: 'crypto',
      rawBid: MoneyMath.toDec(2745.20),
      rawAsk: MoneyMath.toDec(2745.80),
      spreadMarkupPips: _spreadMarkupMap['ETH/USD'] ?? 25,
      decimals: 2,
      contractSize: AppConstants.contractSizeCrypto,
      change24h: -0.64,
      high24h: MoneyMath.toDec(2810.00),
      low24h: MoneyMath.toDec(2690.00),
      volume24h: MoneyMath.toDec(89450),
    );

    _instruments['EUR/USD'] = InstrumentEntity(
      symbol: 'EUR/USD',
      name: 'Euro vs US Dollar',
      category: 'forex',
      rawBid: MoneyMath.toDec(1.0845),
      rawAsk: MoneyMath.toDec(1.0847),
      spreadMarkupPips: _spreadMarkupMap['EUR/USD'] ?? 12,
      decimals: 4,
      contractSize: AppConstants.contractSizeForex,
      change24h: 0.18,
      high24h: MoneyMath.toDec(1.0890),
      low24h: MoneyMath.toDec(1.0815),
      volume24h: MoneyMath.toDec(450000),
      isFavorite: true,
    );

    _instruments['SOL/USD'] = InstrumentEntity(
      symbol: 'SOL/USD',
      name: 'Solana vs US Dollar',
      category: 'crypto',
      rawBid: MoneyMath.toDec(185.20),
      rawAsk: MoneyMath.toDec(185.35),
      spreadMarkupPips: _spreadMarkupMap['SOL/USD'] ?? 20,
      decimals: 2,
      contractSize: AppConstants.contractSizeCrypto,
      change24h: 4.25,
      high24h: MoneyMath.toDec(192.00),
      low24h: MoneyMath.toDec(179.50),
      volume24h: MoneyMath.toDec(156000),
    );

    _instruments['XRP/USD'] = InstrumentEntity(
      symbol: 'XRP/USD',
      name: 'Ripple vs US Dollar',
      category: 'crypto',
      rawBid: MoneyMath.toDec(2.4510),
      rawAsk: MoneyMath.toDec(2.4525),
      spreadMarkupPips: _spreadMarkupMap['XRP/USD'] ?? 10,
      decimals: 4,
      contractSize: AppConstants.contractSizeCrypto,
      change24h: 5.12,
      high24h: MoneyMath.toDec(2.6200),
      low24h: MoneyMath.toDec(2.3100),
      volume24h: MoneyMath.toDec(310000),
    );

    _instruments['BNB/USD'] = InstrumentEntity(
      symbol: 'BNB/USD',
      name: 'Binance Coin vs US Dollar',
      category: 'crypto',
      rawBid: MoneyMath.toDec(645.00),
      rawAsk: MoneyMath.toDec(645.50),
      spreadMarkupPips: _spreadMarkupMap['BNB/USD'] ?? 20,
      decimals: 2,
      contractSize: AppConstants.contractSizeCrypto,
      change24h: 1.85,
      high24h: MoneyMath.toDec(660.00),
      low24h: MoneyMath.toDec(630.00),
      volume24h: MoneyMath.toDec(42000),
    );

    _instruments['ADA/USD'] = InstrumentEntity(
      symbol: 'ADA/USD',
      name: 'Cardano vs US Dollar',
      category: 'crypto',
      rawBid: MoneyMath.toDec(0.7850),
      rawAsk: MoneyMath.toDec(0.7860),
      spreadMarkupPips: _spreadMarkupMap['ADA/USD'] ?? 10,
      decimals: 4,
      contractSize: AppConstants.contractSizeCrypto,
      change24h: 2.30,
      high24h: MoneyMath.toDec(0.8200),
      low24h: MoneyMath.toDec(0.7500),
      volume24h: MoneyMath.toDec(98000),
    );

    _instruments['XAG/USD'] = InstrumentEntity(
      symbol: 'XAG/USD',
      name: 'Silver vs US Dollar',
      category: 'metals',
      rawBid: MoneyMath.toDec(32.40),
      rawAsk: MoneyMath.toDec(32.43),
      spreadMarkupPips: _spreadMarkupMap['XAG/USD'] ?? 18,
      decimals: 2,
      contractSize: AppConstants.contractSizeSilver,
      change24h: 2.15,
      high24h: MoneyMath.toDec(33.10),
      low24h: MoneyMath.toDec(31.80),
      volume24h: MoneyMath.toDec(120400),
    );

    // 2. Pre-generate realistic Candlesticks matching exact initial prices
    for (final sym in _instruments.keys) {
      _candleHistory[sym] = _generateRealisticCandles(_instruments[sym]!.bid.toDouble());
    }

    // 3. Connect real Binance feed
    _connectRealBinanceFeed();
  }

  Future<void> _connectRealBinanceFeed() async {
    try {
      final realInitialQuotes = await _binanceSource.fetchInitialPrices();
      for (final quote in realInitialQuotes) {
        _applyIncomingQuote(quote);
      }
    } catch (_) {}

    _binanceTickSub?.cancel();
    _binanceTickSub = _binanceSource.cryptoStream.listen((quote) {
      _applyIncomingQuote(quote);
    });

    _binanceKlineSub?.cancel();
    _binanceKlineSub = _binanceSource.klineStream.listen((entry) {
      _applyIncomingKline(entry.key, entry.value);
    });
  }

  void _applyIncomingQuote(InstrumentEntity quote) {
    final symbol = quote.symbol;
    final markup = _spreadMarkupMap[symbol] ?? 15;
    final mid = quote.midPrice.toDouble();

    final updated = quote.copyWith(
      spreadMarkupPips: markup,
      name: _instruments[symbol]?.name ?? quote.name,
      category: _instruments[symbol]?.category ?? quote.category,
      contractSize: _instruments[symbol]?.contractSize ?? quote.contractSize,
      isFavorite: _instruments[symbol]?.isFavorite ?? false,
    );

    _instruments[symbol] = updated;
    _tickController.add(updated);

    // Dynamically update latest candle across all cached timeframes for this symbol
    for (final tf in ChartTimeframe.values) {
      final key = '${symbol}_${tf.name}';
      final candles = _candleHistory[key];
      if (candles != null && candles.isNotEmpty) {
        final last = candles.last;
        candles[candles.length - 1] = last.copyWith(
          close: mid,
          high: max(last.high, mid),
          low: min(last.low, mid),
        );
      }
    }

    final symCandles = _candleHistory[symbol];
    if (symCandles != null && symCandles.isNotEmpty) {
      final last = symCandles.last;
      symCandles[symCandles.length - 1] = last.copyWith(
        close: mid,
        high: max(last.high, mid),
        low: min(last.low, mid),
      );
    }
  }

  void _applyIncomingKline(String symbol, CandleStickModel liveCandle) {
    final candles = _candleHistory[symbol];
    if (candles != null && candles.isNotEmpty) {
      final last = candles.last;
      if (last.time.year == liveCandle.time.year &&
          last.time.month == liveCandle.time.month &&
          last.time.day == liveCandle.time.day &&
          last.time.hour == liveCandle.time.hour &&
          last.time.minute == liveCandle.time.minute) {
        candles[candles.length - 1] = liveCandle;
      } else if (liveCandle.time.isAfter(last.time)) {
        candles.add(liveCandle);
        if (candles.length > 500) {
          candles.removeAt(0);
        }
      }
    }
  }

  void updateSpreadMarkup(String symbol, int markupPips) {
    _spreadMarkupMap[symbol] = markupPips;
    final current = _instruments[symbol];
    if (current != null) {
      _instruments[symbol] = current.copyWith(spreadMarkupPips: markupPips);
      _tickController.add(_instruments[symbol]!);
    }
  }

  int getSpreadMarkup(String symbol) => _spreadMarkupMap[symbol] ?? 10;

  List<InstrumentEntity> getAllInstruments() => _instruments.values.toList();

  InstrumentEntity? getInstrument(String symbol) => _instruments[symbol];

  List<CandleStickModel> getCandles(String symbol, [ChartTimeframe timeframe = ChartTimeframe.h1]) {
    final key = '${symbol}_${timeframe.name}';
    final inst = _instruments[symbol];
    final curPrice = inst != null ? inst.midPrice.toDouble() : 4480.0;

    var list = _candleHistory[key];
    if (list == null || list.isEmpty || (list.last.close - curPrice).abs() / curPrice > 0.04) {
      list = _generateRealisticCandles(curPrice, timeframe, 300);
      _candleHistory[key] = list;
      _candleHistory[symbol] = list;
      _fetchRealKlinesAsync(symbol, timeframe);
    }
    return list;
  }

  Future<List<CandleStickModel>> fetchCandlesAsync([String? symbol, ChartTimeframe? timeframe]) async {
    final sym = symbol ?? 'XAU/USD';
    final tf = timeframe ?? ChartTimeframe.h1;
    final key = '${sym}_${tf.name}';

    final inst = _instruments[sym];
    final curPrice = inst != null ? inst.midPrice.toDouble() : 4480.0;

    // Fetch from real Binance source if available
    final candles = await _binanceSource.fetchKlines(sym, tf, limit: 500);
    if (candles.isNotEmpty) {
      _candleHistory[key] = candles;
      _candleHistory[sym] = candles;
      return candles;
    }

    // High quality continuous realistic candlestick generation anchored directly to current price
    var existing = _candleHistory[key];
    if (existing == null || existing.isEmpty || (existing.last.close - curPrice).abs() / curPrice > 0.04) {
      existing = _generateRealisticCandles(curPrice, tf, 300);
      _candleHistory[key] = existing;
      _candleHistory[sym] = existing;
    }
    return existing;
  }

  void _fetchRealKlinesAsync(String symbol, ChartTimeframe timeframe) async {
    try {
      final key = '${symbol}_${timeframe.name}';
      final candles = await _binanceSource.fetchKlines(symbol, timeframe, limit: 500);
      if (candles.isNotEmpty) {
        _candleHistory[key] = candles;
        _candleHistory[symbol] = candles;
      }
    } catch (_) {}
  }

  List<CandleStickModel> _generateRealisticCandles(
    double basePrice, [
    ChartTimeframe timeframe = ChartTimeframe.h1,
    int count = 300,
  ]) {
    final now = DateTime.now();
    final random = Random(basePrice.toInt() ^ (timeframe.index * 37));

    Duration stepDuration;
    double volatility;
    switch (timeframe) {
      case ChartTimeframe.m1:
        stepDuration = const Duration(minutes: 1);
        volatility = 0.0008;
        break;
      case ChartTimeframe.m5:
        stepDuration = const Duration(minutes: 5);
        volatility = 0.0016;
        break;
      case ChartTimeframe.m15:
        stepDuration = const Duration(minutes: 15);
        volatility = 0.0028;
        break;
      case ChartTimeframe.m30:
        stepDuration = const Duration(minutes: 30);
        volatility = 0.0040;
        break;
      case ChartTimeframe.h1:
        stepDuration = const Duration(hours: 1);
        volatility = 0.0060;
        break;
      case ChartTimeframe.h4:
        stepDuration = const Duration(hours: 4);
        volatility = 0.0110;
        break;
      case ChartTimeframe.d1:
        stepDuration = const Duration(days: 1);
        volatility = 0.0200;
        break;
    }

    double currentClose = basePrice;
    final generatedBackwards = <CandleStickModel>[];

    for (int k = 0; k < count; k++) {
      final time = now.subtract(stepDuration * k);

      // Mean-reverting realistic wave to keep chart within authentic realistic trading corridors
      final meanReversion = (basePrice - currentClose) * 0.025;
      final noise = (random.nextDouble() - 0.495) * (currentClose * volatility);
      final change = noise + meanReversion;

      final open = k == 0 ? (currentClose - change * 0.4) : (currentClose - change);
      final close = currentClose;

      final bodyHigh = max(open, close);
      final bodyLow = min(open, close);
      final wickScale = currentClose * (volatility * 0.55);
      final high = bodyHigh + (random.nextDouble() * wickScale);
      final low = max(0.01, bodyLow - (random.nextDouble() * wickScale));
      final volume = (150 + random.nextDouble() * 750) * (k == 0 ? 0.7 : 1.0);

      generatedBackwards.add(CandleStickModel(
        time: time,
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume,
      ));

      currentClose = open;
    }

    return generatedBackwards.reversed.toList();
  }

  void dispose() {
    _binanceTickSub?.cancel();
    _binanceKlineSub?.cancel();
    _tickController.close();
  }
}
