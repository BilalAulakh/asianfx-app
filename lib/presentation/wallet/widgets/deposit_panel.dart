import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../blocs/blocs.dart';
import '../../../core/math/money_math.dart';
import '../../../data/datasources/supabase_deposit_service.dart';

/// USDT (TRC-20) deposit.
///
/// 1. The user enters an amount and asks for an address. The SERVER assigns a
///    company address by weighted rotation (rpc_create_deposit_request) - the
///    client never chooses it - and the user pays exactly that address.
/// 2. The user attaches a payment screenshot; the deposit is then under review.
///
/// Every address looks the same to the user. Whether a deposit is approved by
/// an admin or verified on-chain automatically is decided server-side and is
/// never shown here. Nothing here credits the wallet.
class DepositPanel extends StatefulWidget {
  final VoidCallback? onClose;
  final DepositService? service;

  /// How often an open screen re-checks requests that are being verified.
  final Duration pollEvery;

  const DepositPanel({super.key, this.onClose, this.service, this.pollEvery = const Duration(seconds: 10)});

  @override
  State<DepositPanel> createState() => _DepositPanelState();
}

class _DepositPanelState extends State<DepositPanel> {
  late final DepositService _service = widget.service ?? DepositService.instance;

  final _amountController = TextEditingController();

  DepositConfig? _config;
  bool _loadingConfig = true;

  List<DepositRequest> _requests = const [];
  bool _loadingRequests = false;
  String? _requestsError;

  Uint8List? _proofBytes;
  String? _proofFileName;
  bool _isPicking = false;
  bool _isBusy = false;
  bool _addressCopied = false;
  Timer? _poll;

  bool get _isDark => context.watch<ThemeCubit>().state;
  Color get _cardBg => _isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get _subCardBg => _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _subtleBorder => _isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
  Color get _textPrimary => _isDark ? Colors.white : const Color(0xFF0F172A);
  Color get _textSecondary => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFFF4757);
  static const _amber = Color(0xFFFFB300);
  static const _blue = Color(0xFF3B82F6);

  /// Requests submitted while the server still refused screenshots on
  /// automatic addresses (before 20261006000400): treated as submitted.
  final Set<String> _submitted = {};

  bool _needsProof(DepositRequest r) => r.awaitingProof && !_submitted.contains(r.id);

  /// The request the user is working on: created, screenshot not attached yet.
  DepositRequest? get _active {
    for (final r in _requests) {
      if (_needsProof(r)) return r;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _loadRequests();
    // Silently picks up approvals that happen while the screen is open.
    _poll = Timer.periodic(widget.pollEvery, (_) {
      if (_requests.any((r) => r.isAutoVerifying)) _loadRequests(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _amountController.dispose();
    super.dispose();
  }

  /// The open request this field was last filled from.
  String? _amountFilledFor;

  /// Shows the open request's amount in the field once per request, so the
  /// user can see and correct it; never overwrites what they are typing.
  void _syncAmountField() {
    final active = _active;
    if (active == null || _amountFilledFor == active.id) return;
    _amountFilledFor = active.id;
    _amountController.text = active.amountClaimed.toString();
  }

  /// The typed amount differs from the open request's amount.
  bool _amountChanged(DepositRequest r) {
    final typed = _parsedAmount;
    return typed != null && typed != r.amountClaimed;
  }

  Future<void> _loadConfig() async {
    final cfg = await _service.loadConfig();
    if (!mounted) return;
    setState(() {
      _config = cfg;
      _loadingConfig = false;
      _syncAmountField();
      if (_amountController.text.isEmpty) _amountController.text = cfg.minDeposit.toString();
    });
  }

  Future<void> _loadRequests({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loadingRequests = true;
        _requestsError = null;
      });
    }
    try {
      final list = await _service.myRequests();
      if (!mounted) return;
      final before = {for (final r in _requests) r.id: r.status};
      setState(() {
        _requests = list;
        _loadingRequests = false;
        _requestsError = null;
        _syncAmountField();
      });
      // Credited since we last looked (admin or automatic): refresh the balance.
      final newlyApproved = list.where(
          (r) => r.status == DepositStatus.approved && before.containsKey(r.id) && before[r.id] != DepositStatus.approved);
      if (newlyApproved.isNotEmpty) {
        context.read<TradingEngineBloc>().refreshBalance();
        final r = newlyApproved.first;
        _snack('${MoneyMath.formatCurrency(r.amountCredited ?? r.amountClaimed)} USDT credited to your account.', _green);
      }
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _requestsError = e.toString();
        _loadingRequests = false;
      });
    }
  }

  Future<void> _pickProof() async {
    setState(() => _isPicking = true);
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1920);
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        setState(() {
          _proofBytes = bytes;
          _proofFileName = file.name;
        });
      }
    } catch (e) {
      _snack('Could not open the image: $e', _red);
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Decimal? get _parsedAmount {
    final amount = Decimal.tryParse(_amountController.text.trim());
    return amount != null && amount > Decimal.zero ? amount : null;
  }

  bool get _isAmountValid {
    final amount = _parsedAmount;
    final min = _config?.minDeposit;
    return amount != null && (min == null || amount >= min);
  }

  Future<void> _copyAddress(String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (!mounted) return;
    setState(() => _addressCopied = true);
    _snack('Address copied!', _green);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _addressCopied = false);
    });
  }

  Future<void> _getAddress() async {
    final amount = _parsedAmount;
    if (amount == null || !_isAmountValid) {
      _snack('Enter an amount of at least ${_config?.minDeposit ?? 10} USDT.', _red);
      return;
    }
    setState(() => _isBusy = true);
    try {
      final wasOpen = _active?.id;
      final r = await _service.createRequest(amount: amount, minDeposit: _config?.minDeposit);
      if (!mounted) return;
      setState(() {
        _requests = [r, ..._requests.where((x) => x.id != r.id)];
        _amountFilledFor = r.id;
        _amountController.text = r.amountClaimed.toString();
      });
      if (wasOpen == r.id) _snack('Amount updated to ${MoneyMath.formatCurrency(r.amountClaimed)} USDT.', _green);
    } on DepositServiceException catch (e) {
      _snack(e.message, _red);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _confirmSent(DepositRequest r) async {
    if (_proofBytes == null) {
      _snack('Please attach a screenshot of your payment.', _red);
      return;
    }
    final amount = _parsedAmount;
    if (amount == null || !_isAmountValid) {
      _snack('Enter an amount of at least ${_config?.minDeposit ?? 10} USDT.', _red);
      return;
    }
    setState(() => _isBusy = true);
    try {
      // Save an edited amount first: the server updates this same open request
      // (no screenshot yet), so the claim matches what the user sent.
      if (_amountChanged(r)) {
        r = await _service.createRequest(amount: amount, minDeposit: _config?.minDeposit);
      }
      try {
        await _service.attachProof(depositId: r.id, proofBytes: _proofBytes!, proofFileName: _proofFileName);
      } on DepositServiceException catch (e) {
        // Older server: it is verified automatically anyway, so it counts as submitted.
        if (e.code != 'AUTO_VERIFY_IN_PROGRESS') rethrow;
        _submitted.add(r.id);
      }
      if (!mounted) return;
      setState(() {
        _proofBytes = null;
        _proofFileName = null;
      });
      _snack('Deposit submitted for review. Your balance is credited once it is verified.', _green);
      await _loadRequests();
    } on DepositServiceException catch (e) {
      _snack(e.message, _red);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: color,
      duration: const Duration(seconds: 5),
      content: Text(message,
          style: TextStyle(fontWeight: FontWeight.bold, color: color == _red ? Colors.white : Colors.black)),
    ));
  }

  InputDecoration _inputDecoration({String? hint, String? prefix, String? suffixText}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _textSecondary, fontSize: 12),
        prefixText: prefix,
        prefixStyle: const TextStyle(color: _green, fontSize: 16, fontWeight: FontWeight.bold),
        suffixText: suffixText,
        suffixStyle: TextStyle(color: _textSecondary, fontSize: 12, fontWeight: FontWeight.w700),
        filled: true,
        fillColor: _subCardBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _subtleBorder)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _subtleBorder)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _green)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textSecondary)),
      );

  ButtonStyle _primaryStyle() => ElevatedButton.styleFrom(
        backgroundColor: _green,
        foregroundColor: Colors.black,
        disabledBackgroundColor: _green.withValues(alpha: 0.25),
        disabledForegroundColor: Colors.black.withValues(alpha: 0.5),
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  @override
  Widget build(BuildContext context) {
    final active = _active;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _green.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 16),
          if (_loadingConfig || (_loadingRequests && _requests.isEmpty))
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: _green, strokeWidth: 2)),
            )
          else if (active == null)
            ..._amountStep()
          else
            ..._paymentStep(active),
          const SizedBox(height: 22),
          _requestsSection(),
        ],
      ),
    );
  }

  Widget _header() => Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.currency_bitcoin, color: _green, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Deposit USDT (TRC-20)',
                style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.bold, color: _textPrimary)),
          ),
          if (widget.onClose != null)
            IconButton(
              icon: Icon(Icons.close_rounded, color: _textSecondary, size: 20),
              tooltip: 'Hide Deposit',
              onPressed: widget.onClose,
            ),
        ],
      );

  // ── Step 1: amount -> server assigns the address ──────────────────────────
  List<Widget> _amountStep() {
    final min = _config?.minDeposit ?? Decimal.fromInt(10);
    return [
      _label('Amount you will send (USDT)'),
      TextField(
        controller: _amountController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,4}'))],
        onChanged: (_) => setState(() {}),
        style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
        decoration: _inputDecoration(hint: '0.00', prefix: '\$ ', suffixText: 'USDT').copyWith(
          errorText: _amountController.text.isNotEmpty && !_isAmountValid ? 'Minimum deposit is $min USDT' : null,
        ),
      ),
      const SizedBox(height: 8),
      Text('You will get a deposit address for this payment. Send only to the address shown.',
          style: TextStyle(fontSize: 11, color: _textSecondary)),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: _isBusy || !_isAmountValid ? null : _getAddress,
        style: _primaryStyle(),
        icon: _isBusy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
            : const Icon(Icons.qr_code_2_rounded, size: 18),
        label: const Text('GET DEPOSIT ADDRESS',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5)),
      ),
    ];
  }

  Widget _addressBox(DepositRequest r) {
    final address = r.payToAddress ?? '-';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _subCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The amount is the editable field above; only the address is shown here.
          _label('Send to this TRC-20 address'),
          Row(
            children: [
              Expanded(
                child: SelectableText(address,
                    style: TextStyle(
                        fontFamily: 'monospace', fontWeight: FontWeight.bold, color: _textPrimary, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: r.payToAddress == null ? null : () => _copyAddress(address),
                icon: Icon(_addressCopied ? Icons.check_rounded : Icons.copy_rounded, size: 16),
                label: Text(_addressCopied ? 'Copied!' : 'Copy'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _addressCopied ? _green : _green.withValues(alpha: 0.15),
                  foregroundColor: _addressCopied ? Colors.black : _green,
                  elevation: 0,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10), side: const BorderSide(color: _green)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Send only USDT on the TRON (TRC-20) network, to this exact address. '
            'Other assets, networks or addresses cannot be recovered.',
            style: TextStyle(fontSize: 10.5, color: _textSecondary),
          ),
        ],
      ),
    );
  }

  // ── Step 2: pay, then attach the screenshot ───────────────────────────────
  List<Widget> _paymentStep(DepositRequest r) => [
        _label('Amount you will send (USDT)'),
        // A changed amount is saved together with the screenshot when the user
        // taps "I have sent the payment".
        TextField(
          key: const Key('deposit_amount'),
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,4}'))],
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
          decoration: _inputDecoration(hint: '0.00', prefix: '\$ ', suffixText: 'USDT').copyWith(
            errorText: _amountController.text.isNotEmpty && !_isAmountValid
                ? 'Minimum deposit is ${_config?.minDeposit ?? 10} USDT'
                : null,
          ),
        ),
        const SizedBox(height: 14),
        _addressBox(r),
        const SizedBox(height: 14),
        _label('Payment screenshot (required)'),
        _proofPicker(),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _isBusy || _proofBytes == null || !_isAmountValid ? null : () => _confirmSent(r),
          style: _primaryStyle(),
          child: _isBusy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('I HAVE SENT THE PAYMENT',
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5)),
        ),
      ];

  Widget _proofPicker() {
    if (_proofBytes == null) {
      return OutlinedButton.icon(
        onPressed: _isPicking ? null : _pickProof,
        icon: _isPicking
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _green))
            : const Icon(Icons.photo_library_outlined, size: 16),
        label: const Text('Attach screenshot (PNG / JPG, max 10 MB)'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _green,
          side: BorderSide(color: _subtleBorder),
          minimumSize: const Size(0, 48),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _subCardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _green),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(_proofBytes!, width: 48, height: 48, fit: BoxFit.cover),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_proofFileName ?? 'screenshot'} • ${(_proofBytes!.lengthInBytes / 1024).toStringAsFixed(0)} KB',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _textPrimary, fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: _red, size: 20),
            tooltip: 'Remove',
            onPressed: () => setState(() {
              _proofBytes = null;
              _proofFileName = null;
            }),
          ),
        ],
      ),
    );
  }

  // ── History ────────────────────────────────────────────────────────────────
  Widget _requestsSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('My deposit requests',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.bold, color: _textPrimary)),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loadingRequests ? null : _loadRequests,
                icon: _loadingRequests
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _green))
                    : Icon(Icons.refresh_rounded, color: _textSecondary, size: 20),
              ),
            ],
          ),
          if (_requestsError != null)
            Text(_requestsError!, style: const TextStyle(color: _red, fontSize: 12))
          else if (_requests.isEmpty && !_loadingRequests)
            Text('No deposit requests yet.', style: TextStyle(color: _textSecondary, fontSize: 12))
          else
            ..._requests.map(_requestTile),
        ],
      );

  /// User-facing status: the same for every address; never exposes how a
  /// deposit is verified or internal failure codes.
  (Color, String) _statusOf(DepositRequest r) {
    if (r.status == DepositStatus.approved) return (_green, 'APPROVED');
    if (r.status == DepositStatus.rejected) return (_red, 'REJECTED');
    if (_needsProof(r)) return (_textSecondary, 'AWAITING PAYMENT');
    return (_amber, 'UNDER REVIEW');
  }

  Widget _requestTile(DepositRequest r) {
    final (color, label) = _statusOf(r);
    final approved = r.status == DepositStatus.approved;
    final credited = r.amountCredited;
    final shownAmount = approved && credited != null ? credited : r.amountClaimed;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _subCardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(MoneyMath.formatCurrency(shownAmount),
                  style: TextStyle(fontWeight: FontWeight.w900, color: _textPrimary, fontSize: 14)),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ),
              const Spacer(),
              Text(DateFormat('yyyy-MM-dd HH:mm').format(r.createdAt.toLocal()),
                  style: TextStyle(fontSize: 10, color: _textSecondary)),
            ],
          ),
          if (approved && credited != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                credited != r.amountClaimed
                    ? '${MoneyMath.formatCurrency(credited)} USDT credited '
                        '(you entered ${MoneyMath.formatCurrency(r.amountClaimed)}; the amount received is credited).'
                    : '${MoneyMath.formatCurrency(credited)} USDT credited.',
                style: TextStyle(fontSize: 11, color: _textSecondary),
              ),
            ),
          if (r.hasTxid)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                onTap: () => launchUrl(r.tronscanUrl, mode: LaunchMode.externalApplication),
                child: Text(
                  'TXID ${r.txid.substring(0, 10)}…${r.txid.substring(r.txid.length - 8)}  ↗',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: _blue),
                ),
              ),
            ),
          if (r.status == DepositStatus.rejected && (r.rejectReason ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Reason: ${r.rejectReason}', style: const TextStyle(fontSize: 11, color: _red)),
            ),
        ],
      ),
    );
  }
}
