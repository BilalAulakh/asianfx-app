import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/entities/trading_entities.dart';

class TradingState {
  final List<TradeEntity> openTrades;
  final List<TradeEntity> tradeHistory;
  final bool isLoading;
  final String? error;

  const TradingState({
    this.openTrades = const [],
    this.tradeHistory = const [],
    this.isLoading = false,
    this.error,
  });

  double get totalFloatingPl {
    return openTrades.fold(0.0, (sum, t) => sum + t.floatingPl);
  }

  TradingState copyWith({
    List<TradeEntity>? openTrades,
    List<TradeEntity>? tradeHistory,
    bool? isLoading,
    String? error,
  }) {
    return TradingState(
      openTrades: openTrades ?? this.openTrades,
      tradeHistory: tradeHistory ?? this.tradeHistory,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class TradingNotifier extends StateNotifier<TradingState> {
  TradingNotifier() : super(const TradingState()) {
    _loadInitialTrades();
  }

  void _loadInitialTrades() {
    state = TradingState(
      openTrades: [
        TradeEntity(
          id: 'trd_101',
          symbol: 'EURUSD',
          side: OrderSide.buy,
          type: OrderType.market,
          status: OrderStatus.open,
          lotSize: 1.0,
          openPrice: 1.0850,
          currentPrice: 1.0875,
          floatingPl: 250.0,
          leverage: 100,
          openTime: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        TradeEntity(
          id: 'trd_102',
          symbol: 'XAUUSD',
          side: OrderSide.sell,
          type: OrderType.market,
          status: OrderStatus.open,
          lotSize: 0.5,
          openPrice: 2045.50,
          currentPrice: 2041.20,
          floatingPl: 215.0,
          leverage: 100,
          openTime: DateTime.now().subtract(const Duration(hours: 5)),
        ),
      ],
      tradeHistory: [
        TradeEntity(
          id: 'trd_099',
          symbol: 'BTCUSD',
          side: OrderSide.buy,
          type: OrderType.market,
          status: OrderStatus.closed,
          lotSize: 0.1,
          openPrice: 42100.0,
          closePrice: 43500.0,
          floatingPl: 140.0,
          leverage: 50,
          openTime: DateTime.now().subtract(const Duration(days: 1)),
          closeTime: DateTime.now().subtract(const Duration(hours: 12)),
        ),
      ],
    );
  }

  Future<bool> executeOrder({
    required String symbol,
    required OrderSide side,
    required OrderType type,
    required double lotSize,
    required double price,
    double? stopLoss,
    double? takeProfit,
    double leverage = 100.0,
  }) async {
    state = state.copyWith(isLoading: true);
    await Future.delayed(const Duration(milliseconds: 600));

    final newTrade = TradeEntity(
      id: 'trd_${DateTime.now().millisecondsSinceEpoch}',
      symbol: symbol,
      side: side,
      type: type,
      status: OrderStatus.open,
      lotSize: lotSize,
      openPrice: price,
      currentPrice: price,
      stopLoss: stopLoss,
      takeProfit: takeProfit,
      leverage: leverage,
      openTime: DateTime.now(),
      floatingPl: 0.0,
    );

    state = state.copyWith(
      openTrades: [newTrade, ...state.openTrades],
      isLoading: false,
    );
    return true;
  }

  Future<void> closePosition(String tradeId) async {
    final tradeIndex = state.openTrades.indexWhere((t) => t.id == tradeId);
    if (tradeIndex == -1) return;

    final trade = state.openTrades[tradeIndex];
    final closedTrade = TradeEntity(
      id: trade.id,
      symbol: trade.symbol,
      side: trade.side,
      type: trade.type,
      status: OrderStatus.closed,
      lotSize: trade.lotSize,
      openPrice: trade.openPrice,
      closePrice: trade.currentPrice ?? trade.openPrice,
      floatingPl: trade.floatingPl,
      leverage: trade.leverage,
      openTime: trade.openTime,
      closeTime: DateTime.now(),
    );

    final updatedOpen = List<TradeEntity>.from(state.openTrades)..removeAt(tradeIndex);
    state = state.copyWith(
      openTrades: updatedOpen,
      tradeHistory: [closedTrade, ...state.tradeHistory],
    );
  }
}

final tradingProvider = StateNotifierProvider<TradingNotifier, TradingState>((ref) {
  return TradingNotifier();
});
