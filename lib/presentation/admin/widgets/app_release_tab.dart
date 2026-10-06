import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../blocs/blocs.dart';
import '../../../data/datasources/app_update_service.dart';

/// Admin: publish a new Android build. Installed apps see "Update available"
/// (or a blocking "Update required") and update from inside the app.
class AppReleaseTab extends StatefulWidget {
  final AppUpdateService? service;
  const AppReleaseTab({super.key, this.service});

  @override
  State<AppReleaseTab> createState() => _AppReleaseTabState();
}

class _AppReleaseTabState extends State<AppReleaseTab> {
  late final AppUpdateService _service = widget.service ?? AppUpdateService.instance;

  final _versionName = TextEditingController();
  final _versionCode = TextEditingController();
  final _apkUrl = TextEditingController();
  final _notes = TextEditingController();
  final _sha = TextEditingController();
  bool _force = false;

  AppRelease? _current;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFFF4757);

  bool _isDark = true;
  Color get _cardBg => _isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get _subBg => _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _border => _isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
  Color get _textPrimary => _isDark ? Colors.white : const Color(0xFF0F172A);
  Color get _textSecondary => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_versionName, _versionCode, _apkUrl, _notes, _sha]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _service.fetchLatest();
      if (!mounted) return;
      setState(() {
        _current = r;
        _loading = false;
        if (r != null) {
          _versionCode.text = '${r.versionCode + 1}';
          _apkUrl.text = r.apkUrl ?? '';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the current release. Run APPLY_APP_RELEASE.sql in Supabase first.';
      });
    }
  }

  String? _validate() {
    final code = int.tryParse(_versionCode.text.trim());
    if (!RegExp(r'^[0-9A-Za-z.+_-]{1,32}$').hasMatch(_versionName.text.trim())) return 'Enter the version, e.g. 1.0.1';
    if (code == null || code < 1) return 'Enter the build number (the number after + in pubspec.yaml).';
    if (_current != null && code <= _current!.versionCode) {
      return 'Build number must be higher than the published build ${_current!.versionCode}.';
    }
    if (!_apkUrl.text.trim().startsWith('https://')) return 'The download link must start with https://';
    final sha = _sha.text.trim();
    if (sha.isNotEmpty && !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha)) return 'SHA-256 must be 64 characters (0-9, a-f).';
    return null;
  }

  Future<void> _publish() async {
    final problem = _validate();
    if (problem != null) return _snack(problem, _red);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Publish update?'),
        content: Text(_force
            ? 'Every user on an older version will have to update to ${_versionName.text.trim()} before using the app.'
            : 'Users will see "Update available" for version ${_versionName.text.trim()}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final r = await _service.publish(
        versionCode: int.parse(_versionCode.text.trim()),
        versionName: _versionName.text.trim(),
        apkUrl: _apkUrl.text.trim(),
        notes: _notes.text,
        force: _force,
        apkSha256: _sha.text,
      );
      if (!mounted) return;
      setState(() {
        _current = r;
        _versionName.clear();
        _versionCode.text = '${r.versionCode + 1}';
        _notes.clear();
        _sha.clear();
        _force = false;
      });
      _snack('Version ${r.versionName} published. Users get the update when they open the app.', _green);
    } on AppUpdateException catch (e) {
      _snack(e.message, _red);
    } catch (e) {
      _snack('Publish failed: $e', _red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: color,
      content: Text(message,
          style: TextStyle(fontWeight: FontWeight.bold, color: color == _red ? Colors.white : Colors.black)),
    ));
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _textSecondary, fontSize: 12),
        filled: true,
        fillColor: _subBg,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _green)),
      );

  Widget _field(String label, TextEditingController c, String hint,
          {TextInputType? keyboard, int maxLines = 1, List<TextInputFormatter>? formatters}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: c,
              keyboardType: keyboard,
              maxLines: maxLines,
              inputFormatters: formatters,
              style: TextStyle(color: _textPrimary, fontSize: 13),
              decoration: _dec(hint),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    _isDark = context.watch<ThemeCubit>().state;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _green.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.system_update_rounded, color: _green),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Publish App Update',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.bold, color: _textPrimary)),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
                icon: Icon(Icons.refresh_rounded, color: _textSecondary, size: 20),
              ),
            ]),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator(color: _green, strokeWidth: 2)),
              )
            else ...[
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: const TextStyle(color: _red, fontSize: 12)),
                ),
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _subBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: Text(
                  _current == null
                      ? 'No version published yet.'
                      : 'Live version: ${_current!.versionName} (build ${_current!.versionCode})'
                          '${_current!.minVersionCode >= _current!.versionCode && _current!.versionCode > 1 ? ' - required' : ''}',
                  style: TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              _field('Version', _versionName, 'e.g. 1.0.1'),
              _field('Build number', _versionCode, 'number after + in pubspec.yaml, e.g. 2',
                  keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly]),
              _field('APK download link', _apkUrl, 'https://your-site.com/FXAsian.apk', keyboard: TextInputType.url),
              _field("What's new (shown to users)", _notes, '- Faster prices\n- Bug fixes', maxLines: 4),
              _field('SHA-256 of the APK (optional)', _sha, 'printed by the release build script'),
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  value: _force,
                  onChanged: (v) => setState(() => _force = v),
                  activeThumbColor: _green,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Required update', style: TextStyle(color: _textPrimary, fontSize: 13)),
                  subtitle: Text('Older versions cannot be used until they update.',
                      style: TextStyle(color: _textSecondary, fontSize: 11)),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _saving ? null : _publish,
                icon: _saving
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.publish_rounded, size: 18),
                label: const Text('PUBLISH UPDATE', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'First upload the new APK to the website, then publish here. The APK must be signed with the '
                'same key as before, otherwise phones refuse the update.',
                style: TextStyle(color: _textSecondary, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
