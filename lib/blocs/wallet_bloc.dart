import 'package:flutter_bloc/flutter_bloc.dart';
import '../domain/entities/trading_entities.dart';

class WalletState {
  final WalletEntity wallet;
  final List<TransactionEntity> transactions;
  final bool isLoading;
  final String? error;

  const WalletState({
    required this.wallet,
    this.transactions = const [],
    this.isLoading = false,
    this.error,
  });

  double get balance => wallet.balance;
  double get totalBalance => wallet.balance;
  double get equity => wallet.equity;
  double get margin => wallet.margin;
  double get freeMargin => wallet.freeMargin;
  double get marginLevel => wallet.marginLevel;
  double get floatingPl => wallet.floatingPl;

  WalletState copyWith({
    WalletEntity? wallet,
    List<TransactionEntity>? transactions,
    bool? isLoading,
    String? error,
  }) {
    return WalletState(
      wallet: wallet ?? this.wallet,
      transactions: transactions ?? this.transactions,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class WalletCubit extends Cubit<WalletState> {
  WalletCubit()
      : super(
          const WalletState(
            wallet: WalletEntity(
              id: 'wlt_001',
              userId: 'usr_001',
              currency: 'USD',
              type: 'live',
              balance: 0.0,
              equity: 0.0,
              margin: 0.0,
              freeMargin: 0.0,
              marginLevel: 0.0,
              floatingPl: 0.0,
            ),
            transactions: [],
          ),
        );

  void addPendingTransaction(TransactionEntity tx) {
    emit(state.copyWith(
      transactions: [tx, ...state.transactions],
    ));
  }

  void creditDeposit(double amount, String method, {String? txId}) {
    final newBal = state.balance + amount;
    final newEquity = state.equity + amount;
    final newFree = state.freeMargin + amount;

    final tx = TransactionEntity(
      id: txId ?? 'tx_${DateTime.now().millisecondsSinceEpoch}',
      type: 'deposit',
      amount: amount,
      currency: 'USD',
      status: 'completed',
      method: method,
      description: 'Instant Deposit via $method',
      createdAt: DateTime.now(),
    );

    emit(state.copyWith(
      wallet: state.wallet.copyWith(
        balance: newBal,
        equity: newEquity,
        freeMargin: newFree,
      ),
      transactions: [tx, ...state.transactions],
    ));
  }

  void debitWithdrawal(double amount, String method, {String? txId, bool autoApprove = false}) {
    final newBal = (state.balance - amount).clamp(0.0, 1000000000.0);
    final newEquity = (state.equity - amount).clamp(0.0, 1000000000.0);
    final newFree = (state.freeMargin - amount).clamp(0.0, 1000000000.0);

    final tx = TransactionEntity(
      id: txId ?? 'tx_${DateTime.now().millisecondsSinceEpoch}',
      type: 'withdrawal',
      amount: amount,
      currency: 'USD',
      status: autoApprove ? 'completed' : 'pending',
      method: method,
      description: autoApprove
          ? 'Instant Withdrawal via $method'
          : 'Withdrawal via $method',
      createdAt: DateTime.now(),
    );

    emit(state.copyWith(
      wallet: state.wallet.copyWith(
        balance: newBal,
        equity: newEquity,
        freeMargin: newFree,
      ),
      transactions: [tx, ...state.transactions],
    ));
  }

  void updateWalletBalance(double balance, {double? equity, double? margin, double? freeMargin}) {
    emit(state.copyWith(
      wallet: state.wallet.copyWith(
        balance: balance,
        equity: equity ?? balance,
        margin: margin ?? state.margin,
        freeMargin: freeMargin ?? balance,
      ),
    ));
  }
}

typedef WalletBloc = WalletCubit;
