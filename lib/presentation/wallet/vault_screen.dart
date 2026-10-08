import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../blocs/blocs.dart';
import '../../core/math/money_math.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/trading_entities.dart';
import '../../domain/entities/user_entity.dart';
import '../../data/datasources/supabase_deposit_service.dart';
import 'widgets/deposit_panel.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _scrollController = ScrollController();
  final GlobalKey _depositSectionKey = GlobalKey();
  bool _showDepositSection = false;

  bool get _isDark => context.watch<ThemeCubit>().state;
  Color get _cardBg => context.cardBg;
  Color get _subCardBg => context.inputBg;
  Color get _subtleBorder => context.subtleBorderColor;
  Color get _textPrimary => context.textPrimaryColor;
  Color get _textSecondary => context.textSecondaryColor;
  Color get _mutedValue => context.textPrimaryColor;

  static const _brandGreen = AppColors.profit;
  static const _lossRed = AppColors.loss;

  List<BoxShadow> get _cardShadow => const [];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToDeposit() {
    if (_depositSectionKey.currentContext != null) {
      Scrollable.ensureVisible(
        _depositSectionKey.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final engineState = context.watch<TradingEngineBloc>().state;
    final account = engineState.accountState;
    // Show the authoritative wallet balance. This used to read the in-memory
    // double-entry aggregate (a demo bookkeeping figure) and then rewrite a
    // balance of exactly 10,000 or 25,000 to zero, so a real $10,000 account
    // displayed $0. Free margin also now includes floating PnL, matching the
    // number the server checks when an order is submitted.
    final displayedBalance = account.ledgerBalance;
    final cleanFreeMargin = account.freeMargin < Decimal.zero
        ? Decimal.zero
        : account.freeMargin;
    final authUser = context.watch<AuthBloc>().state.user;
    final isDark = _isDark;

    final rawId = authUser?.id ?? 'TRADER01';
    final accountId = (rawId.length > 8 ? rawId.substring(0, 8) : rawId)
        .toUpperCase();

    final floating = account.unrealizedPnl;
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──────────────────────────────────────────────────────
              Row(
                children: [
                  Text(
                    'Accounts',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme',
                    onPressed: () => context.read<ThemeCubit>().toggleTheme(),
                    icon: Icon(
                      isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                      color: _textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Account card ────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: isDark ? null : Border.all(color: _subtleBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _tag('Real', highlight: true),
                        _tag('Standard'),
                        _tag('#AFX-$accountId'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${MoneyMath.formatCurrency(displayedBalance, symbol: '')} ${account.currency}',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                        height: 1.1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Balance',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: _textSecondary),
                    ),
                    const SizedBox(height: 16),
                    Divider(height: 1, thickness: 1, color: _subtleBorder),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _vaultBreakdownItem('Free margin', MoneyMath.formatCurrency(cleanFreeMargin)),
                        _vaultBreakdownItem('Used margin', MoneyMath.formatCurrency(account.usedMargin)),
                        _vaultBreakdownItem(
                          'Floating P/L',
                          floating == Decimal.zero
                              ? MoneyMath.formatCurrency(Decimal.zero)
                              : MoneyMath.formatPnL(floating),
                          valueColor: floating > Decimal.zero
                              ? _brandGreen
                              : floating < Decimal.zero
                                  ? _lossRed
                                  : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Round actions (Exness) ────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _actionButton(
                          icon: Icons.swap_vert_rounded,
                          label: 'Trade',
                          filled: true,
                          onTap: () => context.go(AppRoutes.markets),
                        ),
                        _actionButton(
                          icon: _showDepositSection ? Icons.close_rounded : Icons.arrow_downward_rounded,
                          label: _showDepositSection ? 'Hide' : 'Deposit',
                          filled: false,
                          onTap: () {
                            setState(() => _showDepositSection = !_showDepositSection);
                            if (_showDepositSection) {
                              WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToDeposit());
                            }
                          },
                        ),
                        _actionButton(
                          icon: Icons.arrow_upward_rounded,
                          label: 'Withdraw',
                          filled: false,
                          onTap: () => _showWithdrawModal(context, authUser),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

                // ── Active Open Trades Section (Directly Below Balance & Action Buttons) ──
                _buildActiveTradesSection(engineState.openPositions),
                const SizedBox(height: 20),

                // ── USDT TRC-20 deposit (manual admin verification) ──
                if (_showDepositSection)
                  DepositPanel(
                    key: _depositSectionKey,
                    onClose: () => setState(() => _showDepositSection = false),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTradesSection(List<TradeEntity> positions) {
    if (positions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _subtleBorder),
          boxShadow: _cardShadow,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: _brandGreen.withValues(alpha: _isDark ? 0.14 : 0.12),
                borderRadius: BorderRadius.circular(12),
                border: _isDark
                    ? Border.all(color: _brandGreen.withValues(alpha: 0.45))
                    : null,
                boxShadow: _isDark
                    ? [
                        BoxShadow(
                          color: _brandGreen.withValues(alpha: 0.25),
                          blurRadius: 14,
                        ),
                      ]
                    : null,
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                color: _brandGreen,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No Active Trades Open',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'All funds available in Free Margin for trading.',
                    style: TextStyle(fontSize: 11, color: _textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Total floating PnL of all open positions
    final totalPnL = positions.fold<Decimal>(
      Decimal.zero,
      (sum, p) => sum + p.unrealizedPnl,
    );
    final isTotalProfit = totalPnL >= Decimal.zero;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF16C784),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'OPEN TRADES (${positions.length})',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: _textPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isTotalProfit
                      ? const Color(0xFF16C784).withValues(alpha: 0.15)
                      : const Color(0xFFE5484D).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  MoneyMath.formatPnL(totalPnL),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: isTotalProfit
                        ? const Color(0xFF16C784)
                        : const Color(0xFFE5484D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // List of Active Trades
          ...positions.map((pos) {
            final isPosProfit = pos.unrealizedPnl >= Decimal.zero;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _subCardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _subtleBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Row 1: Symbol, Side badge, Lots, Floating PnL
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: pos.isBuy
                              ? const Color(0xFF16C784).withValues(alpha: 0.15)
                              : const Color(0xFFE5484D).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          pos.isBuy ? 'BUY' : 'SELL',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: pos.isBuy
                                ? const Color(0xFF16C784)
                                : const Color(0xFFE5484D),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${pos.symbol} • ${pos.lots.toDouble().toStringAsFixed(2)} Lots',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        MoneyMath.formatPnL(pos.unrealizedPnl),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: isPosProfit
                              ? const Color(0xFF16C784)
                              : const Color(0xFFE5484D),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Row 2: Entry, Current Price, Locked Margin
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Entry: ${MoneyMath.formatDec(pos.openPrice, 2)}',
                        style: TextStyle(fontSize: 11, color: _textSecondary),
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.trending_up,
                            size: 12,
                            color: _textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Live: ${MoneyMath.formatDec(pos.currentPrice, 2)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _textPrimary,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Margin: ${MoneyMath.formatCurrency(pos.requiredMargin)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFFFDE02),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Row 3: Direct Close Trade Button
                  OutlinedButton.icon(
                    onPressed: () async {
                      await context.read<TradingEngineBloc>().closePosition(
                        pos.id,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: _cardBg,
                            content: Text(
                              'Position ${pos.symbol} Closed. Margin released & PnL booked to Ledger.',
                              style: TextStyle(color: _textPrimary),
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.close_rounded, size: 14),
                    label: const Text(
                      'CLOSE POSITION',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE5484D),
                      side: const BorderSide(color: Color(0xFFE5484D)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _vaultBreakdownItem(String label, String value, {Color? valueColor}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11.5,
              color: _textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: valueColor ?? _mutedValue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String label, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.brandPrimary.withValues(alpha: _isDark ? 0.16 : 0.35)
            : _subCardBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: highlight ? context.accentColor : _textSecondary,
        ),
      ),
    );
  }

  /// Exness round action: icon in a circle with the label underneath.
  Widget _actionButton({
    required IconData icon,
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: filled ? AppColors.brandPrimary : _subCardBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: filled ? Colors.black : _textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWithdrawModal(BuildContext context, UserEntity? user) {
    // For now: allow withdrawal requests without requiring KYC approval
    final amountController = TextEditingController();
    final addressController = TextEditingController();
    String? amountError;
    String? addressError;
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final textPrimary = context.textPrimaryColor;
          final textSecondary = context.textSecondaryColor;
          final freeMargin = context.read<TradingEngineBloc>().state.accountState.freeMargin;
          final available = freeMargin < Decimal.zero ? Decimal.zero : freeMargin;

          InputDecoration field(String label, {String? hint, String? prefix, String? error}) => InputDecoration(
                labelText: label,
                hintText: hint,
                prefixText: prefix,
                errorText: error,
                filled: true,
                fillColor: context.inputBg,
                floatingLabelBehavior: FloatingLabelBehavior.always,
                contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
                labelStyle: TextStyle(color: textSecondary, fontSize: 14),
                hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.7), fontSize: 13),
                prefixStyle: TextStyle(color: textPrimary, fontWeight: FontWeight.w700, fontSize: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _subtleBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _subtleBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.accentColor, width: 1.5),
                ),
              );

          Future<void> submit() async {
            final amt = double.tryParse(amountController.text.trim().replaceAll(',', '')) ?? 0.0;
            final address = addressController.text.trim();
            setModalState(() {
              amountError = amt <= 0
                  ? 'Enter an amount'
                  : MoneyMath.toDec(amt) > available
                      ? 'More than your free margin (${MoneyMath.formatCurrency(available)})'
                      : null;
              addressError = DepositService.isValidTronAddress(address)
                  ? null
                  : 'Enter a valid TRC-20 address (starts with T)';
            });
            if (amountError != null || addressError != null) return;

            final authUser = context.read<AuthBloc>().state.user;
            final effectiveUserId = authUser?.id ?? 'usr_institutional_01';
            final txId = 'TX-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

            // 1. Hold the funds server-side FIRST. rpc_request_withdrawal locks
            //    the wallet, re-verifies balance and free margin, debits inside
            //    a transaction and records a withdrawal_hold ledger entry.
            //    withdrawFunds() used to only change a client-side number, so
            //    the real wallet was never debited and the money could be spent
            //    again. Nothing is recorded locally until this succeeds.
            final messenger = ScaffoldMessenger.of(context);
            final adminBloc = context.read<AdminBloc>();
            final walletBloc = context.read<WalletBloc>();

            setModalState(() => submitting = true);
            try {
              await context.read<TradingEngineCubit>().requestWithdrawal(
                    amount: MoneyMath.toDec(amt),
                    method: 'USDT (TRC-20)',
                    destination: address,
                    requestId: txId,
                  );
            } catch (e) {
              if (ctx.mounted) setModalState(() => submitting = false);
              messenger.showSnackBar(
                SnackBar(
                  backgroundColor: AppColors.loss,
                  content: Text(
                    'Withdrawal rejected: ${e.toString().replaceAll('Exception: ', '')}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              );
              return;
            }

            // 2. Mirror the accepted request for the admin queue and local UI.
            adminBloc.addTransactionRequest(
              AdminTransaction(
                id: txId,
                userId: effectiveUserId,
                userName: authUser?.fullName ?? 'Trader',
                userEmail: authUser?.email ?? 'trader@asianfx.com',
                type: 'WITHDRAWAL',
                amount: amt,
                method: 'USDT (TRC-20)',
                accountOrAddress: address,
                status: AdminTxStatus.pending,
                isAutoApproved: false,
                createdAt: DateTime.now(),
              ),
            );
            walletBloc.debitWithdrawal(amt, 'USDT (TRC-20)', txId: txId, autoApprove: false);

            if (ctx.mounted) Navigator.of(ctx).pop();
            messenger.showSnackBar(
              SnackBar(
                backgroundColor: AppColors.profit,
                content: Text(
                  '✓ Withdrawal of \$${amt.toStringAsFixed(2)} submitted — funds held pending approval.',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              left: 20,
              right: 20,
              top: 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Withdraw USDT (TRC-20)',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: textSecondary, size: 22),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  Text(
                    'Available: ${MoneyMath.formatCurrency(available)}',
                    style: TextStyle(fontSize: 13, color: textSecondary),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: textPrimary, fontWeight: FontWeight.w700, fontSize: 18),
                    onChanged: (_) {
                      if (amountError != null) setModalState(() => amountError = null);
                    },
                    decoration: field('Amount (USD)', hint: '0.00', prefix: '\$ ', error: amountError),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: addressController,
                    style: TextStyle(color: textPrimary, fontSize: 14),
                    autocorrect: false,
                    onChanged: (_) {
                      if (addressError != null) setModalState(() => addressError = null);
                    },
                    decoration: field('Wallet address (USDT TRC-20)', hint: 'T…', error: addressError),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Funds are held now and sent to this address after admin approval.',
                    style: TextStyle(fontSize: 12, color: textSecondary),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: submitting ? null : submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandPrimary,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: AppColors.brandPrimary.withValues(alpha: 0.5),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: submitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                            )
                          : const Text(
                              'Submit withdrawal request',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
