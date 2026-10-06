import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../blocs/blocs.dart';
import '../../../core/math/money_math.dart';
import '../../../data/datasources/supabase_deposit_service.dart';
import '../../../data/datasources/withdrawal_admin_service.dart';
import 'reason_dialog.dart';

/// Admin queue for USDT withdrawals (server-backed).
///
/// Workflow: check the user and the destination address, send the USDT from
/// the company wallet, paste that payment's TXID and press "Mark as Paid".
/// Or reject with a reason, which returns the held amount to the user.
///
/// Layout note: the app theme gives Filled/Outlined buttons an infinite minimum
/// width, so every button here sets its own minimumSize.
class WithdrawalRequestsTab extends StatefulWidget {
  final WithdrawalAdminService? service;

  const WithdrawalRequestsTab({super.key, this.service});

  @override
  State<WithdrawalRequestsTab> createState() => _WithdrawalRequestsTabState();
}

class _WithdrawalRequestsTabState extends State<WithdrawalRequestsTab> {
  late final WithdrawalAdminService _service = widget.service ?? WithdrawalAdminService.instance;

  String? _filter = 'PENDING';
  List<WithdrawalRequest> _items = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.list(status: _filter);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on DepositServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = switch (e.code) {
          'FORBIDDEN' => 'This account is not recognised as an administrator by the server.',
          _ when e.message.contains('rpc_admin_list_withdrawals') =>
            'Run APPLY_WITHDRAWALS_ADMIN.sql in the Supabase SQL Editor to enable this screen.',
          _ => e.message,
        };
        _loading = false;
      });
    }
  }

  void _setFilter(String? f) {
    if (_filter == f) return;
    setState(() => _filter = f);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeCubit>().state;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final pending = _items.where((w) => w.isPending).length;
    final pendingTotal = _items.where((w) => w.isPending).fold<Decimal>(Decimal.zero, (s, w) => s + w.amount);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _filter == 'PENDING'
                      ? 'Pending withdrawals ($pending) - ${MoneyMath.formatCurrency(pendingTotal)} to pay'
                      : 'Withdrawal requests',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: textPrimary),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
                icon: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.refresh_rounded, color: textSecondary),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final (value, label) in const [
                ('PENDING', 'Pending'),
                (null, 'All'),
                ('APPROVED', 'Paid'),
                ('REJECTED', 'Rejected'),
              ])
                ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 11)),
                  selected: _filter == value,
                  onSelected: (_) => _setFilter(value),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFFF4757))),
            )
          else if (_items.isEmpty && !_loading)
            Padding(
              padding: const EdgeInsets.all(30),
              child: Center(child: Text('No withdrawal requests in this queue.', style: TextStyle(color: textSecondary))),
            )
          else
            for (final w in _items)
              _WithdrawalCard(key: ValueKey(w.id), withdrawal: w, service: _service, onReviewed: _load),
        ],
      ),
    );
  }
}

class _WithdrawalCard extends StatefulWidget {
  final WithdrawalRequest withdrawal;
  final WithdrawalAdminService service;
  final VoidCallback onReviewed;

  const _WithdrawalCard({super.key, required this.withdrawal, required this.service, required this.onReviewed});

  @override
  State<_WithdrawalCard> createState() => _WithdrawalCardState();
}

class _WithdrawalCardState extends State<_WithdrawalCard> {
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFFF4757);
  static const _amber = Color(0xFFFFB300);

  final _txidController = TextEditingController();
  final _noteController = TextEditingController();
  bool _busy = false;
  bool _touched = false;

  // Captured in build(): dialogs and snack bars use these too.
  bool _isDark = true;
  Color get _cardBg => _isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get _fieldBg => _isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
  Color get _border => _isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
  Color get _textPrimary => _isDark ? Colors.white : const Color(0xFF0F172A);
  Color get _textSecondary => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

  WithdrawalRequest get w => widget.withdrawal;

  @override
  void initState() {
    super.initState();
    _txidController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _txidController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: color,
      content: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    ));
  }

  void _copy(String value, String what) {
    Clipboard.setData(ClipboardData(text: value));
    _snack('$what copied.', _green);
  }

  String? get _txidError {
    final v = _txidController.text.trim();
    if (v.isEmpty) return 'Paste the TXID of the USDT payment you sent.';
    if (!DepositService.isValidTxid(v)) return 'A TRON TXID is 64 hexadecimal characters (now ${v.length}).';
    return null;
  }

  Future<void> _markPaid() async {
    setState(() => _touched = true);
    if (_txidError != null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        title: Text('Mark as paid?', style: TextStyle(color: _textPrimary, fontSize: 16)),
        content: Text(
          'Confirm you sent ${MoneyMath.formatCurrency(w.amount)} USDT to\n${w.destination ?? '-'}\n\n'
          'This settles the withdrawal and cannot be undone.',
          style: TextStyle(color: _textSecondary, fontSize: 12),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white, minimumSize: const Size(120, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, paid'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => widget.service.approve(w.id, payoutTxid: _txidController.text, adminNote: _noteController.text),
        'Withdrawal marked as paid.');
  }

  Future<void> _reject() async {
    final reason = await showReasonDialog(
      context,
      title: 'Reject withdrawal',
      message: '${MoneyMath.formatCurrency(w.amount)} will be returned to the user\'s balance. '
          'The user sees this reason.',
      hint: 'e.g. Wallet address is not a TRC-20 address',
      confirmLabel: 'Reject',
      background: _cardBg,
      textPrimary: _textPrimary,
      textSecondary: _textSecondary,
    );
    if (reason == null) return;
    if (reason.isEmpty) {
      _snack('A reason is required to reject a withdrawal.', _red);
      return;
    }
    await _run(() => widget.service.reject(w.id, reason: reason, adminNote: _noteController.text),
        'Withdrawal rejected. Funds returned to the user.');
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      _snack(success, _green);
      widget.onReviewed();
    } on DepositServiceException catch (e) {
      _snack(e.code == 'FORBIDDEN' ? 'Only administrators can review withdrawals.' : e.message, _red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _kv(String k, String v, {Color? color, Widget? trailing, bool mono = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 132, child: Text(k, style: TextStyle(fontSize: 11.5, color: _textSecondary))),
            Expanded(
              child: SelectableText(v,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: color ?? _textPrimary,
                    fontFamily: mono ? 'monospace' : null,
                  )),
            ),
            ?trailing,
          ],
        ),
      );

  Widget _section(String title, List<Widget> children) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: _fieldBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: TextStyle(fontSize: 10, letterSpacing: 0.6, fontWeight: FontWeight.w800, color: _textSecondary)),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      );

  Widget _warning(String text) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _amber.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 16, color: _amber),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: _amber, fontWeight: FontWeight.w600))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    _isDark = context.watch<ThemeCubit>().state;
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    final (statusColor, statusLabel) = switch (w.status) {
      WithdrawalStatus.pending => (_amber, 'PENDING'),
      WithdrawalStatus.approved => (_green, 'PAID'),
      WithdrawalStatus.rejected => (_red, 'REJECTED'),
      WithdrawalStatus.cancelled => (_textSecondary, 'CANCELLED'),
    };
    final kycColor = w.kycApproved ? _green : _red;
    final pnlColor = w.realizedPnlTotal >= Decimal.zero ? _green : _red;
    final txidError = (_touched || _txidController.text.isNotEmpty) ? _txidError : null;

    final warnings = <String>[
      if (!w.kycApproved) 'KYC is ${w.kycStatus.replaceAll('_', ' ').toLowerCase()} - identity not verified.',
      if (!w.destinationLooksValid) 'Destination is not a valid TRC-20 address. Do not send - reject instead.',
      if (w.openPositions > 0) 'User has ${w.openPositions} open position(s); their equity can still change.',
      if (w.totalWithdrawn + w.amount > w.totalDeposited && w.totalDeposited > Decimal.zero)
        'Paying this takes withdrawals above deposits (profit payout).',
      if (w.totalDeposited == Decimal.zero) 'No approved deposits on record for this user.',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: w.isPending ? _amber.withValues(alpha: 0.6) : _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(statusLabel,
                              style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(w.fullName ?? w.userEmail ?? w.userId,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _textPrimary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Requested ${fmt.format(w.createdAt.toLocal())}  ·  ${w.method ?? 'USDT (TRC-20)'}',
                        style: TextStyle(fontSize: 11.5, color: _textSecondary)),
                  ],
                ),
              ),
              Text(MoneyMath.formatCurrency(w.amount),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _red)),
            ],
          ),

          // ── Pay to ───────────────────────────────────────────────────────
          _section('Pay to', [
            _kv(
              'Destination address',
              w.destination?.trim().isNotEmpty == true ? w.destination!.trim() : 'Not provided',
              mono: true,
              color: w.destinationLooksValid ? _green : _red,
              trailing: w.destination?.trim().isNotEmpty == true
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Copy address',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _copy(w.destination!.trim(), 'Address'),
                        icon: Icon(Icons.copy_rounded, size: 16, color: _textSecondary),
                      ),
                      if (w.destinationTronscanUrl != null)
                        IconButton(
                          tooltip: 'Open on Tronscan',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => launchUrl(w.destinationTronscanUrl!, mode: LaunchMode.externalApplication),
                          icon: Icon(Icons.open_in_new_rounded, size: 16, color: _textSecondary),
                        ),
                    ])
                  : null,
            ),
            _kv('Amount to send', '${MoneyMath.formatCurrency(w.amount)} USDT'),
            _kv('Network', 'TRON (TRC-20)'),
          ]),

          // ── User ─────────────────────────────────────────────────────────
          _section('User', [
            if (w.fullName != null) _kv('Name', w.fullName!),
            _kv('Email', w.userEmail ?? '-'),
            _kv('User ID', w.userId, mono: true,
                trailing: IconButton(
                  tooltip: 'Copy user ID',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copy(w.userId, 'User ID'),
                  icon: Icon(Icons.copy_rounded, size: 16, color: _textSecondary),
                )),
            _kv('KYC status', w.kycStatus.replaceAll('_', ' '), color: kycColor),
            if (w.userCreatedAt != null) _kv('Account created', fmt.format(w.userCreatedAt!.toLocal())),
            if (w.lastSignInAt != null) _kv('Last sign-in', fmt.format(w.lastSignInAt!.toLocal())),
          ]),

          // ── Account ──────────────────────────────────────────────────────
          _section('Account', [
            _kv('Balance (after hold)', w.walletBalance == null ? '-' : MoneyMath.formatCurrency(w.walletBalance!)),
            _kv('Used margin', w.heldMargin == null ? '-' : MoneyMath.formatCurrency(w.heldMargin!)),
            _kv('Open positions', '${w.openPositions}', color: w.openPositions > 0 ? _amber : null),
            _kv('Realized P/L (all time)', MoneyMath.formatPnL(w.realizedPnlTotal), color: pnlColor),
            _kv('Total deposited', MoneyMath.formatCurrency(w.totalDeposited)),
            _kv('Total withdrawn', MoneyMath.formatCurrency(w.totalWithdrawn)),
            _kv('Other withdrawals', '${w.previousWithdrawals}'),
          ]),

          if (w.isPending) ...[
            for (final text in warnings) _warning(text),
          ],

          // ── Outcome (reviewed) ───────────────────────────────────────────
          if (w.status == WithdrawalStatus.approved)
            _section('Payment', [
              _kv('Payout TXID', w.payoutTxid ?? '-', mono: true,
                  trailing: w.payoutTronscanUrl == null
                      ? null
                      : IconButton(
                          tooltip: 'Open on Tronscan',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => launchUrl(w.payoutTronscanUrl!, mode: LaunchMode.externalApplication),
                          icon: Icon(Icons.open_in_new_rounded, size: 16, color: _textSecondary),
                        )),
              _kv('Paid by', w.reviewedBy ?? '-'),
              if (w.reviewedAt != null) _kv('Paid at', fmt.format(w.reviewedAt!.toLocal())),
              if ((w.adminNote ?? '').isNotEmpty) _kv('Admin note', w.adminNote!),
            ]),
          if (w.status == WithdrawalStatus.rejected)
            _section('Rejected', [
              _kv('Reason', w.rejectReason ?? '-', color: _red),
              _kv('Rejected by', w.reviewedBy ?? '-'),
              if (w.reviewedAt != null) _kv('Rejected at', fmt.format(w.reviewedAt!.toLocal())),
              if ((w.adminNote ?? '').isNotEmpty) _kv('Admin note', w.adminNote!),
            ]),

          // ── Actions (pending) ────────────────────────────────────────────
          if (w.isPending) ...[
            const SizedBox(height: 14),
            Text('After sending the USDT, paste the payment TXID:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: _txidController,
              enabled: !_busy,
              maxLength: 64,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]'))],
              style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: _textPrimary),
              decoration: InputDecoration(
                hintText: 'Payout transaction ID (64 hex characters)',
                hintStyle: TextStyle(color: _textSecondary, fontSize: 12),
                errorText: txidError,
                filled: true,
                fillColor: _fieldBg,
                isDense: true,
                suffixIcon: _txidController.text.isNotEmpty && _txidError == null
                    ? const Icon(Icons.check_circle_rounded, color: _green)
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
                enabledBorder:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _green)),
              ),
            ),
            TextField(
              controller: _noteController,
              enabled: !_busy,
              style: TextStyle(fontSize: 12.5, color: _textPrimary),
              decoration: InputDecoration(
                hintText: 'Internal admin note (optional, not shown to the user)',
                hintStyle: TextStyle(color: _textSecondary, fontSize: 12),
                filled: true,
                fillColor: _fieldBg,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
                enabledBorder:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _reject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _red,
                      side: const BorderSide(color: _red),
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('REJECT & REFUND', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _markPaid,
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _busy
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_outline_rounded, size: 18),
                    label: const Text('MARK AS PAID', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
