import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/ledger_repository.dart';
import '../domain/entities/ledger_entities.dart';
import 'auth_provider.dart';

final ledgerRepositoryProvider = Provider<LedgerRepository>((ref) {
  return LedgerRepository();
});

class LedgerNotifier extends StateNotifier<List<LedgerTransaction>> {
  final LedgerRepository _repository;
  final Ref _ref;

  LedgerNotifier(this._repository, this._ref) : super([]) {
    refresh();
  }

  void refresh() {
    state = _repository.getTransactions();
  }

  /// Deposit funds
  LedgerTransaction deposit({
    required String userId,
    required Decimal amount,
    required String method,
  }) {
    final tx = _repository.recordDeposit(
      userId: userId,
      amount: amount,
      method: method,
    );
    refresh();
    return tx;
  }

  /// Withdraw funds
  LedgerTransaction withdraw({
    required String userId,
    required Decimal amount,
    required String destinationAddress,
  }) {
    final tx = _repository.recordWithdrawal(
      userId: userId,
      amount: amount,
      destinationAddress: destinationAddress,
    );
    refresh();
    return tx;
  }

  /// Lock margin when trade opens
  LedgerTransaction lockMargin({
    required String userId,
    required String tradeId,
    required Decimal marginAmount,
    required String symbol,
  }) {
    final tx = _repository.recordMarginLock(
      userId: userId,
      tradeId: tradeId,
      marginAmount: marginAmount,
      symbol: symbol,
    );
    refresh();
    return tx;
  }

  /// Release margin when trade closes
  LedgerTransaction releaseMargin({
    required String userId,
    required String tradeId,
    required Decimal marginAmount,
    required String symbol,
  }) {
    final tx = _repository.recordMarginRelease(
      userId: userId,
      tradeId: tradeId,
      marginAmount: marginAmount,
      symbol: symbol,
    );
    refresh();
    return tx;
  }

  /// Record realized PnL on closed trade
  LedgerTransaction recordTradePnl({
    required String userId,
    required String tradeId,
    required Decimal pnlAmount,
    required String symbol,
  }) {
    final tx = _repository.recordTradePnl(
      userId: userId,
      tradeId: tradeId,
      pnlAmount: pnlAmount,
      symbol: symbol,
    );
    refresh();
    return tx;
  }

  /// Record broker spread fee
  LedgerTransaction recordFee({
    required String userId,
    required String tradeId,
    required Decimal feeAmount,
    required String feeDescription,
  }) {
    final tx = _repository.recordFee(
      userId: userId,
      tradeId: tradeId,
      feeAmount: feeAmount,
      feeDescription: feeDescription,
    );
    refresh();
    return tx;
  }
}

final ledgerProvider = StateNotifierProvider<LedgerNotifier, List<LedgerTransaction>>((ref) {
  final repo = ref.watch(ledgerRepositoryProvider);
  return LedgerNotifier(repo, ref);
});

/// Reactive Client Pure Cash Balance derived from double-entry ledger entries
final clientLedgerBalanceProvider = Provider<Decimal>((ref) {
  final txs = ref.watch(ledgerProvider);
  final authUser = ref.watch(authProvider).user;
  final userId = authUser?.id ?? 'usr_institutional_01';
  final repo = ref.watch(ledgerRepositoryProvider);
  return repo.getClientLedgerBalance(userId);
});

/// Reactive Treasury & Audit Proof Provider
final treasuryAuditProofProvider = Provider<TreasuryAuditProof>((ref) {
  final _ = ref.watch(ledgerProvider);
  final repo = ref.watch(ledgerRepositoryProvider);
  return repo.generateTreasuryProof();
});
