import 'package:intl/intl.dart';

class AppFormatters {
  AppFormatters._();

  static final _currencyFormatter = NumberFormat('#,##0.00', 'en_US');
  static final _compactFormatter = NumberFormat.compact();
  static final _percentFormatter = NumberFormat('+0.00%;-0.00%', 'en_US');

  /// Format as USD currency: $1,234.56
  static String currency(double amount, {String symbol = '\$'}) {
    return '$symbol${_currencyFormatter.format(amount)}';
  }

  /// Format as compact number: 1.2K, 4.5M
  static String compact(double amount) => _compactFormatter.format(amount);

  /// Format as percent: +1.23%, -0.45%
  static String percent(double value) => _percentFormatter.format(value / 100);

  /// Format for P/L display with color prefix
  static String plAmount(double value, {String symbol = '\$'}) {
    final prefix = value >= 0 ? '+' : '';
    return '$prefix$symbol${_currencyFormatter.format(value)}';
  }

  /// Format lot size: 0.01, 0.10, 1.00
  static String lotSize(double lots) => lots.toStringAsFixed(2);

  /// Format price with specific decimal places
  static String price(double price, {int decimals = 5}) {
    return price.toStringAsFixed(decimals);
  }

  /// Format pips
  static String pips(double pips) => pips.toStringAsFixed(1);

  /// Format date as: 05 Aug 2026
  static String date(DateTime dt) => DateFormat('dd MMM yyyy').format(dt);

  /// Format date as: 05/08/2026 19:48
  static String dateTime(DateTime dt) => DateFormat('dd/MM/yyyy HH:mm').format(dt);

  /// Format as time ago: 2 min ago, 3 hours ago
  static String timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return date(dt);
  }

  /// Format duration: 2h 15m
  static String duration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    return '${d.inSeconds}s';
  }
}
