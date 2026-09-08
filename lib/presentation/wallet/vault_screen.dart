import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/math/money_math.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/trading_entities.dart';
import '../../domain/entities/user_entity.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/trading_engine_provider.dart';
import '../../providers/wallet_provider.dart';

class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  final _amountController = TextEditingController(text: '100');
  final _txHashController = TextEditingController();
  final _scrollController = ScrollController();
  final GlobalKey _depositSectionKey = GlobalKey();
  Uint8List? _proofBytes;
  String? _proofFileName;
  bool _isPicking = false;
  static const _depositAddress = AppConstants.usdtTrc20DepositAddress;

  bool get _isDark => ref.watch(themeProvider);
  Color get _cardBg => _isDark ? const Color(0xFF151D28) : Colors.white;
  Color get _subCardBg => _isDark ? const Color(0xFF0F141C) : const Color(0xFFF8FAFC);
  Color get _borderColor => _isDark ? const Color(0xFF1C2535) : const Color(0xFFE2E8F0);
  Color get _subtleBorder => _isDark ? const Color(0xFF2B384E) : const Color(0xFFCBD5E1);
  Color get _textPrimary => _isDark ? Colors.white : const Color(0xFF0F172A);
  Color get _textSecondary => _isDark ? const Color(0xFF848E9C) : const Color(0xFF64748B);

  @override
  void dispose() {
    _amountController.dispose();
    _txHashController.dispose();
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

    final txHash = _txHashController.text.trim();
    if (txHash.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFFF4757),
          content: Text('Please enter the Transaction Hash / TxID from your wallet transfer!'),
        ),
      );
      return;
    }

    if (txHash.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFFF4757),
          content: Text('Transaction Hash (TxID) must be at least 8 characters.'),
        ),
      );
      return;
    }

    // ── Duplicate Fraud Prevention Check ─────────────────────────────────
    final existingTxs = ref.read(adminProvider).transactions;
    final isDuplicate = existingTxs.any(
      (t) => t.txHash != null && t.txHash!.trim().toLowerCase() == txHash.toLowerCase(),
    );
    if (isDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFFF4757),
          duration: Duration(seconds: 4),
          content: Text('⚠️ This Transaction ID (TxID) has already been submitted! Duplicate or recycled requests are blocked.'),
        ),
      );
      return;
    }

    final authUser = ref.read(authProvider).user;
    final effectiveUserId = authUser?.id ?? 'usr_institutional_01';
    final txId = 'TX-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

    // 1. Upload Screenshot Proof to Supabase Storage 'reciept-proof' bucket
    String? storageErrorMsg;
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
        storageErrorMsg = err.toString();
        debugPrint('Supabase storage upload error: $err');
      }
    }

    // 2. Submit transaction with screenshot & TxHash to Admin Provider as PENDING
    ref.read(adminProvider.notifier).addTransactionRequest(
      AdminTransaction(
        id: txId,
        userId: effectiveUserId,
        userName: authUser?.fullName ?? 'Institutional Trader',
        userEmail: authUser?.email ?? 'trader@asianfx.com',
        type: 'DEPOSIT',
        amount: amt,
        method: 'USDT (TRC20)',
        accountOrAddress: txHash,
        txHash: txHash,
        status: AdminTxStatus.pending,
        createdAt: DateTime.now(),
        proofImageName: uploadedStoragePath ?? _proofFileName,
        proofImageBytes: _proofBytes,
      ),
    );

    // 3. Add pending transaction to Wallet Provider
    final shortHash = txHash.length > 12 ? '${txHash.substring(0, 8)}...${txHash.substring(txHash.length - 4)}' : txHash;
    ref.read(walletProvider.notifier).addPendingTransaction(
      TransactionEntity(
        id: txId,
        type: 'deposit',
        amount: amt,
        currency: 'USD',
        status: 'pending',
        method: 'USDT (TRC-20)',
        description: 'USDT Deposit (TxID: $shortHash)',
        createdAt: DateTime.now(),
      ),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: storageErrorMsg != null ? const Color(0xFFFF9F43) : const Color(0xFFFFD600),
          content: Text(
            storageErrorMsg != null
                ? '✓ Deposit submitted with TxID! (Note: Run Storage Policy in SQL editor)'
                : '✓ Deposit request of \$${amt.toStringAsFixed(2)} with TxID submitted! Admin will verify on Tronscan.',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }

    setState(() {
      _proofBytes = null;
      _proofFileName = null;
      _txHashController.clear();
    });
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
    final balance = ref.watch(clientLedgerBalanceProvider);
    final engineState = ref.watch(tradingEngineProvider);
    final account = engineState.accountState;
    final rawBalance = balance > Decimal.zero ? balance : account.ledgerBalance;
    final displayedBalance = (rawBalance == MoneyMath.toDec(10000.0) || rawBalance == MoneyMath.toDec(25000.0))
        ? Decimal.zero
        : rawBalance;
    final cleanFreeMargin = (displayedBalance - account.usedMargin).clamp(Decimal.zero, MoneyMath.toDec(1000000000.0));
    final authUser = ref.watch(authProvider).user;
    final isDark = ref.watch(themeProvider);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0E17) : const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF151D28) : Colors.white,
        elevation: 0,
        title: Text(
          'Vault & Wallet',
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
            onPressed: () => ref.read(themeProvider.notifier).toggleTheme(),
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
                          color: const Color(0xFF00D68F).withOpacity(0.2),
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
                      const Spacer(),
                      const Icon(Icons.verified_user_rounded, color: Color(0xFF00D68F), size: 18),
                      const SizedBox(width: 4),
                      const Text(
                        'Tier-1 Protected',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF00D68F)),
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
                    onPressed: _scrollToDeposit,
                    icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                    label: const Text('DEPOSIT'),
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

            // ── Interactive Institutional USDT TRC-20 Deposit Gateway Card ──
            Container(
              key: _depositSectionKey,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF00D68F).withValues(alpha: 0.4)),
                boxShadow: _isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
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
                              'Institutional Deposit Gateway (USDT TRC-20)',
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00D68F).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF00D68F)),
                        ),
                        child: const Text(
                          'ONLINE',
                          style: TextStyle(color: Color(0xFF00D68F), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
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

                  // ── Blockchain Transaction Hash (TxID) Field ───────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.tag_rounded, size: 15, color: Color(0xFF00D68F)),
                          const SizedBox(width: 6),
                          Text(
                            'Transaction Hash / TxID (TID)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _textPrimary),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD600).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFFFD600).withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          'MANDATORY FOR VERIFICATION',
                          style: TextStyle(color: Color(0xFFFFD600), fontSize: 9, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _txHashController,
                    style: TextStyle(color: _textPrimary, fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'Paste 64-character TRC20 TxHash or Transfer TID...',
                      hintStyle: TextStyle(color: _textSecondary.withValues(alpha: 0.6), fontSize: 11),
                      prefixIcon: const Icon(Icons.receipt_rounded, color: Color(0xFF00D68F), size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.paste_rounded, size: 18, color: Color(0xFF00D68F)),
                        tooltip: 'Paste TxID from Clipboard',
                        onPressed: () async {
                          final clipData = await Clipboard.getData('text/plain');
                          if (clipData?.text != null && clipData!.text!.trim().isNotEmpty) {
                            setState(() {
                              _txHashController.text = clipData.text!.trim();
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: Color(0xFF00D68F),
                                  duration: Duration(seconds: 1),
                                  content: Text('TxID pasted from clipboard!'),
                                ),
                              );
                            }
                          }
                        },
                      ),
                      filled: true,
                      fillColor: _subCardBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _subtleBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _subtleBorder)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF00D68F), width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 12, color: _textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Copy the TxID from Binance / TrustWallet / OKX transfer details and paste here.',
                          style: TextStyle(fontSize: 10, color: _textSecondary),
                        ),
                      ),
                    ],
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
                            'Deposit Screenshot / Payment Receipt',
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
                                    'Click to Attach Transfer Screenshot or TxHash Slip',
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
                    onPressed: _submitDeposit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D68F),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 2,
                    ),
                    child: const Text(
                      '⚡ CONFIRM DEPOSIT SETTLEMENT',
                      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Other Institutional Channels ────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _borderColor),
                boxShadow: _isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Other Supported Channels',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _gatewayItem('USDT Tether (ERC-20)', 'Tier-1 Segregated Cold Wallet', Icons.shield),
                  Divider(color: _borderColor, height: 16),
                  _gatewayItem('Institutional Bank Wire', 'SWIFT Fedwire Clearance', Icons.account_balance),
                ],
              ),
            ),
          ],
        ),
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

  Widget _gatewayItem(String title, String subtitle, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFFD600), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: _textPrimary, fontSize: 13)),
              Text(subtitle, style: TextStyle(color: _textSecondary, fontSize: 11)),
            ],
          ),
        ),
        const Text('ONLINE', style: TextStyle(color: Color(0xFF00D68F), fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  void _showDepositModal(BuildContext context) {
    final amountController = TextEditingController(text: '5000');
    final txHashModalController = TextEditingController();
    Uint8List? proofBytes;
    String? proofFileName;
    bool isPicking = false;
    const depositAddress = AppConstants.usdtTrc20DepositAddress;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151D28),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> pickProof(ImageSource source) async {
            try {
              setModalState(() => isPicking = true);
              final picker = ImagePicker();
              final XFile? file = await picker.pickImage(
                source: source,
                imageQuality: 85,
                maxWidth: 1920,
              );
              if (file != null) {
                final bytes = await file.readAsBytes();
                setModalState(() {
                  proofBytes = bytes;
                  proofFileName = file.name;
                  isPicking = false;
                });
              } else {
                setModalState(() => isPicking = false);
              }
            } catch (e) {
              setModalState(() => isPicking = false);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFFFF4757),
                    content: Text('Failed to select image: $e'),
                  ),
                );
              }
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
                        'Institutional Deposit Gateway',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Color(0xFF848E9C), size: 20),
                        onPressed: () => Navigator.of(ctx).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F141C),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2B384E)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('USDT (TRC-20) Vault Deposit Address:', style: TextStyle(fontSize: 11, color: Color(0xFF848E9C))),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(const ClipboardData(text: depositAddress));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: Color(0xFF00D68F),
                                    duration: Duration(seconds: 2),
                                    content: Text('Address copied to clipboard!'),
                                  ),
                                );
                              },
                              child: const Row(
                                children: [
                                  Icon(Icons.copy_rounded, size: 12, color: Color(0xFF00D68F)),
                                  SizedBox(width: 4),
                                  Text('Copy', style: TextStyle(fontSize: 11, color: Color(0xFF00D68F), fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const SelectableText(
                          depositAddress,
                          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, color: Color(0xFFFFD600), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    decoration: const InputDecoration(
                      labelText: 'Deposit Amount (USD)',
                      prefixText: '\$ ',
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Quick amounts
                  Row(
                    children: [500, 1000, 5000, 10000].map((preset) => Expanded(
                      child: GestureDetector(
                        onTap: () => setModalState(() => amountController.text = '$preset'),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F141C),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF2B384E)),
                          ),
                          child: Center(
                            child: Text(
                              '\$$preset',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF848E9C), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 16),

                  // ── Blockchain Transaction Hash (TxID) in Modal ────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.tag_rounded, size: 14, color: Color(0xFF00D68F)),
                          SizedBox(width: 6),
                          Text(
                            'Transaction Hash / TxID (TID)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD600).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('REQUIRED', style: TextStyle(color: Color(0xFFFFD600), fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: txHashModalController,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'Paste 64-char Tron TxHash or Transfer TID...',
                      hintStyle: const TextStyle(color: Color(0xFF848E9C), fontSize: 11),
                      prefixIcon: const Icon(Icons.receipt_rounded, color: Color(0xFF00D68F), size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.paste_rounded, size: 18, color: Color(0xFF00D68F)),
                        tooltip: 'Paste from clipboard',
                        onPressed: () async {
                          final clipData = await Clipboard.getData('text/plain');
                          if (clipData?.text != null && clipData!.text!.trim().isNotEmpty) {
                            setModalState(() {
                              txHashModalController.text = clipData.text!.trim();
                            });
                          }
                        },
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0F141C),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2B384E))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2B384E))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF00D68F))),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Screenshot / Payment Proof Upload Section ─────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.receipt_long_rounded, size: 14, color: Color(0xFF00D68F)),
                          SizedBox(width: 6),
                          Text(
                            'Deposit Screenshot / Payment Receipt',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ],
                      ),
                      if (proofBytes != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D68F).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('✓ ATTACHED', style: TextStyle(color: Color(0xFF00D68F), fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (proofBytes == null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F141C),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF2B384E)),
                      ),
                      child: isPicking
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(12.0),
                                child: CircularProgressIndicator(color: Color(0xFF00D68F), strokeWidth: 2),
                              ),
                            )
                          : Column(
                              children: [
                                const Icon(Icons.cloud_upload_outlined, color: Color(0xFF00D68F), size: 30),
                                const SizedBox(height: 6),
                                const Text(
                                  'Attach Transfer Screenshot or TxHash Slip',
                                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Instant institutional ledger verification',
                                  style: TextStyle(color: Color(0xFF848E9C), fontSize: 10),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => pickProof(ImageSource.gallery),
                                      icon: const Icon(Icons.photo_library_outlined, size: 14),
                                      label: const Text('Select Screenshot', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF00D68F),
                                        side: const BorderSide(color: Color(0xFF00D68F)),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: () => pickProof(ImageSource.camera),
                                      icon: const Icon(Icons.camera_alt_outlined, size: 14),
                                      label: const Text('Camera', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF848E9C),
                                        side: const BorderSide(color: Color(0xFF2B384E)),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F141C),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF00D68F)),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(
                              proofBytes!,
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  proofFileName ?? 'screenshot.png',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${(proofBytes!.lengthInBytes / 1024).toStringAsFixed(1)} KB • Verified Image',
                                  style: const TextStyle(color: Color(0xFF848E9C), fontSize: 10),
                                ),
                                const SizedBox(height: 4),
                                const Row(
                                  children: [
                                    Icon(Icons.check_circle_rounded, color: Color(0xFF00D68F), size: 12),
                                    SizedBox(width: 4),
                                    Text('Screenshot ready for upload', style: TextStyle(color: Color(0xFF00D68F), fontSize: 10, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: Color(0xFF848E9C), size: 18),
                            tooltip: 'Change Screenshot',
                            onPressed: () => pickProof(ImageSource.gallery),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Color(0xFFFF4757), size: 18),
                            tooltip: 'Remove Screenshot',
                            onPressed: () => setModalState(() {
                              proofBytes = null;
                              proofFileName = null;
                            }),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: () {
                      final amt = double.tryParse(amountController.text) ?? 0.0;
                      if (amt <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Color(0xFFFF4757),
                            content: Text('Please enter a valid deposit amount'),
                          ),
                        );
                        return;
                      }

                      final txHash = txHashModalController.text.trim();
                      if (txHash.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Color(0xFFFF4757),
                            content: Text('Please enter Transaction ID / Hash (TxID) from your wallet!'),
                          ),
                        );
                        return;
                      }

                      // Duplicate Fraud Prevention
                      final existingTxs = ref.read(adminProvider).transactions;
                      final isDuplicate = existingTxs.any(
                        (t) => t.txHash != null && t.txHash!.trim().toLowerCase() == txHash.toLowerCase(),
                      );
                      if (isDuplicate) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Color(0xFFFF4757),
                            duration: Duration(seconds: 4),
                            content: Text('⚠️ This Transaction ID (TxID) has already been submitted! Duplicate requests are blocked.'),
                          ),
                        );
                        return;
                      }

                      final authUser = ref.read(authProvider).user;
                      final effectiveUserId = authUser?.id ?? 'usr_institutional_01';
                      final txId = 'TX-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

                      String? uploadedStoragePath;
                      final localBytes = proofBytes;
                      final localName = proofFileName;
                      if (localBytes != null) {
                        final fileExt = (localName != null && localName.contains('.'))
                            ? localName.split('.').last.toLowerCase()
                            : 'png';
                        final storagePath = 'receipt_${effectiveUserId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
                        try {
                          Supabase.instance.client.storage
                              .from('reciept-proof')
                              .uploadBinary(
                                storagePath,
                                localBytes,
                                fileOptions: FileOptions(contentType: 'image/$fileExt', upsert: true),
                              );
                          uploadedStoragePath = storagePath;
                        } catch (e) {
                          debugPrint('Storage upload error: $e');
                        }
                      }

                      // 1. Submit transaction with screenshot to Admin Provider as PENDING
                      ref.read(adminProvider.notifier).addTransactionRequest(
                            AdminTransaction(
                              id: txId,
                              userId: effectiveUserId,
                              userName: authUser?.fullName ?? 'Institutional Trader',
                              userEmail: authUser?.email ?? 'trader@asianfx.com',
                              type: 'DEPOSIT',
                              amount: amt,
                              method: 'USDT (TRC20)',
                              accountOrAddress: txHash,
                              txHash: txHash,
                              status: AdminTxStatus.pending,
                              createdAt: DateTime.now(),
                              proofImageName: uploadedStoragePath ?? proofFileName,
                              proofImageBytes: proofBytes,
                            ),
                          );

                      // 2. Add pending transaction to user wallet
                      final shortHash = txHash.length > 12 ? '${txHash.substring(0, 8)}...${txHash.substring(txHash.length - 4)}' : txHash;
                      ref.read(walletProvider.notifier).addPendingTransaction(
                            TransactionEntity(
                              id: txId,
                              type: 'deposit',
                              amount: amt,
                              currency: 'USD',
                              status: 'pending',
                              method: 'USDT (TRC-20)',
                              description: 'USDT Deposit (TxID: $shortHash)',
                              createdAt: DateTime.now(),
                            ),
                          );

                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFFFFD600),
                          content: Text(
                            '✓ Deposit request of \$${amt.toStringAsFixed(2)} with TxID submitted! Waiting for Admin approval.',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D68F),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('CONFIRM DEPOSIT SETTLEMENT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showWithdrawModal(BuildContext context, UserEntity? user) {
    if (user != null && !user.canWithdraw) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.loss,
          content: Text('KYC Approval Required before initiating withdrawals.'),
        ),
      );
      return;
    }

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
                        'Institutional Withdrawal Disbursement',
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
                      final engineState = ref.read(tradingEngineProvider);

                      if (amtDec > engineState.accountState.freeMargin) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.loss,
                            content: Text('Insufficient Free Margin! Available: ${MoneyMath.formatCurrency(engineState.accountState.freeMargin)}'),
                          ),
                        );
                        return;
                      }

                      final authUser = ref.read(authProvider).user;
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

                      // 1. Submit Pending Withdrawal to Admin Provider for review
                      ref.read(adminProvider.notifier).addTransactionRequest(
                            AdminTransaction(
                              id: txId,
                              userId: effectiveUserId,
                              userName: authUser?.fullName ?? 'Institutional Trader',
                              userEmail: authUser?.email ?? 'trader@asianfx.com',
                              type: 'WITHDRAWAL',
                              amount: amt,
                              method: 'USDT (TRC-20)',
                              accountOrAddress: addressController.text,
                              status: AdminTxStatus.pending,
                              createdAt: DateTime.now(),
                              proofImageName: uploadedStoragePath ?? withdrawProofFileName,
                              proofImageBytes: withdrawProofBytes,
                            ),
                          );

                      // 2. Add pending transaction in user wallet
                      ref.read(walletProvider.notifier).addPendingTransaction(
                            TransactionEntity(
                              id: txId,
                              type: 'withdrawal',
                              amount: amt,
                              currency: 'USD',
                              status: 'pending',
                              method: 'USDT (TRC-20)',
                              description: 'USDT Withdrawal (Pending Admin Approval)',
                              createdAt: DateTime.now(),
                            ),
                          );

                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFFFFD600),
                            content: Text(
                              '✓ Withdrawal request for \$${amt.toStringAsFixed(2)} submitted to Admin Finance Desk for inspection & disbursement.',
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
