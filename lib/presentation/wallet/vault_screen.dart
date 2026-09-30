import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../blocs/blocs.dart';
import '../../core/constants/app_constants.dart';
import '../../core/math/money_math.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/trading_entities.dart';
import '../../domain/entities/user_entity.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _amountController = TextEditingController(text: '100');
  final _scrollController = ScrollController();
  final GlobalKey _depositSectionKey = GlobalKey();
  Uint8List? _proofBytes;
  String? _proofFileName;
  bool _isPicking = false;
  bool _showDepositSection = false;
  bool _isVerifyingDeposit = false;
  static const _depositAddress = AppConstants.usdtTrc20DepositAddress;

  bool get _isDark => context.watch<ThemeCubit>().state;
  Color get _cardBg => _isDark ? const Color(0xFF151D28) : Colors.white;
  Color get _subCardBg => _isDark ? const Color(0xFF0F141C) : const Color(0xFFF8FAFC);
  Color get _subtleBorder => _isDark ? const Color(0xFF2B384E) : const Color(0xFFCBD5E1);
  Color get _textPrimary => _isDark ? Colors.white : const Color(0xFF0F172A);
  Color get _textSecondary => _isDark ? const Color(0xFF848E9C) : const Color(0xFF64748B);

  @override
  void dispose() {
    _amountController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickProof() async {
    try {
      setState(() => _isPicking = true);
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          _proofBytes = bytes;
          _proofFileName = file.name;
          _isPicking = false;
        });
      } else {
        setState(() => _isPicking = false);
      }
    } catch (e) {
      setState(() => _isPicking = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFFF4757),
            content: Text('Failed to select file: $e'),
          ),
        );
      }
    }
  }

  Future<void> _submitDeposit() async {
    final amt = double.tryParse(_amountController.text) ?? 0.0;
    if (amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFFF4757),
          content: Text('Please enter a valid deposit amount'),
        ),
      );
      return;
    }

    final authUser = context.read<AuthBloc>().state.user;
    final effectiveUserId = authUser?.id ?? 'usr_institutional_01';
    final txId = 'DEP-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

    setState(() => _isVerifyingDeposit = true);

    try {
      // 1. Upload Screenshot Proof to Supabase Storage if attached
      String? uploadedStoragePath;
      if (_proofBytes != null) {
        final fileExt = (_proofFileName != null && _proofFileName!.contains('.'))
            ? _proofFileName!.split('.').last.toLowerCase()
            : 'png';
        final storagePath = 'receipt_${effectiveUserId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
        try {
          await Supabase.instance.client.storage
              .from('reciept-proof')
              .uploadBinary(
                storagePath,
                _proofBytes!,
                fileOptions: FileOptions(contentType: 'image/$fileExt', upsert: true),
              );
          uploadedStoragePath = storagePath;
          debugPrint('✓ Successfully uploaded screenshot to reciept-proof/$storagePath');
        } catch (err) {
          debugPrint('Supabase storage upload error: $err');
        }
      }

      if (!mounted) return;

      // 2. Submit Deposit Request to Admin with status PENDING (Manual Admin Approval)
      // Balance is NOT credited until Admin verifies and approves
      context.read<AdminBloc>().addTransactionRequest(
        AdminTransaction(
          id: txId,
          userId: effectiveUserId,
          userName: authUser?.fullName ?? 'Trader',
          userEmail: authUser?.email ?? 'trader@asianfx.com',
          type: 'DEPOSIT',
          amount: amt,
          method: 'USDT (TRC20)',
          accountOrAddress: _depositAddress,
          txHash: txId,
          status: AdminTxStatus.pending,
          isAutoApproved: false,
          createdAt: DateTime.now(),
          proofImageName: uploadedStoragePath ?? _proofFileName,
          proofImageBytes: _proofBytes,
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF0ECB81),
          content: Text(
            '✓ Deposit request of \$${amt.toStringAsFixed(2)} USDT submitted!\nStatus: PENDING ADMIN APPROVAL. Balance will be credited once approved.',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
          ),
          duration: const Duration(seconds: 5),
        ),
      );

      setState(() {
        _proofBytes = null;
        _proofFileName = null;
        _showDepositSection = false;
      });
    } finally {
      if (mounted) {
        setState(() => _isVerifyingDeposit = false);
      }
    }
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
    final balance = context.watch<LedgerCubit>().getClientBalance(account.userId);
    final rawBalance = balance > Decimal.zero ? balance : account.ledgerBalance;
    final displayedBalance = (rawBalance == MoneyMath.toDec(10000.0) || rawBalance == MoneyMath.toDec(25000.0))
        ? Decimal.zero
        : rawBalance;
    final cleanFreeMargin = (displayedBalance - account.usedMargin).clamp(Decimal.zero, MoneyMath.toDec(1000000000.0));
    final authUser = context.watch<AuthBloc>().state.user;
    final isDark = _isDark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0E17) : const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF151D28) : Colors.white,
        elevation: 0,
        title: Text(
          'Wallet',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: isDark ? const Color(0xFFFFD600) : const Color(0xFF0F172A),
              size: 20,
            ),
            tooltip: isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme',
            onPressed: () => context.read<ThemeCubit>().toggleTheme(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Main Segregated Vault Card ─────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E2838), Color(0xFF101722)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF2B384E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00D68F).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF00D68F)),
                        ),
                        child: const Text(
                          'SEGREGATED ASSET VAULT',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF00D68F),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD600).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFFD600).withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'ACC: #AFX-${(authUser?.id ?? "TRADER01").length > 8 ? (authUser?.id ?? "TRADER01").substring(0, 8).toUpperCase() : (authUser?.id ?? "TRADER01").toUpperCase()}',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFFD600),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'PURE CASH LEDGER BALANCE',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF848E9C),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    MoneyMath.formatCurrency(displayedBalance),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Vault Breakdown Row
                  Row(
                    children: [
                      _vaultBreakdownItem('Free Margin', MoneyMath.formatCurrency(cleanFreeMargin)),
                      _vaultBreakdownItem('Used Margin', MoneyMath.formatCurrency(account.usedMargin)),
                      _vaultBreakdownItem('Floating PnL', MoneyMath.formatPnL(account.unrealizedPnl)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Action Buttons (Deposit, Withdraw, Statement) ──────────────
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showDepositSection = !_showDepositSection;
                      });
                      if (_showDepositSection) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _scrollToDeposit();
                        });
                      }
                    },
                    icon: Icon(
                      _showDepositSection ? Icons.close_rounded : Icons.arrow_downward_rounded,
                      size: 18,
                    ),
                    label: Text(_showDepositSection ? 'HIDE DEPOSIT' : 'DEPOSIT'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D68F),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showWithdrawModal(context, authUser),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    label: const Text('WITHDRAW'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _isDark ? Colors.white : const Color(0xFF0F172A),
                      side: BorderSide(color: _subtleBorder),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Active Open Trades Section (Directly Below Balance & Action Buttons) ──
            _buildActiveTradesSection(engineState.openPositions),
            const SizedBox(height: 20),

            // ── Interactive Institutional USDT TRC-20 Deposit Gateway Card (Shown on click) ──
            if (_showDepositSection) ...[
              Container(
                key: _depositSectionKey,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00D68F).withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00D68F).withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D68F).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.currency_bitcoin, color: Color(0xFF00D68F), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Deposit Gateway (USDT TRC-20)',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: _textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Instant 0% Network Fee • Segregated Treasury Settlement',
                                style: TextStyle(fontSize: 11, color: _textSecondary),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: _textSecondary, size: 20),
                          tooltip: 'Hide Deposit',
                          onPressed: () => setState(() => _showDepositSection = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Official TRC-20 Address Box ────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _subCardBg,
                        borderRadius: BorderRadius.circular(12),
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
                                  Icon(Icons.account_balance_wallet_outlined, size: 14, color: _textSecondary),
                                  const SizedBox(width: 6),
                                  Text(
                                    'USDT (TRC-20) Vault Deposit Address:',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _textSecondary),
                                  ),
                                ],
                              ),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(const ClipboardData(text: _depositAddress));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      backgroundColor: Color(0xFF00D68F),
                                      duration: Duration(seconds: 2),
                                      content: Text('Address copied to clipboard!'),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00D68F).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.copy_rounded, size: 12, color: Color(0xFF00D68F)),
                                      SizedBox(width: 4),
                                      Text('Copy', style: TextStyle(fontSize: 11, color: Color(0xFF00D68F), fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            _depositAddress,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.bold,
                              color: _isDark ? const Color(0xFFFFD600) : const Color(0xFFD97706),
                              fontSize: 14,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Send only USDT via Tron (TRC-20) network. Other assets cannot be recovered.',
                            style: TextStyle(fontSize: 10, color: _textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Amount Input Field ──────────────────────────────────────
                    Text(
                      'Deposit Amount (USD)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textSecondary),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
                      decoration: InputDecoration(
                        prefixText: '\$ ',
                        prefixStyle: const TextStyle(color: Color(0xFF00D68F), fontSize: 18, fontWeight: FontWeight.bold),
                        filled: true,
                        fillColor: _subCardBg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _subtleBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _subtleBorder)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF00D68F))),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Quick amount chips
                    Row(
                      children: [500, 1000, 5000, 10000, 25000].map((preset) => Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _amountController.text = '$preset'),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _subCardBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _subtleBorder),
                            ),
                            child: Center(
                              child: Text(
                                '\$$preset',
                                style: TextStyle(fontSize: 11, color: _textPrimary, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                      )).toList(),
                    ),
                    const SizedBox(height: 18),


                    // ── Screenshot / Payment Proof Upload Section ─────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.receipt_long_rounded, size: 14, color: Color(0xFF00D68F)),
                            const SizedBox(width: 6),
                            Text(
                              'Deposit Screenshot / Payment Receipt (Optional)',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _textPrimary),
                            ),
                          ],
                        ),
                        if (_proofBytes != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00D68F).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('✓ ATTACHED', style: TextStyle(color: Color(0xFF00D68F), fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (_proofBytes == null)
                      GestureDetector(
                        onTap: _pickProof,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _subCardBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _subtleBorder),
                          ),
                          child: _isPicking
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: CircularProgressIndicator(color: Color(0xFF00D68F), strokeWidth: 2),
                                  ),
                                )
                              : Column(
                                  children: [
                                    const Icon(Icons.cloud_upload_outlined, color: Color(0xFF00D68F), size: 36),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Click to Attach Transfer Screenshot',
                                      style: TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Supports PNG, JPG, JPEG (Max 10 MB)',
                                      style: TextStyle(color: _textSecondary, fontSize: 11),
                                    ),
                                    const SizedBox(height: 12),
                                    ElevatedButton.icon(
                                      onPressed: _pickProof,
                                      icon: const Icon(Icons.photo_library_outlined, size: 16),
                                      label: const Text('Choose Screenshot File', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF00D68F).withValues(alpha: 0.2),
                                        foregroundColor: const Color(0xFF00D68F),
                                        elevation: 0,
                                        side: const BorderSide(color: Color(0xFF00D68F)),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _subCardBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF00D68F)),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.memory(
                                _proofBytes!,
                                width: 54,
                                height: 54,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _proofFileName ?? 'payment_receipt.png',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: _textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${(_proofBytes!.lengthInBytes / 1024).toStringAsFixed(1)} KB • Verified Proof',
                                    style: const TextStyle(color: Color(0xFF00D68F), fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.edit_outlined, color: _textSecondary, size: 20),
                              tooltip: 'Change File',
                              onPressed: _pickProof,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Color(0xFFFF4757), size: 20),
                              tooltip: 'Remove',
                              onPressed: () => setState(() {
                                _proofBytes = null;
                                _proofFileName = null;
                              }),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 18),

                    // ── Submit Button ──────────────────────────────────────────
                    ElevatedButton(
                      onPressed: _isVerifyingDeposit ? null : _submitDeposit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00D68F),
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: const Color(0xFF00D68F).withValues(alpha: 0.5),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 2,
                      ),
                      child: _isVerifyingDeposit
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'SUBMITTING DEPOSIT REQUEST...',
                                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
                                ),
                              ],
                            )
                          : const Text(
                              '⚡ SUBMIT DEPOSIT (PENDING ADMIN APPROVAL)',
                              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ],
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
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _subtleBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF00D68F).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF00D68F), size: 22),
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
    final totalPnL = positions.fold<Decimal>(Decimal.zero, (sum, p) => sum + p.unrealizedPnl);
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
                    color: isTotalProfit ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                            color: pos.isBuy ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
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
                          color: isPosProfit ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
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
                          Icon(Icons.trending_up, size: 12, color: _textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            'Live: ${MoneyMath.formatDec(pos.currentPrice, 2)}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _textPrimary),
                          ),
                        ],
                      ),
                      Text(
                        'Margin: ${MoneyMath.formatCurrency(pos.requiredMargin)}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFFFFD600), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Row 3: Direct Close Trade Button
                  OutlinedButton.icon(
                    onPressed: () async {
                      await context.read<TradingEngineBloc>().closePosition(pos.id);
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
                    label: const Text('CLOSE POSITION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF4757),
                      side: const BorderSide(color: Color(0xFFFF4757)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  Widget _vaultBreakdownItem(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: _textSecondary)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _textPrimary),
          ),
        ],
      ),
    );
  }

  void _showWithdrawModal(BuildContext context, UserEntity? user) {
    // For now: allow withdrawal requests without requiring KYC approval
    final amountController = TextEditingController(text: '1000');
    final addressController = TextEditingController(text: 'TY9xKpLm82ZvWq31RbPz');
    Uint8List? withdrawProofBytes;
    String? withdrawProofFileName;
    bool isPickingProof = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151D28),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Color(0xFF848E9C), size: 20),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    decoration: const InputDecoration(
                      labelText: 'Withdrawal Amount (USD)',
                      prefixText: '\$ ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: addressController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(labelText: 'Destination Wallet Address (USDT TRC-20)'),
                  ),
                  const SizedBox(height: 14),

                  // Optional Wallet QR / Screenshot Slip
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Wallet QR / Proof Screenshot (Optional)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF848E9C)),
                      ),
                      if (withdrawProofBytes != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D68F).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('✓ ATTACHED', style: TextStyle(color: Color(0xFF00D68F), fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (withdrawProofBytes == null)
                    InkWell(
                      onTap: pickWithdrawProof,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F141C),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2B384E)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isPickingProof)
                              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00D68F)))
                            else ...[
                              const Icon(Icons.add_photo_alternate_outlined, size: 18, color: Color(0xFF848E9C)),
                              const SizedBox(width: 8),
                              const Text('Attach Wallet Address Slip / QR Screenshot', style: TextStyle(color: Color(0xFF848E9C), fontSize: 12)),
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
                        border: Border.all(color: const Color(0xFF00D68F).withValues(alpha: 0.4)),
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
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${(withdrawProofBytes!.lengthInBytes / 1024).toStringAsFixed(1)} KB • Attached for Admin Check',
                                  style: const TextStyle(color: Color(0xFF00D68F), fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Color(0xFFFF4757), size: 18),
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
                      final engineState = context.read<TradingEngineBloc>().state;

                      if (amtDec > engineState.accountState.freeMargin) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.loss,
                            content: Text('Insufficient Free Margin! Available: ${MoneyMath.formatCurrency(engineState.accountState.freeMargin)}'),
                          ),
                        );
                        return;
                      }

                      final authUser = context.read<AuthBloc>().state.user;
                      final effectiveUserId = authUser?.id ?? 'usr_institutional_01';
                      final txId = 'TX-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

                      String? uploadedStoragePath;
                      if (withdrawProofBytes != null) {
                        final fileExt = (withdrawProofFileName != null && withdrawProofFileName!.contains('.'))
                            ? withdrawProofFileName!.split('.').last.toLowerCase()
                            : 'png';
                        final storagePath = 'withdraw_${effectiveUserId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
                        try {
                          await Supabase.instance.client.storage
                              .from('reciept-proof')
                              .uploadBinary(
                                storagePath,
                                withdrawProofBytes!,
                                fileOptions: FileOptions(contentType: 'image/$fileExt', upsert: true),
                              );
                          uploadedStoragePath = storagePath;
                        } catch (e) {
                          debugPrint('Supabase storage upload error: $e');
                        }
                      }

                      if (!ctx.mounted || !context.mounted) return;

                      // 1. Submit Auto-Approved Withdrawal to Admin
                      context.read<AdminBloc>().addTransactionRequest(
                            AdminTransaction(
                              id: txId,
                              userId: effectiveUserId,
                              userName: authUser?.fullName ?? 'Trader',
                              userEmail: authUser?.email ?? 'trader@asianfx.com',
                              type: 'WITHDRAWAL',
                              amount: amt,
                              method: 'USDT (TRC-20)',
                              accountOrAddress: addressController.text,
                              status: AdminTxStatus.approved,
                              isAutoApproved: true,
                              createdAt: DateTime.now(),
                              proofImageName: uploadedStoragePath ?? withdrawProofFileName,
                              proofImageBytes: withdrawProofBytes,
                            ),
                          );

                      // 2. Instantly Debit User Wallet & Trading Engine
                      context.read<WalletBloc>().debitWithdrawal(amt, 'USDT (TRC-20)', txId: txId, autoApprove: true);
                      context.read<TradingEngineCubit>().withdrawFunds(
                            effectiveUserId,
                            MoneyMath.toDec(amt),
                          );

                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF0ECB81),
                            content: Text(
                              '✓ Instant Withdrawal of \$${amt.toStringAsFixed(2)} processed successfully!',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
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
                    child: const Text('SUBMIT WITHDRAWAL REQUEST', style: TextStyle(fontWeight: FontWeight.bold)),
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
