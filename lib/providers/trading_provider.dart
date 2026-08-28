import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_constants.dart';
import '../core/math/money_math.dart';
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
          id: 'trd_100',
          orderId: 'ord_100',
          symbol: 'BTC/USD',
          side: OrderSide.buy,
          type: OrderType.market,
          status: OrderStatus.open,
          lots: MoneyMath.toDec(0.10),
          contractSize: AppConstants.contractSizeCrypto,
          openPrice: MoneyMath.toDec(96250.0),
          currentPrice: MoneyMath.toDec(96480.0),
          unrealizedPnl: MoneyMath.toDec(23.00),
          requiredMargin: MoneyMath.toDec(96.25),
          leverage: Decimal.fromInt(100),
          openTime: DateTime.now().subtract(const Duration(minutes: 18)),
        ),
      ],
      tradeHistory: [
        TradeEntity(
          id: 'trd_099',
          orderId: 'ord_099',
          symbol: 'BTC/USD',
          side: OrderSide.buy,
          type: OrderType.market,
          status: OrderStatus.closed,
          lots: MoneyMath.toDec(0.1),
          contractSize: AppConstants.contractSizeCrypto,
          openPrice: MoneyMath.toDec(95100.0),
          closePrice: MoneyMath.toDec(96300.0),
          currentPrice: MoneyMath.toDec(96300.0),
          unrealizedPnl: Decimal.zero,
          realizedPnl: MoneyMath.toDec(120.0),
          requiredMargin: Decimal.zero,
          leverage: Decimal.fromInt(50),
          openTime: DateTime.now().subtract(const Duration(days: 1)),
          closeTime: DateTime.now().subtract(const Duration(hours: 12)),
        ),
      ],
    );
  }

  void updatePriceTick(String symbol, double currentBid, double currentAsk) {
    if (state.openTrades.isEmpty) return;
    final updated = state.openTrades.map((trade) {
      if (trade.symbol == symbol) {
        final currentPrice = trade.side == OrderSide.buy ? currentBid : currentAsk;
        final delta = trade.side == OrderSide.buy
            ? (currentBid - trade.openPrice.toDouble())
            : (trade.openPrice.toDouble() - currentAsk);
        final pl = delta * trade.lots.toDouble() * trade.contractSize.toDouble();
        return trade.copyWith(
          currentPrice: MoneyMath.toDec(currentPrice),
          unrealizedPnl: MoneyMath.toDec(pl),
        );
      }
      return trade;
    }).toList();
    state = state.copyWith(openTrades: updated);
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
    await Future.delayed(const Duration(milliseconds: 300));

    final newTrade = TradeEntity(
      id: 'trd_${DateTime.now().millisecondsSinceEpoch}',
      orderId: 'ord_${DateTime.now().millisecondsSinceEpoch}',
      symbol: symbol,
      side: side,
      type: type,
      status: OrderStatus.open,
      lots: MoneyMath.toDec(lotSize),
      contractSize: symbol.contains('XAU')
          ? AppConstants.contractSizeGold
          : (symbol.contains('BTC') ? AppConstants.contractSizeCrypto : AppConstants.contractSizeForex),
      openPrice: MoneyMath.toDec(price),
      currentPrice: MoneyMath.toDec(price),
      requiredMargin: MoneyMath.toDec((price * lotSize) / leverage),
      stopLoss: stopLoss != null ? MoneyMath.toDec(stopLoss) : null,
      takeProfit: takeProfit != null ? MoneyMath.toDec(takeProfit) : null,
      leverage: MoneyMath.toDec(leverage),
      openTime: DateTime.now(),
      unrealizedPnl: Decimal.zero,
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
    final closedTrade = trade.copyWith(
      status: OrderStatus.closed,
      closePrice: trade.currentPrice,
      realizedPnl: trade.unrealizedPnl,
      unrealizedPnl: Decimal.zero,
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
