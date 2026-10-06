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
  static final Decimal _two = Decimal.fromInt(2);
  static final Decimal _ten = Decimal.fromInt(10);

  /// Scale used for intermediate ratio results (rates, divisions).
  static const int ratioScale = 10;

  /// Scale used for stored monetary values. Mirrors NUMERIC(18, 4) in Postgres
  /// so client-side previews never disagree with the authoritative server row.
  static const int moneyScale = 4;

  /// Convert num / String / double to Decimal safely
  static Decimal toDec(dynamic value) {
    if (value == null) return Decimal.zero;
    if (value is Decimal) return value;
    if (value is int) return Decimal.fromInt(value);
    if (value is BigInt) return Decimal.fromBigInt(value);
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

  /// Exact Decimal division. Falls back to [scale] digits only when the
  /// quotient has infinite precision (e.g. 1/3). Never routes through double.
  static Decimal divide(Decimal numerator, Decimal denominator, {int scale = ratioScale}) {
    if (denominator == Decimal.zero) return Decimal.zero;
    return (numerator / denominator).toDecimal(scaleOnInfinitePrecision: scale);
  }

  /// Round a monetary amount to the stored money scale (4 dp).
  static Decimal roundMoney(Decimal value) => value.round(scale: moneyScale);

  /// Size of one price point (the last quoted digit) for an instrument with
  /// [decimals] quoted digits. 2 -> 0.01, 4 -> 0.0001, 1 -> 0.1, 5 -> 0.00001.
  ///
  /// The old implementation hard-coded a 3-branch lookup which silently
  /// returned 0.001 for indices (decimals == 1) and 5-digit FX (decimals == 5),
  /// making their spreads 100x too small / too large.
  static Decimal pointSize(int decimals) {
    if (decimals <= 0) return Decimal.one;
    return divide(Decimal.one, _ten.pow(decimals).toDecimal(), scale: decimals);
  }

  /// Format Decimal to standard USD currency string ($1,234.56)
  static String formatCurrency(Decimal value, {String symbol = '\$'}) {
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return '$symbol${formatter.format(double.parse(value.toStringAsFixed(2)))}';
  }

  /// Format Decimal to exact decimal places
  static String formatDec(Decimal value, int decimals) => value.toStringAsFixed(decimals);

  /// Format lot size (e.g., 0.01, 1.50)
  static String formatLots(Decimal lots) => lots.toStringAsFixed(2);

  /// Format PnL with sign and color prefix (+ $120.50 or - $45.20)
  static String formatPnL(Decimal pnl, {String symbol = '\$'}) {
    final prefix = pnl >= Decimal.zero ? '+' : '-';
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return '$prefix$symbol${formatter.format(double.parse(pnl.abs().toStringAsFixed(2)))}';
  }

  /// Notional value of a position expressed in the instrument's QUOTE currency.
  static Decimal calcNotional({
    required Decimal lots,
    required Decimal contractSize,
    required Decimal price,
  }) =>
      lots * contractSize * price;

  /// Calculate Required Margin in the ACCOUNT currency (USD):
  ///
  ///   margin = (lots * contractSize * openPrice * quoteToUsdRate) / leverage
  ///
  /// [quoteToUsdRate] converts one unit of the instrument's quote currency into
  /// USD. It is 1 for `XXX/USD` instruments (gold, BTC, EURUSD, US indices) and
  /// must be supplied for every other quote currency:
  ///   * USD/JPY  -> 1 / 153.60
  ///   * EUR/GBP  -> GBP/USD mid
  ///   * GER40/EUR-> EUR/USD mid
  ///
  /// Without it a 1-lot USD/JPY position reported ~$153,600 of required margin
  /// instead of $1,000 (the notional was left denominated in yen).
  static Decimal calcRequiredMargin({
    required Decimal lots,
    required Decimal contractSize,
    required Decimal openPrice,
    required Decimal leverage,
    Decimal? quoteToUsdRate,
  }) {
    if (leverage <= Decimal.zero) return Decimal.zero;
    final notionalQuote = calcNotional(lots: lots, contractSize: contractSize, price: openPrice);
    final notionalUsd = notionalQuote * (quoteToUsdRate ?? Decimal.one);
    return roundMoney(divide(notionalUsd, leverage));
  }

  /// Calculate Unrealized PnL in the ACCOUNT currency (USD):
  /// Buy (Long)   = (Current Bid - Open Price) * Lots * Contract Size * rate
  /// Sell (Short) = (Open Price - Current Ask) * Lots * Contract Size * rate
  ///
  /// See [calcRequiredMargin] for [quoteToUsdRate] semantics.
  static Decimal calcUnrealizedPnL({
    required bool isBuy,
    required Decimal openPrice,
    required Decimal currentPrice, // Bid for Long, Ask for Short
    required Decimal lots,
    required Decimal contractSize,
    Decimal? quoteToUsdRate,
  }) {
    final priceDiff = isBuy ? (currentPrice - openPrice) : (openPrice - currentPrice);
    final pnlQuote = priceDiff * lots * contractSize;
    return roundMoney(pnlQuote * (quoteToUsdRate ?? Decimal.one));
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
    return divide(equity * hundred, usedMargin, scale: 4);
  }

  /// Apply a dealer spread markup of [markupPips] price points to a raw price.
  ///
  /// [pipDecimals] is the instrument's quoted digit count; one point is
  /// 10^-pipDecimals (see [pointSize]).
  static Decimal applySpreadMarkup({
    required Decimal rawPrice,
    required int markupPips,
    required int pipDecimals,
    required bool isAsk,
  }) {
    final markup = pointSize(pipDecimals) * Decimal.fromInt(markupPips);
    return isAsk ? (rawPrice + markup) : (rawPrice - markup);
  }

  /// Apply exactly half of [markupPoints] to one side of the book.
  ///
  /// The previous code did `(markupPoints / 2).round()` per side, so an odd
  /// markup of 15 points became 8 + 8 = 16 points of total spread and a 3-point
  /// silver markup became 2 + 2 = 4. Splitting in Decimal keeps the configured
  /// total spread exact.
  static Decimal applyHalfSpreadMarkup({
    required Decimal rawPrice,
    required int markupPoints,
    required int decimals,
    required bool isAsk,
  }) {
    final half = divide(pointSize(decimals) * Decimal.fromInt(markupPoints), _two,
        scale: decimals + 2);
    return isAsk ? (rawPrice + half) : (rawPrice - half);
  }

  /// Calculate Estimated Liquidation Price (Stop Out Threshold)
  static Decimal calcLiquidationPrice({
    required bool isBuy,
    required Decimal openPrice,
    required Decimal lots,
    required Decimal contractSize,
    required Decimal stopOutMargin,
    required Decimal availableEquity,
    Decimal? quoteToUsdRate,
  }) {
    if (lots <= Decimal.zero || contractSize <= Decimal.zero) return Decimal.zero;
    final rate = quoteToUsdRate ?? Decimal.one;
    if (rate <= Decimal.zero) return Decimal.zero;
    final maxLossUsd = availableEquity - stopOutMargin;
    // Convert the USD loss budget back into quote-currency price units.
    final maxPriceMove = divide(divide(maxLossUsd, rate), lots * contractSize);
    if (isBuy) {
      final liq = openPrice - maxPriceMove;
      return liq > Decimal.zero ? liq : Decimal.zero;
    }
    return openPrice + maxPriceMove;
  }
}
