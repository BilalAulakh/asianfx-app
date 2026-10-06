import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../blocs/blocs.dart';
import '../../core/math/money_math.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/trading_entities.dart';
import '../../domain/entities/user_entity.dart';
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
  Color get _cardBg => _isDark ? const Color(0xFF15222C) : Colors.white;
  Color get _subCardBg =>
      _isDark ? const Color(0xFF0F1A22) : const Color(0xFFF5F8FA);
  Color get _subtleBorder =>
      _isDark ? const Color(0xFF233440) : const Color(0xFFE3EBF0);
  Color get _textPrimary => _isDark ? Colors.white : const Color(0xFF0B1B2B);
  Color get _textSecondary =>
      _isDark ? const Color(0xFF8FA3B3) : const Color(0xFF64748B);
  Color get _mutedValue =>
      _isDark ? const Color(0xFF9FB0BF) : const Color(0xFF5B6B7B);

  static const _brandGreen = Color(0xFF1EC27E);
  static const _lossRed = Color(0xFFFF4757);

  List<BoxShadow> get _cardShadow => _isDark
      ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ]
      : [
          BoxShadow(
            color: const Color(0xFF0B1B2B).withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ];

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

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0A1218)
          : const Color(0xFFE8F0F3),
      body: Container(
        // Fill the whole screen, not just the content height.
        constraints: const BoxConstraints.expand(),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [Color(0xFF111D25), Color(0xFF0A1218)]
                : const [Color(0xFFF6F9FB), Color(0xFFE8F0F3)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ────────────────────────────────────────────────────
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Wallet',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 30,
                          height: 3,
                          decoration: BoxDecoration(
                            color: _brandGreen,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Tooltip(
                      message: isDark
                          ? 'Switch to Light Theme'
                          : 'Switch to Dark Theme',
                      child: Material(
                        color: isDark ? const Color(0xFF1A2832) : Colors.white,
                        shape: CircleBorder(
                          side: BorderSide(color: _subtleBorder),
                        ),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => context.read<ThemeCubit>().toggleTheme(),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Icon(
                              Icons.dark_mode_rounded,
                              size: 20,
                              color: _textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // ── Balance card ──────────────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? null : Colors.white,
                    gradient: isDark
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF1A2A35), Color(0xFF101B23)],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _subtleBorder),
                    boxShadow: _cardShadow,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _CardWavePainter(isDark: isDark),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _pill(
                                    icon: Icons.shield_rounded,
                                    label: 'SEGREGATED ASSET VAULT',
                                    fg: isDark
                                        ? _brandGreen
                                        : const Color(0xFF15965E),
                                    bg: isDark
                                        ? _brandGreen.withValues(alpha: 0.08)
                                        : const Color(0xFFDDF5E9),
                                    border: isDark
                                        ? _brandGreen.withValues(alpha: 0.55)
                                        : const Color(0xFFB9EAD1),
                                  ),
                                  _pill(
                                    icon: Icons.person_outline_rounded,
                                    label: 'ACC: #AFX-$accountId',
                                    fg: isDark
                                        ? const Color(0xFFF5C451)
                                        : const Color(0xFF9A6A00),
                                    bg: isDark
                                        ? const Color(
                                            0xFFF5C451,
                                          ).withValues(alpha: 0.06)
                                        : const Color(0xFFFFF4D6),
                                    border: isDark
                                        ? const Color(
                                            0xFFF5C451,
                                          ).withValues(alpha: 0.55)
                                        : const Color(0xFFF5DFA0),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'PURE CASH LEDGER BALANCE',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.4,
                                  color: _textSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                MoneyMath.formatCurrency(displayedBalance),
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 38,
                                  fontWeight: FontWeight.w800,
                                  color: _textPrimary,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Divider(
                                height: 1,
                                thickness: 1,
                                color: _subtleBorder,
                              ),
                              const SizedBox(height: 14),
                              IntrinsicHeight(
                                child: Row(
                                  children: [
                                    _vaultBreakdownItem(
                                      'Free Margin',
                                      MoneyMath.formatCurrency(cleanFreeMargin),
                                      valueColor: _brandGreen,
                                    ),
                                    VerticalDivider(
                                      width: 24,
                                      thickness: 1,
                                      color: _subtleBorder,
                                    ),
                                    _vaultBreakdownItem(
                                      'Used Margin',
                                      MoneyMath.formatCurrency(
                                        account.usedMargin,
                                      ),
                                    ),
                                    VerticalDivider(
                                      width: 24,
                                      thickness: 1,
                                      color: _subtleBorder,
                                    ),
                                    _vaultBreakdownItem(
                                      'Floating PnL',
                                      account.unrealizedPnl == Decimal.zero
                                          ? MoneyMath.formatCurrency(
                                              Decimal.zero,
                                            )
                                          : MoneyMath.formatPnL(
                                              account.unrealizedPnl,
                                            ),
                                      valueColor:
                                          account.unrealizedPnl > Decimal.zero
                                          ? _brandGreen
                                          : account.unrealizedPnl < Decimal.zero
                                          ? _lossRed
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // ── Deposit / Withdraw ────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      flex: 11,
                      child: _actionButton(
                        icon: _showDepositSection
                            ? Icons.close_rounded
                            : Icons.arrow_downward_rounded,
                        label: _showDepositSection ? 'Hide Deposit' : 'Deposit',
                        filled: true,
                        onTap: () {
                          setState(
                            () => _showDepositSection = !_showDepositSection,
                          );
                          if (_showDepositSection) {
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _scrollToDeposit(),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 9,
                      child: _actionButton(
                        icon: Icons.arrow_upward_rounded,
                        label: 'WITHDRAW',
                        filled: false,
                        onTap: () => _showWithdrawModal(context, authUser),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

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
                      color: Color(0xFF00D68F),
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
                      ? const Color(0xFF00D68F).withValues(alpha: 0.15)
                      : const Color(0xFFFF4757).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  MoneyMath.formatPnL(totalPnL),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: isTotalProfit
                        ? const Color(0xFF00D68F)
                        : const Color(0xFFFF4757),
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
                              ? const Color(0xFF00D68F).withValues(alpha: 0.15)
                              : const Color(0xFFFF4757).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          pos.isBuy ? 'BUY' : 'SELL',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: pos.isBuy
                                ? const Color(0xFF00D68F)
                                : const Color(0xFFFF4757),
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
                              ? const Color(0xFF00D68F)
                              : const Color(0xFFFF4757),
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
                          color: Color(0xFFFFD600),
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
                      foregroundColor: const Color(0xFFFF4757),
                      side: const BorderSide(color: Color(0xFFFF4757)),
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

  Widget _pill({
    required IconData icon,
    required String label,
    required Color fg,
    required Color bg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    final fg = filled ? Colors.white : _textPrimary;
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: filled
            ? _brandGreen
            : (_isDark ? const Color(0xFF1A2832) : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: filled ? null : Border.all(color: _subtleBorder),
        boxShadow: filled
            ? [
                BoxShadow(
                  color: _brandGreen.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : _cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: fg),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: filled ? 18 : 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: filled ? 0 : 0.4,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWithdrawModal(BuildContext context, UserEntity? user) {
    // For now: allow withdrawal requests without requiring KYC approval
    final amountController = TextEditingController(text: '1000');
    final addressController = TextEditingController();
    Uint8List? withdrawProofBytes;
    String? withdrawProofFileName;
    bool isPickingProof = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151D28),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> pickWithdrawProof() async {
            try {
              setModalState(() => isPickingProof = true);
              final picker = ImagePicker();
              final XFile? file = await picker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 85,
                maxWidth: 1920,
              );
              if (file != null) {
                final bytes = await file.readAsBytes();
                setModalState(() {
                  withdrawProofBytes = bytes;
                  withdrawProofFileName = file.name;
                  isPickingProof = false;
                });
              } else {
                setModalState(() => isPickingProof = false);
              }
            } catch (e) {
              setModalState(() => isPickingProof = false);
            }
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Withdrawal Disbursement',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Color(0xFF848E9C),
                          size: 20,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Withdrawal Amount (USD)',
                      prefixText: '\$ ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: addressController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Destination Wallet Address (USDT TRC-20)',
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Optional Wallet QR / Screenshot Slip
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Wallet QR / Proof Screenshot (Optional)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF848E9C),
                        ),
                      ),
                      if (withdrawProofBytes != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF00D68F,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '✓ ATTACHED',
                            style: TextStyle(
                              color: Color(0xFF00D68F),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (withdrawProofBytes == null)
                    InkWell(
                      onTap: pickWithdrawProof,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F141C),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2B384E)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isPickingProof)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF00D68F),
                                ),
                              )
                            else ...[
                              const Icon(
                                Icons.add_photo_alternate_outlined,
                                size: 18,
                                color: Color(0xFF848E9C),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Attach Wallet Address Slip / QR Screenshot',
                                style: TextStyle(
                                  color: Color(0xFF848E9C),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F141C),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF00D68F).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(
                              withdrawProofBytes!,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  withdrawProofFileName ?? 'wallet_proof.png',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${(withdrawProofBytes!.lengthInBytes / 1024).toStringAsFixed(1)} KB • Attached for Admin Check',
                                  style: const TextStyle(
                                    color: Color(0xFF00D68F),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Color(0xFFFF4757),
                              size: 18,
                            ),
                            onPressed: () => setModalState(() {
                              withdrawProofBytes = null;
                              withdrawProofFileName = null;
                            }),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 18),

                  ElevatedButton(
                    onPressed: () async {
                      final amt = double.tryParse(amountController.text) ?? 0.0;
                      final amtDec = MoneyMath.toDec(amt);
                      final engineState = context
                          .read<TradingEngineBloc>()
                          .state;

                      if (amtDec > engineState.accountState.freeMargin) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.loss,
                            content: Text(
                              'Insufficient Free Margin! Available: ${MoneyMath.formatCurrency(engineState.accountState.freeMargin)}',
                            ),
                          ),
                        );
                        return;
                      }

                      final authUser = context.read<AuthBloc>().state.user;
                      final effectiveUserId =
                          authUser?.id ?? 'usr_institutional_01';
                      final txId =
                          'TX-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

                      String? uploadedStoragePath;
                      if (withdrawProofBytes != null) {
                        final fileExt =
                            (withdrawProofFileName != null &&
                                withdrawProofFileName!.contains('.'))
                            ? withdrawProofFileName!
                                  .split('.')
                                  .last
                                  .toLowerCase()
                            : 'png';
                        final storagePath =
                            'withdraw_${effectiveUserId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
                        try {
                          await Supabase.instance.client.storage
                              .from('reciept-proof')
                              .uploadBinary(
                                storagePath,
                                withdrawProofBytes!,
                                fileOptions: FileOptions(
                                  contentType: 'image/$fileExt',
                                  upsert: true,
                                ),
                              );
                          uploadedStoragePath = storagePath;
                        } catch (e) {
                          debugPrint('Supabase storage upload error: $e');
                        }
                      }

                      if (!ctx.mounted || !context.mounted) return;

                      // 1. Hold the funds server-side FIRST. rpc_request_withdrawal locks
                      //    the wallet, re-verifies balance and free margin, debits inside
                      //    a transaction and records a withdrawal_hold ledger entry.
                      //    withdrawFunds() used to only change a client-side number, so
                      //    the real wallet was never debited and the money could be spent
                      //    again. Nothing is recorded locally until this succeeds.
                      final messenger = ScaffoldMessenger.of(context);
                      final adminBloc = context.read<AdminBloc>();
                      final walletBloc = context.read<WalletBloc>();

                      try {
                        await context
                            .read<TradingEngineCubit>()
                            .requestWithdrawal(
                              amount: MoneyMath.toDec(amt),
                              method: 'USDT (TRC-20)',
                              destination: addressController.text,
                              requestId: txId,
                            );
                      } catch (e) {
                        if (context.mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFFFF4757),
                              content: Text(
                                'Withdrawal rejected: ${e.toString().replaceAll('Exception: ', '')}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          );
                        }
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
                          accountOrAddress: addressController.text,
                          status: AdminTxStatus.pending,
                          isAutoApproved: false,
                          createdAt: DateTime.now(),
                          proofImageName:
                              uploadedStoragePath ?? withdrawProofFileName,
                          proofImageBytes: withdrawProofBytes,
                        ),
                      );
                      walletBloc.debitWithdrawal(
                        amt,
                        'USDT (TRC-20)',
                        txId: txId,
                        autoApprove: false,
                      );

                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                      if (context.mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF0ECB81),
                            content: Text(
                              '✓ Withdrawal of \$${amt.toStringAsFixed(2)} submitted — funds held pending approval.',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4757),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'SUBMIT WITHDRAWAL REQUEST',
                      style: TextStyle(fontWeight: FontWeight.bold),
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

/// Soft green wave in the balance card's right corner.
class _CardWavePainter extends CustomPainter {
  final bool isDark;
  const _CardWavePainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const green = Color(0xFF1EC27E);

    final back = Path()
      ..moveTo(w * 0.55, h)
      ..cubicTo(w * 0.72, h * 0.62, w * 0.80, h * 0.30, w, h * 0.12)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
      back,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            green.withValues(alpha: isDark ? 0.40 : 0.16),
            green.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(w * 0.5, 0, w * 0.5, h)),
    );

    final front = Path()
      ..moveTo(w * 0.68, h)
      ..cubicTo(w * 0.80, h * 0.78, w * 0.88, h * 0.55, w, h * 0.42)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
      front,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            green.withValues(alpha: isDark ? 0.30 : 0.10),
            green.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(w * 0.6, h * 0.4, w * 0.4, h * 0.6)),
    );
  }

  @override
  bool shouldRepaint(covariant _CardWavePainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
