import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import '../../core/math/money_math.dart';
import 'trading_entities.dart';

/// Single Instrument Exposure Summary for Chief Dealer
class InstrumentExposure extends Equatable {
  final String symbol;
  final Decimal totalBuyLots;
  final Decimal totalSellLots;
  final Decimal netExposureLots;  // Buy Lots - Sell Lots
  final Decimal grossExposureLots; // Buy Lots + Sell Lots
  final Decimal clientFloatingPnl;
  final Decimal houseFloatingPnl; // Inverse of client PnL in B-Book
  final int activePositionCount;
  final int spreadMarkupPips;
  final ExecutionRouting routing;

  const InstrumentExposure({
    required this.symbol,
    required this.totalBuyLots,
    required this.totalSellLots,
    required this.netExposureLots,
    required this.grossExposureLots,
    required this.clientFloatingPnl,
    required this.houseFloatingPnl,
    required this.activePositionCount,
    required this.spreadMarkupPips,
    required this.routing,
  });

  Decimal get totalLongLots => totalBuyLots;
  Decimal get totalShortLots => totalSellLots;

  bool get isHouseNetLong => netExposureLots < Decimal.zero; // Client net short means house is net long
  bool get isHouseNetShort => netExposureLots > Decimal.zero;

  @override
  List<Object?> get props => [
        symbol, totalBuyLots, totalSellLots, netExposureLots,
        clientFloatingPnl, spreadMarkupPips, routing,
      ];
}

/// Global Dealing Desk Exposure & Risk Summary
class DealerRiskSummary extends Equatable {
  final Decimal totalGrossExposureLots;
  final Decimal totalNetExposureLots;
  final Decimal aggregateClientFloatingPnl;
  final Decimal aggregateHouseFloatingPnl;
  final Decimal feeRevenueEarned;
  final int totalOpenPositions;
  final int bBookOrderCount;
  final int aBookOrderCount;
  final List<InstrumentExposure> instrumentExposures;
  final DateTime lastRefreshed;

  const DealerRiskSummary({
    required this.totalGrossExposureLots,
    required this.totalNetExposureLots,
    required this.aggregateClientFloatingPnl,
    required this.aggregateHouseFloatingPnl,
    required this.feeRevenueEarned,
    required this.totalOpenPositions,
    required this.bBookOrderCount,
    required this.aBookOrderCount,
    required this.instrumentExposures,
    required this.lastRefreshed,
  });

  @override
  List<Object?> get props => [
        totalGrossExposureLots, totalNetExposureLots,
        aggregateClientFloatingPnl, aggregateHouseFloatingPnl,
        feeRevenueEarned, totalOpenPositions, lastRefreshed,
      ];
}
