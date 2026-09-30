import 'dart:async';
import 'dart:math';
import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/datasources/market_feed_service.dart';
import '../domain/entities/chart_entities.dart';
import '../domain/entities/trading_entities.dart';

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

class MarketTickReceivedEvent extends MarketEvent {
  final InstrumentEntity instrument;
  MarketTickReceivedEvent(this.instrument);
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
    _tickSub = feedService.tickStream.listen((instrument) {
      add(MarketTickReceivedEvent(instrument));
    });

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

  DateTime _getCandlePeriodStart(DateTime time, ChartTimeframe tf) {
    switch (tf) {
      case ChartTimeframe.m1:
        return DateTime(time.year, time.month, time.day, time.hour, time.minute);
      case ChartTimeframe.m5:
        final m = (time.minute ~/ 5) * 5;
        return DateTime(time.year, time.month, time.day, time.hour, m);
      case ChartTimeframe.m15:
        final m = (time.minute ~/ 15) * 15;
        return DateTime(time.year, time.month, time.day, time.hour, m);
      case ChartTimeframe.m30:
        final m = (time.minute ~/ 30) * 30;
        return DateTime(time.year, time.month, time.day, time.hour, m);
      case ChartTimeframe.h1:
        return DateTime(time.year, time.month, time.day, time.hour);
      case ChartTimeframe.h4:
        final h = (time.hour ~/ 4) * 4;
        return DateTime(time.year, time.month, time.day, h);
      case ChartTimeframe.d1:
        return DateTime(time.year, time.month, time.day);
    }
  }

  void _onTickReceived(
    MarketTickReceivedEvent event,
    Emitter<MarketState> emit,
  ) {
    final updatedQuotes = Map<String, InstrumentEntity>.from(state.liveQuotes);
    updatedQuotes[event.instrument.symbol] = event.instrument;

    // Update instruments list in place
    final updatedList = state.instruments.map((inst) {
      return inst.symbol == event.instrument.symbol ? event.instrument : inst;
    }).toList();

    List<CandleStickModel> updatedCandles = state.candles;
    if (event.instrument.symbol == state.activeSymbol && state.candles.isNotEmpty) {
      final curPrice = event.instrument.midPrice.toDouble();
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
          volume: lastCandle.volume + 1.0,
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
    return super.close();
  }
}
