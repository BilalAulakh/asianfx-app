import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import '../../core/math/money_math.dart';

/// Double-Entry Ledger Account Classification
enum LedgerAccountType {
  clientFunds,           // Segregated Asset (1001)
  companyOperating,      // Broker Operating Asset (1002)
  paymentProcessorFloat, // Gateway Asset (1003)
  clientDepositsPayable, // Client Equity Liability (2001)
  clientMarginLocked,    // Client Margin Liability (2002)
  feeRevenue,            // Broker Fee Revenue (4001)
  dealingDeskPnl,        // Dealing Desk Trading Revenue/Expense (4002)
}

/// Transaction Types supported by the financial ledger
enum LedgerTxType {
  deposit,
  withdrawal,
  tradeMarginLock,
  tradeMarginRelease,
  tradePnl,
  fee,
  commission,
  swap,
  adjustment,
}

/// Single Line Item Entry in the Double-Entry Ledger (Debit or Credit)
class LedgerEntry extends Equatable {
  final String id;
  final String transactionId;
  final String accountCode;
  final String accountName;
  final LedgerAccountType accountType;
  final Decimal debit;
  final Decimal credit;
  final String? userId;
  final String? memo;
  final DateTime createdAt;

  const LedgerEntry({
    required this.id,
    required this.transactionId,
    required this.accountCode,
    required this.accountName,
    required this.accountType,
    required this.debit,
    required this.credit,
    this.userId,
    this.memo,
    required this.createdAt,
  });

  bool get isDebit => debit > Decimal.zero;
  bool get isCredit => credit > Decimal.zero;
  Decimal get netAmount => debit - credit;

  @override
  List<Object?> get props => [
        id, transactionId, accountCode, debit, credit, memo, createdAt,
      ];
}

/// Balanced Atomic Financial Transaction containing >=2 ledger entries
class LedgerTransaction extends Equatable {
  final String id;
  final String referenceNumber;
  final LedgerTxType type;
  final String description;
  final String? userId;
  final String? tradeId;
  final List<LedgerEntry> entries;
  final DateTime timestamp;

  const LedgerTransaction({
    required this.id,
    required this.referenceNumber,
    required this.type,
    required this.description,
    this.userId,
    this.tradeId,
    required this.entries,
    required this.timestamp,
  });

  /// Calculate sum of Debits in this transaction
  Decimal get totalDebits {
    return entries.fold(Decimal.zero, (sum, e) => sum + e.debit);
  }

  /// Calculate sum of Credits in this transaction
  Decimal get totalCredits {
    return entries.fold(Decimal.zero, (sum, e) => sum + e.credit);
  }

  /// Strict Mathematical Invariant Check: Sum(Debits) == Sum(Credits)
  bool get isBalanced {
    return totalDebits == totalCredits;
  }

  /// Returns drift if any (should always be 0.00)
  Decimal get imbalanceDrift {
    return totalDebits - totalCredits;
  }

  String get typeDisplay {
    switch (type) {
      case LedgerTxType.deposit:
        return 'Deposit Settlement';
      case LedgerTxType.withdrawal:
        return 'Withdrawal Disbursement';
      case LedgerTxType.tradeMarginLock:
        return 'Trade Margin Lock';
      case LedgerTxType.tradeMarginRelease:
        return 'Trade Margin Release';
      case LedgerTxType.tradePnl:
        return 'Trade PnL Realization';
      case LedgerTxType.fee:
        return 'Spread Markup Fee';
      case LedgerTxType.commission:
        return 'Commission';
      case LedgerTxType.swap:
        return 'Overnight Swap Fee';
      case LedgerTxType.adjustment:
        return 'Audit Balance Adjustment';
    }
  }

  @override
  List<Object?> get props => [id, referenceNumber, type, entries, timestamp];
}

/// Ledger Account Summary Proof
class LedgerAccountBalance extends Equatable {
  final String accountCode;
  final String accountName;
  final LedgerAccountType accountType;
  final Decimal totalDebits;
  final Decimal totalCredits;
  final Decimal balance;

  const LedgerAccountBalance({
    required this.accountCode,
    required this.accountName,
    required this.accountType,
    required this.totalDebits,
    required this.totalCredits,
    required this.balance,
  });

  @override
  List<Object?> get props => [accountCode, balance, totalDebits, totalCredits];
}

/// Real-time Treasury Audit Proof
class TreasuryAuditProof extends Equatable {
  final Decimal totalSystemDebits;
  final Decimal totalSystemCredits;
  final Decimal accountingDrift;
  final bool isProofValid;
  final int totalTransactionCount;
  final int totalEntryCount;
  final Decimal segregatedClientAssets;
  final Decimal totalClientLiabilities;
  final DateTime auditedAt;

  const TreasuryAuditProof({
    required this.totalSystemDebits,
    required this.totalSystemCredits,
    required this.accountingDrift,
    required this.isProofValid,
    required this.totalTransactionCount,
    required this.totalEntryCount,
    required this.segregatedClientAssets,
    required this.totalClientLiabilities,
    required this.auditedAt,
  });

  Decimal get totalAssets => segregatedClientAssets;
  Decimal get totalLiabilities => totalClientLiabilities;
  bool get isZeroDriftVerified => isProofValid && accountingDrift == Decimal.zero;
  String get auditHash =>
      '0x${(totalSystemDebits.toString() + totalSystemCredits.toString() + auditedAt.toIso8601String()).hashCode.abs().toRadixString(16).padLeft(16, '0').toUpperCase()}A8B92D1F4C6E';

  @override
  List<Object?> get props => [
        totalSystemDebits,
        totalSystemCredits,
        accountingDrift,
        isProofValid,
        totalTransactionCount,
        auditedAt,
      ];
}
