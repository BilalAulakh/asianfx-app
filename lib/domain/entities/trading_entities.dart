import 'package:equatable/equatable.dart';

enum OrderSide { buy, sell }
enum OrderType { market, limit, stop, stopLimit }
enum OrderStatus { pending, open, closed, cancelled, rejected }
enum TradeDirection { long, short }

class InstrumentEntity extends Equatable {
  final String symbol;       // EURUSD, BTCUSD, XAUUSD
  final String name;         // Euro / US Dollar
  final String category;     // forex, crypto, gold, stocks, indices
  final double bid;
  final double ask;
  final double spread;
  final double change24h;    // percentage change
  final double changeAmount; // absolute change
  final double high24h;
  final double low24h;
  final double volume24h;
  final int decimals;
  final String? iconUrl;
  final bool isFavorite;

  const InstrumentEntity({
    required this.symbol,
    required this.name,
    required this.category,
    required this.bid,
    required this.ask,
    required this.spread,
    required this.change24h,
    required this.changeAmount,
    required this.high24h,
    required this.low24h,
    required this.volume24h,
    this.decimals = 5,
    this.iconUrl,
    this.isFavorite = false,
  });

  double get midPrice => (bid + ask) / 2;
  bool get isPositiveChange => change24h >= 0;

  InstrumentEntity copyWith({
    double? bid,
    double? ask,
    double? spread,
    double? change24h,
    double? changeAmount,
    double? high24h,
    double? low24h,
    bool? isFavorite,
  }) {
    return InstrumentEntity(
      symbol: symbol,
      name: name,
      category: category,
      bid: bid ?? this.bid,
      ask: ask ?? this.ask,
      spread: spread ?? this.spread,
      change24h: change24h ?? this.change24h,
      changeAmount: changeAmount ?? this.changeAmount,
      high24h: high24h ?? this.high24h,
      low24h: low24h ?? this.low24h,
      volume24h: volume24h,
      decimals: decimals,
      iconUrl: iconUrl,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  @override
  List<Object?> get props => [symbol, bid, ask, change24h, isFavorite];
}

class TradeEntity extends Equatable {
  final String id;
  final String symbol;
  final OrderSide side;
  final OrderType type;
  final OrderStatus status;
  final double lotSize;
  final double openPrice;
  final double? closePrice;
  final double? stopLoss;
  final double? takeProfit;
  final double? currentPrice;
  final double floatingPl;
  final double commission;
  final double swap;
  final double leverage;
  final DateTime openTime;
  final DateTime? closeTime;

  const TradeEntity({
    required this.id,
    required this.symbol,
    required this.side,
    required this.type,
    required this.status,
    required this.lotSize,
    required this.openPrice,
    this.closePrice,
    this.stopLoss,
    this.takeProfit,
    this.currentPrice,
    this.floatingPl = 0.0,
    this.commission = 0.0,
    this.swap = 0.0,
    required this.leverage,
    required this.openTime,
    this.closeTime,
  });

  bool get isOpen => status == OrderStatus.open;
  bool get isClosed => status == OrderStatus.closed;
  bool get isPending => status == OrderStatus.pending;
  double get netPl => floatingPl - commission - swap;

  @override
  List<Object?> get props => [id, symbol, status, floatingPl, currentPrice];
}

class WalletEntity extends Equatable {
  final String id;
  final String userId;
  final String currency;
  final String type; // fiat, crypto
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

  @override
  List<Object?> get props => [id, currency, balance, equity];
}

class TransactionEntity extends Equatable {
  final String id;
  final String type; // deposit, withdrawal, transfer
  final double amount;
  final String currency;
  final String status; // pending, completed, rejected
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
