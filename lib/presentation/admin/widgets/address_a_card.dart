import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../blocs/blocs.dart';
import '../../../core/utils/tron_address.dart';
import '../../../data/datasources/supabase_deposit_service.dart';

/// The admin's company deposit wallet = ADDRESS A of the rotation.
///
/// Saving makes the address the manual Address A (requests 1, 2, 3 of every 4);
/// the automatic Address B keeps every 4th request. The server
/// (`rpc_admin_set_deposit_address`) re-checks admin rights, updates the rotation
/// under its lock, deactivates the previous Address A and audits the change.
///
/// Every button sets its own minimumSize: the app theme gives Filled/Outlined
/// buttons an infinite minimum width, which breaks layout inside a Row.
class AddressACard extends StatefulWidget {
  final DepositService service;

  /// Called after a successful save (e.g. to refresh the advanced settings).
  final VoidCallback? onSaved;

  const AddressACard({super.key, required this.service, this.onSaved});

  @override
  State<AddressACard> createState() => _AddressACardState();
}

class _AddressACardState extends State<AddressACard> {
  static const _emerald = Color(0xFF10B981);
  static const _red = Color(0xFFFF4757);

  final _controller = TextEditingController();
  String? _addressA;
  CompanyDepositAddress? _addressB;
  bool _loading = true;
  bool _saving = false;
  bool _touched = false;

  // Captured in build(): the confirm dialog and snack bars read these too.
  bool _isDark = true;
  Color get _cardBg => _isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get _fieldBg => _isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
  Color get _border => _isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
  Color get _textPrimary => _isDark ? Colors.white : const Color(0xFF0F172A);
  Color get _textSecondary => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    String? a;
    CompanyDepositAddress? b;
    try {
      final rows = await widget.service.adminListAddresses();
      final active = rows.where((r) => r.isActive && r.weight > 0).toList()
        ..sort((x, y) => x.sortOrder.compareTo(y.sortOrder));
      a = active.where((r) => !r.autoVerify).map((r) => r.address).firstOrNull;
      b = active.where((r) => r.autoVerify).firstOrNull;
    } on DepositServiceException {
      // Rotation not deployed yet: fall back to the single configured address.
    }
    a ??= (await widget.service.loadConfig()).depositAddress;
    if (!mounted) return;
    setState(() {
      _addressA = a;
      _addressB = b;
      _loading = false;
    });
  }

  String? get _validationError {
    final v = _controller.text.trim();
    if (v.isEmpty) return 'Enter the new TRC-20 wallet address.';
    if (!v.startsWith('T')) return 'A TRC-20 address starts with "T".';
    if (v.length != 34) return 'A TRC-20 address is 34 characters (now ${v.length}).';
    if (!TronAddress.hasValidFormat(v)) {
      return 'Contains characters not allowed in a TRON address (0, O, I, l or symbols).';
    }
    if (!TronAddress.isValid(v)) {
      return 'Checksum failed - this is not a real TRON address. Copy it again from your wallet.';
    }
    if (v == _addressA) return 'This is already the current address.';
    if (v == _addressB?.address) return 'This address is already in use for automatic deposits. Use a different one.';
    return null;
  }

  void _clear() {
    _controller.clear();
    setState(() => _touched = false);
  }

  void _copy(String address) {
    Clipboard.setData(ClipboardData(text: address));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Address copied.')));
  }

  Future<void> _save() async {
    setState(() => _touched = true);
    if (_validationError != null) return;
    final next = _controller.text.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        title: Text('Change deposit address?', style: TextStyle(color: _textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New deposits will be told to send USDT to the new address immediately.',
                style: TextStyle(color: _textSecondary, fontSize: 12)),
            const SizedBox(height: 12),
            Text('From', style: TextStyle(color: _textSecondary, fontSize: 11)),
            SelectableText(_addressA ?? '-',
                style: TextStyle(color: _textPrimary, fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 8),
            Text('To', style: TextStyle(color: _textSecondary, fontSize: 11)),
            SelectableText(next,
                style: const TextStyle(
                    color: _emerald, fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('Double-check every character: funds sent to a wrong address cannot be recovered.',
                style: TextStyle(color: _red.withValues(alpha: 0.9), fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: _emerald, foregroundColor: Colors.white, minimumSize: const Size(120, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, update'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final stored = await widget.service.adminSetDepositAddress(next);
      if (!mounted) return;
      setState(() {
        _addressA = stored;
        _touched = false;
      });
      _controller.clear();
      widget.onSaved?.call();
      messenger.showSnackBar(const SnackBar(
        backgroundColor: _emerald,
        content: Text('Deposit address updated.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ));
    } on DepositServiceException catch (e) {
      messenger.showSnackBar(SnackBar(
        backgroundColor: _red,
        content: Text(
          e.code == 'FORBIDDEN' ? 'Only administrators can change the deposit address.' : e.message,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _addressBox({
    required String title,
    required String? address,
    required Color color,
    required IconData icon,
    String? note,
  }) {
    final invalid = address != null && !TronAddress.isValid(address);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textSecondary)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(
            color: _fieldBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: (invalid ? _red : color).withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Icon(invalid ? Icons.error_outline_rounded : icon, size: 18, color: invalid ? _red : color),
              const SizedBox(width: 10),
              Expanded(
                child: _loading
                    ? LinearProgressIndicator(minHeight: 2, color: color)
                    : SelectableText(
                        address ?? '-',
                        style: TextStyle(
                            fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.bold, color: invalid ? _red : color),
                      ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: address == null ? null : () => _copy(address),
                style: TextButton.styleFrom(
                  foregroundColor: color,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy'),
              ),
            ],
          ),
        ),
        if (invalid)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Invalid TRON address (checksum failed): wallets refuse to send here. Save the correct address above.',
              style: TextStyle(color: _red, fontSize: 11.5, fontWeight: FontWeight.bold),
            ),
          )
        else if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(note, style: TextStyle(color: _textSecondary, fontSize: 11)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _isDark = context.watch<ThemeCubit>().state;
    final hasInput = _controller.text.trim().isNotEmpty;
    final error = (_touched || hasInput) ? _validationError : null;
    final valid = hasInput && _validationError == null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _emerald.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _emerald.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.account_balance_wallet_outlined, color: _emerald, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Company Deposit Wallet (USDT TRC-20)',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: _textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('New TRC-20 wallet address',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textSecondary)),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            maxLength: 34,
            enabled: !_saving,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            style: TextStyle(fontFamily: 'monospace', fontSize: 14, color: _textPrimary),
            decoration: InputDecoration(
              hintText: 'T... (34 characters) - copy it from your wallet',
              hintStyle: TextStyle(color: _textSecondary),
              errorText: error,
              errorMaxLines: 2,
              helperText: valid ? 'Valid TRON address (checksum OK)' : null,
              helperStyle: const TextStyle(color: _emerald),
              filled: true,
              fillColor: _fieldBg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              prefixIcon: Icon(Icons.edit_outlined, size: 18, color: _textSecondary),
              suffixIcon: valid ? const Icon(Icons.check_circle_rounded, color: _emerald) : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
              enabledBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
              focusedBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _emerald)),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving || _loading ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _emerald,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _emerald.withValues(alpha: 0.35),
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(_saving ? 'Saving...' : 'Save / Update Address',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              if (hasInput) ...[
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _saving ? null : _clear,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _textSecondary,
                    side: BorderSide(color: _border),
                    minimumSize: const Size(96, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Clear'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          _addressBox(
            title: 'Current Active Address',
            address: _addressA,
            color: _emerald,
            icon: Icons.verified_rounded,
          ),
        ],
      ),
    );
  }
}
