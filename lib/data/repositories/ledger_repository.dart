import 'package:decimal/decimal.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../core/math/money_math.dart';
import '../../domain/entities/ledger_entities.dart';

/// In-Memory & Supabase-Ready High-Precision Double-Entry Financial Ledger Repository
class LedgerRepository {
  final List<LedgerTransaction> _transactions = [];
  final _uuid = const Uuid();

  LedgerRepository() {
    _seedInitialLedgerState();
  }

  /// Seed initial institutional ledger state
  void _seedInitialLedgerState() {
    final now = DateTime.now();

    // 1. Initial Broker Capitalization
    _recordTransactionInternal(
      type: LedgerTxType.adjustment,
      description: 'Broker Initial Capitalization (Tier-1 Liquidity)',
      referenceNumber: 'TX-INIT-001',
      timestamp: now.subtract(const Duration(days: 30)),
      entries: [
        LedgerEntry(
          id: _uuid.v4(),
          transactionId: 'TX-INIT-001',
          accountCode: AppConstants.acctBrokerOperating,
          accountName: 'Broker Operating Cash',
          accountType: LedgerAccountType.companyOperating,
          debit: Decimal.fromInt(1000000), // $1,000,000
          credit: Decimal.zero,
          memo: 'Broker Operating Capital',
          createdAt: now.subtract(const Duration(days: 30)),
        ),
        LedgerEntry(
          id: _uuid.v4(),
          transactionId: 'TX-INIT-001',
          accountCode: AppConstants.acctFeeSpreadRevenue,
          accountName: 'Retained Broker Equity & Reserves',
          accountType: LedgerAccountType.feeRevenue,
          debit: Decimal.zero,
          credit: Decimal.fromInt(1000000),
          memo: 'Broker Retained Equity',
          createdAt: now.subtract(const Duration(days: 30)),
        ),
      ],
    );

  }

  /// Internal helper to enforce invariant before appending
  void _recordTransactionInternal({
    required LedgerTxType type,
    required String description,
    required String referenceNumber,
    required List<LedgerEntry> entries,
    String? userId,
    String? tradeId,
    DateTime? timestamp,
  }) {
    final tx = LedgerTransaction(
      id: _uuid.v4(),
      referenceNumber: referenceNumber,
      type: type,
      description: description,
      userId: userId,
      tradeId: tradeId,
      entries: entries,
      timestamp: timestamp ?? DateTime.now(),
    );

    // INVARIANT CHECK
    if (!tx.isBalanced) {
      throw StateError(
        'DOUBLE-ENTRY VIOLATION: Transaction $referenceNumber is unbalanced! '
        'Debits: ${tx.totalDebits}, Credits: ${tx.totalCredits}, Drift: ${tx.imbalanceDrift}',
      );
    }

    _transactions.insert(0, tx);
  }

  /// 1. Record Client Deposit
  /// Debit: 1001 (Segregated Asset) | Credit: 2001 (Client Deposits Payable)
  LedgerTransaction recordDeposit({
    required String userId,
    required Decimal amount,
    required String method,
    DateTime? timestamp,
  }) {
    final txId = 'TX-DEP-${DateTime.now().millisecondsSinceEpoch}';
    final time = timestamp ?? DateTime.now();

    final entries = [
      LedgerEntry(
        id: _uuid.v4(),
        transactionId: txId,
        accountCode: AppConstants.acctClientFundsSegregated,
        accountName: 'Segregated Client Bank/Cold Storage',
        accountType: LedgerAccountType.clientFunds,
        debit: amount,
        credit: Decimal.zero,
        userId: userId,
        memo: 'Deposit via $method',
        createdAt: time,
      ),
      LedgerEntry(
        id: _uuid.v4(),
        transactionId: txId,
        accountCode: AppConstants.acctClientDepositsPayable,
        accountName: 'Client Deposits Payable (Segregated Equity)',
        accountType: LedgerAccountType.clientDepositsPayable,
        debit: Decimal.zero,
        credit: amount,
        userId: userId,
        memo: 'Credit Client Ledger Balance',
        createdAt: time,
      ),
    ];

    _recordTransactionInternal(
      type: LedgerTxType.deposit,
      description: 'Client Deposit ($method)',
      referenceNumber: txId,
      userId: userId,
      entries: entries,
      timestamp: time,
    );

    return _transactions.first;
  }

  /// 2. Record Client Withdrawal
  /// Debit: 2001 (Client Deposits Payable) | Credit: 1001 (Segregated Asset)
  LedgerTransaction recordWithdrawal({
    required String userId,
    required Decimal amount,
    required String destinationAddress,
    DateTime? timestamp,
  }) {
    final txId = 'TX-WTH-${DateTime.now().millisecondsSinceEpoch}';
    final time = timestamp ?? DateTime.now();

    final entries = [
      LedgerEntry(
        id: _uuid.v4(),
        transactionId: txId,
        accountCode: AppConstants.acctClientDepositsPayable,
        accountName: 'Client Deposits Payable',
        accountType: LedgerAccountType.clientDepositsPayable,
        debit: amount,
        credit: Decimal.zero,
        userId: userId,
        memo: 'Withdrawal to $destinationAddress',
        createdAt: time,
      ),
      LedgerEntry(
        id: _uuid.v4(),
        transactionId: txId,
        accountCode: AppConstants.acctClientFundsSegregated,
        accountName: 'Segregated Client Bank/Cold Storage',
        accountType: LedgerAccountType.clientFunds,
        debit: Decimal.zero,
        credit: amount,
        userId: userId,
        memo: 'Disbursement of funds',
        createdAt: time,
      ),
    ];

    _recordTransactionInternal(
      type: LedgerTxType.withdrawal,
      description: 'Client Withdrawal ($destinationAddress)',
      referenceNumber: txId,
      userId: userId,
      entries: entries,
      timestamp: time,
    );

    return _transactions.first;
  }

  /// 3. Record Trade Margin Lock (Order Opened)
  /// Debit: 2001 (Client Available Funds) | Credit: 2002 (Client Locked Margin)
  LedgerTransaction recordMarginLock({
    required String userId,
    required String tradeId,
    required Decimal marginAmount,
    required String symbol,
  }) {
    final txId = 'TX-MRG-LOCK-${DateTime.now().millisecondsSinceEpoch}';
    final time = DateTime.now();

    final entries = [
      LedgerEntry(
        id: _uuid.v4(),
        transactionId: txId,
        accountCode: AppConstants.acctClientDepositsPayable,
        accountName: 'Client Deposits Payable (Free Balance)',
        accountType: LedgerAccountType.clientDepositsPayable,
        debit: marginAmount,
        credit: Decimal.zero,
        userId: userId,
        memo: 'Margin lock for trade $tradeId ($symbol)',
        createdAt: time,
      ),
      LedgerEntry(
        id: _uuid.v4(),
        transactionId: txId,
        accountCode: AppConstants.acctClientMarginLocked,
        accountName: 'Client Margin Locked',
        accountType: LedgerAccountType.clientMarginLocked,
        debit: Decimal.zero,
        credit: marginAmount,
        userId: userId,
        memo: 'Collateral held for position $tradeId',
        createdAt: time,
      ),
    ];

    _recordTransactionInternal(
      type: LedgerTxType.tradeMarginLock,
      description: 'Trade Margin Lock: $symbol',
      referenceNumber: txId,
      userId: userId,
      tradeId: tradeId,
      entries: entries,
      timestamp: time,
    );

    return _transactions.first;
  }

  /// 4. Record Trade Margin Release (Order Closed / Liquidated)
  /// Debit: 2002 (Client Locked Margin) | Credit: 2001 (Client Available Funds)
  LedgerTransaction recordMarginRelease({
    required String userId,
    required String tradeId,
    required Decimal marginAmount,
    required String symbol,
  }) {
    final txId = 'TX-MRG-REL-${DateTime.now().millisecondsSinceEpoch}';
    final time = DateTime.now();

    final entries = [
      LedgerEntry(
        id: _uuid.v4(),
        transactionId: txId,
        accountCode: AppConstants.acctClientMarginLocked,
        accountName: 'Client Margin Locked',
        accountType: LedgerAccountType.clientMarginLocked,
        debit: marginAmount,
        credit: Decimal.zero,
        userId: userId,
        memo: 'Margin release for trade $tradeId ($symbol)',
        createdAt: time,
      ),
      LedgerEntry(
        id: _uuid.v4(),
        transactionId: txId,
        accountCode: AppConstants.acctClientDepositsPayable,
        accountName: 'Client Deposits Payable (Free Balance)',
        accountType: LedgerAccountType.clientDepositsPayable,
        debit: Decimal.zero,
        credit: marginAmount,
        userId: userId,
        memo: 'Collateral released from position $tradeId',
        createdAt: time,
      ),
    ];

    _recordTransactionInternal(
      type: LedgerTxType.tradeMarginRelease,
      description: 'Trade Margin Release: $symbol',
      referenceNumber: txId,
      userId: userId,
      tradeId: tradeId,
      entries: entries,
      timestamp: time,
    );

    return _transactions.first;
  }

  /// 5. Record Realized Trade PnL
  /// If Profit: Debit 4002 (Dealing Desk / Reserves) | Credit 2001 (Client Deposits Payable)
  /// If Loss:   Debit 2001 (Client Deposits Payable) | Credit 4002 (Dealing Desk / Reserves)
  LedgerTransaction recordTradePnl({
    required String userId,
    required String tradeId,
    required Decimal pnlAmount,
    required String symbol,
  }) {
    final txId = 'TX-PNL-${DateTime.now().millisecondsSinceEpoch}';
    final time = DateTime.now();
    final isProfit = pnlAmount >= Decimal.zero;
    final absPnl = pnlAmount.abs();

    final entries = isProfit
        ? [
            LedgerEntry(
              id: _uuid.v4(),
              transactionId: txId,
              accountCode: AppConstants.acctDealingDeskPnl,
              accountName: 'Dealing Desk B-Book PnL Reserve',
              accountType: LedgerAccountType.dealingDeskPnl,
              debit: absPnl,
              credit: Decimal.zero,
              userId: userId,
              memo: 'Client Profit Disbursement for $tradeId ($symbol)',
              createdAt: time,
            ),
            LedgerEntry(
              id: _uuid.v4(),
              transactionId: txId,
              accountCode: AppConstants.acctClientDepositsPayable,
              accountName: 'Client Deposits Payable',
              accountType: LedgerAccountType.clientDepositsPayable,
              debit: Decimal.zero,
              credit: absPnl,
              userId: userId,
              memo: 'Realized Profit Credited',
              createdAt: time,
            ),
          ]
        : [
            LedgerEntry(
              id: _uuid.v4(),
              transactionId: txId,
              accountCode: AppConstants.acctClientDepositsPayable,
              accountName: 'Client Deposits Payable',
              accountType: LedgerAccountType.clientDepositsPayable,
              debit: absPnl,
              credit: Decimal.zero,
              userId: userId,
              memo: 'Realized Loss Debited for $tradeId ($symbol)',
              createdAt: time,
            ),
            LedgerEntry(
              id: _uuid.v4(),
              transactionId: txId,
              accountCode: AppConstants.acctDealingDeskPnl,
              accountName: 'Dealing Desk B-Book PnL Reserve',
              accountType: LedgerAccountType.dealingDeskPnl,
              debit: Decimal.zero,
              credit: absPnl,
              userId: userId,
              memo: 'Client Loss Booked to House Reserves',
              createdAt: time,
            ),
          ];

    _recordTransactionInternal(
      type: LedgerTxType.tradePnl,
      description: 'Realized PnL: $symbol (${MoneyMath.formatPnL(pnlAmount)})',
      referenceNumber: txId,
      userId: userId,
      tradeId: tradeId,
      entries: entries,
      timestamp: time,
    );

    return _transactions.first;
  }

  /// 6. Record Spread Markup / Commission Fee
  /// Debit: 2001 (Client Deposits Payable) | Credit: 4001 (Fee Revenue)
  LedgerTransaction recordFee({
    required String userId,
    required String tradeId,
    required Decimal feeAmount,
    required String feeDescription,
  }) {
    if (feeAmount <= Decimal.zero) {
      return _transactions.first;
    }

    final txId = 'TX-FEE-${DateTime.now().millisecondsSinceEpoch}';
    final time = DateTime.now();

    final entries = [
      LedgerEntry(
        id: _uuid.v4(),
        transactionId: txId,
        accountCode: AppConstants.acctClientDepositsPayable,
        accountName: 'Client Deposits Payable',
        accountType: LedgerAccountType.clientDepositsPayable,
        debit: feeAmount,
        credit: Decimal.zero,
        userId: userId,
        memo: feeDescription,
        createdAt: time,
      ),
      LedgerEntry(
        id: _uuid.v4(),
        transactionId: txId,
        accountCode: AppConstants.acctFeeSpreadRevenue,
        accountName: 'Broker Fee & Spread Revenue',
        accountType: LedgerAccountType.feeRevenue,
        debit: Decimal.zero,
        credit: feeAmount,
        userId: userId,
        memo: 'Spread markup / commission earned',
        createdAt: time,
      ),
    ];

    _recordTransactionInternal(
      type: LedgerTxType.fee,
      description: feeDescription,
      referenceNumber: txId,
      userId: userId,
      tradeId: tradeId,
      entries: entries,
      timestamp: time,
    );

    return _transactions.first;
  }

  /// Get all ledger transactions (sorted descending by timestamp)
  List<LedgerTransaction> getTransactions({String? userId}) {
    if (userId == null) return List.unmodifiable(_transactions);
    return _transactions.where((tx) => tx.userId == userId || tx.userId == null).toList();
  }

  /// Calculate Client Cash Ledger Balance strictly by aggregating ledger entries
  /// Client Balance = Sum(Credits to 2001) - Sum(Debits to 2001)
  Decimal getClientLedgerBalance(String userId) {
    Decimal balance = Decimal.zero;
    for (final tx in _transactions) {
      for (final entry in tx.entries) {
        if (entry.accountCode == AppConstants.acctClientDepositsPayable &&
            (entry.userId == userId || entry.userId == null || entry.userId == 'usr_institutional_01')) {
          balance += (entry.credit - entry.debit);
        }
      }
    }
    return balance;
  }

  /// Calculate Client Margin Locked
  Decimal getClientMarginLocked(String userId) {
    Decimal margin = Decimal.zero;
    for (final tx in _transactions) {
      for (final entry in tx.entries) {
        if (entry.accountCode == AppConstants.acctClientMarginLocked &&
            (entry.userId == userId || entry.userId == null)) {
          margin += (entry.credit - entry.debit);
        }
      }
    }
    return margin;
  }

  /// Generate Institutional Treasury Audit Proof
  TreasuryAuditProof generateTreasuryProof() {
    Decimal totalDebits = Decimal.zero;
    Decimal totalCredits = Decimal.zero;
    int entryCount = 0;

    Decimal segregatedAssets = Decimal.zero;
    Decimal clientLiabilities = Decimal.zero;

    for (final tx in _transactions) {
      for (final entry in tx.entries) {
        totalDebits += entry.debit;
        totalCredits += entry.credit;
        entryCount++;

        if (entry.accountCode == AppConstants.acctClientFundsSegregated) {
          segregatedAssets += (entry.debit - entry.credit);
        }
        if (entry.accountCode == AppConstants.acctClientDepositsPayable ||
            entry.accountCode == AppConstants.acctClientMarginLocked) {
          clientLiabilities += (entry.credit - entry.debit);
        }
      }
    }

    final drift = totalDebits - totalCredits;
    final isValid = drift == Decimal.zero;

    return TreasuryAuditProof(
      totalSystemDebits: totalDebits,
      totalSystemCredits: totalCredits,
      accountingDrift: drift,
      isProofValid: isValid,
      totalTransactionCount: _transactions.length,
      totalEntryCount: entryCount,
      segregatedClientAssets: segregatedAssets,
      totalClientLiabilities: clientLiabilities,
      auditedAt: DateTime.now(),
    );
  }
}
