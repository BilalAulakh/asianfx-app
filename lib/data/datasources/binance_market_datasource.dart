import 'dart:async';
import 'dart:convert';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/constants/app_constants.dart';
import '../../core/math/money_math.dart';
import '../../domain/entities/chart_entities.dart';
import '../../domain/entities/trading_entities.dart';

/// Real Live Binance WebSocket & REST Market Data Service
/// Integrates:
/// 1. Multi-Stream WebSocket: wss://stream.binance.com:9443/stream?streams={symbol}@trade/{symbol}@ticker/{symbol}@kline_1m
/// 2. REST 24hr Ticker: https://api.binance.com/api/v3/ticker/24hr?symbol={symbol}
/// 3. REST Historical Klines: https://api.binance.com/api/v3/klines?symbol={symbol}&interval={interval}&limit=500
class BinanceMarketDataSource {
  BinanceMarketDataSource._();
  static final BinanceMarketDataSource instance = BinanceMarketDataSource._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  WebSocketChannel? _channel;
  StreamController<InstrumentEntity>? _tickerController;
  StreamController<MapEntry<String, CandleStickModel>>? _klineController;

  final Map<String, InstrumentEntity> _latestQuotes = {};
  final Map<String, List<CandleStickModel>> _candleCache = {};
  bool _isConnected = false;
  Timer? _reconnectTimer;

  // Mapping from app symbol (or raw pair) to Binance pair string
  static const Map<String, String> _appToBinanceSymbol = {
    'BTC/USD': 'BTCUSDT',
    'BTCUSD': 'BTCUSDT',
    'ETH/USD': 'ETHUSDT',
    'ETHUSD': 'ETHUSDT',
    'SOL/USD': 'SOLUSDT',
    'SOLUSD': 'SOLUSDT',
    'XRP/USD': 'XRPUSDT',
    'XRPUSD': 'XRPUSDT',
    'BNB/USD': 'BNBUSDT',
    'BNBUSD': 'BNBUSDT',
    'ADA/USD': 'ADAUSDT',
    'ADAUSD': 'ADAUSDT',
    'DOGE/USD': 'DOGEUSDT',
    'DOGEUSD': 'DOGEUSDT',
    'AVAX/USD': 'AVAXUSDT',
    'AVAXUSD': 'AVAXUSDT',
    'LINK/USD': 'LINKUSDT',
    'LINKUSD': 'LINKUSDT',
    'DOT/USD': 'DOTUSDT',
    'DOTUSD': 'DOTUSDT',
    'NEAR/USD': 'NEARUSDT',
    'NEARUSD': 'NEARUSDT',
    'LTC/USD': 'LTCUSDT',
    'LTCUSD': 'LTCUSDT',
    'XAU/USD': 'PAXGUSDT', // PAX Gold as direct institutional Binance spot proxy for Gold
    'XAUUSD': 'PAXGUSDT',
    'EUR/USD': 'EURUSDT',
    'EURUSD': 'EURUSDT',
    'GBP/USD': 'GBPUSDT',
    'GBPUSD': 'GBPUSDT',
    'AUD/USD': 'AUDUSDT',
    'AUDUSD': 'AUDUSDT',
  };

  // Mapping from Binance pair string to standard app display symbol
  static const Map<String, String> _binanceToAppSymbol = {
    'BTCUSDT': 'BTC/USD',
    'ETHUSDT': 'ETH/USD',
    'SOLUSDT': 'SOL/USD',
    'XRPUSDT': 'XRP/USD',
    'BNBUSDT': 'BNB/USD',
    'ADAUSDT': 'ADA/USD',
    'DOGEUSDT': 'DOGE/USD',
    'AVAXUSDT': 'AVAX/USD',
    'LINKUSDT': 'LINK/USD',
    'DOTUSDT': 'DOT/USD',
    'NEARUSDT': 'NEAR/USD',
    'LTCUSDT': 'LTC/USD',
    'PAXGUSDT': 'XAU/USD',
    'EURUSDT': 'EUR/USD',
    'GBPUSDT': 'GBP/USD',
    'AUDUSDT': 'AUD/USD',
  };

  static const List<String> _streamPairs = [
    'btcusdt',
    'ethusdt',
    'solusdt',
    'xrpusdt',
    'bnbusdt',
    'adausdt',
    'dogeusdt',
    'avaxusdt',
    'linkusdt',
    'dotusdt',
    'nearusdt',
    'ltcusdt',
    'paxgusdt',
    'eurusdt',
    'gbpusdt',
    'audusdt',
  ];

  Stream<InstrumentEntity> get cryptoStream {
    _tickerController ??= StreamController<InstrumentEntity>.broadcast();
    if (!_isConnected) {
      connectToBinance();
    }
    return _tickerController!.stream;
  }

  Stream<MapEntry<String, CandleStickModel>> get klineStream {
    _klineController ??= StreamController<MapEntry<String, CandleStickModel>>.broadcast();
    if (!_isConnected) {
      connectToBinance();
    }
    return _klineController!.stream;
  }

  Map<String, InstrumentEntity> get latestQuotes => _latestQuotes;

  String mapToBinanceSymbol(String symbol) {
    final cleaned = symbol.toUpperCase();
    return _appToBinanceSymbol[cleaned] ?? '${cleaned.replaceAll('/', '').replaceAll('USD', '')}USDT';
  }

  String mapToAppSymbol(String binanceSymbol) {
    final upper = binanceSymbol.toUpperCase();
    return _binanceToAppSymbol[upper] ?? upper.replaceAll('USDT', '/USD');
  }

  /// 1. Fetch 24hr Ticker from Binance REST endpoint:
  /// https://api.binance.com/api/v3/ticker/24hr?symbol={symbol}
  Future<InstrumentEntity?> fetch24hrTicker(String appSymbol) async {
    try {
      final binanceSymbol = mapToBinanceSymbol(appSymbol);
      final response = await _dio.get(
        'https://api.binance.com/api/v3/ticker/24hr',
        queryParameters: {'symbol': binanceSymbol},
      );

      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final inst = _parseTickerMap(response.data as Map<String, dynamic>);
        if (inst != null) {
          _latestQuotes[inst.symbol] = inst;
          return inst;
        }
      }
    } catch (e) {
      // Ignored / handled gracefully
    }
    return null;
  }

  /// Fetch initial real quotes for all supported instruments on startup
  Future<List<InstrumentEntity>> fetchInitialPrices() async {
    final results = <InstrumentEntity>[];
    try {
      final binanceSymbols = jsonEncode([
        'BTCUSDT',
        'ETHUSDT',
        'SOLUSDT',
        'XRPUSDT',
        'BNBUSDT',
        'ADAUSDT',
        'PAXGUSDT',
        'EURUSDT',
      ]);

      final response = await _dio.get(
        'https://api.binance.com/api/v3/ticker/24hr',
        queryParameters: {'symbols': binanceSymbols},
      );

      if (response.statusCode == 200 && response.data is List) {
        for (final item in response.data) {
          final inst = _parseTickerMap(item as Map<String, dynamic>);
          if (inst != null) {
            _latestQuotes[inst.symbol] = inst;
            results.add(inst);
          }
        }
      }
    } catch (e) {
      // Fallback per-symbol fetch if multi-symbol fails
      for (final pair in ['BTC/USD', 'ETH/USD', 'SOL/USD', 'XAU/USD', 'EUR/USD', 'XRP/USD', 'BNB/USD', 'ADA/USD']) {
        final inst = await fetch24hrTicker(pair);
        if (inst != null) results.add(inst);
      }
    }
    return results;
  }

  /// 2. Fetch Historical Klines from Binance REST endpoint:
  /// https://api.binance.com/api/v3/klines?symbol={symbol}&interval={interval}&limit=500
  Future<List<CandleStickModel>> fetchKlines(
    String appSymbol,
    ChartTimeframe timeframe, {
    int limit = 500,
  }) async {
    try {
      final binanceSymbol = mapToBinanceSymbol(appSymbol);
      final interval = _timeframeToBinanceInterval(timeframe);

      final response = await _dio.get(
        'https://api.binance.com/api/v3/klines',
        queryParameters: {
          'symbol': binanceSymbol,
          'interval': interval,
          'limit': limit,
        },
      );

      if (response.statusCode == 200 && response.data is List) {
        final candles = <CandleStickModel>[];
        for (final raw in response.data) {
          if (raw is List && raw.length >= 6) {
            final openTime = DateTime.fromMillisecondsSinceEpoch(raw[0] as int);
            final open = double.tryParse(raw[1].toString()) ?? 0.0;
            final high = double.tryParse(raw[2].toString()) ?? 0.0;
            final low = double.tryParse(raw[3].toString()) ?? 0.0;
            final close = double.tryParse(raw[4].toString()) ?? 0.0;
            final volume = double.tryParse(raw[5].toString()) ?? 0.0;

            if (open > 0 && close > 0) {
              candles.add(CandleStickModel(
                time: openTime,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume,
              ));
            }
          }
        }

        if (candles.isNotEmpty) {
          _candleCache['${appSymbol}_${timeframe.name}'] = candles;
          return candles;
        }
      }
    } catch (e) {
      // Ignored / fallback to cached
    }
    return _candleCache['${appSymbol}_${timeframe.name}'] ?? [];
  }

  String _timeframeToBinanceInterval(ChartTimeframe tf) {
    switch (tf) {
      case ChartTimeframe.m1:
        return '1m';
      case ChartTimeframe.m5:
        return '5m';
      case ChartTimeframe.m15:
        return '15m';
      case ChartTimeframe.m30:
        return '30m';
      case ChartTimeframe.h1:
        return '1h';
      case ChartTimeframe.h4:
        return '4h';
      case ChartTimeframe.d1:
        return '1d';
    }
  }

  /// 3. Connects to Binance Multi-Stream WebSocket:
  /// wss://stream.binance.com:9443/stream?streams={symbol}@trade/{symbol}@ticker/{symbol}@kline_1m
  void connectToBinance() {
    try {
      final streamsList = <String>[];
      for (final pair in _streamPairs) {
        streamsList.add('$pair@trade');
        streamsList.add('$pair@ticker');
        streamsList.add('$pair@kline_1m');
      }

      final streamsParam = streamsList.join('/');
      final uri = Uri.parse('wss://stream.binance.com:9443/stream?streams=$streamsParam');

      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;

      _channel!.stream.listen(
        (data) {
          _handleBinanceMessage(data);
        },
        onError: (err) {
          _isConnected = false;
          _scheduleReconnect();
        },
        onDone: () {
          _isConnected = false;
          _scheduleReconnect();
        },
      );
    } catch (e) {
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  void _handleBinanceMessage(dynamic rawData) {
    try {
      final json = jsonDecode(rawData as String) as Map<String, dynamic>;
      final streamName = (json['stream'] ?? '') as String;
      final data = json.containsKey('data') ? (json['data'] as Map<String, dynamic>) : json;

      if (streamName.contains('@ticker') || data['e'] == '24hrTicker') {
        final instrument = _parseTickerMap(data);
        if (instrument != null) {
          _latestQuotes[instrument.symbol] = instrument;
          _tickerController?.add(instrument);
        }
      } else if (streamName.contains('@trade') || data['e'] == 'trade') {
        _handleTradeMessage(data);
      } else if (streamName.contains('@kline') || data['e'] == 'kline') {
        _handleKlineMessage(data);
      }
    } catch (e) {
      // Ignore format anomalies
    }
  }

  void _handleTradeMessage(Map<String, dynamic> data) {
    try {
      final symbolRaw = (data['s'] ?? '') as String;
      if (symbolRaw.isEmpty) return;

      final appSymbol = mapToAppSymbol(symbolRaw);
      final price = double.tryParse((data['p'] ?? '0').toString()) ?? 0.0;
      if (price <= 0) return;

      final current = _latestQuotes[appSymbol];
      if (current != null) {
        final spreadPct = appSymbol == 'XAU/USD' ? 0.00015 : 0.00005;
        final bid = price * (1 - spreadPct / 2);
        final ask = price * (1 + spreadPct / 2);

        final updated = current.copyWith(
          rawBid: MoneyMath.toDec(bid),
          rawAsk: MoneyMath.toDec(ask),
        );
        _latestQuotes[appSymbol] = updated;
        _tickerController?.add(updated);
      }
    } catch (e) {
      // Ignore
    }
  }

  void _handleKlineMessage(Map<String, dynamic> data) {
    try {
      final symbolRaw = (data['s'] ?? '') as String;
      final k = data['k'] as Map<String, dynamic>?;
      if (symbolRaw.isEmpty || k == null) return;

      final appSymbol = mapToAppSymbol(symbolRaw);
      final openTime = DateTime.fromMillisecondsSinceEpoch(k['t'] as int);
      final open = double.tryParse(k['o'].toString()) ?? 0.0;
      final high = double.tryParse(k['h'].toString()) ?? 0.0;
      final low = double.tryParse(k['l'].toString()) ?? 0.0;
      final close = double.tryParse(k['c'].toString()) ?? 0.0;
      final volume = double.tryParse(k['v'].toString()) ?? 0.0;

      if (open > 0 && close > 0) {
        final candle = CandleStickModel(
          time: openTime,
          open: open,
          high: high,
          low: low,
          close: close,
          volume: volume,
        );
        _klineController?.add(MapEntry(appSymbol, candle));
      }
    } catch (e) {
      // Ignore
    }
  }

  InstrumentEntity? _parseTickerMap(Map<String, dynamic> data) {
    try {
      final symbolRaw = (data['s'] ?? data['symbol']) as String?;
      if (symbolRaw == null) return null;

      final appSymbol = mapToAppSymbol(symbolRaw);
      final lastPrice = double.tryParse((data['c'] ?? data['lastPrice'] ?? '0').toString()) ?? 0.0;
      if (lastPrice <= 0) return null;

      final priceChangePercent = double.tryParse((data['P'] ?? data['priceChangePercent'] ?? '0').toString()) ?? 0.0;
      final highPrice = double.tryParse((data['h'] ?? data['highPrice'] ?? '0').toString()) ?? lastPrice;
      final lowPrice = double.tryParse((data['l'] ?? data['lowPrice'] ?? '0').toString()) ?? lastPrice;
      final volume = double.tryParse((data['v'] ?? data['volume'] ?? '0').toString()) ?? 0.0;

      final spreadPct = appSymbol == 'XAU/USD' ? 0.00015 : 0.00005;
      final bid = double.tryParse((data['b'] ?? data['bidPrice'] ?? '').toString()) ?? (lastPrice * (1 - spreadPct / 2));
      final ask = double.tryParse((data['a'] ?? data['askPrice'] ?? '').toString()) ?? (lastPrice * (1 + spreadPct / 2));

      String name = appSymbol;
      String category = 'crypto';
      int decimals = 2;
      Decimal contractSize = AppConstants.contractSizeCrypto;

      if (appSymbol == 'XAU/USD') {
        name = 'Gold vs US Dollar';
        category = 'forex';
        contractSize = AppConstants.contractSizeGold;
        decimals = 2;
      } else if (appSymbol == 'BTC/USD') {
        name = 'Bitcoin vs US Dollar';
        category = 'crypto';
        contractSize = AppConstants.contractSizeCrypto;
        decimals = 2;
      } else if (appSymbol == 'ETH/USD') {
        name = 'Ethereum vs US Dollar';
        category = 'crypto';
        contractSize = AppConstants.contractSizeCrypto;
        decimals = 2;
      } else if (appSymbol == 'EUR/USD') {
        name = 'Euro vs US Dollar';
        category = 'forex';
        contractSize = AppConstants.contractSizeForex;
        decimals = 4;
      } else if (appSymbol == 'SOL/USD') {
        name = 'Solana vs US Dollar';
        category = 'crypto';
        decimals = 2;
      } else if (appSymbol == 'XRP/USD') {
        name = 'Ripple vs US Dollar';
        category = 'crypto';
        decimals = 4;
      } else if (appSymbol == 'BNB/USD') {
        name = 'Binance Coin vs US Dollar';
        category = 'crypto';
        decimals = 2;
      } else if (appSymbol == 'ADA/USD') {
        name = 'Cardano vs US Dollar';
        category = 'crypto';
        decimals = 4;
      }

      return InstrumentEntity(
        symbol: appSymbol,
        name: name,
        category: category,
        rawBid: MoneyMath.toDec(bid),
        rawAsk: MoneyMath.toDec(ask),
        contractSize: contractSize,
        change24h: priceChangePercent,
        high24h: MoneyMath.toDec(highPrice),
        low24h: MoneyMath.toDec(lowPrice),
        volume24h: MoneyMath.toDec(volume),
        decimals: decimals,
      );
    } catch (e) {
      return null;
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!_isConnected) connectToBinance();
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
  }
}
