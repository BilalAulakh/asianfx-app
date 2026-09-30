import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/repositories/ledger_repository.dart';
import '../domain/entities/ledger_entities.dart';

class LedgerState {
  final List<LedgerTransaction> transactions;
  final TreasuryAuditProof? auditProof;

  const LedgerState({
    this.transactions = const [],
    this.auditProof,
  });

  LedgerState copyWith({
    List<LedgerTransaction>? transactions,
    TreasuryAuditProof? auditProof,
  }) {
    return LedgerState(
      transactions: transactions ?? this.transactions,
      auditProof: auditProof ?? this.auditProof,
    );
  }
}

class LedgerCubit extends Cubit<LedgerState> {
  final LedgerRepository repository;

  LedgerCubit({LedgerRepository? repo})
      : repository = repo ?? LedgerRepository.instance,
        super(const LedgerState()) {
    refresh();
  }

  void refresh({String? userId}) {
    final txs = repository.getTransactions(userId: userId);
    final proof = repository.generateTreasuryProof();
    emit(LedgerState(transactions: txs, auditProof: proof));
  }

  Decimal getClientBalance(String userId) {
    return repository.getClientLedgerBalance(userId);
  }

  Decimal getClientMarginLocked(String userId) {
    return repository.getClientMarginLocked(userId);
  }

  LedgerTransaction deposit({
    required String userId,
    required Decimal amount,
    required String method,
  }) {
    final tx = repository.recordDeposit(
      userId: userId,
      amount: amount,
      method: method,
    );
    refresh(userId: userId);
    return tx;
  }

  LedgerTransaction withdraw({
    required String userId,
    required Decimal amount,
    required String destinationAddress,
  }) {
    final tx = repository.recordWithdrawal(
      userId: userId,
      amount: amount,
      destinationAddress: destinationAddress,
    );
    refresh(userId: userId);
    return tx;
  }

  LedgerTransaction lockMargin({
    required String userId,
    required String tradeId,
    required Decimal marginAmount,
    required String symbol,
  }) {
    final tx = repository.recordMarginLock(
      userId: userId,
      tradeId: tradeId,
      marginAmount: marginAmount,
      symbol: symbol,
    );
    refresh(userId: userId);
    return tx;
  }

  LedgerTransaction releaseMargin({
    required String userId,
    required String tradeId,
    required Decimal marginAmount,
    required String symbol,
  }) {
    final tx = repository.recordMarginRelease(
      userId: userId,
      tradeId: tradeId,
      marginAmount: marginAmount,
      symbol: symbol,
    );
    refresh(userId: userId);
    return tx;
  }

  LedgerTransaction recordTradeRealizedPnl({
    required String userId,
    required String tradeId,
    required Decimal realizedPnl,
    required String symbol,
  }) {
    final tx = repository.recordRealizedPnl(
      userId: userId,
      tradeId: tradeId,
      realizedPnl: realizedPnl,
      symbol: symbol,
    );
    refresh(userId: userId);
    return tx;
  }

  LedgerTransaction recordFeeRevenue({
    required String userId,
    required String tradeId,
    required Decimal feeAmount,
    required String feeDescription,
  }) {
    final tx = repository.recordFeeRevenue(
      userId: userId,
      tradeId: tradeId,
      feeAmount: feeAmount,
      feeDescription: feeDescription,
    );
    refresh(userId: userId);
    return tx;
  }
}

typedef LedgerBloc = LedgerCubit;
