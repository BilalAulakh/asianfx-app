import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/math/money_math.dart';
import '../../data/datasources/market_feed_service.dart';
import '../../domain/entities/dealing_entities.dart';
import '../../domain/entities/trading_entities.dart';
import 'trading_engine_provider.dart';
import 'market_provider.dart';

class DealingDeskNotifier extends StateNotifier<DealerRiskSummary> {
  final Ref _ref;
  final Map<String, ExecutionRouting> _routingMap = {
    'XAU/USD': ExecutionRouting.bBookInternal,
    'BTC/USD': ExecutionRouting.bBookInternal,
    'ETH/USD': ExecutionRouting.hybrid,
    'EUR/USD': ExecutionRouting.aBookStp,
    'XAG/USD': ExecutionRouting.bBookInternal,
  };

  DealingDeskNotifier(this._ref)
      : super(
          DealerRiskSummary(
            totalGrossExposureLots: Decimal.zero,
            totalNetExposureLots: Decimal.zero,
            aggregateClientFloatingPnl: Decimal.zero,
            aggregateHouseFloatingPnl: Decimal.zero,
            feeRevenueEarned: MoneyMath.toDec(1840.50),
            totalOpenPositions: 0,
            bBookOrderCount: 0,
            aBookOrderCount: 0,
            instrumentExposures: const [],
            lastRefreshed: DateTime.now(),
          ),
        ) {
    calculateExposure();
  }

  void updateRouting(String symbol, ExecutionRouting routing) {
    _routingMap[symbol] = routing;
    calculateExposure();
  }

  void toggleRoutingMode(String symbol) {
    final current = _routingMap[symbol] ?? ExecutionRouting.bBookInternal;
    final next = current == ExecutionRouting.bBookInternal
        ? ExecutionRouting.aBookStp
        : ExecutionRouting.bBookInternal;
    updateRouting(symbol, next);
  }

  void updateSpreadMarkup(String symbol, int markupPips) {
    _ref.read(marketFeedServiceProvider).updateSpreadMarkup(symbol, markupPips);
    calculateExposure();
  }

  void calculateExposure() {
    final engineState = _ref.read(tradingEngineProvider);
    final instruments = _ref.read(instrumentsProvider);
    final feedService = _ref.read(marketFeedServiceProvider);

    final exposureList = <InstrumentExposure>[];
    Decimal totalGross = Decimal.zero;
    Decimal totalNet = Decimal.zero;
    Decimal totalClientPnl = Decimal.zero;
    int bBookCount = 0;
    int aBookCount = 0;

    for (final inst in instruments) {
      final matching =
          engineState.openPositions.where((p) => p.symbol == inst.symbol).toList();

      Decimal buyLots = Decimal.zero;
      Decimal sellLots = Decimal.zero;
      Decimal clientPnl = Decimal.zero;

      for (final p in matching) {
        if (p.isBuy) {
          buyLots += p.lots;
        } else {
          sellLots += p.lots;
        }
        clientPnl += p.unrealizedPnl;
      }

      final netLots = buyLots - sellLots;
      final grossLots = buyLots + sellLots;
      final housePnl = -clientPnl;
      final routing = _routingMap[inst.symbol] ?? ExecutionRouting.bBookInternal;
      final markup = feedService.getSpreadMarkup(inst.symbol);

      if (routing == ExecutionRouting.bBookInternal) {
        bBookCount += matching.length;
      } else {
        aBookCount += matching.length;
      }

      totalGross += grossLots;
      totalNet += netLots;
      totalClientPnl += clientPnl;

      exposureList.add(InstrumentExposure(
        symbol: inst.symbol,
        totalBuyLots: buyLots,
        totalSellLots: sellLots,
        netExposureLots: netLots,
        grossExposureLots: grossLots,
        clientFloatingPnl: clientPnl,
        houseFloatingPnl: housePnl,
        activePositionCount: matching.length,
        spreadMarkupPips: markup,
        routing: routing,
      ));
    }

    state = DealerRiskSummary(
      totalGrossExposureLots: totalGross,
      totalNetExposureLots: totalNet,
      aggregateClientFloatingPnl: totalClientPnl,
      aggregateHouseFloatingPnl: -totalClientPnl,
      feeRevenueEarned: MoneyMath.toDec(2450.00),
      totalOpenPositions: engineState.openPositions.length,
      bBookOrderCount: bBookCount,
      aBookOrderCount: aBookCount,
      instrumentExposures: exposureList,
      lastRefreshed: DateTime.now(),
    );
  }
}

final dealingDeskProvider =
    StateNotifierProvider<DealingDeskNotifier, DealerRiskSummary>((ref) {
  return DealingDeskNotifier(ref);
});
