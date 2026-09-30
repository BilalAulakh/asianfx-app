import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/datasources/market_feed_service.dart';
import '../domain/entities/dealing_entities.dart';
import '../domain/entities/trading_entities.dart';
import 'trading_engine_bloc.dart';

export '../domain/entities/dealing_entities.dart';

class DealingDeskCubit extends Cubit<DealerRiskSummary> {
  final MarketFeedService _feedService;
  final TradingEngineCubit? _tradingEngineCubit;

  final Map<String, ExecutionRouting> _routingMap = {
    'XAU/USD': ExecutionRouting.bBookInternal,
    'BTC/USD': ExecutionRouting.bBookInternal,
    'ETH/USD': ExecutionRouting.hybrid,
    'EUR/USD': ExecutionRouting.aBookStp,
    'XAG/USD': ExecutionRouting.bBookInternal,
  };

  DealingDeskCubit({
    MarketFeedService? feedService,
    TradingEngineCubit? tradingEngineCubit,
  })  : _feedService = feedService ?? MarketFeedService(),
        _tradingEngineCubit = tradingEngineCubit,
        super(
          DealerRiskSummary(
            totalGrossExposureLots: Decimal.zero,
            totalNetExposureLots: Decimal.zero,
            aggregateClientFloatingPnl: Decimal.zero,
            aggregateHouseFloatingPnl: Decimal.zero,
            feeRevenueEarned: Decimal.zero,
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
    _feedService.updateSpreadMarkup(symbol, markupPips);
    calculateExposure();
  }

  void calculateExposure() {
    final positions = _tradingEngineCubit?.state.openPositions ?? [];

    final Map<String, List<TradeEntity>> posBySymbol = {};
    for (final p in positions) {
      posBySymbol.putIfAbsent(p.symbol, () => []).add(p);
    }

    // Always include primary market instruments for dealer controls (markup & routing)
    const primarySymbols = [
      'XAU/USD',
      'EUR/USD',
      'GBP/USD',
      'BTC/USD',
      'ETH/USD',
      'USD/JPY',
      'XAG/USD',
      'USD/CAD',
      'AUD/USD',
    ];

    final allSymbols = <String>{
      ...posBySymbol.keys,
      ...primarySymbols,
    };

    final exposureList = <InstrumentExposure>[];
    Decimal totalGross = Decimal.zero;
    Decimal totalClientPnl = Decimal.zero;
    int bBookCount = 0;
    int aBookCount = 0;

    for (final sym in allSymbols) {
      final symPositions = posBySymbol[sym] ?? const [];

      Decimal longLots = Decimal.zero;
      Decimal shortLots = Decimal.zero;
      Decimal symClientPnl = Decimal.zero;

      for (final p in symPositions) {
        if (p.isBuy) {
          longLots += p.lots;
        } else {
          shortLots += p.lots;
        }
        symClientPnl += p.unrealizedPnl;
      }

      final netLots = longLots - shortLots;
      final grossLots = longLots + shortLots;
      totalGross += grossLots;
      totalClientPnl += symClientPnl;

      final routing = _routingMap[sym] ?? ExecutionRouting.bBookInternal;
      if (routing == ExecutionRouting.bBookInternal) {
        bBookCount += symPositions.length;
      } else {
        aBookCount += symPositions.length;
      }

      final markup = _feedService.getSpreadMarkup(sym);

      exposureList.add(
        InstrumentExposure(
          symbol: sym,
          totalBuyLots: longLots,
          totalSellLots: shortLots,
          netExposureLots: netLots,
          grossExposureLots: grossLots,
          clientFloatingPnl: symClientPnl,
          houseFloatingPnl: -symClientPnl,
          activePositionCount: symPositions.length,
          spreadMarkupPips: markup,
          routing: routing,
        ),
      );
    }

    emit(DealerRiskSummary(
      totalGrossExposureLots: totalGross,
      totalNetExposureLots: exposureList.fold(Decimal.zero, (s, e) => s + e.netExposureLots.abs()),
      aggregateClientFloatingPnl: totalClientPnl,
      aggregateHouseFloatingPnl: -totalClientPnl,
      feeRevenueEarned: state.feeRevenueEarned,
      totalOpenPositions: positions.length,
      bBookOrderCount: bBookCount,
      aBookOrderCount: aBookCount,
      instrumentExposures: exposureList,
      lastRefreshed: DateTime.now(),
    ));
  }
}

typedef DealingDeskBloc = DealingDeskCubit;
