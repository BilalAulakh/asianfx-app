import 'package:decimal/decimal.dart';

/// Institutional trading specifications, contract multipliers, and risk thresholds
class AppConstants {
  AppConstants._();

  // App Meta
  static const String appName = 'FXAsian Institutional';
  static const String appVersion = '2.4.0-Enterprise';

  // Precision contract sizes
  static final Decimal contractSizeGold = Decimal.fromInt(100);       // 1 Lot XAUUSD = 100 oz
  static final Decimal contractSizeSilver = Decimal.fromInt(5000);    // 1 Lot XAGUSD = 5,000 oz
  static final Decimal contractSizeForex = Decimal.fromInt(100000);   // 1 Lot EURUSD = 100,000 units
  static final Decimal contractSizeCrypto = Decimal.one;              // 1 Lot BTCUSD = 1 BTC

  // Dynamic leverage choices
  static const List<int> availableLeverages = [50, 100, 200, 500];
  
  static const int defaultLeverage = 100;

  // Margin Risk Thresholds (Exness Institutional Model)
  static const double marginCallLevelPercent = 50.0; // Warning notification
  static const double stopOutLevelPercent = 10.0;     // Mandatory Auto-Liquidation

  // Double-Entry Ledger System Account Codes (Standard Chart of Accounts)
  static const String acctClientFundsSegregated = '1001';    // Asset: Segregated Tier-1 Bank / Cold Wallet
  static const String acctBrokerOperating = '1002';          // Asset: Company Operating Cash
  static const String acctPaymentProcessorFloat = '1003';    // Asset: In-Transit Payment Gateway Float
  static const String acctClientDepositsPayable = '2001';    // Liability: Segregated Client Equity Balance
  static const String acctClientMarginLocked = '2002';       // Liability: Client Used Margin Reserve
  static const String acctFeeSpreadRevenue = '4001';         // Revenue: Spread Markup, Commissions, Swaps
  static const String acctDealingDeskPnl = '4002';           // Revenue/Expense: B-Book Market Making PnL

  static final Decimal defaultClientInitialBalance = Decimal.zero;

  static const String usdtTrc20DepositAddress = 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV';
}
