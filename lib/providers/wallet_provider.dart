import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class WalletNotifier extends StateNotifier<WalletState> {
  WalletNotifier()
      : super(
          WalletState(
            wallet: const WalletEntity(
              id: 'wlt_001',
              userId: 'usr_001',
              currency: 'USD',
              type: 'live',
              balance: 10450.00,
              equity: 10915.00,
              margin: 450.00,
              freeMargin: 10465.00,
              marginLevel: 2425.5,
              floatingPl: 465.00,
            ),
            transactions: [
              TransactionEntity(
                id: 'tx_001',
                type: 'deposit',
                amount: 5000.0,
                currency: 'USD',
                status: 'completed',
                method: 'Credit Card (Visa)',
                description: 'Initial Deposit',
                createdAt: DateTime.now().subtract(const Duration(days: 7)),
              ),
              TransactionEntity(
                id: 'tx_002',
                type: 'deposit',
                amount: 5000.0,
                currency: 'USD',
                status: 'completed',
                method: 'Bank Wire',
                description: 'Top-up Deposit',
                createdAt: DateTime.now().subtract(const Duration(days: 3)),
              ),
            ],
          ),
        );

  Future<bool> deposit({required double amount, required String method}) async {
    state = state.copyWith(isLoading: true);
    await Future.delayed(const Duration(seconds: 1));

    final newTx = TransactionEntity(
      id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
      type: 'deposit',
      amount: amount,
      currency: 'USD',
      status: 'completed',
      method: method,
      description: 'Account Deposit',
      createdAt: DateTime.now(),
    );

    final updatedWallet = WalletEntity(
      id: state.wallet.id,
      userId: state.wallet.userId,
      currency: state.wallet.currency,
      type: state.wallet.type,
      balance: state.wallet.balance + amount,
      equity: state.wallet.equity + amount,
      margin: state.wallet.margin,
      freeMargin: state.wallet.freeMargin + amount,
      marginLevel: state.wallet.marginLevel,
      floatingPl: state.wallet.floatingPl,
    );

    state = state.copyWith(
      wallet: updatedWallet,
      transactions: [newTx, ...state.transactions],
      isLoading: false,
    );
    return true;
  }

  Future<bool> withdraw({required double amount, required String method}) async {
    if (amount > state.wallet.freeMargin) {
      state = state.copyWith(error: 'Insufficient free margin for withdrawal');
      return false;
    }

    state = state.copyWith(isLoading: true);
    await Future.delayed(const Duration(seconds: 1));

    final newTx = TransactionEntity(
      id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
      type: 'withdrawal',
      amount: amount,
      currency: 'USD',
      status: 'pending',
      method: method,
      description: 'Withdrawal request',
      createdAt: DateTime.now(),
    );

    state = state.copyWith(
      transactions: [newTx, ...state.transactions],
      isLoading: false,
    );
    return true;
  }
}

final walletProvider = StateNotifierProvider<WalletNotifier, WalletState>((ref) {
  return WalletNotifier();
});
