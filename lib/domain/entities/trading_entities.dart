import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import '../../core/math/money_math.dart';
import '../../core/constants/app_constants.dart';

enum OrderSide { buy, sell }
enum OrderType { market, limit, stop, stopLimit }
/// Mirrors the `trades.status` CHECK constraint in Postgres. `rejected` is set
/// when a resting order triggers but the account can no longer fund it;
/// `expired` when it outlives `expires_at`.
enum OrderStatus { pending, open, closed, cancelled, liquidated, rejected, expired }
enum ExecutionRouting { bBookInternal, aBookStp, hybrid }

/// Market Financial Instrument with high-precision Decimal pricing
class InstrumentEntity extends Equatable {
  final String symbol;        // XAU/USD, BTC/USD, ETH/USD, EUR/USD, XAG/USD
  final String name;          // Gold vs US Dollar
  final String category;      // metals, crypto, forex, indices
  final Decimal rawBid;
  final Decimal rawAsk;
  final int spreadMarkupPips; // Dynamic spread markup applied by Chief Dealer
  final int decimals;         // Price formatting decimals (e.g. 2 for Gold, 4 for EURUSD)
  final Decimal contractSize; // Gold = 100, Silver = 5000, EURUSD = 100000, BTC = 1
  final double change24h;     // % change
  final Decimal high24h;
  final Decimal low24h;
  final Decimal volume24h;
  final String? iconUrl;
  final bool isFavorite;

  const InstrumentEntity({
    required this.symbol,
    required this.name,
    required this.category,
    required this.rawBid,
    required this.rawAsk,
    this.spreadMarkupPips = 10,
    this.decimals = 2,
    required this.contractSize,
    required this.change24h,
    required this.high24h,
    required this.low24h,
    required this.volume24h,
    this.iconUrl,
    this.isFavorite = false,
  });

  /// Size of one quoted price point (10^-decimals).
  Decimal get pointSize => MoneyMath.pointSize(decimals);

  /// Base currency / asset code of the symbol (`XAU` in `XAU/USD`).
  String get baseCode {
    final i = symbol.indexOf('/');
    return i <= 0 ? symbol : symbol.substring(0, i);
  }

  /// Quote currency code of the symbol (`USD` in `XAU/USD`, `JPY` in `USD/JPY`).
  /// PnL and margin are denominated in this currency before FX conversion.
  String get quoteCode {
    final i = symbol.indexOf('/');
    return (i < 0 || i == symbol.length - 1) ? 'USD' : symbol.substring(i + 1);
  }

  /// Bid price offered to client (rawBid - markup/2), split exactly in Decimal.
  Decimal get bid => MoneyMath.applyHalfSpreadMarkup(
        rawPrice: rawBid,
        markupPoints: spreadMarkupPips,
        decimals: decimals,
        isAsk: false,
      );

  /// Ask price offered to client (rawAsk + markup/2), split exactly in Decimal.
  Decimal get ask => MoneyMath.applyHalfSpreadMarkup(
        rawPrice: rawAsk,
        markupPoints: spreadMarkupPips,
        decimals: decimals,
        isAsk: true,
      );

  /// Mid Price
  Decimal get midPrice => MoneyMath.divide(bid + ask, Decimal.fromInt(2), scale: decimals + 2);

  /// Spread in price units
  Decimal get spread => ask - bid;

  /// Spread expressed in quoted price points.
  double get spreadPoints => MoneyMath.divide(spread, pointSize, scale: 2).toDouble();

  /// Deprecated alias kept for existing UI call sites.
  double get spreadPips => spreadPoints;

  double get changePercent => change24h;
  double get changeAmount => (change24h / 100.0) * midPrice.toDouble();
  bool get isPositiveChange => change24h >= 0;

  InstrumentEntity copyWith({
    String? symbol,
    String? name,
    String? category,
    Decimal? rawBid,
    Decimal? rawAsk,
    int? spreadMarkupPips,
    int? decimals,
    Decimal? contractSize,
    double? change24h,
    Decimal? high24h,
    Decimal? low24h,
    Decimal? volume24h,
    String? iconUrl,
    bool? isFavorite,
  }) {
    return InstrumentEntity(
      symbol: symbol ?? this.symbol,
      name: name ?? this.name,
      category: category ?? this.category,
      rawBid: rawBid ?? this.rawBid,
      rawAsk: rawAsk ?? this.rawAsk,
      spreadMarkupPips: spreadMarkupPips ?? this.spreadMarkupPips,
      decimals: decimals ?? this.decimals,
      contractSize: contractSize ?? this.contractSize,
      change24h: change24h ?? this.change24h,
      high24h: high24h ?? this.high24h,
      low24h: low24h ?? this.low24h,
      volume24h: volume24h ?? this.volume24h,
      iconUrl: iconUrl ?? this.iconUrl,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  @override
  List<Object?> get props => [
        symbol, rawBid, rawAsk, spreadMarkupPips, change24h, isFavorite,
      ];
}

/// Trade / Position Entity with strict Decimal financial accuracy
class TradeEntity extends Equatable {
  final String id;
  final String orderId;
  final String symbol;
  final OrderSide side;
  final OrderType type;
  final OrderStatus status;
  final Decimal lots;
  final Decimal contractSize;
  final Decimal openPrice;
  final Decimal? targetPrice; // For LIMIT / STOP orders
  final Decimal? closePrice;
  final Decimal? stopLoss;
  final Decimal? takeProfit;
  final Decimal currentPrice;
  final Decimal unrealizedPnl;
  final Decimal realizedPnl;
  final Decimal requiredMargin;
  final Decimal commission;
  final Decimal swap;
  final Decimal leverage;
  final ExecutionRouting routing;
  final DateTime openTime;
  final DateTime? closeTime;
  final String? closeReason;

  /// Idempotency key sent with the authoritative open/close RPC so a retried or
  /// double-tapped request can never produce two financial transactions.
  final String? clientRequestId;

  /// FX rate (USD per 1 unit of the instrument's quote currency) captured at
  /// open time. Required to keep margin stable and to audit the PnL conversion.
  final Decimal quoteToUsdRate;

  /// Price the client asked for, kept alongside the filled [openPrice] so
  /// slippage and spread are auditable after the fact.
  final Decimal? requestedPrice;

  /// Dealer spread (in price units) at the moment of execution.
  final Decimal? spreadAtOpen;

  TradeEntity({
    required this.id,
    required this.orderId,
    required this.symbol,
    required this.side,
    required this.type,
    required this.status,
    required this.lots,
    required this.contractSize,
    required this.openPrice,
    this.targetPrice,
    this.closePrice,
    this.stopLoss,
    this.takeProfit,
    required this.currentPrice,
    required this.unrealizedPnl,
    Decimal? realizedPnl,
    required this.requiredMargin,
    Decimal? commission,
    Decimal? swap,
    required this.leverage,
    this.routing = ExecutionRouting.bBookInternal,
    required this.openTime,
    this.closeTime,
    this.closeReason,
    this.clientRequestId,
    Decimal? quoteToUsdRate,
    this.requestedPrice,
    this.spreadAtOpen,
  })  : realizedPnl = realizedPnl ?? Decimal.zero,
        commission = commission ?? Decimal.zero,
        swap = swap ?? Decimal.zero,
        quoteToUsdRate = quoteToUsdRate ?? Decimal.one;

  bool get isOpen => status == OrderStatus.open;
  bool get isClosed => status == OrderStatus.closed || status == OrderStatus.liquidated;
  bool get isPending => status == OrderStatus.pending;
  bool get isCancelled => status == OrderStatus.cancelled;

  /// No further financial event can occur on this order.
  bool get isTerminal =>
      status == OrderStatus.closed ||
      status == OrderStatus.liquidated ||
      status == OrderStatus.cancelled ||
      status == OrderStatus.rejected ||
      status == OrderStatus.expired;
  bool get isBuy => side == OrderSide.buy;
  bool get isSell => side == OrderSide.sell;

  /// Price level a pending order triggers at (falls back to the stored open
  /// price for legacy rows written before target_price was persisted).
  Decimal get triggerPrice => targetPrice ?? openPrice;

  double get floatingPl => unrealizedPnl.toDouble();
  double get lotSize => lots.toDouble();

  Decimal get netUnrealizedPnl => unrealizedPnl - commission - swap;
  Decimal get netRealizedPnl => realizedPnl - commission - swap;

  TradeEntity copyWith({
    String? id,
    String? orderId,
    String? symbol,
    OrderSide? side,
    OrderType? type,
    OrderStatus? status,
    Decimal? lots,
    Decimal? contractSize,
    Decimal? openPrice,
    Decimal? targetPrice,
    Decimal? currentPrice,
    Decimal? closePrice,
    Decimal? unrealizedPnl,
    Decimal? realizedPnl,
    Decimal? requiredMargin,
    Decimal? stopLoss,
    Decimal? takeProfit,
    Decimal? commission,
    Decimal? swap,
    Decimal? leverage,
    ExecutionRouting? routing,
    DateTime? openTime,
    DateTime? closeTime,
    String? closeReason,
    String? clientRequestId,
    Decimal? quoteToUsdRate,
    Decimal? requestedPrice,
    Decimal? spreadAtOpen,
  }) {
    return TradeEntity(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      symbol: symbol ?? this.symbol,
      side: side ?? this.side,
      type: type ?? this.type,
      status: status ?? this.status,
      lots: lots ?? this.lots,
      contractSize: contractSize ?? this.contractSize,
      openPrice: openPrice ?? this.openPrice,
      targetPrice: targetPrice ?? this.targetPrice,
      closePrice: closePrice ?? this.closePrice,
      stopLoss: stopLoss ?? this.stopLoss,
      takeProfit: takeProfit ?? this.takeProfit,
      currentPrice: currentPrice ?? this.currentPrice,
      unrealizedPnl: unrealizedPnl ?? this.unrealizedPnl,
      realizedPnl: realizedPnl ?? this.realizedPnl,
      requiredMargin: requiredMargin ?? this.requiredMargin,
      commission: commission ?? this.commission,
      swap: swap ?? this.swap,
      leverage: leverage ?? this.leverage,
      routing: routing ?? this.routing,
      openTime: openTime ?? this.openTime,
      closeTime: closeTime ?? this.closeTime,
      closeReason: closeReason ?? this.closeReason,
      clientRequestId: clientRequestId ?? this.clientRequestId,
      quoteToUsdRate: quoteToUsdRate ?? this.quoteToUsdRate,
      requestedPrice: requestedPrice ?? this.requestedPrice,
      spreadAtOpen: spreadAtOpen ?? this.spreadAtOpen,
    );
  }

  @override
  List<Object?> get props => [
        id, orderId, symbol, side, type, status, lots, openPrice, targetPrice,
        currentPrice, unrealizedPnl, realizedPnl, requiredMargin, closePrice,
        stopLoss, takeProfit, commission, swap, closeReason, closeTime,
      ];
}

/// Dynamic Margin and Portfolio Risk Account State
class TradingAccountState extends Equatable {
  final String accountId;
  final String userId;
  final String currency;
  final Decimal ledgerBalance;
  final Decimal unrealizedPnl;
  final Decimal usedMargin;
  final Decimal leverage;

  const TradingAccountState({
    required this.accountId,
    required this.userId,
    this.currency = 'USD',
    required this.ledgerBalance,
    required this.unrealizedPnl,
    required this.usedMargin,
    required this.leverage,
  });

  Decimal get equity => ledgerBalance + unrealizedPnl;

  Decimal get freeMargin => MoneyMath.calcFreeMargin(
        equity: equity,
        usedMargin: usedMargin,
      );

  Decimal get marginLevelPercent => MoneyMath.calcMarginLevel(
        equity: equity,
        usedMargin: usedMargin,
      );

  bool get isMarginCall {
    if (usedMargin <= Decimal.zero) return false;
    return marginLevelPercent.toDouble() < AppConstants.marginCallLevelPercent;
  }

  bool get isStopOutLiquidation {
    if (usedMargin <= Decimal.zero) return false;
    return marginLevelPercent.toDouble() <= AppConstants.stopOutLevelPercent;
  }

  TradingAccountState copyWith({
    Decimal? ledgerBalance,
    Decimal? unrealizedPnl,
    Decimal? usedMargin,
    Decimal? leverage,
  }) {
    return TradingAccountState(
      accountId: accountId,
      userId: userId,
      currency: currency,
      ledgerBalance: ledgerBalance ?? this.ledgerBalance,
      unrealizedPnl: unrealizedPnl ?? this.unrealizedPnl,
      usedMargin: usedMargin ?? this.usedMargin,
      leverage: leverage ?? this.leverage,
    );
  }

  @override
  List<Object?> get props => [
        accountId, ledgerBalance, unrealizedPnl, usedMargin, leverage,
      ];
}

/// Legacy/Compatibility Wallet Entity for legacy screens
class WalletEntity extends Equatable {
  final String id;
  final String userId;
  final String currency;
  final String type;
  final double balance;
  final double equity;
  final double margin;
  final double freeMargin;
  final double marginLevel;
  final double floatingPl;

  const WalletEntity({
    required this.id,
    required this.userId,
    required this.currency,
    required this.type,
    required this.balance,
    this.equity = 0.0,
    this.margin = 0.0,
    this.freeMargin = 0.0,
    this.marginLevel = 0.0,
    this.floatingPl = 0.0,
  });

  WalletEntity copyWith({
    String? id,
    String? userId,
    String? currency,
    String? type,
    double? balance,
    double? equity,
    double? margin,
    double? freeMargin,
    double? marginLevel,
    double? floatingPl,
  }) {
    return WalletEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      currency: currency ?? this.currency,
      type: type ?? this.type,
      balance: balance ?? this.balance,
      equity: equity ?? this.equity,
      margin: margin ?? this.margin,
      freeMargin: freeMargin ?? this.freeMargin,
      marginLevel: marginLevel ?? this.marginLevel,
      floatingPl: floatingPl ?? this.floatingPl,
    );
  }

  @override
  List<Object?> get props => [id, currency, balance, equity];
}

/// Legacy/Compatibility Transaction Entity for legacy screens
class TransactionEntity extends Equatable {
  final String id;
  final String type;
  final double amount;
  final String currency;
  final String status;
  final String? method;
  final String? description;
  final DateTime createdAt;

  const TransactionEntity({
    required this.id,
    required this.type,
    required this.amount,
    required this.currency,
    required this.status,
    this.method,
    this.description,
    required this.createdAt,
  });

  bool get isPending => status == 'pending';
  bool get isCompleted => status == 'completed';
  bool get isDeposit => type == 'deposit';

  @override
  List<Object?> get props => [id, type, amount, status, createdAt];
}
