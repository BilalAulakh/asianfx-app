import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../blocs/blocs.dart';
import '../../../core/math/money_math.dart';
import '../../../data/datasources/supabase_deposit_service.dart';
import 'address_a_card.dart';
import 'reason_dialog.dart';

/// Admin queue for manual USDT (TRC-20) deposits.
///
/// Workflow: open the TXID on Tronscan, confirm the transfer reached the company
/// address, type the amount actually received, Approve. Or Reject with a reason.
/// Every decision goes through `rpc_review_deposit`, which re-checks admin
/// rights, locks the request and the wallet, and writes the ledger entry.
class DepositRequestsTab extends StatefulWidget {
  final DepositService? service;

  const DepositRequestsTab({super.key, this.service});

  @override
  State<DepositRequestsTab> createState() => _DepositRequestsTabState();
}

class _DepositRequestsTabState extends State<DepositRequestsTab> {
  late final DepositService _service = widget.service ?? DepositService.instance;

  /// null = all statuses.
  String? _filter = 'PENDING';
  List<DepositRequest> _items = const [];
  bool _loading = false;
  String? _error;

  bool get _isDark => context.watch<ThemeCubit>().state;
  Color get _textPrimary => _isDark ? Colors.white : const Color(0xFF0F172A);
  Color get _textSecondary => _isDark ? const Color(0xFF848E9C) : const Color(0xFF64748B);

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
      final items = await _service.adminList(status: _filter);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on DepositServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.code == 'FORBIDDEN'
            ? 'This account is not recognised as an administrator by the server.'
            : e.message;
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
    final pending = _items.where((d) => d.isPending).length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AddressACard(service: _service),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  switch (_filter) {
                    'PENDING' => 'Pending deposits ($pending) - need your review',
                    'AUTO_APPROVED' => 'Auto-approved deposits (read-only history)',
                    _ => 'Deposit requests',
                  },
                  style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: _textPrimary),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
                icon: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.refresh_rounded, color: _textSecondary),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final (value, label) in const [
                ('PENDING', 'Pending'),
                (null, 'All'),
                ('APPROVED', 'Approved'),
                ('REJECTED', 'Rejected'),
                ('AUTO_APPROVED', 'Auto-approved'),
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
              child: Center(child: Text('No deposit requests in this queue.', style: TextStyle(color: _textSecondary))),
            )
          else
            for (final d in _items)
              _DepositReviewCard(
                key: ValueKey(d.id),
                deposit: d,
                service: _service,
                onReviewed: _load,
              ),
        ],
      ),
    );
  }
}

class _DepositReviewCard extends StatefulWidget {
  final DepositRequest deposit;
  final DepositService service;
  final Future<void> Function() onReviewed;

  const _DepositReviewCard({
    super.key,
    required this.deposit,
    required this.service,
    required this.onReviewed,
  });

  @override
  State<_DepositReviewCard> createState() => _DepositReviewCardState();
}

class _DepositReviewCardState extends State<_DepositReviewCard> {
  late final TextEditingController _amountController =
      TextEditingController(text: widget.deposit.amountClaimed.toString());
  final _noteController = TextEditingController();
  bool _busy = false;
  Future<String?>? _proofUrl;

  static const _green = Color(0xFF00D68F);
  static const _red = Color(0xFFFF4757);
  static const _amber = Color(0xFFFFB300);

  bool get _isDark => context.watch<ThemeCubit>().state;
  Color get _cardBg => _isDark ? const Color(0xFF151D28) : Colors.white;
  Color get _subCardBg => _isDark ? const Color(0xFF0F141C) : const Color(0xFFF8FAFC);
  Color get _border => _isDark ? const Color(0xFF2B384E) : const Color(0xFFCBD5E1);
  Color get _textPrimary => _isDark ? Colors.white : const Color(0xFF0F172A);
  Color get _textSecondary => _isDark ? const Color(0xFF848E9C) : const Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    if (widget.deposit.proofPath != null) {
      _proofUrl = widget.service.proofUrl(widget.deposit.proofPath);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: color,
      duration: const Duration(seconds: 5),
      content: Text(msg,
          style: TextStyle(fontWeight: FontWeight.bold, color: color == _red ? Colors.white : Colors.black)),
    ));
  }

  Future<void> _approve() async {
    Decimal? amount;
    try {
      amount = Decimal.parse(_amountController.text.trim());
    } catch (_) {}
    if (amount == null || amount <= Decimal.zero) {
      _snack('Enter the amount actually received on-chain.', _red);
      return;
    }

    final d = widget.deposit;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve deposit?'),
        content: Text(
          'Credit ${MoneyMath.formatCurrency(amount!)} to ${d.userEmail ?? d.userId}.\n\n'
          'Only approve after confirming on Tronscan that this transfer of USDT (TRC-20) '
          'reached the company address and has not been credited for another request.'
          '${amount != d.amountClaimed ? '\n\nNote: differs from the claimed ${MoneyMath.formatCurrency(d.amountClaimed)}.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve & credit'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _review(approve: true, amount: amount);
  }

  Future<void> _reject() async {
    final reason = await showReasonDialog(
      context,
      title: 'Reject deposit',
      message: 'The user sees this reason. Their balance is not changed.',
      hint: 'e.g. TXID not found / sent to a different address',
      confirmLabel: 'Reject',
    );
    if (reason == null) return;
    if (reason.isEmpty) {
      _snack('A reason is required to reject a deposit.', _red);
      return;
    }
    await _review(approve: false, reason: reason);
  }

  Future<void> _review({required bool approve, Decimal? amount, String? reason}) async {
    setState(() => _busy = true);
    try {
      final res = await widget.service.review(
        depositId: widget.deposit.id,
        approve: approve,
        amountCredited: amount,
        reason: reason,
        adminNote: _noteController.text,
      );
      if (!mounted) return;
      if (res.alreadyReviewed) {
        _snack(res.message ?? 'This deposit was already reviewed.', _amber);
      } else if (approve) {
        _snack('Approved. Credited ${MoneyMath.formatCurrency(res.deposit.amountCredited ?? amount!)}'
            '${res.newBalance != null ? ' — new balance ${MoneyMath.formatCurrency(res.newBalance!)}' : ''}.', _green);
      } else {
        _snack('Deposit rejected.', _green);
      }
      await widget.onReviewed();
    } on DepositServiceException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        'SELF_REVIEW_FORBIDDEN' => 'You cannot review a deposit into your own account.',
        'FORBIDDEN' => 'The server rejected this action: administrator privileges required.',
        _ => e.message,
      };
      _snack(msg, _red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openProof(String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: _ProofViewer(url: url),
      ),
    );
  }

  Widget _kv(String k, String v, {bool mono = false}) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 92, child: Text(k, style: TextStyle(fontSize: 11, color: _textSecondary))),
            Expanded(
              child: SelectableText(v,
                  style: TextStyle(
                      fontSize: 11, color: _textPrimary, fontFamily: mono ? 'monospace' : null)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = widget.deposit;
    final (color, label) = switch (d.status) {
      DepositStatus.pending => (_amber, 'PENDING'),
      DepositStatus.approved => (_green, 'APPROVED'),
      DepositStatus.rejected => (_red, 'REJECTED'),
    };
    final fmt = DateFormat('yyyy-MM-dd HH:mm');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: d.isPending ? _amber.withValues(alpha: 0.6) : _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(d.userEmail ?? d.userId,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Claimed ${MoneyMath.formatCurrency(d.amountClaimed)} ${d.token} (${d.network})',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: _textPrimary)),
          if (d.autoVerifyFailed)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: _red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _red.withValues(alpha: 0.45)),
              ),
              child: Text('Auto-verify failed: ${d.verificationErrorLabel}',
                  style: const TextStyle(color: _red, fontSize: 11.5, fontWeight: FontWeight.bold)),
            ),
          if (d.approvedBySystem)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Auto-approved by the system (verified on-chain) - no action needed',
                  style: TextStyle(color: _green, fontSize: 11.5, fontWeight: FontWeight.bold)),
            ),
          _kv('Submitted', fmt.format(d.createdAt.toLocal())),
          _kv('User ID', d.userId, mono: true),
          _kv('TXID', d.hasTxid ? d.txid : 'Not provided — verify via screenshot', mono: d.hasTxid),
          if (d.fromAddress != null) _kv('From', d.fromAddress!, mono: true),
          if (d.payToAddress != null) _kv('To (company)', d.payToAddress!, mono: true),
          if (d.onchainAmount != null) _kv('On-chain amount', '${MoneyMath.formatCurrency(d.onchainAmount!)} USDT'),
          if (d.status == DepositStatus.approved) ...[
            _kv('Credited', MoneyMath.formatCurrency(d.amountCredited ?? Decimal.zero)),
            _kv('Reviewed', '${d.reviewedBy ?? ''} ${d.reviewedAt != null ? fmt.format(d.reviewedAt!.toLocal()) : ''}'),
          ],
          if (d.status == DepositStatus.rejected) ...[
            _kv('Reason', d.rejectReason ?? ''),
            _kv('Reviewed', '${d.reviewedBy ?? ''} ${d.reviewedAt != null ? fmt.format(d.reviewedAt!.toLocal()) : ''}'),
          ],
          if ((d.adminNote ?? '').isNotEmpty) _kv('Admin note', d.adminNote!),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (d.hasTxid || d.payToAddress != null)
                OutlinedButton.icon(
                  // Without a TXID, open the company wallet's incoming transfers instead.
                  onPressed: () => launchUrl(
                    d.hasTxid
                        ? d.tronscanUrl
                        : Uri.parse('https://tronscan.org/#/address/${d.payToAddress}/transfers'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 14),
                  label: Text(d.hasTxid ? 'Verify on Tronscan' : 'Open company wallet on Tronscan'),
                ),
              if (d.hasTxid)
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: d.txid));
                    _snack('TXID copied.', _green);
                  },
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: const Text('Copy TXID'),
                ),
            ],
          ),
          if (_proofUrl != null) ...[
            const SizedBox(height: 8),
            FutureBuilder<String?>(
              future: _proofUrl,
              builder: (context, snap) {
                final url = snap.data;
                if (snap.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator(minHeight: 2);
                }
                if (url == null) {
                  return Text('Screenshot unavailable.', style: TextStyle(fontSize: 11, color: _textSecondary));
                }
                return InkWell(
                  onTap: () => _openProof(url),
                  child: Container(
                    height: 260,
                    decoration: BoxDecoration(
                      color: _subCardBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(url, fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => Center(
                                child: Text('Could not load screenshot', style: TextStyle(color: _textSecondary)))),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.zoom_in_rounded, size: 16, color: Colors.white),
                                SizedBox(width: 4),
                                Text('Tap to zoom',
                                    style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
          if (d.isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,4}'))],
                    style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      labelText: 'Amount credited (as seen on-chain)',
                      prefixText: '\$ ',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              style: TextStyle(color: _textPrimary, fontSize: 12),
              decoration: const InputDecoration(labelText: 'Internal admin note (optional)', isDense: true),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _reject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _red,
                      side: const BorderSide(color: _red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy ? null : _approve,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('APPROVE', style: TextStyle(fontWeight: FontWeight.bold)),
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

/// Full-screen payment-proof viewer: pinch / wheel / buttons zoom up to 8x,
/// drag to pan, double-tap to toggle 2.5x, and open the original in a new tab.
class _ProofViewer extends StatefulWidget {
  final String url;

  const _ProofViewer({required this.url});

  @override
  State<_ProofViewer> createState() => _ProofViewerState();
}

class _ProofViewerState extends State<_ProofViewer> {
  static const double _minScale = 1.0;
  static const double _maxScale = 8.0;

  final _controller = TransformationController();
  Size _viewport = Size.zero;
  Offset? _doubleTapAt;

  double get _scale => _controller.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransform);
    _controller.dispose();
    super.dispose();
  }

  void _onTransform() => setState(() {});

  /// Zoom to [target] keeping [focal] (viewport coordinates) fixed on screen.
  void _zoomTo(double target, {Offset? focal}) {
    final scale = target.clamp(_minScale, _maxScale);
    final f = focal ?? _viewport.center(Offset.zero);
    final scenePoint = _controller.toScene(f);
    _controller.value = Matrix4.identity()
      ..translateByDouble(f.dx - scenePoint.dx * scale, f.dy - scenePoint.dy * scale, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    if (scale == _minScale) _controller.value = Matrix4.identity();
  }

  Widget _toolButton(IconData icon, String tooltip, VoidCallback? onPressed) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        color: Colors.white,
        disabledColor: Colors.white24,
      );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(builder: (context, constraints) {
            _viewport = constraints.biggest;
            return GestureDetector(
              onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
              onDoubleTap: () => _zoomTo(_scale > 1.01 ? _minScale : 2.5, focal: _doubleTapAt),
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: _minScale,
                maxScale: _maxScale,
                child: SizedBox.expand(
                  child: Image.network(
                    widget.url,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : const Center(child: CircularProgressIndicator(color: Colors.white)),
                    errorBuilder: (_, _, _) => const Center(
                      child: Text('Could not load the screenshot.', style: TextStyle(color: Colors.white70)),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        // Toolbar
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _toolButton(Icons.zoom_out_rounded, 'Zoom out',
                    _scale > _minScale + 0.01 ? () => _zoomTo(_scale / 1.5) : null),
                SizedBox(
                  width: 52,
                  child: Text('${(_scale * 100).round()}%',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                _toolButton(Icons.zoom_in_rounded, 'Zoom in',
                    _scale < _maxScale - 0.01 ? () => _zoomTo(_scale * 1.5) : null),
                _toolButton(Icons.fit_screen_rounded, 'Fit to screen',
                    _scale > _minScale + 0.01 ? () => _zoomTo(_minScale) : null),
                _toolButton(Icons.open_in_new_rounded, 'Open original in new tab',
                    () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication)),
                _toolButton(Icons.close_rounded, 'Close', () => Navigator.of(context).pop()),
              ],
            ),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 16,
          child: IgnorePointer(
            child: Center(
              child: Text('Scroll / pinch to zoom  •  drag to move  •  double-tap to zoom in/out',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ),
          ),
        ),
      ],
    );
  }
}
