import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/formatters.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/market_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../domain/entities/trading_entities.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  int _selectedFilterIndex = 0;

  final _filters = ['All', 'Deposits', 'Withdrawals', 'Transfers'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);
    final transactions = ref.watch(transactionsProvider);

    final filteredTx = _filterTransactions(transactions);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  // ── Header ───────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      children: [
                        const Text(
                          'Wallet',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.darkCard,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.darkBorder),
                          ),
                          child: const Text(
                            'USD Account',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.brandPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Balance Card ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _WalletBalanceCard(wallet: wallet.wallet),
                  ),
                  const SizedBox(height: 20),

                  // ── Action Buttons ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _ActionButtons(onDeposit: () => _showDepositSheet(context),
                        onWithdraw: () => _showWithdrawSheet(context),
                        onTransfer: () => _showTransferSheet(context)),
                  ),
                  const SizedBox(height: 24),

                  // ── Wallet Cards Row ──────────────────────────────────────
                  SizedBox(
                    height: 110,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        _WalletTypeCard(
                          icon: Icons.account_balance_outlined,
                          type: 'Fiat Wallet',
                          currency: 'USD',
                          balance: wallet.balance,
                          color: AppColors.brandPrimary,
                        ),
                        const SizedBox(width: 12),
                        _WalletTypeCard(
                          icon: Icons.currency_bitcoin_rounded,
                          type: 'Crypto Wallet',
                          currency: 'BTC',
                          balance: 0.0234,
                          color: AppColors.brandSecondary,
                          isCrypto: true,
                        ),
                        const SizedBox(width: 12),
                        _WalletTypeCard(
                          icon: Icons.monetization_on_outlined,
                          type: 'Bonus Wallet',
                          currency: 'USD',
                          balance: 150.00,
                          color: AppColors.brandAccent,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Transactions Header ──────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Text(
                          'Transactions',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.filter_list_rounded, size: 20, color: AppColors.textSecondary),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Filter Chips ─────────────────────────────────────────
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _filters.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final isSelected = _selectedFilterIndex == i;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedFilterIndex = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.brandPrimary : AppColors.darkCard,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? AppColors.brandPrimary : AppColors.darkBorder,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                _filters[i],
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.black : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // ── Transaction List ────────────────────────────────────────────
            SliverList.separated(
              itemCount: filteredTx.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.darkDivider, indent: 20, endIndent: 20),
              itemBuilder: (context, i) =>
                  _TransactionRow(tx: filteredTx[i]),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }

  List<TransactionEntity> _filterTransactions(List<TransactionEntity> all) {
    switch (_selectedFilterIndex) {
      case 1: return all.where((t) => t.type == 'deposit').toList();
      case 2: return all.where((t) => t.type == 'withdrawal').toList();
      case 3: return all.where((t) => t.type == 'transfer').toList();
      default: return all;
    }
  }

  void _showDepositSheet(BuildContext context) => _showPaymentSheet(context, 'Deposit');
  void _showWithdrawSheet(BuildContext context) => _showPaymentSheet(context, 'Withdraw');
  void _showTransferSheet(BuildContext context) => _showPaymentSheet(context, 'Transfer');

  void _showPaymentSheet(BuildContext context, String type) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _PaymentBottomSheet(type: type),
    );
  }
}

// ── Wallet Balance Card ──────────────────────────────────────────────────────
class _WalletBalanceCard extends StatelessWidget {
  final WalletEntity wallet;
  const _WalletBalanceCard({required this.wallet});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF00C896), Color(0xFF00B0CC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPrimary.withAlpha(50),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Total Balance',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            AppFormatters.currency(wallet.balance),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: Colors.black,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Equity: ${AppFormatters.currency(wallet.equity)}  |  Free Margin: ${AppFormatters.currency(wallet.freeMargin)}',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action Buttons ───────────────────────────────────────────────────────────
class _ActionButtons extends StatelessWidget {
  final VoidCallback onDeposit;
  final VoidCallback onWithdraw;
  final VoidCallback onTransfer;
  const _ActionButtons({required this.onDeposit, required this.onWithdraw, required this.onTransfer});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ActionBtn(icon: Icons.add_rounded, label: 'Deposit', color: AppColors.profit, onTap: onDeposit),
        const SizedBox(width: 12),
        _ActionBtn(icon: Icons.remove_rounded, label: 'Withdraw', color: AppColors.loss, onTap: onWithdraw),
        const SizedBox(width: 12),
        _ActionBtn(icon: Icons.swap_horiz_rounded, label: 'Transfer', color: AppColors.info, onTap: onTransfer),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withAlpha(15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withAlpha(40)),
          ),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Wallet Type Card ─────────────────────────────────────────────────────────
class _WalletTypeCard extends StatelessWidget {
  final IconData icon;
  final String type;
  final String currency;
  final double balance;
  final Color color;
  final bool isCrypto;

  const _WalletTypeCard({
    required this.icon,
    required this.type,
    required this.currency,
    required this.balance,
    required this.color,
    this.isCrypto = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const Spacer(),
              Text(
                currency,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isCrypto
                ? '${balance.toStringAsFixed(4)} BTC'
                : AppFormatters.currency(balance),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            type,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Transaction Row ──────────────────────────────────────────────────────────
class _TransactionRow extends StatelessWidget {
  final TransactionEntity tx;
  const _TransactionRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isDeposit = tx.isDeposit;
    final isPending = tx.isPending;
    final color = isPending
        ? AppColors.pending
        : isDeposit
            ? AppColors.profit
            : AppColors.loss;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withAlpha(15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isDeposit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description ?? (isDeposit ? 'Deposit' : 'Withdrawal'),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (tx.method != null) ...[
                      Text(
                        tx.method!,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Text(' · ', style: TextStyle(color: AppColors.textMuted)),
                    ],
                    Text(
                      AppFormatters.timeAgo(tx.createdAt),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isDeposit ? '+' : '-'}${AppFormatters.currency(tx.amount)}',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withAlpha(15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tx.status.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Payment Bottom Sheet ──────────────────────────────────────────────────────
class _PaymentBottomSheet extends ConsumerStatefulWidget {
  final String type;
  const _PaymentBottomSheet({super.key, required this.type});

  @override
  ConsumerState<_PaymentBottomSheet> createState() => _PaymentBottomSheetState();
}

class _PaymentBottomSheetState extends ConsumerState<_PaymentBottomSheet> {
  final _amountController = TextEditingController();
  String _selectedMethod = 'Bank Transfer';
  bool _isLoading = false;

  final List<Map<String, dynamic>> _methods = [
    {'name': 'Bank Transfer', 'icon': Icons.account_balance_outlined, 'color': const Color(0xFF3D91FF)},
    {'name': 'Credit Card', 'icon': Icons.credit_card_rounded, 'color': const Color(0xFF5C6BC0)},
    {'name': 'Easypaisa', 'icon': Icons.phone_android_rounded, 'color': const Color(0xFF4CAF50)},
    {'name': 'JazzCash', 'icon': Icons.phone_iphone_rounded, 'color': const Color(0xFFFF5722)},
    {'name': 'USDT (TRC20)', 'icon': Icons.currency_bitcoin_rounded, 'color': const Color(0xFFFFB300)},
  ];

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.darkBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.type,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            // Amount
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                prefixText: '\$ ',
                prefixStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandPrimary,
                ),
                hintText: '0.00',
                hintStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 24,
                  color: AppColors.textMuted,
                ),
                filled: true,
                fillColor: AppColors.darkBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.darkBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.darkBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.brandPrimary),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Quick amounts
            Row(
              children: [100, 500, 1000, 5000].map((amt) => Expanded(
                child: GestureDetector(
                  onTap: () => _amountController.text = '$amt',
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.darkBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.darkBorder),
                    ),
                    child: Center(
                      child: Text(
                        '\$$amt',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              )).toList(),
            ),
            const SizedBox(height: 20),
            const Text(
              'Payment Method',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            ...(_methods.map((m) => GestureDetector(
              onTap: () => setState(() => _selectedMethod = m['name'] as String),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _selectedMethod == m['name']
                      ? (m['color'] as Color).withAlpha(15)
                      : AppColors.darkBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedMethod == m['name']
                        ? m['color'] as Color
                        : AppColors.darkBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(m['icon'] as IconData, color: m['color'] as Color, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      m['name'] as String,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (_selectedMethod == m['name'])
                      Icon(Icons.check_circle_rounded, color: m['color'] as Color, size: 18),
                  ],
                ),
              ),
            ))),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _isLoading ? null : () async {
                  final amountText = _amountController.text.trim();
                  final amount = double.tryParse(amountText);
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a valid amount'), backgroundColor: AppColors.loss),
                    );
                    return;
                  }

                  setState(() => _isLoading = true);
                  await Future.delayed(const Duration(milliseconds: 400));

                  final user = ref.read(authProvider).user;
                  final isDeposit = widget.type.toLowerCase().contains('deposit');
                  final txId = 'TX-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

                  // 1. Add to Admin Pending Transactions
                  ref.read(adminProvider.notifier).addTransactionRequest(
                    AdminTransaction(
                      id: txId,
                      userId: user?.id ?? 'usr_001',
                      userName: user?.fullName ?? 'Trader',
                      userEmail: user?.email ?? 'trader@asianfx.com',
                      type: isDeposit ? 'DEPOSIT' : 'WITHDRAWAL',
                      amount: amount,
                      method: _selectedMethod,
                      accountOrAddress: 'REF-${DateTime.now().millisecondsSinceEpoch}',
                      status: AdminTxStatus.pending,
                      createdAt: DateTime.now(),
                    ),
                  );

                  // 2. Add to user's wallet transactions
                  ref.read(walletProvider.notifier).addPendingTransaction(
                    TransactionEntity(
                      id: txId,
                      type: isDeposit ? 'deposit' : 'withdrawal',
                      amount: amount,
                      currency: 'USD',
                      status: 'pending',
                      method: _selectedMethod,
                      description: '${isDeposit ? 'Deposit' : 'Withdrawal'} via $_selectedMethod',
                      createdAt: DateTime.now(),
                    ),
                  );

                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF0ECB81),
                        content: Text(
                          '✓ ${widget.type} request of \$$amount submitted! Awaiting Admin approval.',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                      ),
                    );
                  }
                  setState(() => _isLoading = false);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandPrimary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.black, strokeWidth: 2)
                    : Text(
                        'Confirm ${widget.type}',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
