import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../data/datasources/app_update_service.dart';

/// Checks for a newer published build on start and when the app comes back to
/// the foreground (at most every 5 minutes; one small RPC per check).
///
/// * Optional update on Wi-Fi: the APK downloads quietly in the background and
///   the user only sees "Update ready - INSTALL".
/// * Optional update on mobile data: "Update available - UPDATE / LATER".
/// * Required update (published as mandatory): a blocking screen until updated.
///
/// Android always asks the user to confirm the install (one tap); apps outside
/// the Play Store cannot install themselves silently.
class UpdateGate extends StatefulWidget {
  final Widget child;
  final AppUpdateService? service;
  const UpdateGate({super.key, required this.child, this.service});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

enum _Phase { hidden, available, downloading, ready, failed }

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  late final AppUpdateService _service = widget.service ?? AppUpdateService.instance;

  static const _green = Color(0xFF10B981);
  static const _checkEvery = Duration(minutes: 5);

  _Phase _phase = _Phase.hidden;
  AppRelease? _release;
  UpdateKind _kind = UpdateKind.none;
  String? _apkPath;
  double _progress = 0;
  String? _message;
  DateTime? _lastCheck;
  int? _dismissedCode;
  bool _checking = false;
  CancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    if (!_service.isSupported) return;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancel?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastCheck;
    if (last == null || DateTime.now().difference(last) >= _checkEvery) _check();
  }

  Future<void> _check() async {
    if (_checking || _phase == _Phase.downloading) return;
    _checking = true;
    _lastCheck = DateTime.now();
    try {
      final current = await _service.currentVersionCode();
      final release = await _service.fetchLatest();
      final kind = updateKindFor(current, release);
      if (!mounted || kind == UpdateKind.none) return;
      if (kind == UpdateKind.optional && _dismissedCode == release!.versionCode) return;
      if (_release?.versionCode == release!.versionCode && _phase != _Phase.hidden) {
        if (kind == UpdateKind.required && _kind != kind) setState(() => _kind = kind);
        return;
      }
      _release = release;
      _kind = kind;
      _apkPath = null;

      if (kind == UpdateKind.optional && await _service.isOnWifi()) {
        // Quiet background download; the card appears once it is ready.
        await _download(quiet: true);
      } else {
        setState(() => _phase = _Phase.available);
      }
    } catch (_) {
      // Offline or the server is unreachable: try again next time.
    } finally {
      _checking = false;
    }
  }

  Future<void> _download({bool quiet = false}) async {
    final release = _release;
    if (release == null) return;
    _cancel = CancelToken();
    setState(() {
      _phase = quiet ? _Phase.hidden : _Phase.downloading;
      _progress = 0;
      _message = null;
    });
    try {
      final path = await _service.download(release, cancel: _cancel, onProgress: (p) {
        if (mounted && !quiet) setState(() => _progress = p);
      });
      if (!mounted) return;
      setState(() {
        _apkPath = path;
        _phase = _Phase.ready;
      });
    } on DioException {
      // Cancelled.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = quiet ? _Phase.available : _Phase.failed;
        _message = quiet ? null : e.toString();
      });
    }
  }

  Future<void> _install() async {
    final path = _apkPath;
    if (path == null) return _download();
    try {
      final opened = await _service.install(path);
      if (!mounted) return;
      setState(() => _message = opened
          ? null
          : 'Allow "Install unknown apps" for FXAsian in the screen that opened, then come back and tap INSTALL.');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _apkPath = null;
        _phase = _Phase.failed;
        _message = 'Could not open the installer. Please try again.';
      });
    }
  }

  void _later() => setState(() {
        _dismissedCode = _release?.versionCode;
        _phase = _Phase.hidden;
      });

  @override
  Widget build(BuildContext context) {
    final show = _phase != _Phase.hidden && _release != null;
    return Stack(
      children: [
        widget.child,
        if (show) ...[
          const ModalBarrier(dismissible: false, color: Colors.black54),
          Center(child: _card(context)),
        ],
      ],
    );
  }

  Widget _card(BuildContext context) {
    final release = _release!;
    final required = _kind == UpdateKind.required;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final title = switch (_phase) {
      _Phase.ready => 'Update ready',
      _Phase.downloading => 'Downloading update…',
      _Phase.failed => 'Update failed',
      _ => required ? 'Update required' : 'Update available',
    };
    final subtitle = required && _phase != _Phase.failed
        ? 'Please update FXAsian to version ${release.versionName} to continue.'
        : 'FXAsian ${release.versionName} is available.';

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _green.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.system_update_rounded, color: _green, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.bold, color: textPrimary)),
              ),
            ]),
            const SizedBox(height: 12),
            Text(subtitle, style: TextStyle(fontSize: 13, color: textSecondary)),
            if ((release.notes ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text("What's new", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textPrimary)),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Text(release.notes!, style: TextStyle(fontSize: 12.5, color: textSecondary, height: 1.4)),
                ),
              ),
            ],
            if (_phase == _Phase.downloading) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 8,
                  color: _green,
                  backgroundColor: _green.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 6),
              Text('${(_progress * 100).toStringAsFixed(0)}%',
                  textAlign: TextAlign.end, style: TextStyle(fontSize: 11, color: textSecondary)),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!,
                  style: TextStyle(
                      fontSize: 12, color: _phase == _Phase.failed ? const Color(0xFFFF4757) : textSecondary)),
            ],
            const SizedBox(height: 18),
            if (_phase != _Phase.downloading)
              ElevatedButton(
                onPressed: _phase == _Phase.ready ? _install : _download,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  switch (_phase) {
                    _Phase.ready => 'INSTALL',
                    _Phase.failed => 'TRY AGAIN',
                    _ => 'UPDATE NOW',
                  },
                  style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
              ),
            if (!required && _phase != _Phase.downloading) ...[
              const SizedBox(height: 6),
              TextButton(
                onPressed: _later,
                style: TextButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
                child: Text('Later', style: TextStyle(color: textSecondary)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
