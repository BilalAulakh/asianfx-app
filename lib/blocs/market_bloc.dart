import 'dart:async';
import 'dart:math';
import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/datasources/market_feed_service.dart';
import '../domain/entities/chart_entities.dart';
import '../domain/entities/trading_entities.dart';
import '../core/utils/fx_session.dart';

// ── Events ────────────────────────────────────────────────────────────────────
abstract class MarketEvent {}

class MarketInitializeEvent extends MarketEvent {}

class MarketSelectSymbolEvent extends MarketEvent {
  final String symbol;
  MarketSelectSymbolEvent(this.symbol);
}

class MarketSelectTimeframeEvent extends MarketEvent {
  final ChartTimeframe timeframe;
  MarketSelectTimeframeEvent(this.timeframe);
}

/// Latest quotes since the previous batch (one entry per symbol).
class MarketTickReceivedEvent extends MarketEvent {
  final List<InstrumentEntity> instruments;
  MarketTickReceivedEvent(this.instruments);
}

class MarketReloadCandlesEvent extends MarketEvent {
  final String? symbol;
  final ChartTimeframe? timeframe;
  MarketReloadCandlesEvent({this.symbol, this.timeframe});
}

// ── State ─────────────────────────────────────────────────────────────────────
class MarketState {
  final List<InstrumentEntity> instruments;
  final String activeSymbol;
  final ChartTimeframe selectedTimeframe;
  final List<CandleStickModel> candles;
  final bool isLoadingCandles;
  final Map<String, InstrumentEntity> liveQuotes;

  const MarketState({
    this.instruments = const [],
    this.activeSymbol = 'XAU/USD',
    this.selectedTimeframe = ChartTimeframe.h1,
    this.candles = const [],
    this.isLoadingCandles = false,
    this.liveQuotes = const {},
  });

  InstrumentEntity? get selectedInstrument {
    if (instruments.isEmpty) return null;
    return liveQuotes[activeSymbol] ??
        instruments.firstWhere(
          (i) => i.symbol == activeSymbol,
          orElse: () => instruments.first,
        );
  }

  InstrumentEntity getInstrument(String symbol) {
    if (liveQuotes.containsKey(symbol)) {
      return liveQuotes[symbol]!;
    }
    for (final inst in instruments) {
      if (inst.symbol == symbol) return inst;
    }
    if (instruments.isNotEmpty) return instruments.first;
    return InstrumentEntity(
      symbol: symbol,
      name: symbol,
      category: 'forex',
      rawBid: Decimal.zero,
      rawAsk: Decimal.zero,
      contractSize: Decimal.fromInt(100000),
      change24h: 0.0,
      high24h: Decimal.zero,
      low24h: Decimal.zero,
      volume24h: Decimal.zero,
    );
  }

  MarketState copyWith({
    List<InstrumentEntity>? instruments,
    String? activeSymbol,
    ChartTimeframe? selectedTimeframe,
    List<CandleStickModel>? candles,
    bool? isLoadingCandles,
    Map<String, InstrumentEntity>? liveQuotes,
  }) {
    return MarketState(
      instruments: instruments ?? this.instruments,
      activeSymbol: activeSymbol ?? this.activeSymbol,
      selectedTimeframe: selectedTimeframe ?? this.selectedTimeframe,
      candles: candles ?? this.candles,
      isLoadingCandles: isLoadingCandles ?? this.isLoadingCandles,
      liveQuotes: liveQuotes ?? this.liveQuotes,
    );
  }
}

// ── Bloc ──────────────────────────────────────────────────────────────────────
class MarketBloc extends Bloc<MarketEvent, MarketState> {
  final MarketFeedService feedService;
  StreamSubscription<InstrumentEntity>? _tickSub;

  /// Ticks are coalesced: every quote arriving within this window is applied
  /// in ONE state update, so screens rebuild at most ~4x/s instead of once per
  /// tick (crypto streams deliver many ticks per second). Only each symbol's
  /// latest quote is kept.
  static const tickBatchWindow = Duration(milliseconds: 250);
  final Map<String, InstrumentEntity> _pendingTicks = {};
  Timer? _tickFlush;

  void _queueTick(InstrumentEntity instrument) {
    _pendingTicks[instrument.symbol] = instrument;
    _tickFlush ??= Timer(tickBatchWindow, () {
      _tickFlush = null;
      if (_pendingTicks.isEmpty || isClosed) return;
      final batch = _pendingTicks.values.toList();
      _pendingTicks.clear();
      add(MarketTickReceivedEvent(batch));
    });
  }

  MarketBloc({required this.feedService}) : super(const MarketState()) {
    on<MarketInitializeEvent>(_onInitialize);
    on<MarketSelectSymbolEvent>(_onSelectSymbol);
    on<MarketSelectTimeframeEvent>(_onSelectTimeframe);
    on<MarketTickReceivedEvent>(_onTickReceived);
    on<MarketReloadCandlesEvent>(_onReloadCandles);

    add(MarketInitializeEvent());
  }

  Future<void> _onInitialize(
    MarketInitializeEvent event,
    Emitter<MarketState> emit,
  ) async {
    final allInstruments = feedService.getAllInstruments();
    final initialCandles = feedService.getCandles(state.activeSymbol, state.selectedTimeframe);

    emit(state.copyWith(
      instruments: allInstruments,
      candles: initialCandles,
    ));

    // Cancel any previous tick subscription
    await _tickSub?.cancel();
    _tickSub = feedService.tickStream.listen(_queueTick);

    // Asynchronously fetch real history from sources
    add(MarketReloadCandlesEvent(
      symbol: state.activeSymbol,
      timeframe: state.selectedTimeframe,
    ));
  }

  Future<void> _onSelectSymbol(
    MarketSelectSymbolEvent event,
    Emitter<MarketState> emit,
  ) async {
    if (state.activeSymbol == event.symbol) return;
    final initialCandles = feedService.getCandles(event.symbol, state.selectedTimeframe);
    emit(state.copyWith(
      activeSymbol: event.symbol,
      candles: initialCandles,
    ));
    add(MarketReloadCandlesEvent(
      symbol: event.symbol,
      timeframe: state.selectedTimeframe,
    ));
  }

  Future<void> _onSelectTimeframe(
    MarketSelectTimeframeEvent event,
    Emitter<MarketState> emit,
  ) async {
    if (state.selectedTimeframe == event.timeframe) return;
    final initialCandles = feedService.getCandles(state.activeSymbol, event.timeframe);
    emit(state.copyWith(
      selectedTimeframe: event.timeframe,
      candles: initialCandles,
    ));
    add(MarketReloadCandlesEvent(
      symbol: state.activeSymbol,
      timeframe: event.timeframe,
    ));
  }

  // Candle buckets follow the FX session clock (rollover 17:00 New York), same as
  // OANDA/TradingView, so the chart countdown and new-candle boundaries agree.
  DateTime _getCandlePeriodStart(DateTime time, ChartTimeframe tf) =>
      FxSession.periodStart(time, tf);

  void _onTickReceived(
    MarketTickReceivedEvent event,
    Emitter<MarketState> emit,
  ) {
    if (event.instruments.isEmpty) return;
    final bySymbol = {for (final i in event.instruments) i.symbol: i};
    final updatedQuotes = {...state.liveQuotes, ...bySymbol};

    // Update instruments list in place
    final updatedList = [for (final inst in state.instruments) bySymbol[inst.symbol] ?? inst];

    List<CandleStickModel> updatedCandles = state.candles;
    final active = bySymbol[state.activeSymbol];
    if (active != null && state.candles.isNotEmpty) {
      final curPrice = active.midPrice.toDouble();
      final now = DateTime.now();
      final currentPeriod = _getCandlePeriodStart(now, state.selectedTimeframe);
      final lastCandle = state.candles.last;
      final lastPeriod = _getCandlePeriodStart(lastCandle.time, state.selectedTimeframe);

      updatedCandles = List<CandleStickModel>.from(state.candles);

      if (currentPeriod.isAfter(lastPeriod)) {
        // Exness-style: New candle forms on interval boundary!
        final newCandle = CandleStickModel(
          time: currentPeriod,
          open: lastCandle.close,
          high: max(lastCandle.close, curPrice),
          low: min(lastCandle.close, curPrice),
          close: curPrice,
          volume: 1.0,
        );
        updatedCandles.add(newCandle);
        if (updatedCandles.length > 1500) {
          updatedCandles.removeAt(0);
        }
      } else {
        // Exness-style: Live candle stretches up (green) and down (red) with real-time ticks
        final updatedLast = lastCandle.copyWith(
          close: curPrice,
          high: max(lastCandle.high, curPrice),
          low: min(lastCandle.low, curPrice),
          volume: lastCandle.volume + 0.1,
        );
        updatedCandles[updatedCandles.length - 1] = updatedLast;
      }
    }

    emit(state.copyWith(
      instruments: updatedList,
      liveQuotes: updatedQuotes,
      candles: updatedCandles,
    ));
  }

  Future<void> _onReloadCandles(
    MarketReloadCandlesEvent event,
    Emitter<MarketState> emit,
  ) async {
    final sym = event.symbol ?? state.activeSymbol;
    final tf = event.timeframe ?? state.selectedTimeframe;

    emit(state.copyWith(isLoadingCandles: true));
    try {
      final candles = await feedService.fetchCandlesAsync(sym, tf);
      if (state.activeSymbol == sym && state.selectedTimeframe == tf) {
        emit(state.copyWith(
          candles: candles,
          isLoadingCandles: false,
        ));
      }
    } catch (_) {
      emit(state.copyWith(isLoadingCandles: false));
    }
  }

  @override
  Future<void> close() {
    _tickSub?.cancel();
    _tickFlush?.cancel();
    return super.close();
  }
}
