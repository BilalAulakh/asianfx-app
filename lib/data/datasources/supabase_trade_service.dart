import 'package:decimal/decimal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/math/money_math.dart';
import '../../domain/entities/trading_entities.dart';

/// Raised when an authoritative trading RPC rejects or cannot reach the server.
///
/// The old service swallowed every error and returned `null`, which the cubit
/// then treated as "RPC unavailable, write the trade directly instead". That
/// silently converted a *rejection* (insufficient margin, bad price, KYC block)
/// into a locally-created position with no margin held anywhere. Failures must
/// now surface.
class TradeServiceException implements Exception {
  /// Machine-readable prefix raised by the RPC, e.g. `INSUFFICIENT_MARGIN`.
  final String code;
  final String message;

  const TradeServiceException(this.code, this.message);

  bool get isOffline => code == 'OFFLINE';

  /// Text suitable for a snackbar. Codes the user can act on get a plain
  /// explanation; everything else shows the server's own message.
  String get userMessage => switch (code) {
        'NO_QUOTE' || 'MARKET_CLOSED' =>
          'No live price right now — the market is closed or the price feed is offline. '
              'Please try again when the market is open.',
        'KYC_REQUIRED' => 'Complete identity verification (KYC) before trading.',
        'KYC_REJECTED' => 'Trading is blocked while your verification is rejected. Please contact support.',
        'WALLET_FROZEN' => 'This account is frozen. Please contact support.',
        'QUOTE_OUT_OF_BAND' || 'SLIPPAGE_EXCEEDED' => 'The price moved. Please review the new price and try again.',
        _ => message,
      };

  @override
  String toString() => userMessage;
}

class SupabaseTradeService {
  static final SupabaseTradeService instance = SupabaseTradeService._();
  SupabaseTradeService._();

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool get isAvailable => _client?.auth.currentUser != null;

  SupabaseClient _requireClient() {
    final c = _client;
    if (c == null) {
      throw const TradeServiceException(
          'OFFLINE', 'Trading server is unreachable. Please check your connection.');
    }
    return c;
  }

  /// Turn a Postgres error into a typed exception. The RPCs raise messages of the
  /// form `CODE: human readable explanation`, so the prefix becomes [code].
  Never _rethrowAsService(Object error) {
    if (error is TradeServiceException) throw error;

    var raw = error is PostgrestException ? error.message : error.toString();
    raw = raw.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();

    final match = RegExp(r'^([A-Z][A-Z0-9_]{2,}):\s*(.+)$', dotAll: true).firstMatch(raw);
    if (match != null) {
      throw TradeServiceException(match.group(1)!, match.group(2)!.trim());
    }
    throw TradeServiceException('RPC_FAILED', raw.isEmpty ? 'Trading request failed.' : raw);
  }

  Map<String, dynamic> _asMap(dynamic res) {
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    throw const TradeServiceException(
        'RPC_FAILED', 'Trading server returned an unexpected response.');
  }

  // ───────────────────────────────────────────────────────────── execution ────

  /// Request an order. The SERVER validates the account, resolves the execution
  /// price, calculates margin, reserves it, writes the ledger and returns the
  /// authoritative trade. Throws [TradeServiceException] on any rejection.
  Future<Map<String, dynamic>> openTrade({
    required String symbol,
    required OrderSide side,
    required OrderType type,
    required Decimal lots,
    required Decimal leverage,
    required String clientRequestId,
    Decimal? targetPrice,
    Decimal? stopLoss,
    Decimal? takeProfit,
    Decimal? requestedPrice,
    DateTime? expiresAt,
  }) async {
    final client = _requireClient();
    try {
      final res = await client.rpc('rpc_open_trade', params: {
        'p_symbol': symbol,
        'p_side': side == OrderSide.buy ? 'buy' : 'sell',
        'p_type': type.name,
        'p_lots': lots.toString(),
        'p_leverage': leverage.toString(),
        'p_target_price': targetPrice?.toString(),
        'p_stop_loss': stopLoss?.toString(),
        'p_take_profit': takeProfit?.toString(),
        'p_client_request_id': clientRequestId,
        'p_requested_price': requestedPrice?.toString(),
        'p_expires_at': expiresAt?.toUtc().toIso8601String(),
      });
      return _asMap(res);
    } catch (e) {
      _rethrowAsService(e);
    }
  }

  /// Close a position. Note there is no close-price parameter: the server picks
  /// the authoritative price, which removes the "submit any close price and mint
  /// a profit" hole in the previous `rpc_close_trade(p_trade_id, p_close_price)`.
  Future<Map<String, dynamic>> closeTrade({required String tradeId}) async {
    final client = _requireClient();
    try {
      final res = await client.rpc('rpc_close_trade', params: {
        'p_trade_id': tradeId,
      });
      return _asMap(res);
    } catch (e) {
      _rethrowAsService(e);
    }
  }

  /// Cancel a resting limit/stop order. Returns `already_filled` (rather than
  /// throwing) when a trigger won the race.
  Future<Map<String, dynamic>> cancelPendingOrder(String orderId) async {
    final client = _requireClient();
    try {
      final res = await client.rpc('rpc_cancel_pending_order', params: {
        'p_order_id': orderId,
      });
      return _asMap(res);
    } catch (e) {
      _rethrowAsService(e);
    }
  }

  /// Authoritative risk pass: expiries, pending triggers, SL/TP and stop-out.
  /// Returns `null` when the call could not be made at all (offline), so the UI
  /// can keep showing its local estimate without inventing financial state.
  Future<Map<String, dynamic>?> syncAccount() async {
    final client = _client;
    if (client == null) return null;
    try {
      final res = await client.rpc('rpc_sync_account');
      return res is Map ? Map<String, dynamic>.from(res) : null;
    } catch (_) {
      return null;
    }
  }

  /// Read-only balance / equity / margin snapshot computed by the server.
  Future<Map<String, dynamic>?> fetchAccountState() async {
    final client = _client;
    if (client == null) return null;
    try {
      final res = await client.rpc('rpc_get_account_state');
      return res is Map ? Map<String, dynamic>.from(res) : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> requestWithdrawal({
    required Decimal amount,
    required String requestId,
    String? method,
    String? destination,
  }) async {
    final client = _requireClient();
    try {
      final res = await client.rpc('rpc_request_withdrawal', params: {
        'p_amount': amount.toString(),
        'p_method': method,
        'p_destination': destination,
        'p_request_id': requestId,
      });
      return _asMap(res);
    } catch (e) {
      _rethrowAsService(e);
    }
  }

  /// Authorized, audited admin credit/debit. Replaces the direct `wallets` upsert
  /// that used to run from the admin screen with the user's own anon key.
  Future<Map<String, dynamic>> adminAdjustBalance({
    required String userId,
    required Decimal amount,
    required String reason,
    required String requestId,
  }) async {
    final client = _requireClient();
    try {
      final res = await client.rpc('rpc_admin_adjust_balance', params: {
        'p_user_id': userId,
        'p_amount': amount.toString(),
        'p_reason': reason,
        'p_request_id': requestId,
      });
      return _asMap(res);
    } catch (e) {
      _rethrowAsService(e);
    }
  }

  /// Persist a dealer markup (admin only, clamped 0..500 and audited server-side).
  /// Returns the value the server actually stored.
  Future<int> adminSetMarkup({required String symbol, required int points}) async {
    final client = _requireClient();
    try {
      final res = _asMap(await client.rpc('rpc_admin_set_markup', params: {
        'p_symbol': symbol,
        'p_points': points,
      }));
      return (res['spread_markup_points'] as num).toInt();
    } catch (e) {
      _rethrowAsService(e);
    }
  }

  /// Persist the global spread multiplier (admin only, 1..10, audited).
  Future<double> adminSetSpreadMultiplier(double multiplier) async {
    final client = _requireClient();
    try {
      final res = _asMap(await client.rpc('rpc_admin_set_spread_multiplier', params: {
        'p_multiplier': multiplier,
      }));
      return double.parse(res['spread_multiplier'].toString());
    } catch (e) {
      _rethrowAsService(e);
    }
  }

  // ─────────────────────────────────────────────────────────────── reading ────

  Future<Map<String, dynamic>?> fetchUserWallet(String userId) async {
    final client = _client;
    if (client == null) return null;
    try {
      return await client.from('wallets').select().eq('user_id', userId).maybeSingle();
    } catch (_) {
      return null;
    }
  }

  /// Fetch every trade row for a user, preserving ALL persisted fields.
  ///
  /// The previous implementation hard-coded `type: OrderType.market`, dropped
  /// commission / swap / target price / leverage-specific data and rebuilt
  /// `currentPrice` from `open_price`, so trade history lost the original order
  /// type and every pending order came back as a market trade.
  Future<List<TradeEntity>> fetchUserTrades(String userId) async {
    final client = _client;
    if (client == null) return [];

    try {
      final res = await client
          .from('trades')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return [for (final row in res as List) tradeFromRow(row as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  /// Only the rows that still carry financial exposure. Never limited: an open
  /// position must always be loaded, however old it is.
  Future<List<TradeEntity>> fetchActiveTrades(String userId) async {
    final client = _client;
    if (client == null) return [];
    try {
      final res = await client
          .from('trades')
          .select()
          .eq('user_id', userId)
          .inFilter('status', ['open', 'pending'])
          .order('created_at', ascending: false);
      return [for (final row in res as List) tradeFromRow(row as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  /// Most recent terminal rows for the history tab.
  ///
  /// Kept separate from [fetchActiveTrades] on purpose: a single capped query
  /// over all statuses could push an old-but-still-open position out of the
  /// result window and make it vanish from the UI.
  Future<List<TradeEntity>> fetchTradeHistory(String userId, {int limit = 300}) async {
    final client = _client;
    if (client == null) return [];
    try {
      final res = await client
          .from('trades')
          .select()
          .eq('user_id', userId)
          .inFilter('status', ['closed', 'liquidated', 'cancelled', 'rejected', 'expired'])
          .order('created_at', ascending: false)
          .limit(limit);
      return [for (final row in res as List) tradeFromRow(row as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────── mapping ────

  static OrderSide orderSideFrom(dynamic value) =>
      (value as String?)?.toLowerCase() == 'sell' ? OrderSide.sell : OrderSide.buy;

  /// Tolerant enum decode: an unrecognised or null value falls back to
  /// [fallback] instead of throwing and crashing the history screen.
  static OrderType orderTypeFrom(dynamic value, {OrderType fallback = OrderType.market}) {
    final raw = (value as String?)?.trim();
    if (raw == null || raw.isEmpty) return fallback;
    final key = raw.toLowerCase().replaceAll(RegExp(r'[_\s-]'), '');
    switch (key) {
      case 'market':
        return OrderType.market;
      case 'limit':
        return OrderType.limit;
      case 'stop':
        return OrderType.stop;
      case 'stoplimit':
        return OrderType.stopLimit;
      default:
        return fallback;
    }
  }

  static OrderStatus orderStatusFrom(dynamic value, {OrderStatus fallback = OrderStatus.open}) {
    final raw = (value as String?)?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return fallback;
    switch (raw) {
      case 'pending':
        return OrderStatus.pending;
      case 'open':
        return OrderStatus.open;
      case 'closed':
        return OrderStatus.closed;
      case 'cancelled':
      case 'canceled':
        return OrderStatus.cancelled;
      case 'liquidated':
        return OrderStatus.liquidated;
      case 'rejected':
        return OrderStatus.rejected;
      case 'expired':
        return OrderStatus.expired;
      default:
        return fallback;
    }
  }

  static Decimal? _decOrNull(dynamic v) => v == null ? null : MoneyMath.toDec(v);

  static Decimal _dec(dynamic v, {Decimal? or}) =>
      v == null ? (or ?? Decimal.zero) : MoneyMath.toDec(v);

  /// Database row -> domain entity, preserving every audit field.
  static TradeEntity tradeFromRow(Map<String, dynamic> row) {
    final openPrice = _dec(row['open_price']);
    final closePrice = _decOrNull(row['close_price']);
    final status = orderStatusFrom(row['status']);

    return TradeEntity(
      id: row['id'] as String,
      orderId: row['order_id'] as String? ?? row['id'] as String,
      symbol: row['symbol'] as String,
      side: orderSideFrom(row['side']),
      type: orderTypeFrom(row['type']),
      status: status,
      lots: _dec(row['lots']),
      contractSize: _dec(row['contract_size'], or: Decimal.one),
      openPrice: openPrice,
      targetPrice: _decOrNull(row['target_price']),
      closePrice: closePrice,
      stopLoss: _decOrNull(row['stop_loss']),
      takeProfit: _decOrNull(row['take_profit']),
      // Prefer the last authoritative price; only fall back to the entry.
      currentPrice: _dec(row['current_price'], or: closePrice ?? openPrice),
      unrealizedPnl: _dec(row['unrealized_pnl']),
      realizedPnl: _dec(row['realized_pnl']),
      requiredMargin: _dec(row['required_margin']),
      commission: _dec(row['commission']),
      swap: _dec(row['swap']),
      leverage: _dec(row['leverage'], or: Decimal.fromInt(100)),
      quoteToUsdRate: _dec(row['quote_to_usd_rate'], or: Decimal.one),
      requestedPrice: _decOrNull(row['requested_price']),
      spreadAtOpen: _decOrNull(row['spread_at_open']),
      clientRequestId: row['client_request_id'] as String?,
      openTime: _parseTime(row['open_time']) ?? _parseTime(row['created_at']) ?? DateTime.now(),
      closeTime: _parseTime(row['close_time']),
      closeReason: row['close_reason'] as String?,
    );
  }

  static DateTime? _parseTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}
