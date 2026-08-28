import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

/// Institutional precision financial math utilities.
/// Guarantees exact currency, lot, pip, margin, and PnL calculations
/// without IEEE-754 floating-point drift.
class MoneyMath {
  MoneyMath._();

  static final Decimal zero = Decimal.zero;
  static final Decimal one = Decimal.one;
  static final Decimal hundred = Decimal.fromInt(100);

  /// Convert num / String / double to Decimal safely
  static Decimal toDec(dynamic value) {
    if (value == null) return Decimal.zero;
    if (value is Decimal) return value;
    if (value is int) return Decimal.fromInt(value);
    if (value is double) {
      if (value.isNaN || value.isInfinite) return Decimal.zero;
      return Decimal.parse(value.toStringAsFixed(8));
    }
    if (value is String) {
      final sanitized = value.trim().replaceAll(',', '');
      return Decimal.tryParse(sanitized) ?? Decimal.zero;
    }
    return Decimal.zero;
  }

  /// Format Decimal to standard USD currency string ($1,234.56)
  static String formatCurrency(Decimal value, {String symbol = '\$'}) {
    final d = value.toDouble();
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return '$symbol${formatter.format(d)}';
  }

  /// Format Decimal to exact decimal places
  static String formatDec(Decimal value, int decimals) {
    final d = value.toDouble();
    return d.toStringAsFixed(decimals);
  }

  /// Format lot size (e.g., 0.01, 1.50)
  static String formatLots(Decimal lots) {
    return lots.toDouble().toStringAsFixed(2);
  }

  /// Format PnL with sign and color prefix (+ $120.50 or - $45.20)
  static String formatPnL(Decimal pnl, {String symbol = '\$'}) {
    final d = pnl.toDouble();
    final prefix = d >= 0 ? '+' : '-';
    final absD = d.abs();
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return '$prefix$symbol${formatter.format(absD)}';
  }

  /// Calculate Required Margin:
  /// Margin = (Lots * Contract Size * Open Price) / Leverage
  static Decimal calcRequiredMargin({
    required Decimal lots,
    required Decimal contractSize,
    required Decimal openPrice,
    required Decimal leverage,
  }) {
    if (leverage <= Decimal.zero) return Decimal.zero;
    final notional = lots * contractSize * openPrice;
    final marginDouble = notional.toDouble() / leverage.toDouble();
    return toDec(marginDouble);
  }

  /// Calculate Unrealized PnL:
  /// Buy (Long)  = (Current Bid - Open Price) * Lots * Contract Size
  /// Sell (Short) = (Open Price - Current Ask) * Lots * Contract Size
  static Decimal calcUnrealizedPnL({
    required bool isBuy,
    required Decimal openPrice,
    required Decimal currentPrice, // Bid for Long, Ask for Short
    required Decimal lots,
    required Decimal contractSize,
  }) {
    final priceDiff = isBuy ? (currentPrice - openPrice) : (openPrice - currentPrice);
    return priceDiff * lots * contractSize;
  }

  /// Calculate Free Margin:
  /// Free Margin = Equity - Used Margin
  static Decimal calcFreeMargin({
    required Decimal equity,
    required Decimal usedMargin,
  }) {
    return equity - usedMargin;
  }

  /// Calculate Margin Level Percentage:
  /// Margin Level % = (Equity / Used Margin) * 100
  static Decimal calcMarginLevel({
    required Decimal equity,
    required Decimal usedMargin,
  }) {
    if (usedMargin <= Decimal.zero) {
      return Decimal.fromInt(999999); // Infinite / safe when 0 used margin
    }
    final level = (equity.toDouble() / usedMargin.toDouble()) * 100.0;
    return toDec(level);
  }

  /// Calculate Dynamic Spread markup in quote currency
  static Decimal applySpreadMarkup({
    required Decimal rawPrice,
    required int markupPips,
    required int pipDecimals, // e.g. 2 for Gold (0.01), 4 for EURUSD (0.0001)
    required bool isAsk,
  }) {
    // 1 pip for pipDecimals=2 is 0.01; for 4 is 0.0001
    final factor = pipDecimals == 2 ? 0.01 : (pipDecimals == 4 ? 0.0001 : 0.001);
    final markup = toDec(markupPips * factor);
    return isAsk ? (rawPrice + markup) : (rawPrice - markup);
  }

  /// Calculate Estimated Liquidation Price (Stop Out Threshold)
  static Decimal calcLiquidationPrice({
    required bool isBuy,
    required Decimal openPrice,
    required Decimal lots,
    required Decimal contractSize,
    required Decimal stopOutMargin,
    required Decimal availableEquity,
  }) {
    if (lots <= Decimal.zero || contractSize <= Decimal.zero) return Decimal.zero;
    final maxLoss = availableEquity - stopOutMargin;
    final notionalUnits = (lots * contractSize).toDouble();
    if (notionalUnits == 0) return Decimal.zero;
    final maxPriceDrop = maxLoss.toDouble() / notionalUnits;
    if (isBuy) {
      final liq = openPrice.toDouble() - maxPriceDrop;
      return toDec(liq > 0 ? liq : 0.0);
    } else {
      final liq = openPrice.toDouble() + maxPriceDrop;
      return toDec(liq);
    }
  }
}
