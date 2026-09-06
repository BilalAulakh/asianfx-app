import 'dart:async';
import 'dart:math';
import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/math/money_math.dart';
import '../../data/datasources/market_feed_service.dart';
import '../../data/datasources/supabase_trade_service.dart';
import '../../domain/entities/trading_entities.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';
import 'ledger_provider.dart';

/// Full Trading Engine State containing positions, orders, account risk & alerts
class TradingEngineState {
  final List<TradeEntity> openPositions;
  final List<TradeEntity> closedTrades;
  final List<TradeEntity> pendingOrders;
  final TradingAccountState accountState;
  final bool isSubmitting;
  final String? lastAlertMessage;
  final DateTime? lastAlertTime;

  const TradingEngineState({
    this.openPositions = const [],
    this.closedTrades = const [],
    this.pendingOrders = const [],
    required this.accountState,
    this.isSubmitting = false,
    this.lastAlertMessage,
    this.lastAlertTime,
  });

  Decimal get totalUnrealizedPnl =>
      openPositions.fold(Decimal.zero, (sum, t) => sum + t.unrealizedPnl);

  Decimal get totalUsedMargin =>
      openPositions.fold(Decimal.zero, (sum, t) => sum + t.requiredMargin);

  int get openPositionsCount => openPositions.length;

  TradingEngineState copyWith({
    List<TradeEntity>? openPositions,
    List<TradeEntity>? closedTrades,
    List<TradeEntity>? pendingOrders,
    TradingAccountState? accountState,
    bool? isSubmitting,
    String? lastAlertMessage,
    DateTime? lastAlertTime,
  }) {
    return TradingEngineState(
      openPositions: openPositions ?? this.openPositions,
      closedTrades: closedTrades ?? this.closedTrades,
      pendingOrders: pendingOrders ?? this.pendingOrders,
      accountState: accountState ?? this.accountState,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      lastAlertMessage: lastAlertMessage,
      lastAlertTime: lastAlertTime,
    );
  }
}

class TradingEngineNotifier extends StateNotifier<TradingEngineState> {
  final Ref _ref;
  final _uuid = const Uuid();
  StreamSubscription<InstrumentEntity>? _feedSub;

  // In-memory per-user persistence cache
  final Map<String, List<TradeEntity>> _userOpenPositionsCache = {};
  final Map<String, List<TradeEntity>> _userClosedTradesCache = {};
  final Map<String, List<TradeEntity>> _userPendingOrdersCache = {};
  final Map<String, TradingAccountState> _userAccountCache = {};

  TradingEngineNotifier(this._ref)
      : super(
          TradingEngineState(
            accountState: TradingAccountState(
              accountId: 'ACT-INST-8801',
              userId: 'usr_institutional_01',
              currency: 'USD',
              ledgerBalance: Decimal.zero,
              unrealizedPnl: Decimal.zero,
              usedMargin: Decimal.zero,
              leverage: Decimal.fromInt(AppConstants.defaultLeverage),
            ),
          ),
        ) {
    _listenToMarketTicks();
  }

  void _syncUserCache(String userId) {
    _userOpenPositionsCache[userId] = state.openPositions;
    _userClosedTradesCache[userId] = state.closedTrades;
    _userPendingOrdersCache[userId] = state.pendingOrders;
    _userAccountCache[userId] = state.accountState;
  }

  /// Switch active trading engine to the authenticated user's portfolio
  void switchUser(String userId, {Decimal? initialBalance}) {
    final currentUserId = state.accountState.userId;
    // Save current user state to cache
    _syncUserCache(currentUserId);

    // Retrieve or initialize target user state
    final userOpen = _userOpenPositionsCache[userId] ?? const [];
    final userClosed = _userClosedTradesCache[userId] ?? const [];
    final userPending = _userPendingOrdersCache[userId] ?? const [];
    var userAccount = _userAccountCache[userId] ??
        TradingAccountState(
          accountId: 'ACT-${userId.toUpperCase().replaceAll('-', '').substring(0, min(8, userId.length))}',
          userId: userId,
          currency: 'USD',
          ledgerBalance: initialBalance ?? AppConstants.defaultClientInitialBalance,
          unrealizedPnl: Decimal.zero,
          usedMargin: Decimal.zero,
          leverage: Decimal.fromInt(AppConstants.defaultLeverage),
        );

    if (userAccount.ledgerBalance == MoneyMath.toDec(10000.0) ||
        userAccount.ledgerBalance == MoneyMath.toDec(25000.0)) {
      userAccount = userAccount.copyWith(ledgerBalance: Decimal.zero);
    }

    final totalUsed = userOpen.fold(Decimal.zero, (s, p) => s + p.requiredMargin);
    final totalUnrealized = userOpen.fold(Decimal.zero, (s, p) => s + p.unrealizedPnl);

    state = state.copyWith(
      openPositions: userOpen,
      closedTrades: userClosed,
      pendingOrders: userPending,
      accountState: userAccount.copyWith(
        usedMargin: totalUsed,
        unrealizedPnl: totalUnrealized,
      ),
    );

    _syncUserCache(userId);

    // Asynchronously fetch real Supabase wallet balance
    try {
      Supabase.instance.client
          .from('wallets')
          .select('balance')
          .eq('user_id', userId)
          .maybeSingle()
          .then((res) {
        if (res != null && res['balance'] != null) {
          var balNum = (res['balance'] as num).toDouble();
          if (balNum == 10000.0 || balNum == 25000.0) {
            balNum = 0.0;
            Supabase.instance.client
                .from('wallets')
                .update({'balance': 0.0, 'held_margin': 0.0})
                .eq('user_id', userId)
                .catchError((_) {});
          }
          final realBal = MoneyMath.toDec(balNum);
          if (state.accountState.userId == userId) {
            state = state.copyWith(
              accountState: state.accountState.copyWith(ledgerBalance: realBal),
            );
          }
          if (_userAccountCache.containsKey(userId)) {
            _userAccountCache[userId] = _userAccountCache[userId]!.copyWith(ledgerBalance: realBal);
          }
        }
      }).catchError((_) {});
    } catch (_) {}

    // Asynchronously fetch any remote Supabase trades
    SupabaseTradeService.instance.fetchUserTrades(userId).then((supabaseTrades) {
      if (supabaseTrades.isNotEmpty && state.accountState.userId == userId) {
        final remoteOpens = supabaseTrades.where((t) => t.isOpen).toList();
        final remoteClosed = supabaseTrades.where((t) => t.isClosed).toList();
        state = state.copyWith(
          openPositions: remoteOpens.isNotEmpty ? remoteOpens : state.openPositions,
          closedTrades: remoteClosed.isNotEmpty ? remoteClosed : state.closedTrades,
        );
        _syncUserCache(userId);
      }
    });
  }

  /// Explicitly set balance for a user (e.g. reset legacy demo balance)
  void setBalance(String userId, Decimal balance) {
    if (state.accountState.userId == userId) {
      state = state.copyWith(
        accountState: state.accountState.copyWith(ledgerBalance: balance),
      );
    }
    if (_userAccountCache.containsKey(userId)) {
      _userAccountCache[userId] = _userAccountCache[userId]!.copyWith(ledgerBalance: balance);
    }
  }

  /// Deposit funds into a trader's account
  void depositFunds(String userId, Decimal amount) {
    if (state.accountState.userId == userId) {
      final newBalance = state.accountState.ledgerBalance + amount;
      state = state.copyWith(
        accountState: state.accountState.copyWith(ledgerBalance: newBalance),
      );
    }
    // Update cache as well
    if (_userAccountCache.containsKey(userId)) {
      final cached = _userAccountCache[userId]!;
      _userAccountCache[userId] = cached.copyWith(
        ledgerBalance: cached.ledgerBalance + amount,
      );
    }
  }

  /// Withdraw funds from a trader's account
  void withdrawFunds(String userId, Decimal amount) {
    if (state.accountState.userId == userId) {
      final newBalance = (state.accountState.ledgerBalance - amount).clamp(Decimal.zero, MoneyMath.toDec(1000000000.0));
      state = state.copyWith(
        accountState: state.accountState.copyWith(ledgerBalance: newBalance),
      );
    }
    // Update cache as well
    if (_userAccountCache.containsKey(userId)) {
      final cached = _userAccountCache[userId]!;
      _userAccountCache[userId] = cached.copyWith(
        ledgerBalance: (cached.ledgerBalance - amount).clamp(Decimal.zero, MoneyMath.toDec(1000000000.0)),
      );
    }
  }


  void _listenToMarketTicks() {
    _feedSub?.cancel();
    _feedSub = MarketFeedService().tickStream.listen((instrument) {
      _processPriceTick(instrument);
    });
  }

  /// Process live price tick: recalculate PnL, check TP/SL, Margin Call & Liquidation
  void _processPriceTick(InstrumentEntity inst) {
    if (state.openPositions.isEmpty && state.pendingOrders.isEmpty) return;

    final updatedPositions = <TradeEntity>[];
    final closedByTrigger = <TradeEntity>[];

    final bid = inst.bid;
    final ask = inst.ask;

    for (final pos in state.openPositions) {
      if (pos.symbol != inst.symbol) {
        updatedPositions.add(pos);
        continue;
      }

      final execPrice = pos.isBuy ? bid : ask;
      final newUnrealized = MoneyMath.calcUnrealizedPnL(
        isBuy: pos.isBuy,
        openPrice: pos.openPrice,
        currentPrice: execPrice,
        lots: pos.lots,
        contractSize: pos.contractSize,
      );

      // Check Take Profit trigger
      if (pos.takeProfit != null) {
        final tpTriggered = pos.isBuy
            ? (bid >= pos.takeProfit!)
            : (ask <= pos.takeProfit!);
        if (tpTriggered) {
          final closed = pos.copyWith(
            status: OrderStatus.closed,
            closePrice: execPrice,
            currentPrice: execPrice,
            unrealizedPnl: Decimal.zero,
            realizedPnl: newUnrealized,
            closeTime: DateTime.now(),
            closeReason: 'take_profit',
          );
          closedByTrigger.add(closed);
          _settleClosedPositionLedger(closed);
          continue;
        }
      }

      // Check Stop Loss trigger
      if (pos.stopLoss != null) {
        final slTriggered = pos.isBuy
            ? (bid <= pos.stopLoss!)
            : (ask >= pos.stopLoss!);
        if (slTriggered) {
          final closed = pos.copyWith(
            status: OrderStatus.closed,
            closePrice: execPrice,
            currentPrice: execPrice,
            unrealizedPnl: Decimal.zero,
            realizedPnl: newUnrealized,
            closeTime: DateTime.now(),
            closeReason: 'stop_loss',
          );
          closedByTrigger.add(closed);
          _settleClosedPositionLedger(closed);
          continue;
        }
      }

      updatedPositions.add(pos.copyWith(
        currentPrice: execPrice,
        unrealizedPnl: newUnrealized,
      ));
    }

    // Process pending limit/stop orders
    final remainingPending = <TradeEntity>[];
    for (final order in state.pendingOrders) {
      if (order.symbol != inst.symbol || order.targetPrice == null) {
        remainingPending.add(order);
        continue;
      }

      bool isFilled = false;
      Decimal fillPrice = Decimal.zero;

      if (order.type == OrderType.limit) {
        if (order.isBuy && ask <= order.targetPrice!) {
          isFilled = true;
          fillPrice = ask;
        } else if (order.isSell && bid >= order.targetPrice!) {
          isFilled = true;
          fillPrice = bid;
        }
      } else if (order.type == OrderType.stop) {
        if (order.isBuy && ask >= order.targetPrice!) {
          isFilled = true;
          fillPrice = ask;
        } else if (order.isSell && bid <= order.targetPrice!) {
          isFilled = true;
          fillPrice = bid;
        }
      }

      if (isFilled) {
        final filledTrade = order.copyWith(
          status: OrderStatus.open,
          openPrice: fillPrice,
          currentPrice: fillPrice,
        );
        updatedPositions.add(filledTrade);
        // Lock margin in ledger
        _ref.read(ledgerProvider.notifier).lockMargin(
              userId: state.accountState.userId,
              tradeId: filledTrade.id,
              marginAmount: filledTrade.requiredMargin,
              symbol: filledTrade.symbol,
            );
      } else {
        remainingPending.add(order);
      }
    }

    // Refresh cash balance from double-entry ledger
    final ledgerBalance = _ref.read(clientLedgerBalanceProvider);

    final totalUnrealized =
        updatedPositions.fold(Decimal.zero, (s, p) => s + p.unrealizedPnl);
    final totalUsed =
        updatedPositions.fold(Decimal.zero, (s, p) => s + p.requiredMargin);

    var updatedAccountState = state.accountState.copyWith(
      ledgerBalance: ledgerBalance,
      unrealizedPnl: totalUnrealized,
      usedMargin: totalUsed,
    );

    // Stop-Out Auto-Liquidation Check (Equity / Used Margin <= 50%)
    if (updatedPositions.isNotEmpty && updatedAccountState.isStopOutLiquidation) {
      // Find position with highest loss to liquidate
      updatedPositions.sort((a, b) => a.unrealizedPnl.compareTo(b.unrealizedPnl));
      final liquidatedPos = updatedPositions.removeAt(0);

      final closedLiquidated = liquidatedPos.copyWith(
        status: OrderStatus.liquidated,
        closePrice: liquidatedPos.currentPrice,
        unrealizedPnl: Decimal.zero,
        realizedPnl: liquidatedPos.unrealizedPnl,
        closeTime: DateTime.now(),
        closeReason: 'stop_out_liquidation',
      );

      closedByTrigger.add(closedLiquidated);
      _settleClosedPositionLedger(closedLiquidated);

      // Recalculate margins after liquidation
      final postUsed =
          updatedPositions.fold(Decimal.zero, (s, p) => s + p.requiredMargin);
      final postUnrealized =
          updatedPositions.fold(Decimal.zero, (s, p) => s + p.unrealizedPnl);
      final postLedger = _ref.read(clientLedgerBalanceProvider);

      updatedAccountState = updatedAccountState.copyWith(
        ledgerBalance: postLedger,
        usedMargin: postUsed,
        unrealizedPnl: postUnrealized,
      );

      state = state.copyWith(
        openPositions: updatedPositions,
        closedTrades: [...closedByTrigger, ...state.closedTrades],
        pendingOrders: remainingPending,
        accountState: updatedAccountState,
        lastAlertMessage:
            '⚠️ STOP-OUT LIQUIDATION: ${liquidatedPos.symbol} auto-liquidated to protect equity!',
        lastAlertTime: DateTime.now(),
      );
      return;
    }

    state = state.copyWith(
      openPositions: updatedPositions,
      closedTrades: [...closedByTrigger, ...state.closedTrades],
      pendingOrders: remainingPending,
      accountState: updatedAccountState,
      lastAlertMessage: updatedAccountState.isMarginCall
          ? '⚠️ MARGIN CALL WARNING: Margin level below 100%! Deposit funds or close trades.'
          : null,
      lastAlertTime: updatedAccountState.isMarginCall ? DateTime.now() : null,
    );

    if (closedByTrigger.isNotEmpty) {
      _syncUserCache(state.accountState.userId);
      for (final closed in closedByTrigger) {
        SupabaseTradeService.instance.updateClosedTrade(closed);
      }
    }
  }

  /// Open a new Order (Market, Limit, Stop)
  Future<bool> placeOrder({
    required InstrumentEntity instrument,
    required OrderSide side,
    required OrderType type,
    required Decimal lots,
    Decimal? targetPrice,
    Decimal? stopLoss,
    Decimal? takeProfit,
    Decimal? leverage,
  }) async {
    final authUser = _ref.read(authProvider).user;
    if (authUser != null && !authUser.canTrade) {
      throw Exception('KYC Verification required to open live positions.');
    }

    state = state.copyWith(isSubmitting: true);
    await Future.delayed(const Duration(milliseconds: 300));

    final activeLev = leverage ?? state.accountState.leverage;
    final execPrice = side == OrderSide.buy ? instrument.ask : instrument.bid;
    final orderPrice = type == OrderType.market ? execPrice : (targetPrice ?? execPrice);

    final requiredMargin = MoneyMath.calcRequiredMargin(
      lots: lots,
      contractSize: instrument.contractSize,
      openPrice: orderPrice,
      leverage: activeLev,
    );

    // Free margin validation
    if (requiredMargin > state.accountState.freeMargin) {
      state = state.copyWith(isSubmitting: false);
      throw Exception(
        'Insufficient Free Margin! Required: ${MoneyMath.formatCurrency(requiredMargin)}, '
        'Available: ${MoneyMath.formatCurrency(state.accountState.freeMargin)}',
      );
    }

    final tradeId = 'POS-${_uuid.v4().substring(0, 8).toUpperCase()}';
    final orderId = 'ORD-${_uuid.v4().substring(0, 8).toUpperCase()}';

    final isMarket = type == OrderType.market;

    final newTrade = TradeEntity(
      id: tradeId,
      orderId: orderId,
      symbol: instrument.symbol,
      side: side,
      type: type,
      status: isMarket ? OrderStatus.open : OrderStatus.pending,
      lots: lots,
      contractSize: instrument.contractSize,
      openPrice: orderPrice,
      targetPrice: targetPrice,
      currentPrice: execPrice,
      unrealizedPnl: Decimal.zero,
      requiredMargin: requiredMargin,
      stopLoss: stopLoss,
      takeProfit: takeProfit,
      leverage: activeLev,
      openTime: DateTime.now(),
    );

    if (isMarket) {
      // 1. Lock Margin in Double-Entry Ledger
      _ref.read(ledgerProvider.notifier).lockMargin(
            userId: state.accountState.userId,
            tradeId: tradeId,
            marginAmount: requiredMargin,
            symbol: instrument.symbol,
          );

      // 2. Book Spread Markup Fee in Ledger
      final spreadFee = MoneyMath.toDec(instrument.spread.toDouble() * lots.toDouble() * 0.5);
      _ref.read(ledgerProvider.notifier).recordFee(
            userId: state.accountState.userId,
            tradeId: tradeId,
            feeAmount: spreadFee,
            feeDescription: 'Spread Markup (${instrument.symbol})',
          );

      final updatedPositions = [newTrade, ...state.openPositions];
      final totalUsed = updatedPositions.fold(Decimal.zero, (s, p) => s + p.requiredMargin);
      final totalUnrealized = updatedPositions.fold(Decimal.zero, (s, p) => s + p.unrealizedPnl);

      state = state.copyWith(
        openPositions: updatedPositions,
        accountState: state.accountState.copyWith(
          usedMargin: totalUsed,
          unrealizedPnl: totalUnrealized,
        ),
        isSubmitting: false,
      );
      _syncUserCache(state.accountState.userId);

      // Attempt Atomic Backend Execution via Supabase RPC, falling back to direct table sync
      SupabaseTradeService.instance.openTradeRpc(trade: newTrade).then((rpcResult) {
        if (rpcResult == null) {
          SupabaseTradeService.instance.insertTrade(
            trade: newTrade,
            userId: state.accountState.userId,
          );
        }
      });
    } else {
      state = state.copyWith(
        pendingOrders: [newTrade, ...state.pendingOrders],
        isSubmitting: false,
      );
      _syncUserCache(state.accountState.userId);
    }

    return true;
  }

  /// Close an open position manually (Full or Partial)
  Future<void> closePosition(String tradeId) async {
    final idx = state.openPositions.indexWhere((t) => t.id == tradeId);
    if (idx == -1) return;

    final pos = state.openPositions[idx];
    final closed = pos.copyWith(
      status: OrderStatus.closed,
      closePrice: pos.currentPrice,
      realizedPnl: pos.unrealizedPnl,
      unrealizedPnl: Decimal.zero,
      closeTime: DateTime.now(),
      closeReason: 'manual',
    );

    _settleClosedPositionLedger(closed);

    final updatedOpen = List<TradeEntity>.from(state.openPositions)..removeAt(idx);
    final totalUsed = updatedOpen.fold(Decimal.zero, (s, p) => s + p.requiredMargin);
    final totalUnrealized = updatedOpen.fold(Decimal.zero, (s, p) => s + p.unrealizedPnl);
    final postLedger = _ref.read(clientLedgerBalanceProvider);

    state = state.copyWith(
      openPositions: updatedOpen,
      closedTrades: [closed, ...state.closedTrades],
      accountState: state.accountState.copyWith(
        ledgerBalance: postLedger > Decimal.zero ? postLedger : state.accountState.ledgerBalance + pos.unrealizedPnl,
        usedMargin: totalUsed,
        unrealizedPnl: totalUnrealized,
      ),
    );
    _syncUserCache(state.accountState.userId);

    // Settle in Supabase via RPC or table update
    final closePriceNum = closed.closePrice?.toDouble() ?? closed.currentPrice.toDouble();
    SupabaseTradeService.instance.closeTradeRpc(
      tradeId: tradeId,
      closePrice: closePriceNum,
    ).then((rpcResult) {
      if (rpcResult == null) {
        SupabaseTradeService.instance.updateClosedTrade(closed);
      }
    });
  }

  /// Cancel a pending limit/stop order
  void cancelPendingOrder(String orderId) {
    final updatedPending =
        state.pendingOrders.where((o) => o.id != orderId && o.orderId != orderId).toList();
    state = state.copyWith(pendingOrders: updatedPending);
  }

  /// Double-Entry Ledger Settlement for closed position
  void _settleClosedPositionLedger(TradeEntity closed) {
    // 1. Release Margin Lock
    _ref.read(ledgerProvider.notifier).releaseMargin(
          userId: state.accountState.userId,
          tradeId: closed.id,
          marginAmount: closed.requiredMargin,
          symbol: closed.symbol,
        );

    // 2. Book Realized PnL in Double-Entry Ledger
    _ref.read(ledgerProvider.notifier).recordTradePnl(
          userId: state.accountState.userId,
          tradeId: closed.id,
          pnlAmount: closed.realizedPnl,
          symbol: closed.symbol,
        );
  }

  @override
  void dispose() {
    _feedSub?.cancel();
    super.dispose();
  }
}

final tradingEngineProvider =
    StateNotifierProvider<TradingEngineNotifier, TradingEngineState>((ref) {
  return TradingEngineNotifier(ref);
});
