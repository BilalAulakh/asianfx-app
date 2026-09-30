import 'package:equatable/equatable.dart';

/// Single Candlestick OHLCV bar
class CandleStickModel extends Equatable {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const CandleStickModel({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume = 0.0,
  });

  bool get isBullish => close >= open;
  double get bodyHeight => (close - open).abs();
  double get range => high - low;

  CandleStickModel copyWith({
    DateTime? time,
    double? open,
    double? high,
    double? low,
    double? close,
    double? volume,
  }) {
    return CandleStickModel(
      time: time ?? this.time,
      open: open ?? this.open,
      high: high ?? this.high,
      low: low ?? this.low,
      close: close ?? this.close,
      volume: volume ?? this.volume,
    );
  }

  @override
  List<Object?> get props => [time, open, high, low, close, volume];
}

enum ChartTimeframe {
  m1('1M', '1 Minute', Duration(minutes: 1)),
  m5('5M', '5 Minutes', Duration(minutes: 5)),
  m15('15M', '15 Minutes', Duration(minutes: 15)),
  m30('30M', '30 Minutes', Duration(minutes: 30)),
  h1('1H', '1 Hour', Duration(hours: 1)),
  h4('4H', '4 Hours', Duration(hours: 4)),
  d1('1D', '1 Day', Duration(days: 1));

  final String label;
  final String description;
  final Duration duration;
  const ChartTimeframe(this.label, this.description, this.duration);
}

enum ChartStyle {
  candlestick,
  line,
}
