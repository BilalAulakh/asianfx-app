import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../domain/entities/trading_entities.dart';

/// Real Live Binance WebSocket Market Data Service
/// Connects directly to Binance official public WebSocket API (100% FREE - $0/month)
class BinanceMarketDataSource {
  BinanceMarketDataSource._();
  static final BinanceMarketDataSource instance = BinanceMarketDataSource._();

  WebSocketChannel? _channel;
  StreamController<InstrumentEntity>? _tickerController;
  final Map<String, InstrumentEntity> _latestCryptoQuotes = {};
  bool _isConnected = false;

  Stream<InstrumentEntity> get cryptoStream {
    _tickerController ??= StreamController<InstrumentEntity>.broadcast();
    if (!_isConnected) {
      connectToBinance();
    }
    return _tickerController!.stream;
  }

  Map<String, InstrumentEntity> get latestCryptoQuotes => _latestCryptoQuotes;

  /// Connects to Binance Multi-Stream WebSocket
  void connectToBinance() {
    try {
      final streams = [
        'btcusdt@ticker',
        'ethusdt@ticker',
        'solusdt@ticker',
        'xrpusdt@ticker',
        'bnbusdt@ticker',
        'adausdt@ticker',
      ].join('/');

      final uri = Uri.parse('wss://stream.binance.com:9443/ws/$streams');
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;

      _channel!.stream.listen(
        (data) {
          _handleBinanceMessage(data);
        },
        onError: (err) {
          print('[Binance WS Error]: $err');
          _isConnected = false;
          _reconnect();
        },
        onDone: () {
          print('[Binance WS Disconnected]');
          _isConnected = false;
          _reconnect();
        },
      );
    } catch (e) {
      print('[Binance Connection Failed]: $e');
      _isConnected = false;
    }
  }

  void _handleBinanceMessage(dynamic rawData) {
    try {
      final json = jsonDecode(rawData as String) as Map<String, dynamic>;

      // Binance Ticker event "24hrTicker"
      if (json['e'] == '24hrTicker' || json.containsKey('s')) {
        final symbolRaw = json['s'] as String; // e.g. BTCUSDT
        final symbol = symbolRaw.replaceAll('USDT', 'USD');
        final lastPrice = double.parse(json['c'] as String);
        final priceChangePercent = double.parse(json['P'] as String);
        final priceChangeAmount = double.parse(json['p'] as String);
        final highPrice = double.parse(json['h'] as String);
        final lowPrice = double.parse(json['l'] as String);
        final volume = double.parse(json['v'] as String);

        // Calculate bid/ask with micro spread
        final spreadPct = 0.0001; // 0.01% spread
        final bid = lastPrice * (1 - spreadPct / 2);
        final ask = lastPrice * (1 + spreadPct / 2);

        String name = symbol;
        if (symbol == 'BTCUSD') name = 'Bitcoin / US Dollar';
        if (symbol == 'ETHUSD') name = 'Ethereum / US Dollar';
        if (symbol == 'SOLUSD') name = 'Solana / US Dollar';
        if (symbol == 'XRPUSD') name = 'Ripple / US Dollar';
        if (symbol == 'BNBUSD') name = 'Binance Coin / US Dollar';
        if (symbol == 'ADAUSD') name = 'Cardano / US Dollar';

        final instrument = InstrumentEntity(
          symbol: symbol,
          name: name,
          category: 'crypto',
          bid: bid,
          ask: ask,
          spread: ask - bid,
          change24h: priceChangePercent,
          changeAmount: priceChangeAmount,
          high24h: highPrice,
          low24h: lowPrice,
          volume24h: volume,
          decimals: lastPrice > 10 ? 2 : 4,
        );

        _latestCryptoQuotes[symbol] = instrument;
        _tickerController?.add(instrument);
      }
    } catch (e) {
      // Ignore parse errors
    }
  }

  void _reconnect() {
    Timer(const Duration(seconds: 3), () {
      if (!_isConnected) connectToBinance();
    });
  }

  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
  }
}
