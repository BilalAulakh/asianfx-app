import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/datasources/market_feed_service.dart';
import '../data/datasources/supabase_trade_service.dart';
import '../domain/entities/dealing_entities.dart';
import '../domain/entities/trading_entities.dart';
import 'trading_engine_bloc.dart';

export '../domain/entities/dealing_entities.dart';

/// Dealer exposure view + dealer controls.
///
/// * Markup is persisted with `rpc_admin_set_markup` (audited, clamped 0..500)
///   and read back from the `instruments` table by MarketFeedService.
/// * "A-Book / B-Book" is an INTERNAL TAG only. There is no liquidity-provider
///   bridge: every trade is held by the broker and nothing is hedged
///   externally, whatever the tag says.
class DealingDeskCubit extends Cubit<DealerRiskSummary> {
  final MarketFeedService _feedService;
  final TradingEngineCubit? _tradingEngineCubit;
  final SupabaseTradeService _trades = SupabaseTradeService.instance;

  /// Slider value being dragged but not yet saved, per symbol.
  final Map<String, int> _pendingMarkup = {};

  /// Internal book tags (display / reporting only — no routing happens).
  final Map<String, ExecutionRouting> _routingMap = {
    'XAU/USD': ExecutionRouting.bBookInternal,
    'BTC/USD': ExecutionRouting.bBookInternal,
    'ETH/USD': ExecutionRouting.hybrid,
    'EUR/USD': ExecutionRouting.aBookStp,
    'XAG/USD': ExecutionRouting.bBookInternal,
  };

  DealingDeskCubit({
    MarketFeedService? feedService,
    this._tradingEngineCubit,
  })  : _feedService = feedService ?? MarketFeedService(),
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

  /// Live slider preview; nothing is saved until [commitSpreadMarkup].
  void previewSpreadMarkup(String symbol, int points) {
    _pendingMarkup[symbol] = points;
    calculateExposure();
  }

  /// Persist the markup server-side. Returns an error message, or null on success.
  Future<String?> commitSpreadMarkup(String symbol, int points) async {
    _pendingMarkup[symbol] = points;
    try {
      final stored = await _trades.adminSetMarkup(symbol: symbol, points: points);
      _feedService.updateSpreadMarkup(symbol, stored);
      return null;
    } on TradeServiceException catch (e) {
      return e.code == 'FORBIDDEN'
          ? 'Not saved: the server did not recognise you as an administrator.'
          : 'Not saved: ${e.message}';
    } finally {
      _pendingMarkup.remove(symbol);
      if (!isClosed) calculateExposure();
    }
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

      final markup = _pendingMarkup[sym] ?? _feedService.getSpreadMarkup(sym);

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
