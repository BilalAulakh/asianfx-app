import 'dart:async';
import 'dart:math';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/feature_flags.dart';
import '../../core/math/money_math.dart';
import '../../domain/entities/trading_entities.dart';
import '../../domain/entities/chart_entities.dart';
import 'binance_market_datasource.dart';
import '../../core/utils/candle_math.dart';
import '../../core/utils/fx_session.dart';

/// Market data for DISPLAY.
///
/// Live mode (default, `kDemoMode == false`):
///   * crypto  - real-time Binance stream;
///   * everything else - the server's own published quotes (`market_quotes`,
///     source='publisher'), i.e. exactly the prices the RPCs will fill at;
///   * dealer markup / spread multiplier / staleness limit come from the
///     `instruments` and `broker_config` tables;
///   * no simulated ticks, no price "gliding", no generated candle history.
///     A symbol with no recent real price is reported by [isStale].
///
/// Demo mode (`--dart-define=ASIANFX_DEMO_MODE=true`) keeps the old synthetic
/// micro-ticks and generated candles, and the app shows a "DEMO PRICES" banner.
class MarketFeedService {
  static final MarketFeedService _instance = MarketFeedService._internal();
  factory MarketFeedService() => _instance;

  final BinanceMarketDataSource _binanceSource = BinanceMarketDataSource.instance;
  final StreamController<InstrumentEntity> _tickController = StreamController<InstrumentEntity>.broadcast();
  Stream<InstrumentEntity> get tickStream => _tickController.stream;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    },
  ));

  StreamSubscription? _binanceTickSub;
  StreamSubscription? _binanceKlineSub;
  Timer? _liveTickTimer;
  Timer? _liveMarketSyncTimer;
  Timer? _serverQuoteTimer;

  /// When the last REAL price for a symbol was observed (source time).
  final Map<String, DateTime> _lastLiveAt = {};

  /// broker_config.quote_max_age_seconds (server default 60).
  int _quoteMaxAgeSeconds = 60;
  int get quoteMaxAgeSeconds => _quoteMaxAgeSeconds;

  /// broker_config.spread_multiplier (global widening applied by the publisher).
  double _spreadMultiplier = 1.0;
  double get spreadMultiplier => _spreadMultiplier;

  DateTime? _lastServerConfigLoad;

  final Map<String, List<CandleStickModel>> _candleHistory = {};
  final Map<String, InstrumentEntity> _instruments = {};
  final Map<String, double> _anchorPrices = {};
  final Map<String, double> _priceVelocity = {};

  static const Map<String, String> _appToYahooSymbol = {
    'XAU/USD': 'GC=F',
    'XAG/USD': 'SI=F',
    'XPT/USD': 'PL=F',
    'WTI/USD': 'CL=F',
    'BRENT/USD': 'BZ=F',
    'NGAS/USD': 'NG=F',
    'US30/USD': '^DJI',
    'NAS100/USD': '^IXIC',
    'SPX500/USD': '^GSPC',
    'GER40/EUR': '^GDAXI',
    'UK100/GBP': '^FTSE',
    'JP225/USD': '^N225',
    'AAPL/USD': 'AAPL',
    'NVDA/USD': 'NVDA',
    'TSLA/USD': 'TSLA',
    'AMZN/USD': 'AMZN',
    'MSFT/USD': 'MSFT',
    'GOOGL/USD': 'GOOGL',
    'EUR/USD': 'EURUSD=X',
    'GBP/USD': 'GBPUSD=X',
    'USD/JPY': 'JPY=X',
    'USD/CHF': 'CHF=X',
    'AUD/USD': 'AUDUSD=X',
    'USD/CAD': 'CAD=X',
    'NZD/USD': 'NZDUSD=X',
    'USD/PKR': 'PKR=X',
    'USD/INR': 'INR=X',
    'USD/TRY': 'TRY=X',
    'USD/SGD': 'SGD=X',
    'USD/AED': 'AED=X',
  };

  /// instruments.commission_per_lot (USD charged once when a trade opens), per
  /// symbol, loaded with the server config. Missing = no commission.
  final Map<String, Decimal> _commissionPerLot = {};

  Decimal commissionPerLot(String symbol) => _commissionPerLot[symbol] ?? Decimal.zero;

  // Dealer markup in points, per symbol. Live mode overwrites these with
  // instruments.spread_markup_points from the database (the same values the
  // publisher uses); the literals below are only the seed / demo defaults and
  // match the instruments seed in 20261001000000_trading_core_schema.sql.
  final Map<String, int> _markupPoints = {
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
    'XAG/USD': 3,
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
    _addInst('EUR/USD', 'Euro vs US Dollar', 'forex', 1.1633, 1.1635, 4, AppConstants.contractSizeForex, 0.18, 1.1690, 1.1585, 450000, true);
    _addInst('GBP/USD', 'British Pound vs US Dollar', 'forex', 1.3549, 1.3552, 4, AppConstants.contractSizeForex, 0.35, 1.3620, 1.3480, 380000, true);
    _addInst('USD/JPY', 'US Dollar vs Japanese Yen', 'forex', 153.59, 153.62, 2, AppConstants.contractSizeForex, -0.22, 154.30, 152.95, 410000, true);
    _addInst('XAU/USD', 'Gold vs US Dollar', 'forex', 4192.04, 4192.44, 2, AppConstants.contractSizeGold, 0.24, 4219.41, 4165.69, 248000, true);
    _addInst('XAG/USD', 'Silver vs US Dollar', 'forex', 63.78, 63.81, 2, AppConstants.contractSizeSilver, -5.19, 67.95, 63.75, 185000, true);
    _addInst('XPT/USD', 'Platinum vs US Dollar', 'forex', 1045.60, 1046.20, 2, AppConstants.contractSizeGold, 0.85, 1060.00, 1032.50, 48000, false);
    _addInst('USD/CHF', 'US Dollar vs Swiss Franc', 'forex', 0.8095, 0.8098, 4, AppConstants.contractSizeForex, 0.12, 0.8140, 0.8050, 220000, false);
    _addInst('AUD/USD', 'Australian Dollar vs US Dollar', 'forex', 0.7221, 0.7224, 4, AppConstants.contractSizeForex, 0.45, 0.7280, 0.7160, 290000, false);
    _addInst('USD/CAD', 'US Dollar vs Canadian Dollar', 'forex', 1.3795, 1.3798, 4, AppConstants.contractSizeForex, -0.15, 1.3850, 1.3740, 260000, false);
    _addInst('NZD/USD', 'New Zealand Dollar vs US Dollar', 'forex', 0.5845, 0.5849, 4, AppConstants.contractSizeForex, 0.28, 0.5890, 0.5790, 180000, false);
    _addInst('EUR/GBP', 'Euro vs British Pound', 'forex', 0.8585, 0.8588, 4, AppConstants.contractSizeForex, -0.11, 0.8620, 0.8540, 210000, false);
    _addInst('EUR/JPY', 'Euro vs Japanese Yen', 'forex', 178.65, 178.69, 2, AppConstants.contractSizeForex, -0.08, 179.40, 177.80, 320000, false);
    _addInst('GBP/JPY', 'British Pound vs Japanese Yen', 'forex', 208.10, 208.15, 2, AppConstants.contractSizeForex, 0.15, 209.20, 207.10, 340000, false);
    _addInst('AUD/CAD', 'Australian Dollar vs Canadian Dollar', 'forex', 0.9960, 0.9964, 4, AppConstants.contractSizeForex, 0.10, 1.0020, 0.9910, 190000, false);
    _addInst('AUD/CHF', 'Australian Dollar vs Swiss Franc', 'forex', 0.5845, 0.5849, 4, AppConstants.contractSizeForex, 0.22, 0.5890, 0.5800, 160000, false);
    _addInst('AUD/JPY', 'Australian Dollar vs Japanese Yen', 'forex', 110.85, 110.89, 2, AppConstants.contractSizeForex, 0.35, 111.40, 110.20, 240000, false);
    _addInst('AUD/NZD', 'Australian Dollar vs New Zealand Dollar', 'forex', 1.2350, 1.2354, 4, AppConstants.contractSizeForex, 0.08, 1.2410, 1.2290, 150000, false);
    _addInst('CAD/CHF', 'Canadian Dollar vs Swiss Franc', 'forex', 0.5865, 0.5869, 4, AppConstants.contractSizeForex, -0.05, 0.5910, 0.5820, 140000, false);
    _addInst('CAD/JPY', 'Canadian Dollar vs Japanese Yen', 'forex', 111.30, 111.34, 2, AppConstants.contractSizeForex, 0.18, 112.00, 110.70, 175000, false);
    _addInst('CHF/JPY', 'Swiss Franc vs Japanese Yen', 'forex', 189.70, 189.74, 2, AppConstants.contractSizeForex, -0.12, 190.50, 188.80, 185000, false);
    _addInst('EUR/AUD', 'Euro vs Australian Dollar', 'forex', 1.6110, 1.6114, 4, AppConstants.contractSizeForex, -0.25, 1.6180, 1.6040, 210000, false);
    _addInst('EUR/CAD', 'Euro vs Canadian Dollar', 'forex', 1.6045, 1.6049, 4, AppConstants.contractSizeForex, 0.05, 1.6120, 1.5980, 195000, false);
    _addInst('EUR/CHF', 'Euro vs Swiss Franc', 'forex', 0.9415, 0.9418, 4, AppConstants.contractSizeForex, 0.04, 0.9460, 0.9370, 170000, false);
    _addInst('EUR/NZD', 'Euro vs New Zealand Dollar', 'forex', 1.9900, 1.9905, 4, AppConstants.contractSizeForex, -0.18, 1.9980, 1.9820, 160000, false);
    _addInst('GBP/AUD', 'British Pound vs Australian Dollar', 'forex', 1.8760, 1.8765, 4, AppConstants.contractSizeForex, 0.12, 1.8840, 1.8680, 220000, false);
    _addInst('GBP/CAD', 'British Pound vs Canadian Dollar', 'forex', 1.8685, 1.8690, 4, AppConstants.contractSizeForex, 0.20, 1.8760, 1.8610, 205000, false);
    _addInst('GBP/CHF', 'British Pound vs Swiss Franc', 'forex', 1.0965, 1.0969, 4, AppConstants.contractSizeForex, 0.14, 1.1020, 1.0910, 180000, false);
    _addInst('GBP/NZD', 'British Pound vs New Zealand Dollar', 'forex', 2.3180, 2.3186, 4, AppConstants.contractSizeForex, 0.25, 2.3270, 2.3090, 190000, false);
    _addInst('NZD/CAD', 'New Zealand Dollar vs Canadian Dollar', 'forex', 0.8060, 0.8064, 4, AppConstants.contractSizeForex, -0.06, 0.8110, 0.8010, 140000, false);
    _addInst('NZD/CHF', 'New Zealand Dollar vs Swiss Franc', 'forex', 0.4730, 0.4734, 4, AppConstants.contractSizeForex, 0.10, 0.4770, 0.4690, 130000, false);
    _addInst('NZD/JPY', 'New Zealand Dollar vs Japanese Yen', 'forex', 89.75, 89.79, 2, AppConstants.contractSizeForex, 0.22, 90.30, 89.20, 165000, false);

    // Asian & Global Emerging Currencies
    _addInst('USD/SGD', 'US Dollar vs Singapore Dollar', 'forex', 1.3280, 1.3284, 4, AppConstants.contractSizeForex, -0.05, 1.3320, 1.3240, 195000, false);
    _addInst('USD/HKD', 'US Dollar vs Hong Kong Dollar', 'forex', 7.7780, 7.7785, 4, AppConstants.contractSizeForex, 0.02, 7.7810, 7.7750, 230000, false);
    _addInst('USD/TRY', 'US Dollar vs Turkish Lira', 'forex', 48.51, 48.56, 2, AppConstants.contractSizeForex, 0.85, 48.90, 48.10, 110000, false);
    _addInst('USD/ZAR', 'US Dollar vs South African Rand', 'forex', 18.25, 18.28, 2, AppConstants.contractSizeForex, -0.45, 18.45, 18.05, 145000, false);
    _addInst('USD/MXN', 'US Dollar vs Mexican Peso', 'forex', 20.35, 20.38, 2, AppConstants.contractSizeForex, 0.65, 20.60, 20.10, 170000, false);
    _addInst('USD/SEK', 'US Dollar vs Swedish Krona', 'forex', 10.45, 10.48, 2, AppConstants.contractSizeForex, 0.15, 10.58, 10.35, 125000, false);
    _addInst('USD/NOK', 'US Dollar vs Norwegian Krone', 'forex', 10.75, 10.78, 2, AppConstants.contractSizeForex, -0.10, 10.88, 10.65, 130000, false);
    _addInst('USD/AED', 'US Dollar vs UAE Dirham', 'forex', 3.6725, 3.6730, 4, AppConstants.contractSizeForex, 0.01, 3.6735, 3.6720, 280000, false);
    _addInst('USD/INR', 'US Dollar vs Indian Rupee', 'forex', 95.12, 95.17, 2, AppConstants.contractSizeForex, 0.08, 95.40, 94.80, 210000, false);
    _addInst('USD/PKR', 'US Dollar vs Pakistani Rupee', 'forex', 277.28, 277.58, 2, AppConstants.contractSizeForex, 0.12, 278.50, 276.80, 350000, true);

    // ── 2. COMMODITIES (ENERGY) ───────────────────────────────────────────────
    _addInst('WTI/USD', 'US Crude Oil Spot (WTI)', 'commodities', 102.00, 102.05, 2, AppConstants.contractSizeCommodity, 5.53, 104.50, 99.80, 315000, true);
    _addInst('BRENT/USD', 'Brent Crude Oil Spot', 'commodities', 106.38, 106.43, 2, AppConstants.contractSizeCommodity, 5.10, 108.80, 104.10, 285000, false);
    _addInst('NGAS/USD', 'Natural Gas Spot', 'commodities', 3.450, 3.458, 3, AppConstants.contractSizeCommodity, -2.10, 3.580, 3.380, 135000, false);

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

    if (kDemoMode) {
      // DEMO ONLY: synthetic candle history + micro-ticks.
      for (final sym in _instruments.keys) {
        final initialCandles = _generateRealisticCandles(
          _instruments[sym]!.bid.toDouble(),
          timeframe: ChartTimeframe.h1,
          count: 180,
          symbol: sym,
        );
        _candleHistory[sym] = initialCandles;
        _candleHistory['${sym}_h1'] = initialCandles;
      }
      _connectRealBinanceFeed();
      _startLiveTickSimulation();
      return;
    }

    // LIVE: real crypto stream + the server's published book. The seed prices
    // above are placeholders only and stay flagged stale until a real price lands.
    _connectRealBinanceFeed();
    refreshServerQuotes();
    _serverQuoteTimer?.cancel();
    // Prices are PUSHED over Supabase Realtime the moment the publisher writes
    // them. This timer (re)connects the subscription after sign-in and polls as
    // a fallback: every 5 s without a live subscription, every 30 s with one.
    _serverQuoteTimer = Timer.periodic(const Duration(seconds: 5), (_) => _serverQuoteHeartbeat());
  }

  // ----------------------------------------------------- live: realtime push ---

  RealtimeChannel? _quotesChannel;
  bool _quotesRealtimeLive = false;
  DateTime? _lastQuotePoll;

  /// Whether published prices currently arrive by push (for tests / diagnostics).
  bool get quotesRealtimeLive => _quotesRealtimeLive;

  void _serverQuoteHeartbeat() {
    final client = _supabase;
    if (client == null) {
      // Signed out: RLS would deliver nothing; drop the channel until sign-in.
      _closeQuotesChannel();
      return;
    }
    if (_quotesChannel == null) _openQuotesChannel(client);

    final now = DateTime.now();
    final pollEvery = _quotesRealtimeLive ? const Duration(seconds: 30) : const Duration(seconds: 5);
    if (_lastQuotePoll == null || now.difference(_lastQuotePoll!) >= pollEvery) {
      _lastQuotePoll = now;
      refreshServerQuotes();
    }
  }

  void _openQuotesChannel(SupabaseClient client) {
    _quotesChannel = client
        .channel('market_quotes_live')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'market_quotes',
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isNotEmpty) applyServerQuote(Map<String, dynamic>.from(row));
          },
        )
        .subscribe((status, [error]) {
          _quotesRealtimeLive = status == RealtimeSubscribeStatus.subscribed;
          if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut) {
            // Retry on the next heartbeat; polling covers the gap.
            _closeQuotesChannel();
          }
        });
  }

  void _closeQuotesChannel() {
    final channel = _quotesChannel;
    _quotesChannel = null;
    _quotesRealtimeLive = false;
    if (channel != null) {
      try {
        Supabase.instance.client.removeChannel(channel);
      } catch (_) {}
    }
  }

  // ----------------------------------------------------- live: server book ----

  /// True when [symbol] has no real price newer than quote_max_age_seconds.
  /// Always false in demo mode (everything there is simulated anyway).
  bool isStale(String symbol, [DateTime? now]) {
    if (kDemoMode) return false;
    final at = _lastLiveAt[symbol];
    if (at == null) return true;
    return (now ?? DateTime.now()).toUtc().difference(at.toUtc()).inSeconds > _quoteMaxAgeSeconds;
  }

  DateTime? lastLiveAt(String symbol) => _lastLiveAt[symbol];

  /// Effective markup the publisher applies: points x global multiplier.
  int _effectiveMarkup(String symbol, [int fallback = 15]) =>
      ((_markupPoints[symbol] ?? fallback) * _spreadMultiplier).round();

  SupabaseClient? get _supabase {
    try {
      final c = Supabase.instance.client;
      return c.auth.currentSession == null ? null : c;
    } catch (_) {
      return null;
    }
  }

  /// Pull dealer config (every 5 minutes) and the published quote book.
  Future<void> refreshServerQuotes({bool forceConfig = false}) async {
    final client = _supabase;
    if (client == null) return;

    try {
      final configDue = _lastServerConfigLoad == null ||
          DateTime.now().difference(_lastServerConfigLoad!) > const Duration(minutes: 5);
      if (forceConfig || configDue) {
        // select('*') so a column not yet deployed (e.g. spread_multiplier before
        // the dealer-controls migration) is just absent instead of failing the
        // whole refresh — applyServerConfig already treats missing keys as defaults.
        final cfg = await client
            .from('broker_config')
            .select('*')
            .eq('id', 1)
            .maybeSingle();
        final markups = await client.from('instruments').select('symbol, spread_markup_points, commission_per_lot');
        applyServerConfig(cfg, [for (final r in markups) Map<String, dynamic>.from(r)]);
        _lastServerConfigLoad = DateTime.now();
      }

      final rows = await client
          .from('market_quotes')
          .select('symbol, bid, ask, source, updated_at')
          .eq('source', 'publisher');
      for (final r in rows) {
        applyServerQuote(Map<String, dynamic>.from(r));
      }
    } catch (e) {
      debugPrint('Server quote refresh failed: $e');
    }
  }

  @visibleForTesting
  void applyServerConfig(Map<String, dynamic>? cfg, List<Map<String, dynamic>> markups) {
    if (cfg != null) {
      final age = cfg['quote_max_age_seconds'];
      if (age is num && age > 0) _quoteMaxAgeSeconds = age.toInt();
      final mult = cfg['spread_multiplier'];
      if (mult != null) _spreadMultiplier = double.tryParse(mult.toString())?.clamp(1.0, 10.0) ?? 1.0;
    }
    for (final m in markups) {
      final sym = m['symbol']?.toString();
      final pts = m['spread_markup_points'];
      if (sym != null && pts is num) _markupPoints[sym] = pts.toInt();
      final comm = m['commission_per_lot'];
      if (sym != null && comm != null) _commissionPerLot[sym] = MoneyMath.toDec(comm);
    }
    // Re-label every instrument with the server's effective markup.
    for (final sym in _instruments.keys.toList()) {
      _instruments[sym] = _instruments[sym]!.copyWith(spreadMarkupPips: _effectiveMarkup(sym));
    }
  }

  /// Display a published quote so that the shown bid/ask equal the server's
  /// exactly (InstrumentEntity re-applies half the markup to each raw side).
  @visibleForTesting
  void applyServerQuote(Map<String, dynamic> row) {
    final sym = row['symbol']?.toString();
    if (sym == null || row['source'] != 'publisher') return;
    final inst = _instruments[sym];
    if (inst == null) return;
    final updatedAt = DateTime.tryParse(row['updated_at']?.toString() ?? '');
    if (updatedAt == null) return;

    // Crypto keeps the real-time Binance stream while that stream is healthy.
    if (inst.category == 'crypto' && !isStale(sym)) return;

    final prev = _lastLiveAt[sym];
    if (prev != null && !updatedAt.isAfter(prev) && inst.category != 'crypto') return;

    final markup = _effectiveMarkup(sym);
    final half = MoneyMath.divide(
        MoneyMath.pointSize(inst.decimals) * Decimal.fromInt(markup), Decimal.fromInt(2),
        scale: inst.decimals + 2);
    final bid = MoneyMath.toDec(row['bid']);
    final ask = MoneyMath.toDec(row['ask']);
    if (bid <= Decimal.zero || ask < bid) return;

    final updated = inst.copyWith(
      rawBid: bid + half,
      rawAsk: ask - half,
      spreadMarkupPips: markup,
      high24h: MoneyMath.toDec(max(inst.high24h.toDouble(), ask.toDouble())),
      low24h: MoneyMath.toDec(min(inst.low24h.toDouble(), bid.toDouble())),
    );
    _instruments[sym] = updated;
    _lastLiveAt[sym] = updatedAt.toUtc();
    _tickController.add(updated);
    _updateLiveCandlesAcrossTimeframes(sym, updated.midPrice.toDouble());
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
      spreadMarkupPips: _markupPoints[symbol] ?? 15,
      decimals: decimals,
      contractSize: contractSize,
      change24h: change24h,
      high24h: MoneyMath.toDec(high24h),
      low24h: MoneyMath.toDec(low24h),
      volume24h: MoneyMath.toDec(volume24h),
      isFavorite: isFavorite,
    );
    _anchorPrices[symbol] = bid;
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

    if (!kDemoMode) return; // live non-crypto prices come from the server book

    // DEMO: approximate quotes from public sources (daily FX rates, delayed
    // Yahoo quotes) smoothed by the simulator. Never used for real money.
    _syncAllLiveMarkets();
    _liveMarketSyncTimer?.cancel();
    _liveMarketSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _syncAllLiveMarkets();
    });
  }

  Future<void> _syncAllLiveMarkets() async {
    // 1. Live Forex Rates from Open Exchange API
    _fetchLiveForexRates();

    // 2. Live Precious Metals, Commodities, Stocks & Indices from Real Global Financial Feed
    const priorityLiveSymbols = [
      'XAU/USD', 'XAG/USD', 'XPT/USD',
      'WTI/USD', 'BRENT/USD', 'NGAS/USD',
      'US30/USD', 'NAS100/USD', 'SPX500/USD', 'GER40/EUR', 'JP225/USD',
      'AAPL/USD', 'NVDA/USD', 'TSLA/USD', 'AMZN/USD', 'MSFT/USD', 'GOOGL/USD',
    ];

    for (final sym in priorityLiveSymbols) {
      final yahooSym = _appToYahooSymbol[sym];
      if (yahooSym != null) {
        _fetchYahooLiveQuote(sym, yahooSym);
      }
    }
  }

  Future<void> _fetchLiveForexRates() async {
    try {
      final res = await _dio.get('https://open.er-api.com/v6/latest/USD');
      if (res.statusCode == 200 && res.data != null && res.data['rates'] != null) {
        final rates = res.data['rates'] as Map<String, dynamic>;

        double? getRate(String code) {
          final val = rates[code];
          if (val is num) return val.toDouble();
          return null;
        }

        final eur = getRate('EUR');
        final gbp = getRate('GBP');
        final jpy = getRate('JPY');
        final chf = getRate('CHF');
        final cad = getRate('CAD');
        final aud = getRate('AUD');
        final nzd = getRate('NZD');
        final pkr = getRate('PKR');
        final inr = getRate('INR');
        final tryRate = getRate('TRY');
        final sgd = getRate('SGD');
        final hkd = getRate('HKD');
        final zar = getRate('ZAR');
        final mxn = getRate('MXN');
        final sek = getRate('SEK');
        final nok = getRate('NOK');
        final aed = getRate('AED');

        void updateFx(String sym, double? price, int decimals) {
          if (price == null || price <= 0) return;
          final inst = _instruments[sym];
          if (inst == null) return;
          final pipStep = pow(10, -decimals).toDouble();
          final markup = _markupPoints[sym] ?? 12;

          _anchorPrices[sym] = price;
          final currentBid = inst.rawBid.toDouble();
          final diff = (price - currentBid).abs();
          final bid = diff < 0.002 ? price : currentBid + ((price - currentBid) * 0.15);
          final ask = bid + (markup * pipStep);

          final high = max(inst.high24h.toDouble(), ask);
          final low = min(inst.low24h.toDouble(), bid);

          final updated = inst.copyWith(
            rawBid: MoneyMath.toDec(bid),
            rawAsk: MoneyMath.toDec(ask),
            high24h: MoneyMath.toDec(high),
            low24h: MoneyMath.toDec(low),
          );
          _instruments[sym] = updated;
          _tickController.add(updated);
        }

        // Direct USD Major & Exotic Pairs
        if (eur != null) updateFx('EUR/USD', 1.0 / eur, 4);
        if (gbp != null) updateFx('GBP/USD', 1.0 / gbp, 4);
        if (aud != null) updateFx('AUD/USD', 1.0 / aud, 4);
        if (nzd != null) updateFx('NZD/USD', 1.0 / nzd, 4);
        if (jpy != null) updateFx('USD/JPY', jpy, 2);
        if (chf != null) updateFx('USD/CHF', chf, 4);
        if (cad != null) updateFx('USD/CAD', cad, 4);
        if (pkr != null) updateFx('USD/PKR', pkr, 2);
        if (inr != null) updateFx('USD/INR', inr, 2);
        if (tryRate != null) updateFx('USD/TRY', tryRate, 2);
        if (sgd != null) updateFx('USD/SGD', sgd, 4);
        if (hkd != null) updateFx('USD/HKD', hkd, 4);
        if (zar != null) updateFx('USD/ZAR', zar, 2);
        if (mxn != null) updateFx('USD/MXN', mxn, 2);
        if (sek != null) updateFx('USD/SEK', sek, 2);
        if (nok != null) updateFx('USD/NOK', nok, 2);
        if (aed != null) updateFx('USD/AED', aed, 4);

        // Cross Currency Pairs
        if (eur != null && gbp != null) updateFx('EUR/GBP', gbp / eur, 4);
        if (eur != null && jpy != null) updateFx('EUR/JPY', jpy / eur, 2);
        if (gbp != null && jpy != null) updateFx('GBP/JPY', jpy / gbp, 2);
        if (aud != null && cad != null) updateFx('AUD/CAD', cad / aud, 4);
        if (aud != null && chf != null) updateFx('AUD/CHF', chf / aud, 4);
        if (aud != null && jpy != null) updateFx('AUD/JPY', jpy / aud, 2);
        if (aud != null && nzd != null) updateFx('AUD/NZD', nzd / aud, 4);
        if (cad != null && chf != null) updateFx('CAD/CHF', chf / cad, 4);
        if (cad != null && jpy != null) updateFx('CAD/JPY', jpy / cad, 2);
        if (chf != null && jpy != null) updateFx('CHF/JPY', jpy / chf, 2);
        if (eur != null && aud != null) updateFx('EUR/AUD', aud / eur, 4);
        if (eur != null && cad != null) updateFx('EUR/CAD', cad / eur, 4);
        if (eur != null && chf != null) updateFx('EUR/CHF', chf / eur, 4);
        if (eur != null && nzd != null) updateFx('EUR/NZD', nzd / eur, 4);
        if (gbp != null && aud != null) updateFx('GBP/AUD', aud / gbp, 4);
        if (gbp != null && cad != null) updateFx('GBP/CAD', cad / gbp, 4);
        if (gbp != null && chf != null) updateFx('GBP/CHF', chf / gbp, 4);
        if (gbp != null && nzd != null) updateFx('GBP/NZD', nzd / gbp, 4);
        if (nzd != null && cad != null) updateFx('NZD/CAD', cad / nzd, 4);
        if (nzd != null && chf != null) updateFx('NZD/CHF', chf / nzd, 4);
        if (nzd != null && jpy != null) updateFx('NZD/JPY', jpy / nzd, 2);
      }
    } catch (_) {}
  }

  Future<void> _fetchYahooLiveQuote(String appSymbol, String yahooSymbol) async {
    try {
      final res = await _dio.get('https://query1.finance.yahoo.com/v8/finance/chart/$yahooSymbol?interval=1m&range=1d');
      if (res.statusCode == 200 && res.data != null) {
        final chart = res.data['chart'];
        final result = chart?['result'] as List?;
        if (result != null && result.isNotEmpty) {
          final meta = result[0]['meta'] as Map<String, dynamic>?;
          if (meta != null) {
            final priceNum = meta['regularMarketPrice'] ?? meta['chartPreviousClose'];
            if (priceNum is num && priceNum > 0) {
              final inst = _instruments[appSymbol];
              if (inst == null) return;

              final curPrice = priceNum.toDouble();
              final prevClose = (meta['previousClose'] ?? meta['chartPreviousClose'] ?? curPrice) as num;
              final high24 = (meta['regularMarketDayHigh'] ?? curPrice) as num;
              final low24 = (meta['regularMarketDayLow'] ?? curPrice) as num;
              final change24h = prevClose > 0 ? ((curPrice - prevClose) / prevClose) * 100 : 0.0;

              _anchorPrices[appSymbol] = curPrice;

              final pipStep = pow(10, -inst.decimals).toDouble();
              final markup = _markupPoints[appSymbol] ?? 10;
              final currentBid = inst.rawBid.toDouble();
              final diff = (curPrice - currentBid).abs();

              // Smoothly glide towards anchor without shock
              final targetBid = diff < (curPrice * 0.005)
                  ? curPrice
                  : currentBid + ((curPrice - currentBid) * 0.15);
              final targetAsk = targetBid + (markup * pipStep);

              final updated = inst.copyWith(
                rawBid: MoneyMath.toDec(targetBid),
                rawAsk: MoneyMath.toDec(targetAsk),
                high24h: MoneyMath.toDec(high24.toDouble()),
                low24h: MoneyMath.toDec(low24.toDouble()),
                change24h: double.parse(change24h.toStringAsFixed(2)),
              );

              _instruments[appSymbol] = updated;
              _tickController.add(updated);

              _updateLiveCandlesAcrossTimeframes(appSymbol, updated.midPrice.toDouble());
            }
          }
        }
      }
    } catch (_) {}
  }

  // Candle buckets follow the FX session clock (rollover 17:00 New York), same as
  // OANDA/TradingView, so the chart countdown and new-candle boundaries agree.
  DateTime _getCandlePeriodStart(DateTime time, ChartTimeframe tf) =>
      FxSession.periodStart(time, tf);

  void _updateLiveCandlesAcrossTimeframes(String symbol, double price) {
    final now = DateTime.now();
    for (final tf in ChartTimeframe.values) {
      final key = '${symbol}_${tf.name}';
      final candles = _candleHistory[key];
      if (candles != null && candles.isNotEmpty) {
        final last = candles.last;
        final currentPeriod = _getCandlePeriodStart(now, tf);
        final lastPeriod = _getCandlePeriodStart(last.time, tf);

        if (currentPeriod.isAfter(lastPeriod)) {
          // Exness: Period boundary reached, start new candle!
          candles.add(CandleStickModel(
            time: currentPeriod,
            open: last.close,
            high: max(last.close, price),
            low: min(last.close, price),
            close: price,
            volume: 1.0,
          ));
          if (candles.length > maxCandlesInMemory) {
            candles.removeAt(0);
          }
        } else {
          // Exness: Dynamically stretch candle body and extend wicks live with price
          candles[candles.length - 1] = last.copyWith(
            close: price,
            high: max(last.high, price),
            low: min(last.low, price),
            volume: last.volume + 1.0,
          );
        }
      }
    }
    final symCandles = _candleHistory[symbol];
    if (symCandles != null && symCandles.isNotEmpty) {
      final last = symCandles.last;
      final currentPeriod = _getCandlePeriodStart(now, ChartTimeframe.h1);
      final lastPeriod = _getCandlePeriodStart(last.time, ChartTimeframe.h1);

      if (currentPeriod.isAfter(lastPeriod)) {
        symCandles.add(CandleStickModel(
          time: currentPeriod,
          open: last.close,
          high: max(last.close, price),
          low: min(last.close, price),
          close: price,
          volume: 1.0,
        ));
        if (symCandles.length > maxCandlesInMemory) {
          symCandles.removeAt(0);
        }
      } else {
        symCandles[symCandles.length - 1] = last.copyWith(
          close: price,
          high: max(last.high, price),
          low: min(last.low, price),
          volume: last.volume + 1.0,
        );
      }
    }
  }

  /// DEMO ONLY. Synthetic micro-ticks; never started in live mode.
  void _startLiveTickSimulation() {
    if (!kDemoMode) return;
    _liveTickTimer?.cancel();
    final random = Random();
    // Calm, steady institutional market cadence (every 4000ms = 4.0 seconds)
    _liveTickTimer = Timer.periodic(const Duration(milliseconds: 4000), (_) {
      final symbols = _instruments.keys.toList();
      if (symbols.isEmpty) return;

      // Ensure Gold (XAU/USD) ticks with calm, authentic market motion
      final targetSymbols = <String>{'XAU/USD'};

      // Add 1 priority pair per cycle (Forex or Crypto)
      const extraPriority = ['EUR/USD', 'GBP/USD', 'BTC/USD', 'USD/JPY', 'XAG/USD', 'ETH/USD'];
      targetSymbols.add(extraPriority[random.nextInt(extraPriority.length)]);

      // Add 1 random asset across all markets
      targetSymbols.add(symbols[random.nextInt(symbols.length)]);

      for (final sym in targetSymbols) {
        final inst = _instruments[sym];
        if (inst == null) continue;

        final pipStep = pow(10, -inst.decimals).toDouble();
        
        // Micro-movements: Very gentle and authentic price steps (sub-cent precision)
        double stepMagnitude;
        if (sym.contains('XAU')) {
          stepMagnitude = 0.005 + (random.nextDouble() * 0.010); // 0.5 to 1.5 cents max (ultra-calm!)
        } else if (sym.contains('XAG')) {
          stepMagnitude = 0.001 + (random.nextDouble() * 0.002);
        } else if (inst.category == 'crypto') {
          stepMagnitude = sym.contains('BTC') ? (0.5 + random.nextDouble() * 1.0) : (pipStep * 0.5);
        } else {
          stepMagnitude = pipStep * (0.15 + random.nextDouble() * 0.25); // 0.15 to 0.4 pip
        }

        final rawNoise = (random.nextDouble() - 0.5) * 2.0 * stepMagnitude;
        
        // Momentum persistence: 80% previous direction, 20% new noise (smooth wave, no ping-pong jitter!)
        final prevVel = _priceVelocity[sym] ?? 0.0;
        final smoothedDelta = (prevVel * 0.80) + (rawNoise * 0.20);
        _priceVelocity[sym] = smoothedDelta;

        // Stable mean reversion pull to keep price centered around real market anchor
        final anchor = _anchorPrices[sym] ?? inst.rawBid.toDouble();
        final drift = inst.rawBid.toDouble() - anchor;
        final pullFactor = (drift.abs() > anchor * 0.001) ? 0.35 : 0.12;
        final pull = -drift * pullFactor;
        final delta = smoothedDelta + pull;
        
        // Preserve raw liquidity spread so spread markup does not compound
        final baseSpread = (inst.rawAsk - inst.rawBid).toDouble();
        final rawSpread = baseSpread > 0 ? baseSpread : (pipStep * 2);
        final newRawBidNum = max(pipStep, inst.rawBid.toDouble() + delta);
        final newRawAskNum = newRawBidNum + rawSpread;

        final newBid = MoneyMath.toDec(newRawBidNum);
        final newAsk = MoneyMath.toDec(newRawAskNum);
        final newHigh = MoneyMath.toDec(max(inst.high24h.toDouble(), newRawAskNum));
        final newLow = MoneyMath.toDec(min(inst.low24h.toDouble(), newRawBidNum));
        final changeDelta = (random.nextDouble() - 0.5) * 0.002;
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

        // Update latest candle smoothly
        _updateLiveCandlesAcrossTimeframes(sym, updated.midPrice.toDouble());
      }
    });
  }

  void _applyIncomingQuote(InstrumentEntity quote) {
    final symbol = quote.symbol;
    final markup = _effectiveMarkup(symbol);
    _lastLiveAt[symbol] = DateTime.now().toUtc();
    final mid = quote.midPrice.toDouble();

    final updated = quote.copyWith(
      spreadMarkupPips: markup,
      name: _instruments[symbol]?.name ?? quote.name,
      category: _instruments[symbol]?.category ?? quote.category,
      contractSize: _instruments[symbol]?.contractSize ?? quote.contractSize,
      isFavorite: _instruments[symbol]?.isFavorite ?? false,
    );

    _instruments[symbol] = updated;
    _anchorPrices[symbol] = mid;
    _tickController.add(updated);

    // Dynamically update latest candle across all cached timeframes for this symbol
    _updateLiveCandlesAcrossTimeframes(symbol, mid);
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
        if (candles.length > maxCandlesInMemory) {
          candles.removeAt(0);
        }
      }
    }
  }

  /// Mirror a markup the SERVER has accepted (rpc_admin_set_markup).
  void updateSpreadMarkup(String symbol, int markupPoints) {
    _markupPoints[symbol] = markupPoints;
    final current = _instruments[symbol];
    if (current != null) {
      _instruments[symbol] = current.copyWith(spreadMarkupPips: _effectiveMarkup(symbol));
      _tickController.add(_instruments[symbol]!);
    }
  }

  /// Mirror a spread multiplier the server has accepted.
  void updateSpreadMultiplier(double multiplier) {
    _spreadMultiplier = multiplier.clamp(1.0, 10.0);
    for (final sym in _instruments.keys.toList()) {
      _instruments[sym] = _instruments[sym]!.copyWith(spreadMarkupPips: _effectiveMarkup(sym));
    }
  }

  /// Configured (un-multiplied) markup points for [symbol].
  int getSpreadMarkup(String symbol) => _markupPoints[symbol] ?? 10;

  List<InstrumentEntity> getAllInstruments() => _instruments.values.toList();

  InstrumentEntity? getInstrument(String symbol) => _instruments[symbol];

  /// USD value of one unit of [currencyCode], resolved from the live book.
  ///
  /// Needed because margin and PnL are first computed in the instrument's quote
  /// currency. Without this conversion a 1-lot USD/JPY trade reported its PnL
  /// and margin in yen while the account is denominated in USD.
  Decimal usdPerCurrency(String currencyCode) {
    final code = currencyCode.toUpperCase();
    if (code.isEmpty || code == 'USD') return Decimal.one;

    final direct = _instruments['$code/USD'];
    if (direct != null && direct.midPrice > Decimal.zero) return direct.midPrice;

    final inverse = _instruments['USD/$code'];
    if (inverse != null && inverse.midPrice > Decimal.zero) {
      return MoneyMath.divide(Decimal.one, inverse.midPrice);
    }

    // Unknown quote currency: fall back to 1:1 rather than zeroing the position.
    return Decimal.one;
  }

  /// USD per 1 unit of [symbol]'s quote currency (1 for every `XXX/USD` pair).
  Decimal quoteToUsdRate(String symbol) {
    final inst = _instruments[symbol];
    final quote = inst?.quoteCode ??
        (symbol.contains('/') ? symbol.split('/').last.toUpperCase() : 'USD');
    return usdPerCurrency(quote);
  }

  /// Convenience overload for a quote object that may not be in the cache yet.
  Decimal quoteToUsdRateFor(InstrumentEntity instrument) =>
      usdPerCurrency(instrument.quoteCode);

  /// Emit a custom or simulated tick into the live market feed stream (useful for tests & simulation)
  void emitTick(InstrumentEntity instrument) {
    _instruments[instrument.symbol] = instrument;
    _tickController.add(instrument);
    _updateLiveCandlesAcrossTimeframes(instrument.symbol, instrument.midPrice.toDouble());
  }

  int getHistoryCountForTimeframe(ChartTimeframe tf) {
    switch (tf) {
      case ChartTimeframe.d1:
        return 1095; // 3 full years of daily history (2023-2026)
      case ChartTimeframe.h4:
        return 1200; // ~7 months of 4-hour candles
      case ChartTimeframe.h1:
        return 1440; // 2 full months of 1-hour candles
      case ChartTimeframe.m30:
        return 960; // 20 days of 30-min candles
      case ChartTimeframe.m15:
        return 960; // 10 days of 15-min candles
      case ChartTimeframe.m5:
        return 864; // 3 days of 5-min candles
      case ChartTimeframe.m1:
        return 720; // 12 hours of 1-min candles
    }
  }

  List<CandleStickModel> getCandles(String symbol, [ChartTimeframe timeframe = ChartTimeframe.h1]) {
    final key = '${symbol}_${timeframe.name}';
    final inst = _instruments[symbol];
    final curPrice = inst != null ? inst.midPrice.toDouble() : 4480.0;
    final requiredCount = getHistoryCountForTimeframe(timeframe);

    final list = _candleHistory[key];
    if ((list == null || list.isEmpty) && !kDemoMode) {
      return const []; // live: real history arrives via fetchCandlesAsync
    }
    if (list == null || list.isEmpty) {
      final generated = _generateRealisticCandles(
        curPrice,
        timeframe: timeframe,
        count: requiredCount,
        symbol: symbol,
      );
      _candleHistory[key] = generated;
      _candleHistory[symbol] = generated;
      return generated;
    } else {
      // Anchoring the latest candle to current mid price ensures the chart connects seamlessly to live ticker
      final last = list.last;
      list[list.length - 1] = last.copyWith(
        close: curPrice,
        high: max(last.high, curPrice),
        low: min(last.low, curPrice),
      );
      return list;
    }
  }

  /// Candles kept per chart (paged history included): years of daily bars.
  static const int maxCandlesInMemory = 20000;

  /// Price shift applied to proxy history (PAXG) per chart, reused for older pages.
  final Map<String, double> _metalBasis = {};

  /// Charts whose source has no older history left to page in.
  final Set<String> _historyExhausted = {};

  static bool _isSpotMetal(String sym) => sym == 'XAU/USD' || sym == 'XAG/USD' || sym == 'XPT/USD';

  /// Proxy history (PAXG token / COMEX futures) -> spot chart: drop candles from
  /// closed sessions (weekends) and shift the series so its last close equals the
  /// live published spot mid, removing the proxy's premium / futures basis.
  /// Without a live price yet, the series is only filtered.
  @visibleForTesting
  List<CandleStickModel> alignMetalHistory(String sym, List<CandleStickModel> raw, ChartTimeframe tf) =>
      _alignMetalHistory(sym, raw, tf);

  List<CandleStickModel> _alignMetalHistory(String sym, List<CandleStickModel> raw, ChartTimeframe tf) {
    final half = Duration(seconds: tf.duration.inSeconds ~/ 2);
    final open = raw.where((c) => FxSession.isMarketOpen(c.time.add(half))).toList();
    if (open.isEmpty) return raw;

    final inst = _instruments[sym];
    final key = '${sym}_${tf.name}';
    if (inst == null || _lastLiveAt[sym] == null) {
      _metalBasis[key] = 0;
      return open;
    }
    final basis = inst.midPrice.toDouble() - open.last.close;
    _metalBasis[key] = basis;
    if (basis == 0) return open;
    return [
      for (final c in open)
        c.copyWith(open: c.open + basis, high: c.high + basis, low: c.low + basis, close: c.close + basis),
    ];
  }

  /// Intraday charts of spot metals use the broker's own minute candles
  /// (built server-side from the published execution prices, every 3 s).
  static bool _usesOwnCandles(String sym, ChartTimeframe tf) =>
      !kDemoMode && _isSpotMetal(sym) && tf.duration <= const Duration(minutes: 30);

  /// The broker's 1-minute candles for [sym], folded into [tf]. Empty when
  /// signed out, offline, or before the price-candles migration is applied.
  Future<List<CandleStickModel>> _ownCandles(String sym, ChartTimeframe tf) async {
    final client = _supabase;
    if (client == null) return const [];
    try {
      final minutes = min(3000, tf.duration.inMinutes * getHistoryCountForTimeframe(tf));
      final rows = await client.rpc('rpc_get_price_candles', params: {'p_symbol': sym, 'p_limit': minutes});
      return CandleMath.aggregate(CandleMath.fromServerRows(rows), tf);
    } catch (e) {
      debugPrint('Own candles unavailable for $sym: $e');
      return const [];
    }
  }

  /// [proxy] history with the broker's own candles laid over its recent part.
  Future<List<CandleStickModel>> _withOwnCandles(
      String sym, ChartTimeframe tf, List<CandleStickModel> proxy) async {
    if (!_usesOwnCandles(sym, tf)) return proxy;
    return CandleMath.merge(proxy, await _ownCandles(sym, tf));
  }

  Future<List<CandleStickModel>> fetchCandlesAsync([String? symbol, ChartTimeframe? timeframe]) async {
    final sym = symbol ?? 'XAU/USD';
    final tf = timeframe ?? ChartTimeframe.h1;
    final key = '${sym}_${tf.name}';

    final inst = _instruments[sym];
    final curPrice = inst != null ? inst.midPrice.toDouble() : 4480.0;
    final requiredCount = getHistoryCountForTimeframe(tf);
    _historyExhausted.remove(key);
    _metalBasis.remove(key);

    // 1. Crypto: real Binance history.
    if (inst?.category == 'crypto') {
      final binanceCandles = await _binanceSource.fetchKlines(sym, tf, limit: 1000);
      if (binanceCandles.isNotEmpty && binanceCandles.length >= 60) {
        _candleHistory[key] = binanceCandles;
        _candleHistory[sym] = binanceCandles;
        return binanceCandles;
      }
    }

    // 1b. Gold: PAX Gold klines give a real-time, minute-level history shape
    //     (Yahoo only has COMEX futures, delayed ~10 min). PAXG trades at its own
    //     premium and through the weekend, so the series is re-based onto the
    //     live spot price and closed-market candles are dropped.
    if (sym == 'XAU/USD') {
      final paxg = await _binanceSource.fetchKlines('PAXG/USD', tf, limit: 1000);
      if (paxg.length >= 60) {
        final candles = await _withOwnCandles(sym, tf, _alignMetalHistory(sym, paxg, tf));
        _candleHistory[key] = candles;
        _candleHistory[sym] = candles;
        return candles;
      }
    }

    // 2. Fetch from real Yahoo Finance source for Metals, Commodities, Forex, Stocks, Indices
    final yahooSym = _appToYahooSymbol[sym];
    if (yahooSym != null) {
      final yahooCandles = await _fetchYahooCandles(sym, yahooSym, tf);
      if (yahooCandles.isNotEmpty && yahooCandles.length >= 20) {
        // DEMO ONLY: rescale history onto the simulated price. Live mode shows
        // the real series untouched.
        final lastClose = yahooCandles.last.close;
        if (kDemoMode && lastClose > 0 && curPrice > 0 && (lastClose - curPrice).abs() / curPrice > 0.01) {
          final scale = curPrice / lastClose;
          for (int i = 0; i < yahooCandles.length; i++) {
            final c = yahooCandles[i];
            yahooCandles[i] = c.copyWith(
              open: c.open * scale,
              high: c.high * scale,
              low: c.low * scale,
              close: c.close * scale,
            );
          }
        }
        // Silver / platinum history is COMEX futures: re-base onto live spot.
        final series = _isSpotMetal(sym) && !kDemoMode
            ? await _withOwnCandles(sym, tf, _alignMetalHistory(sym, yahooCandles, tf))
            : yahooCandles;
        _candleHistory[key] = series;
        _candleHistory[sym] = series;
        return series;
      }
    }

    // 3. No proxy history: the broker's own candles alone, if any.
    if (_usesOwnCandles(sym, tf)) {
      final own = await _ownCandles(sym, tf);
      if (own.isNotEmpty) {
        _candleHistory[key] = own;
        _candleHistory[sym] = own;
        return own;
      }
    }

    // 4. No real history available.
    final existing = _candleHistory[key];
    if (!kDemoMode) return existing ?? const [];
    // DEMO ONLY: deterministic synthetic series.
    if (existing == null || existing.isEmpty) {
      final fallback = _generateRealisticCandles(
        curPrice,
        timeframe: tf,
        count: requiredCount,
        symbol: sym,
      );
      _candleHistory[key] = fallback;
      _candleHistory[sym] = fallback;
      return fallback;
    }
    return existing;
  }

  /// Older candles that end before [before], prepended to the cached series
  /// (chart paging when the user scrolls back). Binance-backed charts (crypto,
  /// gold via PAXG) page 1000 candles at a time back to the listing date; Yahoo
  /// series are loaded in full up front, so they have nothing more to page.
  /// Returns an empty list when nothing older exists or the request failed.
  Future<List<CandleStickModel>> fetchOlderCandles(String sym, ChartTimeframe tf, DateTime before) async {
    final key = '${sym}_${tf.name}';
    if (_historyExhausted.contains(key)) return const [];

    final String source;
    if (_instruments[sym]?.category == 'crypto') {
      source = sym;
    } else if (sym == 'XAU/USD' && _metalBasis.containsKey(key)) {
      source = 'PAXG/USD';
    } else {
      _historyExhausted.add(key);
      return const [];
    }

    const pageSize = 1000;
    final raw = await _binanceSource.fetchKlinesBefore(source, tf, before, limit: pageSize);
    if (raw == null) return const []; // network error: try again on the next scroll
    if (raw.length < pageSize ~/ 2) _historyExhausted.add(key);

    var page = raw;
    if (source == 'PAXG/USD') {
      final half = Duration(seconds: tf.duration.inSeconds ~/ 2);
      final basis = _metalBasis[key] ?? 0;
      page = [
        for (final c in raw)
          if (FxSession.isMarketOpen(c.time.add(half)))
            c.copyWith(open: c.open + basis, high: c.high + basis, low: c.low + basis, close: c.close + basis),
      ];
    }
    if (page.isEmpty) return const [];

    final existing = _candleHistory[key];
    if (existing != null && existing.isNotEmpty) {
      final merged = [...page.where((c) => c.time.isBefore(existing.first.time)), ...existing];
      _candleHistory[key] = merged.length > maxCandlesInMemory
          ? merged.sublist(merged.length - maxCandlesInMemory)
          : merged;
    }
    return page;
  }

  Future<List<CandleStickModel>> _fetchYahooCandles(String symbol, String yahooSymbol, ChartTimeframe timeframe) async {
    try {
      String interval;
      String range;
      switch (timeframe) {
        // The longest range Yahoo serves for each interval (intraday data is
        // capped: 7 days of 1m, 60 days of 5m-30m, 730 days of 1h).
        case ChartTimeframe.m1:
          interval = '1m';
          range = '7d';
          break;
        case ChartTimeframe.m5:
          interval = '5m';
          range = '60d';
          break;
        case ChartTimeframe.m15:
          interval = '15m';
          range = '60d';
          break;
        case ChartTimeframe.m30:
          interval = '30m';
          range = '60d';
          break;
        case ChartTimeframe.h1:
          interval = '1h';
          range = '730d';
          break;
        case ChartTimeframe.h4:
          interval = '1h'; // Yahoo has no 4h: folded into 4h candles below
          range = '730d';
          break;
        case ChartTimeframe.d1:
          interval = '1d';
          range = '10y';
          break;
      }

      final res = await _dio.get('https://query1.finance.yahoo.com/v8/finance/chart/$yahooSymbol?interval=$interval&range=$range');
      if (res.statusCode == 200 && res.data != null) {
        final result = res.data['chart']?['result'] as List?;
        if (result != null && result.isNotEmpty) {
          final timestamps = result[0]['timestamp'] as List?;
          final quote = result[0]['indicators']?['quote']?[0] as Map<String, dynamic>?;

          if (timestamps != null && quote != null) {
            final opens = quote['open'] as List?;
            final highs = quote['high'] as List?;
            final lows = quote['low'] as List?;
            final closes = quote['close'] as List?;
            final volumes = quote['volume'] as List?;

            final List<CandleStickModel> list = [];
            for (int i = 0; i < timestamps.length; i++) {
              final o = opens != null && i < opens.length ? opens[i] : null;
              final h = highs != null && i < highs.length ? highs[i] : null;
              final l = lows != null && i < lows.length ? lows[i] : null;
              final c = closes != null && i < closes.length ? closes[i] : null;
              final v = volumes != null && i < volumes.length ? volumes[i] : null;

              if (o is num && h is num && l is num && c is num) {
                list.add(CandleStickModel(
                  time: DateTime.fromMillisecondsSinceEpoch((timestamps[i] as int) * 1000),
                  open: o.toDouble(),
                  high: h.toDouble(),
                  low: l.toDouble(),
                  close: c.toDouble(),
                  volume: (v is num) ? v.toDouble() : 1000.0,
                ));
              }
            }

            if (list.isNotEmpty) {
              return timeframe == ChartTimeframe.h4 ? CandleMath.aggregate(list, timeframe) : list;
            }
          }
        }
      }
    } catch (_) {}
    return [];
  }


  List<CandleStickModel> _generateRealisticCandles(
    double basePrice, {
    ChartTimeframe timeframe = ChartTimeframe.h1,
    int count = 180,
    String? symbol,
  }) {
    final now = DateTime.now();
    // Deterministic asset and timeframe seed: never jumps or inverts on price ticks
    final symbolHash = (symbol ?? 'ASSET').hashCode.abs() % 100000;
    final seed = symbolHash ^ (timeframe.index * 1337) ^ 0x5A5A;
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
    final macroFreq = max(60.0, n / 7.0);
    final macroPhase = random.nextDouble() * 2 * pi;
    final wave1Freq = 14.0 + (random.nextDouble() * 8.0);
    final wave2Freq = 32.0 + (random.nextDouble() * 16.0);
    final phase1 = random.nextDouble() * 2 * pi;
    final phase2 = random.nextDouble() * 2 * pi;

    final rawPath = List<double>.filled(n, 0.0);
    double accumulated = 0.0;

    for (int i = 0; i < n; i++) {
      final shock = (random.nextDouble() + random.nextDouble() + random.nextDouble() - 1.5) * 1.6;
      final macroWave = sin((i / macroFreq) * 2 * pi + macroPhase) * 0.40 * barVolatility;
      final waveDeriv = (cos((i / wave1Freq) * 2 * pi + phase1) * 0.35 +
                         cos((i / wave2Freq) * 2 * pi + phase2) * 0.25) * barVolatility;
      accumulated += (shock * barVolatility) + macroWave + waveDeriv;
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
    _liveMarketSyncTimer?.cancel();
    _serverQuoteTimer?.cancel();
    _closeQuotesChannel();
    _binanceTickSub?.cancel();
    _binanceKlineSub?.cancel();
    _tickController.close();
  }
}
