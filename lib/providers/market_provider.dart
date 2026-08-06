import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/datasources/mock_market_datasource.dart';
import '../domain/entities/trading_entities.dart';

// ── Instruments List Provider ─────────────────────────────────────────────────
final instrumentsProvider = StateNotifierProvider<InstrumentsNotifier, List<InstrumentEntity>>((ref) {
  return InstrumentsNotifier();
});

class InstrumentsNotifier extends StateNotifier<List<InstrumentEntity>> {
  InstrumentsNotifier() : super([]) {
    _init();
  }

  final _dataSource = MockMarketDataSource.instance;

  void _init() {
    state = _dataSource.getInitialInstruments();
    // Subscribe to live updates for all instruments
    for (final inst in state) {
      _dataSource.streamPrice(inst.symbol).listen((updated) {
        state = [
          for (final i in state)
            if (i.symbol == updated.symbol) updated else i,
        ];
      });
    }
  }

  void toggleFavorite(String symbol) {
    state = [
      for (final i in state)
        if (i.symbol == symbol) i.copyWith(isFavorite: !i.isFavorite) else i,
    ];
  }

  List<InstrumentEntity> byCategory(String category) =>
      state.where((i) => i.category == category).toList();

  List<InstrumentEntity> get favorites =>
      state.where((i) => i.isFavorite).toList();

  List<InstrumentEntity> search(String query) => state
      .where((i) =>
          i.symbol.toLowerCase().contains(query.toLowerCase()) ||
          i.name.toLowerCase().contains(query.toLowerCase()))
      .toList();
}

// ── Selected Instrument Provider ──────────────────────────────────────────────
final selectedInstrumentProvider = StateProvider<InstrumentEntity?>((ref) => null);

// ── OHLC Data Provider ────────────────────────────────────────────────────────
final selectedTimeframeProvider = StateProvider<String>((ref) => '1h');

final ohlcProvider = Provider.family<List<OhlcCandle>, String>((ref, symbol) {
  final tf = ref.watch(selectedTimeframeProvider);
  return MockMarketDataSource.instance.getOhlcData(symbol, tf);
});

// ── Live Price Stream Provider ────────────────────────────────────────────────
final priceStreamProvider = StreamProvider.family<InstrumentEntity, String>((ref, symbol) {
  return MockMarketDataSource.instance.streamPrice(symbol);
});

// ── Wallet Provider ───────────────────────────────────────────────────────────
final walletProvider = StateNotifierProvider<WalletNotifier, WalletEntity>((ref) {
  return WalletNotifier();
});

class WalletNotifier extends StateNotifier<WalletEntity> {
  WalletNotifier() : super(const WalletEntity(
    id: 'w_001',
    userId: 'usr_001',
    currency: 'USD',
    type: 'fiat',
    balance: 10000.00,
    equity: 10245.50,
    margin: 500.00,
    freeMargin: 9745.50,
    marginLevel: 2049.1,
    floatingPl: 245.50,
  ));

  void updateFloatingPl(double pl) {
    state = WalletEntity(
      id: state.id,
      userId: state.userId,
      currency: state.currency,
      type: state.type,
      balance: state.balance,
      equity: state.balance + pl,
      margin: state.margin,
      freeMargin: state.balance + pl - state.margin,
      marginLevel: state.margin > 0 ? ((state.balance + pl) / state.margin) * 100 : 0,
      floatingPl: pl,
    );
  }
}

// ── Trading Provider ──────────────────────────────────────────────────────────
final openTradesProvider = StateNotifierProvider<TradesNotifier, List<TradeEntity>>((ref) {
  return TradesNotifier();
});

class TradesNotifier extends StateNotifier<List<TradeEntity>> {
  TradesNotifier() : super(_mockTrades);

  static final _mockTrades = [
    TradeEntity(
      id: 'tr_001',
      symbol: 'EURUSD',
      side: OrderSide.buy,
      type: OrderType.market,
      status: OrderStatus.open,
      lotSize: 0.10,
      openPrice: 1.08421,
      stopLoss: 1.07800,
      takeProfit: 1.09200,
      currentPrice: 1.08532,
      floatingPl: 11.10,
      commission: 0.70,
      swap: -0.35,
      leverage: 100,
      openTime: DateTime.now().subtract(const Duration(hours: 2, minutes: 15)),
    ),
    TradeEntity(
      id: 'tr_002',
      symbol: 'XAUUSD',
      side: OrderSide.buy,
      type: OrderType.market,
      status: OrderStatus.open,
      lotSize: 0.05,
      openPrice: 2335.20,
      stopLoss: 2310.00,
      takeProfit: 2380.00,
      currentPrice: 2341.50,
      floatingPl: 31.50,
      commission: 2.50,
      swap: -1.20,
      leverage: 50,
      openTime: DateTime.now().subtract(const Duration(hours: 5, minutes: 42)),
    ),
    TradeEntity(
      id: 'tr_003',
      symbol: 'BTCUSD',
      side: OrderSide.sell,
      type: OrderType.market,
      status: OrderStatus.open,
      lotSize: 0.01,
      openPrice: 68100.00,
      stopLoss: 69000.00,
      takeProfit: 66000.00,
      currentPrice: 67842.50,
      floatingPl: 25.75,
      commission: 5.00,
      swap: -8.40,
      leverage: 10,
      openTime: DateTime.now().subtract(const Duration(hours: 1, minutes: 08)),
    ),
  ];

  void addTrade(TradeEntity trade) {
    state = [...state, trade];
  }

  void closeTrade(String tradeId) {
    state = state.map((t) => t.id == tradeId
        ? TradeEntity(
            id: t.id, symbol: t.symbol, side: t.side, type: t.type,
            status: OrderStatus.closed, lotSize: t.lotSize,
            openPrice: t.openPrice, currentPrice: t.currentPrice,
            closePrice: t.currentPrice, stopLoss: t.stopLoss,
            takeProfit: t.takeProfit, floatingPl: t.floatingPl,
            commission: t.commission, swap: t.swap, leverage: t.leverage,
            openTime: t.openTime, closeTime: DateTime.now(),
          )
        : t
    ).toList();
  }

  double get totalFloatingPl =>
      state.where((t) => t.isOpen).fold(0.0, (sum, t) => sum + t.floatingPl);
}

// ── Transactions Provider ─────────────────────────────────────────────────────
final transactionsProvider = StateProvider<List<TransactionEntity>>((ref) => _mockTransactions);

final _mockTransactions = [
  TransactionEntity(
    id: 'tx_001',
    type: 'deposit',
    amount: 5000.00,
    currency: 'USD',
    status: 'completed',
    method: 'Bank Transfer',
    description: 'Account funded',
    createdAt: DateTime.now().subtract(const Duration(days: 3)),
  ),
  TransactionEntity(
    id: 'tx_002',
    type: 'deposit',
    amount: 5000.00,
    currency: 'USD',
    status: 'completed',
    method: 'Credit Card',
    description: 'Visa ending 4242',
    createdAt: DateTime.now().subtract(const Duration(days: 10)),
  ),
  TransactionEntity(
    id: 'tx_003',
    type: 'withdrawal',
    amount: 250.00,
    currency: 'USD',
    status: 'pending',
    method: 'Bank Transfer',
    description: 'Withdrawal to bank account',
    createdAt: DateTime.now().subtract(const Duration(hours: 4)),
  ),
];
