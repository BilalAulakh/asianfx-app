import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../blocs/blocs.dart';
import '../../../core/utils/tron_address.dart';
import '../../../data/datasources/supabase_deposit_service.dart';

/// Company deposit addresses: weighted rotation + automatic verification.
///
/// New deposit requests get an address in rotation order (weights 3 and 1 give
/// A,A,A,B,...). Addresses with Auto Verify are checked on-chain and credited
/// automatically up to Max Auto Approve; everything else goes to manual review.
///
/// Every button sets its own minimumSize: the app theme's infinite-width button
/// minimum breaks layout inside a Row.
class DepositAddressesManager extends StatefulWidget {
  final DepositService service;

  const DepositAddressesManager({super.key, required this.service});

  @override
  State<DepositAddressesManager> createState() => _DepositAddressesManagerState();
}

class _DepositAddressesManagerState extends State<DepositAddressesManager> {
  static const _emerald = Color(0xFF10B981);
  static const _red = Color(0xFFFF4757);

  List<CompanyDepositAddress> _rows = const [];
  bool _loading = true;
  String? _error;
  final _newAddress = TextEditingController();
  bool _adding = false;

  bool _isDark = true;
  Color get _cardBg => _isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get _fieldBg => _isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
  Color get _border => _isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
  Color get _textPrimary => _isDark ? Colors.white : const Color(0xFF0F172A);
  Color get _textSecondary => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _newAddress.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _newAddress.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.service.adminListAddresses();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on DepositServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message.contains('rpc_admin_list_deposit_addresses')
            ? 'Run APPLY_AUTO_VERIFY.sql in the Supabase SQL Editor to enable address rotation.'
            : e.message;
        _loading = false;
      });
    }
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: color,
      content: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    ));
  }

  Future<void> _save(CompanyDepositAddress row, {int? weight, bool? isActive, bool? autoVerify, Decimal? maxAuto}) async {
    try {
      final saved = await widget.service.adminUpsertAddress(
        address: row.address,
        weight: weight,
        isActive: isActive,
        autoVerify: autoVerify,
        maxAutoApproveUsd: maxAuto,
      );
      if (!mounted) return;
      setState(() => _rows = [for (final r in _rows) r.address == saved.address ? saved : r]);
      _snack('Saved ${saved.label ?? saved.address}.', _emerald);
    } on DepositServiceException catch (e) {
      _snack(e.message, _red);
    }
  }

  Future<void> _add() async {
    final address = _newAddress.text.trim();
    if (!TronAddress.isValid(address)) return;
    setState(() => _adding = true);
    try {
      final saved = await widget.service.adminUpsertAddress(address: address, weight: 1, isActive: true, autoVerify: false);
      if (!mounted) return;
      _newAddress.clear();
      setState(() => _rows = [..._rows.where((r) => r.address != saved.address), saved]);
      _snack('Address added to the rotation.', _emerald);
    } on DepositServiceException catch (e) {
      _snack(e.message, _red);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// One rotation cycle, e.g. "A A A B", from active addresses in order.
  String _rotationPreview() {
    final active = _rows.where((r) => r.isActive && r.weight > 0).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (active.isEmpty) return 'No active address - deposits are disabled.';
    final names = <String>[];
    for (var i = 0; i < active.length; i++) {
      final short = String.fromCharCode(65 + i);
      names.addAll(List.filled(active[i].weight, short));
    }
    return '${names.join(' → ')} → repeat';
  }

  @override
  Widget build(BuildContext context) {
    _isDark = context.watch<ThemeCubit>().state;
    final newAddr = _newAddress.text.trim();
    final newAddrError = newAddr.isEmpty
        ? null
        : !TronAddress.hasValidFormat(newAddr)
            ? 'Starts with "T", 34 characters.'
            : !TronAddress.isValid(newAddr)
                ? 'Checksum failed - this is not a real TRON address. Copy it again from the wallet.'
                : _rows.any((r) => r.address == newAddr)
                    ? 'Already in the list.'
                    : null;

    return Container(
      padding: const EdgeInsets.all(16),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Deposit Addresses',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: _textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      _loading || _error != null ? 'Company USDT (TRC-20) addresses' : 'Rotation: ${_rotationPreview()}',
                      style: TextStyle(fontSize: 11, color: _textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Reload',
                onPressed: _loading ? null : _load,
                icon: Icon(Icons.refresh_rounded, color: _textSecondary, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2, color: _emerald)
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: _red, fontSize: 12))
          else ...[
            for (var i = 0; i < _rows.length; i++)
              _AddressRow(
                key: ValueKey('${_rows[i].address}-${_rows[i].maxAutoApproveUsd}-${_rows[i].weight}'),
                row: _rows[i],
                letter: String.fromCharCode(65 + i),
                isDark: _isDark,
                onSave: (w, active, auto, max) => _save(_rows[i], weight: w, isActive: active, autoVerify: auto, maxAuto: max),
              ),
            const SizedBox(height: 10),
            Text('Add address', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textSecondary)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _newAddress,
                    maxLength: 34,
                    inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                    style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: _textPrimary),
                    decoration: InputDecoration(
                      hintText: 'T... (copy it from the wallet, do not type it)',
                      hintStyle: TextStyle(color: _textSecondary, fontSize: 12),
                      errorText: newAddrError,
                      errorMaxLines: 2,
                      isDense: true,
                      filled: true,
                      fillColor: _fieldBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
                      enabledBorder:
                          OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _adding || newAddr.isEmpty || newAddrError != null ? null : _add,
                  style: FilledButton.styleFrom(
                    backgroundColor: _emerald,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(110, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AddressRow extends StatefulWidget {
  final CompanyDepositAddress row;
  final String letter;
  final bool isDark;
  final Future<void> Function(int? weight, bool? isActive, bool? autoVerify, Decimal? maxAuto) onSave;

  const _AddressRow({super.key, required this.row, required this.letter, required this.isDark, required this.onSave});

  @override
  State<_AddressRow> createState() => _AddressRowState();
}

class _AddressRowState extends State<_AddressRow> {
  static const _emerald = Color(0xFF10B981);
  static const _red = Color(0xFFFF4757);
  static const _amber = Color(0xFFFFB300);

  late final _max = TextEditingController(text: widget.row.maxAutoApproveUsd.toString());
  bool _saving = false;

  Color get _fieldBg => widget.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
  Color get _border => widget.isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
  Color get _textPrimary => widget.isDark ? Colors.white : const Color(0xFF0F172A);
  Color get _textSecondary => widget.isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

  @override
  void dispose() {
    _max.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _saving = true);
    await f();
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final maxValue = Decimal.tryParse(_max.text.trim());
    final maxChanged = maxValue != null && maxValue != r.maxAutoApproveUsd;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _fieldBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: r.checksumValid ? _border : _red.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: (r.autoVerify ? _emerald : _amber).withValues(alpha: 0.18),
                child: Text(widget.letter,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: r.autoVerify ? _emerald : _amber)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SelectableText(r.address,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold, color: _textPrimary)),
              ),
              IconButton(
                tooltip: 'Copy',
                visualDensity: VisualDensity.compact,
                onPressed: () => Clipboard.setData(ClipboardData(text: r.address)),
                icon: Icon(Icons.copy_rounded, size: 16, color: _textSecondary),
              ),
            ],
          ),
          if (!r.checksumValid)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Invalid TRON address (checksum failed): wallets refuse to send here. '
                'Set weight 0 or deactivate it, and add the correct address.',
                style: TextStyle(color: _red, fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Weight', style: TextStyle(fontSize: 12, color: _textSecondary)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving || r.weight <= 0 ? null : () => _run(() => widget.onSave(r.weight - 1, null, null, null)),
                  icon: Icon(Icons.remove_circle_outline, size: 18, color: _textSecondary),
                ),
                Text('${r.weight}', style: TextStyle(fontWeight: FontWeight.bold, color: _textPrimary)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving || r.weight >= 100 ? null : () => _run(() => widget.onSave(r.weight + 1, null, null, null)),
                  icon: Icon(Icons.add_circle_outline, size: 18, color: _textSecondary),
                ),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Active', style: TextStyle(fontSize: 12, color: _textSecondary)),
                Switch(
                  value: r.isActive,
                  activeThumbColor: _emerald,
                  onChanged: _saving ? null : (v) => _run(() => widget.onSave(null, v, null, null)),
                ),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Auto Verify', style: TextStyle(fontSize: 12, color: _textSecondary)),
                Switch(
                  value: r.autoVerify,
                  activeThumbColor: _emerald,
                  onChanged: _saving ? null : (v) => _run(() => widget.onSave(null, null, v, null)),
                ),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Max Auto Approve \$', style: TextStyle(fontSize: 12, color: _textSecondary)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _max,
                    enabled: !_saving,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                    style: TextStyle(fontSize: 13, color: _textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _border)),
                      enabledBorder:
                          OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _border)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(56, 36), foregroundColor: _emerald),
                  onPressed: _saving || !maxChanged ? null : () => _run(() => widget.onSave(null, null, null, maxValue)),
                  child: const Text('Save'),
                ),
              ]),
            ],
          ),
          Text(
            r.autoVerify
                ? 'Automatic: verified on-chain and credited up to \$${r.maxAutoApproveUsd}; above that, failures and timeouts go to Pending.'
                : 'Manual: every deposit waits for an admin in Pending.',
            style: TextStyle(fontSize: 11, color: _textSecondary),
          ),
        ],
      ),
    );
  }
}
