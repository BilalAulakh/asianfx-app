import 'package:decimal/decimal.dart';

/// Institutional trading specifications, contract multipliers, and risk thresholds
class AppConstants {
  AppConstants._();

  // App Meta
  static const String appName = 'FXAsian';
  static const String appVersion = '2.4.0-Enterprise';

  // Precision contract sizes
  static final Decimal contractSizeGold = Decimal.fromInt(100);       // 1 Lot XAUUSD = 100 oz
  static final Decimal contractSizeSilver = Decimal.fromInt(5000);    // 1 Lot XAGUSD = 5,000 oz
  static final Decimal contractSizeForex = Decimal.fromInt(100000);   // 1 Lot EURUSD = 100,000 units
  static final Decimal contractSizeCrypto = Decimal.one;              // 1 Lot BTCUSD = 1 BTC
  static final Decimal contractSizeCommodity = Decimal.fromInt(100);  // 1 Lot Oil/Gas = 100 units
  static final Decimal contractSizeIndex = Decimal.one;               // 1 Lot Index CFD = 1 unit
  static final Decimal contractSizeStock = Decimal.fromInt(10);       // 1 Lot Stock CFD = 10 shares

  // Dynamic leverage choices
  static const List<int> availableLeverages = [50, 100, 200, 500];

  static const int defaultLeverage = 100;

  // Volume (lot) limits enforced on both the client preview and the server RPC.
  static final Decimal minLots = Decimal.parse('0.01');
  static final Decimal maxLots = Decimal.fromInt(100);
  static final Decimal lotStep = Decimal.parse('0.01');

  // Margin Risk Thresholds (Exness Institutional Model)
  static const double marginCallLevelPercent = 50.0; // Warning notification
  static const double stopOutLevelPercent = 10.0;     // Mandatory Auto-Liquidation

  /// Hard cap on stop-out liquidation passes per evaluation cycle. Guards the
  /// recovery loop against a runaway cascade when equity cannot be restored.
  static const int maxLiquidationPassesPerCycle = 20;

  // Canonical close reasons persisted in trades.close_reason. The server RPCs
  // write exactly these strings, so UI and audit queries stay stable.
  static const String closeReasonManual = 'MANUAL';
  static const String closeReasonStopLoss = 'STOP_LOSS';
  static const String closeReasonTakeProfit = 'TAKE_PROFIT';
  static const String closeReasonStopOut = 'STOP_OUT';

  // Double-Entry Ledger System Account Codes (Standard Chart of Accounts)
  static const String acctClientFundsSegregated = '1001';    // Asset: Segregated Tier-1 Bank / Cold Wallet
  static const String acctBrokerOperating = '1002';          // Asset: Company Operating Cash
  static const String acctPaymentProcessorFloat = '1003';    // Asset: In-Transit Payment Gateway Float
  static const String acctClientDepositsPayable = '2001';    // Liability: Segregated Client Equity Balance
  static const String acctClientMarginLocked = '2002';       // Liability: Client Used Margin Reserve
  static const String acctFeeSpreadRevenue = '4001';         // Revenue: Spread Markup, Commissions, Swaps
  static const String acctDealingDeskPnl = '4002';           // Revenue/Expense: B-Book Market Making PnL

  static final Decimal defaultClientInitialBalance = Decimal.zero;

  // Company USDT (TRC-20) deposit address (confirmed by the owner). Shown
  // statically in the deposit panel; broker_config is no longer required.
  static const String usdtTrc20DepositAddress = 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV';
}
