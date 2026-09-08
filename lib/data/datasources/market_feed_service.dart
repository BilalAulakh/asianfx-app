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
  Timer? _liveTickTimer;

  final Map<String, List<CandleStickModel>> _candleHistory = {};
  final Map<String, InstrumentEntity> _instruments = {};

  // Dealer Spread Markup Map (Symbol -> pips)
  final Map<String, int> _spreadMarkupMap = {
    // Forex Majors & Minors
    'EUR/USD': 12,
    'GBP/USD': 15,
    'USD/JPY': 14,
    'USD/CHF': 15,
    'AUD/USD': 14,
    'USD/CAD': 16,
    'NZD/USD': 18,
    'EUR/GBP': 15,
    'EUR/JPY': 18,
    'GBP/JPY': 20,
    'AUD/CAD': 16,
    'AUD/CHF': 16,
    'AUD/JPY': 16,
    'AUD/NZD': 18,
    'CAD/CHF': 18,
    'CAD/JPY': 18,
    'CHF/JPY': 18,
    'EUR/AUD': 16,
    'EUR/CAD': 16,
    'EUR/CHF': 15,
    'EUR/NZD': 20,
    'GBP/AUD': 20,
    'GBP/CAD': 20,
    'GBP/CHF': 18,
    'GBP/NZD': 22,
    'NZD/CAD': 18,
    'NZD/CHF': 18,
    'NZD/JPY': 18,

    // Asian & Global Exotics
    'USD/SGD': 20,
    'USD/HKD': 15,
    'USD/TRY': 45,
    'USD/ZAR': 35,
    'USD/MXN': 35,
    'USD/SEK': 30,
    'USD/NOK': 30,
    'USD/AED': 10,
    'USD/INR': 25,
    'USD/PKR': 50,

    // Metals
    'XAU/USD': 15,
    'XAG/USD': 18,
    'XPT/USD': 25,

    // Commodities
    'WTI/USD': 20,
    'BRENT/USD': 20,
    'NGAS/USD': 25,

    // Crypto
    'BTC/USD': 40,
    'ETH/USD': 25,
    'SOL/USD': 20,
    'XRP/USD': 10,
    'BNB/USD': 20,
    'ADA/USD': 10,
    'DOGE/USD': 10,
    'AVAX/USD': 15,
    'LINK/USD': 15,
    'DOT/USD': 12,
    'NEAR/USD': 12,
    'LTC/USD': 18,

    // Indices
    'US30/USD': 25,
    'NAS100/USD': 20,
    'SPX500/USD': 15,
    'GER40/EUR': 20,
    'UK100/GBP': 18,
    'JP225/USD': 25,

    // Stocks
    'AAPL/USD': 15,
    'NVDA/USD': 15,
    'TSLA/USD': 20,
    'AMZN/USD': 15,
    'MSFT/USD': 15,
    'GOOGL/USD': 15,
  };

  MarketFeedService._internal() {
    _initializeFeed();
  }

  void _initializeFeed() {
    // ── 1. FOREX MAJOR & CROSS PAIRS ──────────────────────────────────────────
    _addInst('EUR/USD', 'Euro vs US Dollar', 'forex', 1.0845, 1.0847, 4, AppConstants.contractSizeForex, 0.18, 1.0890, 1.0815, 450000, true);
    _addInst('GBP/USD', 'British Pound vs US Dollar', 'forex', 1.2980, 1.2983, 4, AppConstants.contractSizeForex, 0.35, 1.3040, 1.2925, 380000, true);
    _addInst('USD/JPY', 'US Dollar vs Japanese Yen', 'forex', 153.40, 153.43, 2, AppConstants.contractSizeForex, -0.22, 154.10, 152.85, 410000, true);
    _addInst('USD/CHF', 'US Dollar vs Swiss Franc', 'forex', 0.8870, 0.8873, 4, AppConstants.contractSizeForex, 0.12, 0.8910, 0.8840, 220000, false);
    _addInst('AUD/USD', 'Australian Dollar vs US Dollar', 'forex', 0.6540, 0.6543, 4, AppConstants.contractSizeForex, 0.45, 0.6590, 0.6495, 290000, false);
    _addInst('USD/CAD', 'US Dollar vs Canadian Dollar', 'forex', 1.3980, 1.3984, 4, AppConstants.contractSizeForex, -0.15, 1.4030, 1.3940, 260000, false);
    _addInst('NZD/USD', 'New Zealand Dollar vs US Dollar', 'forex', 0.5890, 0.5894, 4, AppConstants.contractSizeForex, 0.28, 0.5930, 0.5850, 180000, false);
    _addInst('EUR/GBP', 'Euro vs British Pound', 'forex', 0.8355, 0.8358, 4, AppConstants.contractSizeForex, -0.11, 0.8390, 0.8320, 210000, false);
    _addInst('EUR/JPY', 'Euro vs Japanese Yen', 'forex', 166.35, 166.39, 2, AppConstants.contractSizeForex, -0.08, 167.20, 165.70, 320000, false);
    _addInst('GBP/JPY', 'British Pound vs Japanese Yen', 'forex', 199.10, 199.15, 2, AppConstants.contractSizeForex, 0.15, 200.20, 198.30, 340000, false);
    _addInst('AUD/CAD', 'Australian Dollar vs Canadian Dollar', 'forex', 0.9150, 0.9154, 4, AppConstants.contractSizeForex, 0.10, 0.9190, 0.9120, 190000, false);
    _addInst('AUD/CHF', 'Australian Dollar vs Swiss Franc', 'forex', 0.5800, 0.5804, 4, AppConstants.contractSizeForex, 0.22, 0.5835, 0.5770, 160000, false);
    _addInst('AUD/JPY', 'Australian Dollar vs Japanese Yen', 'forex', 100.30, 100.34, 2, AppConstants.contractSizeForex, 0.35, 100.85, 99.80, 240000, false);
    _addInst('AUD/NZD', 'Australian Dollar vs New Zealand Dollar', 'forex', 1.1105, 1.1109, 4, AppConstants.contractSizeForex, 0.08, 1.1145, 1.1070, 150000, false);
    _addInst('CAD/CHF', 'Canadian Dollar vs Swiss Franc', 'forex', 0.6345, 0.6349, 4, AppConstants.contractSizeForex, -0.05, 0.6380, 0.6315, 140000, false);
    _addInst('CAD/JPY', 'Canadian Dollar vs Japanese Yen', 'forex', 109.70, 109.74, 2, AppConstants.contractSizeForex, 0.18, 110.30, 109.20, 175000, false);
    _addInst('CHF/JPY', 'Swiss Franc vs Japanese Yen', 'forex', 172.90, 172.94, 2, AppConstants.contractSizeForex, -0.12, 173.60, 172.20, 185000, false);
    _addInst('EUR/AUD', 'Euro vs Australian Dollar', 'forex', 1.6580, 1.6584, 4, AppConstants.contractSizeForex, -0.25, 1.6640, 1.6520, 210000, false);
    _addInst('EUR/CAD', 'Euro vs Canadian Dollar', 'forex', 1.5160, 1.5164, 4, AppConstants.contractSizeForex, 0.05, 1.5220, 1.5110, 195000, false);
    _addInst('EUR/CHF', 'Euro vs Swiss Franc', 'forex', 0.9620, 0.9623, 4, AppConstants.contractSizeForex, 0.04, 0.9660, 0.9590, 170000, false);
    _addInst('EUR/NZD', 'Euro vs New Zealand Dollar', 'forex', 1.8410, 1.8415, 4, AppConstants.contractSizeForex, -0.18, 1.8490, 1.8350, 160000, false);
    _addInst('GBP/AUD', 'British Pound vs Australian Dollar', 'forex', 1.9840, 1.9845, 4, AppConstants.contractSizeForex, 0.12, 1.9920, 1.9760, 220000, false);
    _addInst('GBP/CAD', 'British Pound vs Canadian Dollar', 'forex', 1.8140, 1.8145, 4, AppConstants.contractSizeForex, 0.20, 1.8210, 1.8080, 205000, false);
    _addInst('GBP/CHF', 'British Pound vs Swiss Franc', 'forex', 1.1510, 1.1514, 4, AppConstants.contractSizeForex, 0.14, 1.1560, 1.1470, 180000, false);
    _addInst('GBP/NZD', 'British Pound vs New Zealand Dollar', 'forex', 2.2030, 2.2036, 4, AppConstants.contractSizeForex, 0.25, 2.2120, 2.1950, 190000, false);
    _addInst('NZD/CAD', 'New Zealand Dollar vs Canadian Dollar', 'forex', 0.8235, 0.8239, 4, AppConstants.contractSizeForex, -0.06, 0.8280, 0.8190, 140000, false);
    _addInst('NZD/CHF', 'New Zealand Dollar vs Swiss Franc', 'forex', 0.5225, 0.5229, 4, AppConstants.contractSizeForex, 0.10, 0.5260, 0.5195, 130000, false);
    _addInst('NZD/JPY', 'New Zealand Dollar vs Japanese Yen', 'forex', 90.35, 90.39, 2, AppConstants.contractSizeForex, 0.22, 90.85, 89.90, 165000, false);

    // Asian & Global Emerging Currencies
    _addInst('USD/SGD', 'US Dollar vs Singapore Dollar', 'forex', 1.3480, 1.3484, 4, AppConstants.contractSizeForex, -0.05, 1.3520, 1.3440, 195000, false);
    _addInst('USD/HKD', 'US Dollar vs Hong Kong Dollar', 'forex', 7.7820, 7.7825, 4, AppConstants.contractSizeForex, 0.02, 7.7850, 7.7790, 230000, false);
    _addInst('USD/TRY', 'US Dollar vs Turkish Lira', 'forex', 34.25, 34.30, 2, AppConstants.contractSizeForex, 0.85, 34.60, 33.95, 110000, false);
    _addInst('USD/ZAR', 'US Dollar vs South African Rand', 'forex', 18.15, 18.18, 2, AppConstants.contractSizeForex, -0.45, 18.35, 17.98, 145000, false);
    _addInst('USD/MXN', 'US Dollar vs Mexican Peso', 'forex', 19.85, 19.88, 2, AppConstants.contractSizeForex, 0.65, 20.10, 19.65, 170000, false);
    _addInst('USD/SEK', 'US Dollar vs Swedish Krona', 'forex', 10.65, 10.68, 2, AppConstants.contractSizeForex, 0.15, 10.78, 10.55, 125000, false);
    _addInst('USD/NOK', 'US Dollar vs Norwegian Krone', 'forex', 10.95, 10.98, 2, AppConstants.contractSizeForex, -0.10, 11.08, 10.85, 130000, false);
    _addInst('USD/AED', 'US Dollar vs UAE Dirham', 'forex', 3.6725, 3.6730, 4, AppConstants.contractSizeForex, 0.01, 3.6735, 3.6720, 280000, false);
    _addInst('USD/INR', 'US Dollar vs Indian Rupee', 'forex', 84.10, 84.15, 2, AppConstants.contractSizeForex, 0.08, 84.30, 83.95, 210000, false);
    _addInst('USD/PKR', 'US Dollar vs Pakistani Rupee', 'forex', 278.50, 278.80, 2, AppConstants.contractSizeForex, 0.12, 279.20, 277.90, 350000, true);

    // ── 2. METALS ─────────────────────────────────────────────────────────────
    _addInst('XAU/USD', 'Gold vs US Dollar', 'metals', 4479.50, 4479.90, 2, AppConstants.contractSizeGold, 1.45, 4517.76, 4351.92, 184200, true);
    _addInst('XAG/USD', 'Silver vs US Dollar', 'metals', 32.40, 32.43, 2, AppConstants.contractSizeSilver, 2.15, 33.10, 31.80, 120400, true);
    _addInst('XPT/USD', 'Platinum vs US Dollar', 'metals', 985.60, 986.20, 2, AppConstants.contractSizeGold, 0.85, 998.00, 974.50, 48000, false);

    // ── 3. COMMODITIES (ENERGY) ───────────────────────────────────────────────
    _addInst('WTI/USD', 'US Crude Oil Spot (WTI)', 'commodities', 72.85, 72.90, 2, AppConstants.contractSizeCommodity, 1.65, 74.20, 71.50, 215000, true);
    _addInst('BRENT/USD', 'Brent Crude Oil Spot', 'commodities', 76.40, 76.45, 2, AppConstants.contractSizeCommodity, 1.42, 77.80, 75.10, 195000, false);
    _addInst('NGAS/USD', 'Natural Gas Spot', 'commodities', 2.845, 2.852, 3, AppConstants.contractSizeCommodity, -2.10, 2.950, 2.780, 135000, false);

    // ── 4. CRYPTOCURRENCIES ───────────────────────────────────────────────────
    _addInst('BTC/USD', 'Bitcoin vs US Dollar', 'crypto', 96420.00, 96435.00, 2, AppConstants.contractSizeCrypto, 3.82, 98200.00, 94500.00, 54120, true);
    _addInst('ETH/USD', 'Ethereum vs US Dollar', 'crypto', 2745.20, 2745.80, 2, AppConstants.contractSizeCrypto, -0.64, 2810.00, 2690.00, 89450, true);
    _addInst('SOL/USD', 'Solana vs US Dollar', 'crypto', 185.20, 185.35, 2, AppConstants.contractSizeCrypto, 4.25, 192.00, 179.50, 156000, true);
    _addInst('XRP/USD', 'Ripple vs US Dollar', 'crypto', 2.4510, 2.4525, 4, AppConstants.contractSizeCrypto, 5.12, 2.6200, 2.3100, 310000, true);
    _addInst('BNB/USD', 'Binance Coin vs US Dollar', 'crypto', 645.00, 645.50, 2, AppConstants.contractSizeCrypto, 1.85, 660.00, 630.00, 42000, false);
    _addInst('ADA/USD', 'Cardano vs US Dollar', 'crypto', 0.7850, 0.7860, 4, AppConstants.contractSizeCrypto, 2.30, 0.8200, 0.7500, 98000, false);
    _addInst('DOGE/USD', 'Dogecoin vs US Dollar', 'crypto', 0.2640, 0.2645, 4, AppConstants.contractSizeCrypto, 6.45, 0.2850, 0.2450, 280000, false);
    _addInst('AVAX/USD', 'Avalanche vs US Dollar', 'crypto', 34.80, 34.85, 2, AppConstants.contractSizeCrypto, 3.10, 36.20, 33.40, 75000, false);
    _addInst('LINK/USD', 'Chainlink vs US Dollar', 'crypto', 18.50, 18.55, 2, AppConstants.contractSizeCrypto, 2.85, 19.40, 17.80, 62000, false);
    _addInst('DOT/USD', 'Polkadot vs US Dollar', 'crypto', 6.25, 6.28, 2, AppConstants.contractSizeCrypto, 1.95, 6.55, 6.05, 58000, false);
    _addInst('NEAR/USD', 'NEAR Protocol vs US Dollar', 'crypto', 5.40, 5.43, 2, AppConstants.contractSizeCrypto, 4.80, 5.75, 5.10, 84000, false);
    _addInst('LTC/USD', 'Litecoin vs US Dollar', 'crypto', 112.50, 112.70, 2, AppConstants.contractSizeCrypto, 1.20, 116.00, 109.50, 45000, false);

    // ── 5. GLOBAL EQUITY INDICES ───────────────────────────────────────────────
    _addInst('US30/USD', 'Wall Street 30 (Dow Jones)', 'indices', 44250.00, 44255.00, 1, AppConstants.contractSizeIndex, 0.65, 44480.00, 43920.00, 160000, true);
    _addInst('NAS100/USD', 'US Tech 100 (Nasdaq)', 'indices', 21380.00, 21384.00, 1, AppConstants.contractSizeIndex, 1.25, 21550.00, 21100.00, 240000, true);
    _addInst('SPX500/USD', 'US 500 (S&P 500)', 'indices', 6015.00, 6016.50, 1, AppConstants.contractSizeIndex, 0.82, 6045.00, 5970.00, 310000, true);
    _addInst('GER40/EUR', 'Germany 40 (DAX)', 'indices', 20450.00, 20454.00, 1, AppConstants.contractSizeIndex, 0.45, 20580.00, 20310.00, 110000, false);
    _addInst('UK100/GBP', 'UK 100 (FTSE 100)', 'indices', 8420.00, 8423.50, 1, AppConstants.contractSizeIndex, -0.18, 8480.00, 8360.00, 95000, false);
    _addInst('JP225/USD', 'Japan 225 (Nikkei)', 'indices', 38950.00, 38958.00, 1, AppConstants.contractSizeIndex, -0.55, 39400.00, 38650.00, 130000, false);

    // ── 6. GLOBAL STOCKS CFDs ─────────────────────────────────────────────────
    _addInst('AAPL/USD', 'Apple Inc.', 'stocks', 238.40, 238.55, 2, AppConstants.contractSizeStock, 0.95, 241.50, 236.00, 180000, false);
    _addInst('NVDA/USD', 'NVIDIA Corporation', 'stocks', 142.60, 142.75, 2, AppConstants.contractSizeStock, 3.45, 146.20, 138.80, 420000, true);
    _addInst('TSLA/USD', 'Tesla Inc.', 'stocks', 348.50, 348.75, 2, AppConstants.contractSizeStock, 4.10, 356.00, 335.50, 290000, true);
    _addInst('AMZN/USD', 'Amazon.com Inc.', 'stocks', 212.80, 212.95, 2, AppConstants.contractSizeStock, 1.15, 215.40, 209.80, 165000, false);
    _addInst('MSFT/USD', 'Microsoft Corporation', 'stocks', 428.20, 428.40, 2, AppConstants.contractSizeStock, 0.72, 432.00, 424.50, 145000, false);
    _addInst('GOOGL/USD', 'Alphabet Inc. (Google)', 'stocks', 184.50, 184.65, 2, AppConstants.contractSizeStock, 1.30, 187.20, 182.10, 125000, false);

    // 2. Pre-generate realistic Candlesticks matching exact initial prices
    for (final sym in _instruments.keys) {
      _candleHistory[sym] = _generateRealisticCandles(_instruments[sym]!.bid.toDouble());
    }

    // 3. Connect real Binance feed
    _connectRealBinanceFeed();

    // 4. Start live micro-tick engine for continuous institutional market activity
    _startLiveTickSimulation();
  }

  void _addInst(
    String symbol,
    String name,
    String category,
    double bid,
    double ask,
    int decimals,
    Decimal contractSize,
    double change24h,
    double high24h,
    double low24h,
    double volume24h,
    bool isFavorite,
  ) {
    _instruments[symbol] = InstrumentEntity(
      symbol: symbol,
      name: name,
      category: category,
      rawBid: MoneyMath.toDec(bid),
      rawAsk: MoneyMath.toDec(ask),
      spreadMarkupPips: _spreadMarkupMap[symbol] ?? 15,
      decimals: decimals,
      contractSize: contractSize,
      change24h: change24h,
      high24h: MoneyMath.toDec(high24h),
      low24h: MoneyMath.toDec(low24h),
      volume24h: MoneyMath.toDec(volume24h),
      isFavorite: isFavorite,
    );
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

  void _startLiveTickSimulation() {
    _liveTickTimer?.cancel();
    final random = Random();
    _liveTickTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      final symbols = _instruments.keys.toList();
      if (symbols.isEmpty) return;

      // Pick 2-4 random instruments per second to update live
      final count = 2 + random.nextInt(3);
      for (int k = 0; k < count; k++) {
        final sym = symbols[random.nextInt(symbols.length)];
        final inst = _instruments[sym];
        if (inst == null) continue;

        final pipStep = pow(10, -inst.decimals).toDouble();
        final delta = (random.nextDouble() - 0.495) * (pipStep * (inst.category == 'crypto' ? 4 : 2));
        final newBidNum = max(pipStep, inst.bid.toDouble() + delta);
        final spreadAmount = (inst.spreadMarkupPips * pipStep);
        final newAskNum = newBidNum + spreadAmount;

        final newBid = MoneyMath.toDec(newBidNum);
        final newAsk = MoneyMath.toDec(newAskNum);
        final newHigh = MoneyMath.toDec(max(inst.high24h.toDouble(), newAskNum));
        final newLow = MoneyMath.toDec(min(inst.low24h.toDouble(), newBidNum));
        final changeDelta = (random.nextDouble() - 0.5) * 0.02;
        final newChange = double.parse((inst.change24h + changeDelta).clamp(-15.0, 25.0).toStringAsFixed(2));

        final updated = inst.copyWith(
          rawBid: newBid,
          rawAsk: newAsk,
          high24h: newHigh,
          low24h: newLow,
          change24h: newChange,
        );

        _instruments[sym] = updated;
        _tickController.add(updated);

        // Update latest candle close
        final symCandles = _candleHistory[sym];
        if (symCandles != null && symCandles.isNotEmpty) {
          final last = symCandles.last;
          symCandles[symCandles.length - 1] = last.copyWith(
            close: newBidNum,
            high: max(last.high, newBidNum),
            low: min(last.low, newBidNum),
          );
        }
      }
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
    if (list == null ||
        list.isEmpty ||
        list.length > 220 ||
        (list.last.close - curPrice).abs() / curPrice > 0.015 ||
        (list.first.close - list.last.close).abs() / curPrice > 0.05) {
      list = _generateRealisticCandles(curPrice, timeframe, 180);
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
    if (existing == null ||
        existing.isEmpty ||
        existing.length > 220 ||
        (existing.last.close - curPrice).abs() / curPrice > 0.015 ||
        (existing.first.close - existing.last.close).abs() / curPrice > 0.05) {
      existing = _generateRealisticCandles(curPrice, tf, 180);
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
    int count = 180,
  ]) {
    final now = DateTime.now();
    // Deterministic yet asset/timeframe-unique seed for consistent rendering
    final seed = (basePrice * 100).toInt() ^ (timeframe.index * 1337) ^ 0x5A5A;
    final random = Random(seed);

    Duration stepDuration;
    double barVolatility;
    switch (timeframe) {
      case ChartTimeframe.m1:
        stepDuration = const Duration(minutes: 1);
        barVolatility = 0.00045;
        break;
      case ChartTimeframe.m5:
        stepDuration = const Duration(minutes: 5);
        barVolatility = 0.00085;
        break;
      case ChartTimeframe.m15:
        stepDuration = const Duration(minutes: 15);
        barVolatility = 0.0014;
        break;
      case ChartTimeframe.m30:
        stepDuration = const Duration(minutes: 30);
        barVolatility = 0.0020;
        break;
      case ChartTimeframe.h1:
        stepDuration = const Duration(hours: 1);
        barVolatility = 0.0030;
        break;
      case ChartTimeframe.h4:
        stepDuration = const Duration(hours: 4);
        barVolatility = 0.0060;
        break;
      case ChartTimeframe.d1:
        stepDuration = const Duration(days: 1);
        barVolatility = 0.0120;
        break;
    }

    final n = max(60, count);

    // 1. Generate multi-frequency cyclical market swings + Gaussian shock series
    final wave1Freq = 14.0 + (random.nextDouble() * 8.0);
    final wave2Freq = 32.0 + (random.nextDouble() * 16.0);
    final phase1 = random.nextDouble() * 2 * pi;
    final phase2 = random.nextDouble() * 2 * pi;

    final rawPath = List<double>.filled(n, 0.0);
    double accumulated = 0.0;

    for (int i = 0; i < n; i++) {
      final shock = (random.nextDouble() + random.nextDouble() + random.nextDouble() - 1.5) * 1.6;
      final waveDeriv = (cos((i / wave1Freq) * 2 * pi + phase1) * 0.45 +
                         cos((i / wave2Freq) * 2 * pi + phase2) * 0.35) * barVolatility;
      accumulated += (shock * barVolatility) + waveDeriv;
      rawPath[i] = accumulated;
    }

    // 2. Brownian Bridge transformation
    final endDelta = rawPath[n - 1];
    final bridgedPath = List<double>.filled(n, 0.0);
    for (int i = 0; i < n; i++) {
      final t = i / (n - 1);
      bridgedPath[i] = rawPath[i] - (endDelta * t);
    }

    // Convert bridged returns into price path ending exactly at basePrice
    final pricePath = List<double>.filled(n, basePrice);
    for (int i = 0; i < n; i++) {
      pricePath[i] = basePrice * (1.0 + bridgedPath[i]);
    }
    pricePath[n - 1] = basePrice;

    // 3. Build authentic OHLC Candlestick models
    final candles = <CandleStickModel>[];
    for (int i = 0; i < n; i++) {
      final candleTime = now.subtract(stepDuration * (n - 1 - i));
      final open = i == 0
          ? pricePath[0] * (1.0 - (random.nextDouble() - 0.5) * barVolatility * 0.4)
          : candles[i - 1].close;
      final close = pricePath[i];

      final bodyTop = max(open, close);
      final bodyBottom = min(open, close);
      final bodyHeight = bodyTop - bodyBottom;
      final typicalWick = max(basePrice * barVolatility * 0.35, bodyHeight * 0.4);

      final wickRoll = random.nextDouble();
      double upperWick;
      double lowerWick;

      if (wickRoll < 0.08) {
        lowerWick = max(typicalWick * 2.0, bodyHeight * 2.2) * (0.8 + random.nextDouble() * 0.5);
        upperWick = typicalWick * 0.25 * random.nextDouble();
      } else if (wickRoll < 0.16) {
        upperWick = max(typicalWick * 2.0, bodyHeight * 2.2) * (0.8 + random.nextDouble() * 0.5);
        lowerWick = typicalWick * 0.25 * random.nextDouble();
      } else if (wickRoll < 0.24) {
        upperWick = typicalWick * 0.15 * random.nextDouble();
        lowerWick = typicalWick * 0.15 * random.nextDouble();
      } else {
        upperWick = typicalWick * (0.35 + random.nextDouble() * 0.85);
        lowerWick = typicalWick * (0.35 + random.nextDouble() * 0.85);
      }

      final high = bodyTop + upperWick;
      final low = max(0.01, bodyBottom - lowerWick);

      final volume = (300 + (bodyHeight / (basePrice * barVolatility + 1e-6)) * 400 + random.nextDouble() * 500) *
          (i == n - 1 ? 0.75 : 1.0);

      candles.add(CandleStickModel(
        time: candleTime,
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume,
      ));
    }

    return candles;
  }

  void dispose() {
    _liveTickTimer?.cancel();
    _binanceTickSub?.cancel();
    _binanceKlineSub?.cancel();
    _tickController.close();
  }
}
