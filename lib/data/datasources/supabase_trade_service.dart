import 'dart:convert';
import 'package:decimal/decimal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/math/money_math.dart';
import '../../domain/entities/trading_entities.dart';

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

  /// Execute Atomic Order via Supabase Stored Procedure (Margin Hold Check)
  Future<Map<String, dynamic>?> openTradeRpc({
    required TradeEntity trade,
  }) async {
    final client = _client;
    if (client == null) return null;

    try {
      final res = await client.rpc('rpc_open_trade', params: {
        'p_trade_id': trade.id,
        'p_order_id': trade.orderId,
        'p_symbol': trade.symbol,
        'p_side': trade.isBuy ? 'buy' : 'sell',
        'p_lots': trade.lots.toDouble(),
        'p_contract_size': trade.contractSize.toDouble(),
        'p_open_price': trade.openPrice.toDouble(),
        'p_leverage': trade.leverage.toDouble(),
        'p_stop_loss': trade.stopLoss?.toDouble(),
        'p_take_profit': trade.takeProfit?.toDouble(),
      });
      return res is Map<String, dynamic> ? res : null;
    } catch (e) {
      // Return null to trigger client fallback if RPC is not yet loaded in Supabase
      return null;
    }
  }

  /// Close Trade via Supabase Stored Procedure (PnL Settlement & Margin Release)
  Future<Map<String, dynamic>?> closeTradeRpc({
    required String tradeId,
    required double closePrice,
  }) async {
    final client = _client;
    if (client == null) return null;

    try {
      final res = await client.rpc('rpc_close_trade', params: {
        'p_trade_id': tradeId,
        'p_close_price': closePrice,
      });
      return res is Map<String, dynamic> ? res : null;
    } catch (e) {
      return null;
    }
  }

  /// Fetch User Wallet (Balance & Held Margin)
  Future<Map<String, dynamic>?> fetchUserWallet(String userId) async {
    final client = _client;
    if (client == null) return null;

    try {
      final res = await client
          .from('wallets')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      return res;
    } catch (_) {
      return null;
    }
  }

  /// Save / Insert trade into Supabase 'trades' table (direct fallback)
  Future<void> insertTrade({
    required TradeEntity trade,
    required String userId,
  }) async {
    final client = _client;
    if (client == null) return;

    try {
      await client.from('trades').upsert({
        'id': trade.id,
        'user_id': userId,
        'order_id': trade.orderId,
        'symbol': trade.symbol,
        'side': trade.isBuy ? 'buy' : 'sell',
        'type': trade.type.name,
        'status': trade.status.name,
        'lots': trade.lots.toDouble(),
        'contract_size': trade.contractSize.toDouble(),
        'open_price': trade.openPrice.toDouble(),
        'target_price': trade.targetPrice?.toDouble(),
        'stop_loss': trade.stopLoss?.toDouble(),
        'take_profit': trade.takeProfit?.toDouble(),
        'required_margin': trade.requiredMargin.toDouble(),
        'leverage': trade.leverage.toDouble(),
        'open_time': trade.openTime.toIso8601String(),
      });
    } catch (e) {
      // Graceful fallback for offline / unconfigured database table
    }
  }

  /// Update closed trade in Supabase (direct fallback)
  Future<void> updateClosedTrade(TradeEntity trade) async {
    final client = _client;
    if (client == null) return;

    try {
      await client.from('trades').update({
        'status': trade.status.name,
        'close_price': trade.closePrice?.toDouble(),
        'realized_pnl': trade.realizedPnl.toDouble(),
        'close_time': trade.closeTime?.toIso8601String(),
        'close_reason': trade.closeReason,
      }).eq('id', trade.id);
    } catch (e) {
      // Graceful fallback
    }
  }

  /// Fetch trades from Supabase for user
  Future<List<TradeEntity>> fetchUserTrades(String userId) async {
    final client = _client;
    if (client == null) return [];

    try {
      final res = await client
          .from('trades')
          .select()
          .eq('user_id', userId)
          .order('open_time', ascending: false);

      final list = <TradeEntity>[];
      for (final row in res as List) {
        final side = row['side'] == 'buy' ? OrderSide.buy : OrderSide.sell;
        final statusStr = row['status'] as String? ?? 'open';
        OrderStatus status = OrderStatus.open;
        if (statusStr == 'closed') status = OrderStatus.closed;
        if (statusStr == 'pending') status = OrderStatus.pending;
        if (statusStr == 'liquidated') status = OrderStatus.liquidated;

        list.add(TradeEntity(
          id: row['id'] as String,
          orderId: row['order_id'] as String? ?? 'ORD-00',
          symbol: row['symbol'] as String,
          side: side,
          type: OrderType.market,
          status: status,
          lots: MoneyMath.toDec((row['lots'] as num?)?.toDouble() ?? 0.01),
          contractSize: MoneyMath.toDec((row['contract_size'] as num?)?.toDouble() ?? 100.0),
          openPrice: MoneyMath.toDec((row['open_price'] as num?)?.toDouble() ?? 0.0),
          targetPrice: row['target_price'] != null ? MoneyMath.toDec((row['target_price'] as num).toDouble()) : null,
          closePrice: row['close_price'] != null ? MoneyMath.toDec((row['close_price'] as num).toDouble()) : null,
          stopLoss: row['stop_loss'] != null ? MoneyMath.toDec((row['stop_loss'] as num).toDouble()) : null,
          takeProfit: row['take_profit'] != null ? MoneyMath.toDec((row['take_profit'] as num).toDouble()) : null,
          currentPrice: MoneyMath.toDec((row['open_price'] as num?)?.toDouble() ?? 0.0),
          unrealizedPnl: Decimal.zero,
          realizedPnl: row['realized_pnl'] != null ? MoneyMath.toDec((row['realized_pnl'] as num).toDouble()) : Decimal.zero,
          requiredMargin: MoneyMath.toDec((row['required_margin'] as num?)?.toDouble() ?? 0.0),
          leverage: MoneyMath.toDec((row['leverage'] as num?)?.toDouble() ?? 100.0),
          openTime: DateTime.tryParse(row['open_time'] as String? ?? '') ?? DateTime.now(),
          closeTime: row['close_time'] != null ? DateTime.tryParse(row['close_time'] as String) : null,
          closeReason: row['close_reason'] as String?,
        ));
      }
      return list;
    } catch (_) {
      return [];
    }
  }
}
