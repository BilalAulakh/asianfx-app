import '../../domain/entities/chart_entities.dart';

/// FX / metals trading-session clock, matching how OANDA / TradingView bucket candles.
///
/// The FX trading day rolls over at 17:00 New York time (21:00 UTC in summer,
/// 22:00 UTC in winter). 4H and 1D candles are anchored to that rollover; the
/// trading week runs Sunday 17:00 NY → Friday 17:00 NY. Metals (XAU, XAG, XPT,
/// XPD) additionally pause daily 17:00–18:00 NY.
///
/// Internally we work in "session time": NY wall clock shifted +7h, so the
/// 17:00 NY rollover lands exactly on midnight and Sun 17:00 NY becomes Monday.
class FxSession {
  FxSession._();

  static const _rolloverShift = Duration(hours: 7);

  /// True when New York is on daylight-saving time (2nd Sun Mar → 1st Sun Nov).
  static bool isNewYorkDst(DateTime utc) {
    final y = utc.year;
    final dstStart = DateTime.utc(y, 3, _nthSunday(y, 3, 2), 7); // 02:00 EST
    final dstEnd = DateTime.utc(y, 11, _nthSunday(y, 11, 1), 6); // 02:00 EDT
    return !utc.isBefore(dstStart) && utc.isBefore(dstEnd);
  }

  static int _nthSunday(int year, int month, int n) {
    final firstWeekday = DateTime.utc(year, month, 1).weekday; // Mon=1 … Sun=7
    final firstSunday = 1 + (7 - firstWeekday) % 7;
    return firstSunday + (n - 1) * 7;
  }

  static Duration _nyOffset(DateTime utc) =>
      isNewYorkDst(utc) ? const Duration(hours: -4) : const Duration(hours: -5);

  /// Absolute instant → session time (a UTC-flagged DateTime holding session wall clock).
  static DateTime _toSession(DateTime time) {
    final utc = time.toUtc();
    return utc.add(_nyOffset(utc)).add(_rolloverShift);
  }

  /// Session time → absolute instant, using the NY offset in effect at [reference].
  static DateTime _fromSession(DateTime session, DateTime reference) {
    return session.subtract(_rolloverShift).subtract(_nyOffset(reference.toUtc()));
  }

  static DateTime _floorSession(DateTime s, ChartTimeframe tf) {
    switch (tf) {
      case ChartTimeframe.m1:
        return DateTime.utc(s.year, s.month, s.day, s.hour, s.minute);
      case ChartTimeframe.m5:
        return DateTime.utc(s.year, s.month, s.day, s.hour, (s.minute ~/ 5) * 5);
      case ChartTimeframe.m15:
        return DateTime.utc(s.year, s.month, s.day, s.hour, (s.minute ~/ 15) * 15);
      case ChartTimeframe.m30:
        return DateTime.utc(s.year, s.month, s.day, s.hour, (s.minute ~/ 30) * 30);
      case ChartTimeframe.h1:
        return DateTime.utc(s.year, s.month, s.day, s.hour);
      case ChartTimeframe.h4:
        return DateTime.utc(s.year, s.month, s.day, (s.hour ~/ 4) * 4);
      case ChartTimeframe.d1:
        return DateTime.utc(s.year, s.month, s.day);
    }
  }

  /// Start of the candle containing [time], returned in device-local time.
  static DateTime periodStart(DateTime time, ChartTimeframe tf) {
    final start = _floorSession(_toSession(time), tf);
    return _fromSession(start, time).toLocal();
  }

  static bool _isMetal(String? symbol) {
    if (symbol == null) return false;
    final s = symbol.toUpperCase();
    return s.startsWith('XAU') || s.startsWith('XAG') || s.startsWith('XPT') || s.startsWith('XPD');
  }

  /// Whether the market for [symbol] is trading at [now].
  static bool isMarketOpen(DateTime now, {String? symbol}) {
    final s = _toSession(now);
    // Sat/Sun in session time == Fri 17:00 NY → Sun 17:00 NY
    if (s.weekday == DateTime.saturday || s.weekday == DateTime.sunday) return false;
    // Metals daily maintenance break 17:00–18:00 NY (also covers the Sunday open)
    if (_isMetal(symbol) && s.hour == 0) return false;
    return true;
  }

  /// Time left until the current [tf] candle closes, or null while the market is closed.
  static Duration? timeToCandleClose(DateTime now, ChartTimeframe tf, {String? symbol}) {
    if (!isMarketOpen(now, symbol: symbol)) return null;
    final s = _toSession(now);
    final endSession = _floorSession(s, tf).add(tf.duration);
    final end = _fromSession(endSession, now);
    final remaining = end.difference(now.toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// TradingView-style countdown label: "MM:SS", "HH:MM:SS" or "Nd HHh".
  static String formatCountdown(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final days = d.inDays;
    final h = d.inHours % 24;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (days > 0) return '${days}d ${two(h)}h';
    if (d.inHours > 0) return '${two(h)}:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }
}
