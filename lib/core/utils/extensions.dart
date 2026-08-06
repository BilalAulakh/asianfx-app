import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

extension ContextExtensions on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => Theme.of(this).textTheme;
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
  MediaQueryData get mediaQuery => MediaQuery.of(this);
  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  EdgeInsets get padding => MediaQuery.of(this).padding;
  bool get isMobile => MediaQuery.of(this).size.width < 768;
  bool get isTablet => MediaQuery.of(this).size.width >= 768 && MediaQuery.of(this).size.width < 1024;
  bool get isDesktop => MediaQuery.of(this).size.width >= 1024;

  void showSnackBar(String message, {bool isError = false, bool isSuccess = false}) {
    ScaffoldMessenger.of(this).hideCurrentSnackBar();
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : isSuccess ? Icons.check_circle_outline : Icons.info_outline,
              color: isError ? AppColors.loss : isSuccess ? AppColors.profit : AppColors.info,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void pop<T>([T? result]) => Navigator.of(this).pop(result);
}

extension StringExtensions on String {
  String get capitalize => isEmpty ? '' : '${this[0].toUpperCase()}${substring(1)}';
  String get capitalizeWords => split(' ').map((w) => w.capitalize).join(' ');
  bool get isValidEmail => RegExp(
    r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$",
  ).hasMatch(this);
  bool get isValidPhone => RegExp(r'^\+?[0-9]{7,15}$').hasMatch(this);
  bool get isValidPassword => length >= 8 && contains(RegExp(r'[A-Za-z]')) && contains(RegExp(r'[0-9]'));
}

extension DoubleExtensions on double {
  String get toCurrency => '\$${toStringAsFixed(2)}';
  String get toPips => toStringAsFixed(1);
  String get toPercent => '${toStringAsFixed(2)}%';
  Color get plColor => this >= 0 ? AppColors.profit : AppColors.loss;
  String get plFormatted {
    final prefix = this >= 0 ? '+' : '';
    return '$prefix${toStringAsFixed(2)}';
  }
}

extension IntExtensions on int {
  String get toTime {
    final hours = this ~/ 3600;
    final minutes = (this % 3600) ~/ 60;
    final seconds = this % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }
}

extension DateTimeExtensions on DateTime {
  String get toDisplayDate => '$day/${month.toString().padLeft(2, '0')}/$year';
  String get toDisplayTime => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  String get toDisplayDateTime => '$toDisplayDate $toDisplayTime';
  bool get isToday {
    final now = DateTime.now();
    return year == now.year && month == now.month && day == now.day;
  }
}

extension ListExtensions<T> on List<T> {
  List<T> get safeReversed => reversed.toList();
}
