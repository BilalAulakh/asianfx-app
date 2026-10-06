import 'dart:async';
import 'dart:math';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/math/money_math.dart';
import '../data/datasources/market_feed_service.dart';
import '../data/datasources/supabase_trade_service.dart';
import '../data/repositories/ledger_repository.dart';
import '../domain/entities/trading_entities.dart';

/// Full Trading Engine State containing positions, orders, account risk & alerts
class TradingEngineState {
  final List<TradeEntity> openPositions;
  final List<TradeEntity> closedTrades;
  final List<TradeEntity> pendingOrders;
  final TradingAccountState accountState;
  final bool isSubmitting;
  final String? lastAlertMessage;
  final DateTime? lastAlertTime;

  /// One-shot error from a rejected server request (close / cancel). Like
  /// [lastAlertMessage] it is cleared by the next copyWith, so listeners key on
  /// [lastErrorTime].
  final String? lastErrorMessage;
  final DateTime? lastErrorTime;

  /// True when a signed-in Supabase session exists, i.e. every financial
  /// decision is being made and committed by the database. False means the
  /// engine is running in local simulation mode (demo / offline / tests) and
  /// nothing it computes represents real money.
  final bool isServerAuthoritative;

  /// Set when the authoritative sync could not reach the server. The UI keeps
  /// showing the last known server state instead of inventing a new one.
  final bool isServerReachable;

  final DateTime? lastServerSyncAt;

  const TradingEngineState({
    this.openPositions = const [],
    this.closedTrades = const [],
    this.pendingOrders = const [],
    required this.accountState,
    this.isSubmitting = false,
    this.lastAlertMessage,
    this.lastAlertTime,
    this.lastErrorMessage,
    this.lastErrorTime,
    this.isServerAuthoritative = false,
    this.isServerReachable = true,
    this.lastServerSyncAt,
  });

  Decimal get totalUnrealizedPnl =>
      openPositions.fold<Decimal>(Decimal.zero, (sum, t) => sum + t.unrealizedPnl);

  Decimal get totalUsedMargin =>
      openPositions.fold<Decimal>(Decimal.zero, (sum, t) => sum + t.requiredMargin);

  int get openPositionsCount => openPositions.length;

  TradingEngineState copyWith({
    List<TradeEntity>? openPositions,
    List<TradeEntity>? closedTrades,
    List<TradeEntity>? pendingOrders,
    TradingAccountState? accountState,
    bool? isSubmitting,
    String? lastAlertMessage,
    DateTime? lastAlertTime,
    String? lastErrorMessage,
    DateTime? lastErrorTime,
    bool? isServerAuthoritative,
    bool? isServerReachable,
    DateTime? lastServerSyncAt,
  }) {
    return TradingEngineState(
      openPositions: openPositions ?? this.openPositions,
      closedTrades: closedTrades ?? this.closedTrades,
      pendingOrders: pendingOrders ?? this.pendingOrders,
      accountState: accountState ?? this.accountState,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      lastAlertMessage: lastAlertMessage,
      lastAlertTime: lastAlertTime,
      lastErrorMessage: lastErrorMessage,
      lastErrorTime: lastErrorTime,
      isServerAuthoritative: isServerAuthoritative ?? this.isServerAuthoritative,
      isServerReachable: isServerReachable ?? this.isServerReachable,
      lastServerSyncAt: lastServerSyncAt ?? this.lastServerSyncAt,
    );
  }
}

/// Trading engine.
///
/// ## Where authority lives
///
/// When a Supabase session exists this cubit is a **mirror**: it requests
/// orders, displays prices and previews margin, but every balance, margin lock,
/// realized PnL, SL/TP execution and stop-out is decided and committed by the
/// database RPCs. If an RPC fails the request fails — the engine never writes a
/// financial row itself. The previous implementation fell back to
/// `insertTrade()` / `updateClosedTrade()` whenever the RPC returned null, which
/// turned a server *rejection* into a local position with no margin held.
///
/// Without a session (demo mode, offline preview, unit tests) it runs a local
/// simulation so the UI stays usable. That path is clearly marked and is not a
/// source of truth for real funds.
class TradingEngineCubit extends Cubit<TradingEngineState> {
  final _uuid = const Uuid();
  final LedgerRepository _ledgerRepo = LedgerRepository.instance;
  final SupabaseTradeService _trades = SupabaseTradeService.instance;
  final MarketFeedService _feed = MarketFeedService();

  StreamSubscription<InstrumentEntity>? _feedSub;
  RealtimeChannel? _realtimeChannel;

  // In-memory per-user cache used by the local simulation path only.
  final Map<String, List<TradeEntity>> _userOpenPositionsCache = {};
  final Map<String, List<TradeEntity>> _userClosedTradesCache = {};
  final Map<String, List<TradeEntity>> _userPendingOrdersCache = {};
  final Map<String, TradingAccountState> _userAccountCache = {};

  /// Guards against duplicate in-flight financial requests (double tap, retry).
  final Set<String> _inFlightCloses = {};
  final Set<String> _inFlightCancels = {};
  bool _openInFlight = false;

  /// Authoritative risk sync throttle. Ticks arrive every few hundred ms; the
  /// server pass is expensive and must not be spammed.
  static const Duration _syncInterval = Duration(seconds: 3);
  DateTime? _lastSyncAttempt;
  bool _syncInFlight = false;

  TradingEngineCubit()
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

  bool get _serverAuthoritative => _trades.isAvailable;

  void _syncUserCache(String userId) {
    _userOpenPositionsCache[userId] = state.openPositions;
    _userClosedTradesCache[userId] = state.closedTrades;
    _userPendingOrdersCache[userId] = state.pendingOrders;
    _userAccountCache[userId] = state.accountState;
  }

  String _accountIdFor(String userId) =>
      'ACT-${userId.toUpperCase().replaceAll('-', '').substring(0, min(8, userId.length))}';

  // ─────────────────────────────────────────────────────────── user switch ────

  /// Switch the engine to the authenticated user's portfolio.
  void switchUser(String userId, {Decimal? initialBalance}) {
    _syncUserCache(state.accountState.userId);

    final userOpen = _userOpenPositionsCache[userId] ?? const <TradeEntity>[];
    final userClosed = _userClosedTradesCache[userId] ?? const <TradeEntity>[];
    final userPending = _userPendingOrdersCache[userId] ?? const <TradeEntity>[];

    final account = _userAccountCache[userId] ??
        TradingAccountState(
          accountId: _accountIdFor(userId),
          userId: userId,
          currency: 'USD',
          ledgerBalance: initialBalance ?? AppConstants.defaultClientInitialBalance,
          unrealizedPnl: Decimal.zero,
          usedMargin: Decimal.zero,
          leverage: Decimal.fromInt(AppConstants.defaultLeverage),
        );

    emit(state.copyWith(
      openPositions: userOpen,
      closedTrades: userClosed,
      pendingOrders: userPending,
      accountState: account.copyWith(
        usedMargin: userOpen.fold<Decimal>(Decimal.zero, (s, p) => s + p.requiredMargin),
        unrealizedPnl: userOpen.fold<Decimal>(Decimal.zero, (s, p) => s + p.unrealizedPnl),
      ),
      isServerAuthoritative: _serverAuthoritative,
    ));

    _syncUserCache(userId);

    if (_serverAuthoritative) {
      // The server is the source of truth for this account: reload everything
      // and subscribe for pushed changes.
      reloadFromServer();
      _subscribeToRealtime(userId);
    }
  }

  /// Pull the authoritative book and wallet for the active user.
  ///
  /// Unlike the old implementation this REPLACES local state even when the
  /// server returns an empty list — "the server says you have no open positions"
  /// is information, not a reason to keep showing stale local ones.
  Future<void> reloadFromServer() async {
    if (!_serverAuthoritative) return;
    final userId = state.accountState.userId;

    // Active rows are fetched unbounded (an old open position must never fall
    // out of a result window); history is capped for payload size.
    final active = await _trades.fetchActiveTrades(userId);
    final history = await _trades.fetchTradeHistory(userId);
    final snapshot = await _trades.fetchAccountState();

    if (isClosed || state.accountState.userId != userId) return;

    final opens = active.where((t) => t.isOpen).map(_repriceForDisplay).toList();
    final pending = active.where((t) => t.isPending).toList();

    var account = state.accountState;
    if (snapshot != null) {
      account = account.copyWith(
        ledgerBalance: MoneyMath.toDec(snapshot['balance']),
        usedMargin: MoneyMath.toDec(snapshot['used_margin']),
        unrealizedPnl: opens.fold<Decimal>(Decimal.zero, (s, p) => s + p.unrealizedPnl),
      );
    } else {
      account = account.copyWith(
        usedMargin: opens.fold<Decimal>(Decimal.zero, (s, p) => s + p.requiredMargin),
        unrealizedPnl: opens.fold<Decimal>(Decimal.zero, (s, p) => s + p.unrealizedPnl),
      );
    }

    emit(state.copyWith(
      openPositions: opens,
      pendingOrders: pending,
      closedTrades: history,
      accountState: account,
      isServerAuthoritative: true,
      isServerReachable: snapshot != null,
      lastServerSyncAt: DateTime.now(),
    ));
    _syncUserCache(userId);
  }

  void _subscribeToRealtime(String userId) {
    _unsubscribeRealtime();
    try {
      final client = Supabase.instance.client;
      _realtimeChannel = client
          .channel('fx_engine_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'trades',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (_) => reloadFromServer(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'wallets',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (_) => refreshBalance(),
          )
          .subscribe();
    } catch (_) {
      // Realtime is an optimisation; the throttled sync still converges.
      _realtimeChannel = null;
    }
  }

  void _unsubscribeRealtime() {
    final ch = _realtimeChannel;
    _realtimeChannel = null;
    if (ch == null) return;
    try {
      Supabase.instance.client.removeChannel(ch);
    } catch (_) {}
  }

  /// Refresh balance / margin from the authoritative wallet.
  ///
  /// The previous version contained two data-destroying rules that are gone:
  ///   * `if (balance == 10000 || balance == 25000) balance = 0` — and it wrote
  ///     that zero back to Supabase, so a genuine $10,000 deposit was erased.
  ///   * `if (effective > 0) emit(...)` — a balance of exactly 0 was never
  ///     applied, so a wiped-out account kept displaying a stale positive figure.
  Future<void> refreshBalance() async {
    if (!_serverAuthoritative) return;
    final userId = state.accountState.userId;

    final snapshot = await _trades.fetchAccountState();
    if (isClosed || state.accountState.userId != userId) return;

    if (snapshot != null) {
      _applyServerSnapshot(snapshot, reachable: true);
      return;
    }

    final wallet = await _trades.fetchUserWallet(userId);
    if (isClosed || state.accountState.userId != userId) return;

    if (wallet == null) {
      emit(state.copyWith(isServerReachable: false));
      return;
    }

    emit(state.copyWith(
      accountState: state.accountState.copyWith(
        ledgerBalance: MoneyMath.toDec(wallet['balance']),
        usedMargin: MoneyMath.toDec(wallet['held_margin']),
      ),
      isServerReachable: true,
      lastServerSyncAt: DateTime.now(),
    ));
    _syncUserCache(userId);
  }

  void _applyServerSnapshot(Map<String, dynamic> snapshot, {required bool reachable}) {
    emit(state.copyWith(
      accountState: state.accountState.copyWith(
        ledgerBalance: MoneyMath.toDec(snapshot['balance']),
        usedMargin: MoneyMath.toDec(snapshot['used_margin']),
        unrealizedPnl: state.openPositions.fold<Decimal>(Decimal.zero, (s, p) => s + p.unrealizedPnl),
      ),
      isServerReachable: reachable,
      lastServerSyncAt: DateTime.now(),
    ));
    _syncUserCache(state.accountState.userId);
  }

  // ──────────────────────────────────────────────── local simulation wallet ───

  /// Local-simulation balance override.
  ///
  /// Demo / test only: with a live session the balance always comes from the
  /// `wallets` row, so this is a no-op there. Real credits and debits go through
  /// [adminAdjustBalance], [requestWithdrawal] or the deposit Edge Function.
  @visibleForTesting
  void setBalance(String userId, Decimal balance) {
    if (_serverAuthoritative) return;

    if (state.accountState.userId == userId) {
      emit(state.copyWith(
        accountState: state.accountState.copyWith(ledgerBalance: balance),
      ));
    }
    final cached = _userAccountCache[userId];
    _userAccountCache[userId] = cached != null
        ? cached.copyWith(ledgerBalance: balance)
        : TradingAccountState(
            accountId: _accountIdFor(userId),
            userId: userId,
            currency: 'USD',
            ledgerBalance: balance,
            unrealizedPnl: Decimal.zero,
            usedMargin: Decimal.zero,
            leverage: Decimal.fromInt(AppConstants.defaultLeverage),
          );
  }

  /// Mirror a credit that the SERVER has already committed (admin approval,
  /// verified deposit). It never creates money on its own: with a live session
  /// it just re-reads the authoritative wallet.
  Future<void> depositFunds(String userId, Decimal amount) async {
    if (_serverAuthoritative) {
      await refreshBalance();
      return;
    }
    final target = _userAccountCache[userId] ??
        (state.accountState.userId == userId ? state.accountState : null);
    final next = (target?.ledgerBalance ?? Decimal.zero) + amount;
    setBalance(userId, next);
  }

  /// Mirror a debit the server already committed. See [requestWithdrawal] for
  /// the authoritative path.
  Future<void> withdrawFunds(String userId, Decimal amount) async {
    if (_serverAuthoritative) {
      await refreshBalance();
      return;
    }
    final target = _userAccountCache[userId] ??
        (state.accountState.userId == userId ? state.accountState : null);
    final current = target?.ledgerBalance ?? Decimal.zero;
    final next = current - amount;
    setBalance(userId, next < Decimal.zero ? Decimal.zero : next);
  }

  /// Authoritative, audited admin credit/debit. Requires an admin JWT.
  Future<Map<String, dynamic>> adminAdjustBalance({
    required String userId,
    required Decimal amount,
    required String reason,
    String? requestId,
  }) async {
    final result = await _trades.adminAdjustBalance(
      userId: userId,
      amount: amount,
      reason: reason,
      requestId: requestId ?? 'adj-${_uuid.v4()}',
    );
    if (state.accountState.userId == userId) await refreshBalance();
    return result;
  }

  /// Authoritative withdrawal request. Funds are held server-side; approval is
  /// a separate admin action.
  Future<Map<String, dynamic>> requestWithdrawal({
    required Decimal amount,
    String? method,
    String? destination,
    String? requestId,
  }) async {
    final result = await _trades.requestWithdrawal(
      amount: amount,
      method: method,
      destination: destination,
      requestId: requestId ?? 'wd-${_uuid.v4()}',
    );
    await refreshBalance();
    return result;
  }

  // ───────────────────────────────────────────────────────────── quote feed ───

  /// FX rate (USD per unit of quote currency) for an instrument.
  Decimal _rateFor(String symbol) => _feed.quoteToUsdRate(symbol);

  // No client prices are sent to the server any more (no `p_quotes`): every
  // fill, SL/TP and stop-out uses the server's own fresh publisher quote, and
  // the RPCs answer NO_QUOTE when none exists. Local quotes are display-only.

  void _listenToMarketTicks() {
    _feedSub?.cancel();
    _feedSub = _feed.tickStream.listen(_processPriceTick);
  }

  /// Recompute a position's floating PnL against the current book (display only).
  TradeEntity _repriceForDisplay(TradeEntity pos) {
    final inst = _feed.getInstrument(pos.symbol);
    if (inst == null) return pos;
    final execPrice = pos.isBuy ? inst.bid : inst.ask;
    return pos.copyWith(
      currentPrice: execPrice,
      unrealizedPnl: MoneyMath.calcUnrealizedPnL(
        isBuy: pos.isBuy,
        openPrice: pos.openPrice,
        currentPrice: execPrice,
        lots: pos.lots,
        contractSize: pos.contractSize,
        quoteToUsdRate: _rateFor(pos.symbol),
      ),
    );
  }

  /// Live price tick.
  ///
  /// In server mode this only refreshes the *display* and asks the database to
  /// run the authoritative risk pass on a throttle. It no longer closes
  /// positions, fills pending orders or liquidates locally — those are money
  /// operations and belong to `rpc_sync_account`.
  void _processPriceTick(InstrumentEntity inst) {
    if (state.openPositions.isEmpty && state.pendingOrders.isEmpty) return;

    final affects = state.openPositions.any((p) => p.symbol == inst.symbol) ||
        state.pendingOrders.any((p) => p.symbol == inst.symbol);
    if (!affects) return;

    if (_serverAuthoritative) {
      final updated = state.openPositions
          .map((p) => p.symbol == inst.symbol ? _repriceForDisplay(p) : p)
          .toList();

      final totalUnrealized = updated.fold<Decimal>(Decimal.zero, (s, p) => s + p.unrealizedPnl);
      final account = state.accountState.copyWith(unrealizedPnl: totalUnrealized);

      emit(state.copyWith(
        openPositions: updated,
        accountState: account,
        lastAlertMessage: account.isMarginCall ? _marginCallMessage(account) : null,
        lastAlertTime: account.isMarginCall ? DateTime.now() : null,
      ));

      _maybeSyncWithServer();
      return;
    }

    _simulateTick(inst);
  }

  String _marginCallMessage(TradingAccountState account) =>
      '⚠️ MARGIN CALL: margin level ${account.marginLevelPercent.toStringAsFixed(1)}% is below '
      '${AppConstants.marginCallLevelPercent.toStringAsFixed(0)}%. Deposit funds or reduce exposure.';

  /// Throttled authoritative risk pass.
  Future<void> _maybeSyncWithServer() async {
    if (_syncInFlight) return;
    final now = DateTime.now();
    if (_lastSyncAttempt != null && now.difference(_lastSyncAttempt!) < _syncInterval) return;
    _lastSyncAttempt = now;
    _syncInFlight = true;

    try {
      final result = await _trades.syncAccount();
      if (isClosed) return;

      if (result == null) {
        // Do not invent financial state while the server is unreachable.
        emit(state.copyWith(isServerReachable: false));
        return;
      }

      final closed = (result['closed'] as List?) ?? const [];
      final triggered = (result['triggered'] as List?) ?? const [];
      final liquidations = (result['liquidations'] as num?)?.toInt() ?? 0;

      if (closed.isNotEmpty || triggered.isNotEmpty || (result['expired'] as num?) != 0) {
        await reloadFromServer();
      } else {
        final account = result['account'];
        if (account is Map) {
          _applyServerSnapshot(Map<String, dynamic>.from(account), reachable: true);
        }
      }
      if (isClosed) return;

      final alert = _alertFor(closed, liquidations, result['margin_call'] == true);
      if (alert != null) {
        emit(state.copyWith(lastAlertMessage: alert, lastAlertTime: DateTime.now()));
      }
    } finally {
      _syncInFlight = false;
    }
  }

  String? _alertFor(List<dynamic> closed, int liquidations, bool marginCall) {
    if (liquidations > 0) {
      final symbols = closed
          .whereType<Map>()
          .where((c) => c['close_reason'] == AppConstants.closeReasonStopOut)
          .map((c) => c['symbol'])
          .join(', ');
      return '⚠️ STOP-OUT: $liquidations position(s) auto-liquidated'
          '${symbols.isEmpty ? '' : ' ($symbols)'} to protect your equity.';
    }
    for (final c in closed.whereType<Map>()) {
      if (c['close_reason'] == AppConstants.closeReasonStopLoss) {
        return '🛑 Stop Loss hit on ${c['symbol']} — position closed at ${c['close_price']}.';
      }
      if (c['close_reason'] == AppConstants.closeReasonTakeProfit) {
        return '🎯 Take Profit hit on ${c['symbol']} — position closed at ${c['close_price']}.';
      }
    }
    if (marginCall) return _marginCallMessage(state.accountState);
    return null;
  }

  // ─────────────────────────────────────────────────────── order submission ───

  /// Validate a request before it leaves the device.
  ///
  /// This is a UX fast-path only — `rpc_open_trade` performs the identical
  /// checks and is the one that actually decides. None of these existed before,
  /// so a 0-lot order, 1:9999 leverage, or a take profit on the wrong side of
  /// the entry (which fires on the next tick) all went straight through.
  void _validateOrderRequest({
    required InstrumentEntity instrument,
    required OrderSide side,
    required OrderType type,
    required Decimal lots,
    required Decimal leverage,
    required Decimal entryPrice,
    Decimal? targetPrice,
    Decimal? stopLoss,
    Decimal? takeProfit,
  }) {
    if (lots <= Decimal.zero) {
      throw Exception('Volume must be greater than zero.');
    }
    if (lots < AppConstants.minLots || lots > AppConstants.maxLots) {
      throw Exception('Volume must be between ${MoneyMath.formatLots(AppConstants.minLots)} '
          'and ${MoneyMath.formatLots(AppConstants.maxLots)} lots.');
    }
    final steps = MoneyMath.divide(lots, AppConstants.lotStep, scale: 6);
    if (steps != steps.round()) {
      throw Exception('Volume must be a multiple of '
          '${MoneyMath.formatLots(AppConstants.lotStep)} lots.');
    }
    if (leverage <= Decimal.zero) {
      throw Exception('Leverage must be greater than zero.');
    }
    if (!AppConstants.availableLeverages.contains(leverage.toBigInt().toInt())) {
      throw Exception('Leverage 1:${leverage.toStringAsFixed(0)} is not offered. '
          'Choose one of ${AppConstants.availableLeverages.join(', ')}.');
    }

    final isBuy = side == OrderSide.buy;

    if (type != OrderType.market) {
      if (targetPrice == null || targetPrice <= Decimal.zero) {
        throw Exception('Enter a valid trigger price for this ${type.name} order.');
      }
      final ask = instrument.ask;
      final bid = instrument.bid;
      if (type == OrderType.limit && isBuy && targetPrice >= ask) {
        throw Exception('A BUY LIMIT must be below the current ask '
            '(${MoneyMath.formatDec(ask, instrument.decimals)}).');
      }
      if (type == OrderType.limit && !isBuy && targetPrice <= bid) {
        throw Exception('A SELL LIMIT must be above the current bid '
            '(${MoneyMath.formatDec(bid, instrument.decimals)}).');
      }
      if (type == OrderType.stop && isBuy && targetPrice <= ask) {
        throw Exception('A BUY STOP must be above the current ask '
            '(${MoneyMath.formatDec(ask, instrument.decimals)}).');
      }
      if (type == OrderType.stop && !isBuy && targetPrice >= bid) {
        throw Exception('A SELL STOP must be below the current bid '
            '(${MoneyMath.formatDec(bid, instrument.decimals)}).');
      }
    }

    if (stopLoss != null) {
      if (stopLoss <= Decimal.zero) throw Exception('Stop loss must be a positive price.');
      if (isBuy && stopLoss >= entryPrice) {
        throw Exception('For a BUY the stop loss must be below the entry price '
            '(${MoneyMath.formatDec(entryPrice, instrument.decimals)}).');
      }
      if (!isBuy && stopLoss <= entryPrice) {
        throw Exception('For a SELL the stop loss must be above the entry price '
            '(${MoneyMath.formatDec(entryPrice, instrument.decimals)}).');
      }
    }

    if (takeProfit != null) {
      if (takeProfit <= Decimal.zero) throw Exception('Take profit must be a positive price.');
      if (isBuy && takeProfit <= entryPrice) {
        throw Exception('For a BUY the take profit must be above the entry price '
            '(${MoneyMath.formatDec(entryPrice, instrument.decimals)}).');
      }
      if (!isBuy && takeProfit >= entryPrice) {
        throw Exception('For a SELL the take profit must be below the entry price '
            '(${MoneyMath.formatDec(entryPrice, instrument.decimals)}).');
      }
    }
  }

  /// Submit an order (Market, Limit or Stop).
  ///
  /// Returns true only when the authoritative side accepted it. Any rejection
  /// throws and leaves local state untouched — there is no longer a
  /// "RPC failed, write it locally anyway" path.
  Future<bool> placeOrder({
    required InstrumentEntity instrument,
    required OrderSide side,
    required OrderType type,
    required Decimal lots,
    Decimal? targetPrice,
    Decimal? stopLoss,
    Decimal? takeProfit,
    Decimal? leverage,
    bool canTrade = true,
    String? clientRequestId,
  }) async {
    if (!canTrade) {
      throw Exception('KYC Verification required to open live positions.');
    }
    if (_openInFlight) {
      // Double tap / duplicated gesture: ignore rather than send twice.
      return false;
    }

    final activeLev = leverage ?? state.accountState.leverage;
    final execPrice = side == OrderSide.buy ? instrument.ask : instrument.bid;
    final isMarket = type == OrderType.market;
    final entryPrice = isMarket ? execPrice : (targetPrice ?? execPrice);

    _validateOrderRequest(
      instrument: instrument,
      side: side,
      type: type,
      lots: lots,
      leverage: activeLev,
      entryPrice: entryPrice,
      targetPrice: targetPrice,
      stopLoss: stopLoss,
      takeProfit: takeProfit,
    );

    final rate = _feed.quoteToUsdRateFor(instrument);
    final requiredMargin = MoneyMath.calcRequiredMargin(
      lots: lots,
      contractSize: instrument.contractSize,
      openPrice: entryPrice,
      leverage: activeLev,
      quoteToUsdRate: rate,
    );

    // Pending orders reserve no margin until they trigger, so only a market
    // order is pre-checked here (the server re-checks both).
    if (isMarket && requiredMargin > state.accountState.freeMargin) {
      throw Exception(
        'Insufficient Free Margin! Required: ${MoneyMath.formatCurrency(requiredMargin)}, '
        'Available: ${MoneyMath.formatCurrency(state.accountState.freeMargin)}',
      );
    }

    _openInFlight = true;
    emit(state.copyWith(isSubmitting: true));

    try {
      if (_serverAuthoritative) {
        await _placeOrderOnServer(
          instrument: instrument,
          side: side,
          type: type,
          lots: lots,
          leverage: activeLev,
          targetPrice: targetPrice,
          stopLoss: stopLoss,
          takeProfit: takeProfit,
          requestedPrice: isMarket ? execPrice : null,
          clientRequestId: clientRequestId ?? 'ord-${_uuid.v4()}',
        );
      } else {
        _placeOrderLocally(
          instrument: instrument,
          side: side,
          type: type,
          lots: lots,
          leverage: activeLev,
          entryPrice: entryPrice,
          execPrice: execPrice,
          targetPrice: targetPrice,
          stopLoss: stopLoss,
          takeProfit: takeProfit,
          requiredMargin: requiredMargin,
          rate: rate,
        );
      }
      return true;
    } finally {
      _openInFlight = false;
      if (!isClosed) emit(state.copyWith(isSubmitting: false));
    }
  }

  Future<void> _placeOrderOnServer({
    required InstrumentEntity instrument,
    required OrderSide side,
    required OrderType type,
    required Decimal lots,
    required Decimal leverage,
    required String clientRequestId,
    Decimal? targetPrice,
    Decimal? stopLoss,
    Decimal? takeProfit,
    Decimal? requestedPrice,
  }) async {
    // Throws TradeServiceException on any rejection; nothing local changes.
    await _trades.openTrade(
      symbol: instrument.symbol,
      side: side,
      type: type,
      lots: lots,
      leverage: leverage,
      clientRequestId: clientRequestId,
      targetPrice: targetPrice,
      stopLoss: stopLoss,
      takeProfit: takeProfit,
      requestedPrice: requestedPrice,
    );

    // Re-read the authoritative book rather than trusting our own arithmetic.
    await reloadFromServer();
  }

  void _placeOrderLocally({
    required InstrumentEntity instrument,
    required OrderSide side,
    required OrderType type,
    required Decimal lots,
    required Decimal leverage,
    required Decimal entryPrice,
    required Decimal execPrice,
    required Decimal requiredMargin,
    required Decimal rate,
    Decimal? targetPrice,
    Decimal? stopLoss,
    Decimal? takeProfit,
  }) {
    final isMarket = type == OrderType.market;
    final tradeId = 'POS-${_uuid.v4().substring(0, 8).toUpperCase()}';
    final orderId = 'ORD-${_uuid.v4().substring(0, 8).toUpperCase()}';

    final newTrade = TradeEntity(
      id: tradeId,
      orderId: orderId,
      symbol: instrument.symbol,
      side: side,
      type: type,
      status: isMarket ? OrderStatus.open : OrderStatus.pending,
      lots: lots,
      contractSize: instrument.contractSize,
      openPrice: entryPrice,
      targetPrice: targetPrice,
      currentPrice: execPrice,
      unrealizedPnl: Decimal.zero,
      requiredMargin: isMarket ? requiredMargin : Decimal.zero,
      stopLoss: stopLoss,
      takeProfit: takeProfit,
      leverage: leverage,
      quoteToUsdRate: rate,
      requestedPrice: isMarket ? execPrice : null,
      spreadAtOpen: instrument.spread,
      openTime: DateTime.now(),
    );

    if (!isMarket) {
      emit(state.copyWith(pendingOrders: [newTrade, ...state.pendingOrders]));
      _syncUserCache(state.accountState.userId);
      return;
    }

    _ledgerRepo.recordMarginLock(
      userId: state.accountState.userId,
      tradeId: tradeId,
      marginAmount: requiredMargin,
      symbol: instrument.symbol,
    );

    final updatedPositions = [newTrade, ...state.openPositions];
    emit(state.copyWith(
      openPositions: updatedPositions,
      accountState: state.accountState.copyWith(
        usedMargin: updatedPositions.fold<Decimal>(Decimal.zero, (s, p) => s + p.requiredMargin),
        unrealizedPnl: updatedPositions.fold<Decimal>(Decimal.zero, (s, p) => s + p.unrealizedPnl),
      ),
    ));
    _syncUserCache(state.accountState.userId);
  }

  // ───────────────────────────────────────────────────────────────── closing ──

  /// Close an open position.
  ///
  /// Server mode sends no price: `rpc_close_trade` resolves the authoritative
  /// bid/ask itself, settles atomically and returns the realized result. A
  /// second request for the same trade gets `already_closed` instead of a second
  /// settlement.
  Future<void> closePosition(String tradeId) async {
    if (_inFlightCloses.contains(tradeId)) return;
    final idx = state.openPositions.indexWhere((t) => t.id == tradeId);
    if (idx == -1) return;

    _inFlightCloses.add(tradeId);
    try {
      if (_serverAuthoritative) {
        final Map<String, dynamic> result;
        try {
          result = await _trades.closeTrade(tradeId: tradeId);
        } on TradeServiceException catch (e) {
          // e.g. NO_QUOTE when the market is closed: tell the user, keep the position.
          if (!isClosed) {
            emit(state.copyWith(lastErrorMessage: e.userMessage, lastErrorTime: DateTime.now()));
          }
          return;
        }
        if (isClosed) return;
        await reloadFromServer();

        if (result['status'] == 'already_closed' && !isClosed) {
          emit(state.copyWith(
            lastAlertMessage: 'Position was already closed '
                '(${result['close_reason'] ?? 'server'}).',
            lastAlertTime: DateTime.now(),
          ));
        }
        return;
      }

      _closePositionLocally(idx, AppConstants.closeReasonManual);
    } finally {
      _inFlightCloses.remove(tradeId);
    }
  }

  void _closePositionLocally(int idx, String reason) {
    final pos = state.openPositions[idx];
    final closed = pos.copyWith(
      status: reason == AppConstants.closeReasonStopOut
          ? OrderStatus.liquidated
          : OrderStatus.closed,
      closePrice: pos.currentPrice,
      realizedPnl: pos.unrealizedPnl,
      unrealizedPnl: Decimal.zero,
      closeTime: DateTime.now(),
      closeReason: reason,
    );

    _settleClosedPositionLedger(closed);

    final updatedOpen = List<TradeEntity>.from(state.openPositions)..removeAt(idx);
    emit(state.copyWith(
      openPositions: updatedOpen,
      closedTrades: [closed, ...state.closedTrades],
      accountState: state.accountState.copyWith(
        // Realized PnL settles into the simulated balance exactly once.
        ledgerBalance: state.accountState.ledgerBalance + closed.realizedPnl - closed.swap,
        usedMargin: updatedOpen.fold<Decimal>(Decimal.zero, (s, p) => s + p.requiredMargin),
        unrealizedPnl: updatedOpen.fold<Decimal>(Decimal.zero, (s, p) => s + p.unrealizedPnl),
      ),
    ));
    _syncUserCache(state.accountState.userId);
  }

  /// Cancel a pending limit/stop order.
  Future<void> cancelPendingOrder(String orderId) async {
    if (_inFlightCancels.contains(orderId)) return;
    _inFlightCancels.add(orderId);
    try {
      if (_serverAuthoritative) {
        final Map<String, dynamic> result;
        try {
          result = await _trades.cancelPendingOrder(orderId);
        } on TradeServiceException catch (e) {
          if (!isClosed) {
            emit(state.copyWith(lastErrorMessage: e.userMessage, lastErrorTime: DateTime.now()));
          }
          return;
        }
        if (isClosed) return;
        await reloadFromServer();

        if (result['status'] == 'already_filled' && !isClosed) {
          emit(state.copyWith(
            lastAlertMessage: 'Order already filled — it can no longer be cancelled.',
            lastAlertTime: DateTime.now(),
          ));
        }
        return;
      }

      final remaining = state.pendingOrders
          .where((o) => o.id != orderId && o.orderId != orderId)
          .toList();
      emit(state.copyWith(pendingOrders: remaining));
      _syncUserCache(state.accountState.userId);
    } finally {
      _inFlightCancels.remove(orderId);
    }
  }

  /// Double-entry bookkeeping for a simulated close.
  ///
  /// The spread markup fee that used to be posted here on every open has been
  /// removed: the client already pays the spread implicitly by buying at the ask
  /// and selling at the bid, so debiting it again charged them twice — and the
  /// amount itself was wrong (it omitted the contract size, understating the
  /// broker's revenue by 100x for gold).
  void _settleClosedPositionLedger(TradeEntity closed) {
    _ledgerRepo.recordMarginRelease(
      userId: state.accountState.userId,
      tradeId: closed.id,
      marginAmount: closed.requiredMargin,
      symbol: closed.symbol,
    );
    _ledgerRepo.recordRealizedPnl(
      userId: state.accountState.userId,
      tradeId: closed.id,
      realizedPnl: closed.realizedPnl,
      symbol: closed.symbol,
    );
  }

  // ───────────────────────────────────────────── local simulation risk pass ───

  /// Fill price for a triggered stop loss: the current executable side of the
  /// book (bid for a long, ask for a short), never better than the stop level.
  /// Through a gap this is the post-gap price, not the stop level.
  @visibleForTesting
  static Decimal stopLossFillPrice({
    required bool isBuy,
    required Decimal stopLoss,
    required Decimal bid,
    required Decimal ask,
  }) {
    if (isBuy) return bid < stopLoss ? bid : stopLoss;
    return ask > stopLoss ? ask : stopLoss;
  }

  /// Local simulation of the server risk engine, used only when no session
  /// exists. Mirrors `fx_evaluate_account`: expire, trigger, SL/TP, then
  /// liquidate in a bounded loop until the margin level recovers.
  void _simulateTick(InstrumentEntity inst) {
    final bid = inst.bid;
    final ask = inst.ask;
    final rate = _feed.quoteToUsdRateFor(inst);

    final positions = <TradeEntity>[];
    final newlyClosed = <TradeEntity>[];

    for (final pos in state.openPositions) {
      if (pos.symbol != inst.symbol) {
        positions.add(pos);
        continue;
      }

      final execPrice = pos.isBuy ? bid : ask;

      Decimal? triggerPrice;
      String? reason;
      // Risk before reward: a candle that spans both levels stops out first.
      // A stop loss is a STOP order: once triggered it fills at the current
      // executable price, so a gap through the level fills at the post-gap
      // price (mirrors fx_evaluate_account). Take profit fills at its level.
      if (pos.isBuy) {
        if (pos.stopLoss != null && bid <= pos.stopLoss!) {
          triggerPrice = stopLossFillPrice(isBuy: true, stopLoss: pos.stopLoss!, bid: bid, ask: ask);
          reason = AppConstants.closeReasonStopLoss;
        } else if (pos.takeProfit != null && bid >= pos.takeProfit!) {
          triggerPrice = pos.takeProfit;
          reason = AppConstants.closeReasonTakeProfit;
        }
      } else {
        if (pos.stopLoss != null && ask >= pos.stopLoss!) {
          triggerPrice = stopLossFillPrice(isBuy: false, stopLoss: pos.stopLoss!, bid: bid, ask: ask);
          reason = AppConstants.closeReasonStopLoss;
        } else if (pos.takeProfit != null && ask <= pos.takeProfit!) {
          triggerPrice = pos.takeProfit;
          reason = AppConstants.closeReasonTakeProfit;
        }
      }

      if (reason != null && triggerPrice != null) {
        final realized = MoneyMath.calcUnrealizedPnL(
          isBuy: pos.isBuy,
          openPrice: pos.openPrice,
          currentPrice: triggerPrice,
          lots: pos.lots,
          contractSize: pos.contractSize,
          quoteToUsdRate: rate,
        );
        newlyClosed.add(pos.copyWith(
          status: OrderStatus.closed,
          closePrice: triggerPrice,
          currentPrice: triggerPrice,
          unrealizedPnl: Decimal.zero,
          realizedPnl: realized,
          closeTime: DateTime.now(),
          closeReason: reason,
        ));
        continue;
      }

      positions.add(pos.copyWith(
        currentPrice: execPrice,
        unrealizedPnl: MoneyMath.calcUnrealizedPnL(
          isBuy: pos.isBuy,
          openPrice: pos.openPrice,
          currentPrice: execPrice,
          lots: pos.lots,
          contractSize: pos.contractSize,
          quoteToUsdRate: rate,
        ),
      ));
    }

    // Pending order triggers, on the correct side of the book.
    final remainingPending = <TradeEntity>[];
    for (final order in state.pendingOrders) {
      if (order.symbol != inst.symbol || order.targetPrice == null) {
        remainingPending.add(order);
        continue;
      }

      Decimal? fillPrice;
      if (order.type == OrderType.limit) {
        if (order.isBuy && ask <= order.targetPrice!) fillPrice = ask;
        if (order.isSell && bid >= order.targetPrice!) fillPrice = bid;
      } else if (order.type == OrderType.stop) {
        if (order.isBuy && ask >= order.targetPrice!) fillPrice = ask;
        if (order.isSell && bid <= order.targetPrice!) fillPrice = bid;
      }

      if (fillPrice == null) {
        remainingPending.add(order);
        continue;
      }

      // Margin is validated at TRIGGER time, not at placement time.
      final margin = MoneyMath.calcRequiredMargin(
        lots: order.lots,
        contractSize: order.contractSize,
        openPrice: fillPrice,
        leverage: order.leverage,
        quoteToUsdRate: rate,
      );
      final usedSoFar = positions.fold<Decimal>(Decimal.zero, (s, p) => s + p.requiredMargin);
      final unrealSoFar = positions.fold<Decimal>(Decimal.zero, (s, p) => s + p.unrealizedPnl);
      final free = (state.accountState.ledgerBalance + unrealSoFar) - usedSoFar;

      if (free < margin) {
        remainingPending.add(order.copyWith(
          status: OrderStatus.rejected,
          closeReason: 'INSUFFICIENT_MARGIN',
        ));
        continue;
      }

      positions.add(order.copyWith(
        status: OrderStatus.open,
        openPrice: fillPrice,
        currentPrice: fillPrice,
        requiredMargin: margin,
        quoteToUsdRate: rate,
        openTime: DateTime.now(),
      ));
      _ledgerRepo.recordMarginLock(
        userId: state.accountState.userId,
        tradeId: order.id,
        marginAmount: margin,
        symbol: order.symbol,
      );
    }

    // Settle SL/TP fills into the simulated balance.
    var balance = state.accountState.ledgerBalance;
    for (final closed in newlyClosed) {
      _settleClosedPositionLedger(closed);
      balance += closed.realizedPnl - closed.swap;
    }

    var account = state.accountState.copyWith(
      ledgerBalance: balance,
      usedMargin: positions.fold<Decimal>(Decimal.zero, (s, p) => s + p.requiredMargin),
      unrealizedPnl: positions.fold<Decimal>(Decimal.zero, (s, p) => s + p.unrealizedPnl),
    );

    // Stop-out: keep liquidating the worst loser until the level recovers, with
    // a hard pass cap. Previously exactly one position was closed per tick and
    // the function returned, so an account could stay far below the stop-out
    // level until the next tick happened to arrive.
    var liquidations = 0;
    while (positions.isNotEmpty &&
        account.isStopOutLiquidation &&
        liquidations < AppConstants.maxLiquidationPassesPerCycle) {
      positions.sort((a, b) => a.unrealizedPnl.compareTo(b.unrealizedPnl));
      final victim = positions.removeAt(0);

      final liquidated = victim.copyWith(
        status: OrderStatus.liquidated,
        closePrice: victim.currentPrice,
        unrealizedPnl: Decimal.zero,
        realizedPnl: victim.unrealizedPnl,
        closeTime: DateTime.now(),
        closeReason: AppConstants.closeReasonStopOut,
      );
      newlyClosed.add(liquidated);
      _settleClosedPositionLedger(liquidated);

      balance += liquidated.realizedPnl - liquidated.swap;
      account = account.copyWith(
        ledgerBalance: balance,
        usedMargin: positions.fold<Decimal>(Decimal.zero, (s, p) => s + p.requiredMargin),
        unrealizedPnl: positions.fold<Decimal>(Decimal.zero, (s, p) => s + p.unrealizedPnl),
      );
      liquidations++;
    }

    String? alert;
    if (liquidations > 0) {
      alert = '⚠️ STOP-OUT: $liquidations position(s) auto-liquidated to protect equity.';
    } else if (account.isMarginCall) {
      alert = _marginCallMessage(account);
    }

    emit(state.copyWith(
      openPositions: positions,
      closedTrades: [...newlyClosed, ...state.closedTrades],
      pendingOrders: remainingPending.where((o) => o.isPending).toList(),
      accountState: account,
      lastAlertMessage: alert,
      lastAlertTime: alert == null ? null : DateTime.now(),
    ));

    if (newlyClosed.isNotEmpty) _syncUserCache(state.accountState.userId);
  }

  @override
  Future<void> close() {
    _feedSub?.cancel();
    _unsubscribeRealtime();
    return super.close();
  }
}

typedef TradingEngineBloc = TradingEngineCubit;
