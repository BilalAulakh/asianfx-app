import 'package:asianfxapp/core/theme/app_theme.dart';
import 'package:asianfxapp/data/datasources/app_update_service.dart';
import 'package:asianfxapp/presentation/common/widgets/update_gate.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = 'https://fxasian.example/FXAsian.apk';

class _FakeUpdates extends AppUpdateService {
  _FakeUpdates({required this.current, required this.release, this.wifi = false});

  final int current;
  final AppRelease? release;
  final bool wifi;
  int downloads = 0;
  final installs = <String>[];

  @override
  bool get isSupported => true;
  @override
  Future<int> currentVersionCode() async => current;
  @override
  Future<AppRelease?> fetchLatest() async => release;
  @override
  Future<bool> isOnWifi() async => wifi;
  @override
  Future<String> download(AppRelease release, {void Function(double)? onProgress, CancelToken? cancel}) async {
    downloads++;
    onProgress?.call(1);
    return '/cache/updates/FXAsian-${release.versionCode}.apk';
  }

  @override
  Future<bool> install(String path) async {
    installs.add(path);
    return true;
  }
}

AppRelease _release({int code = 3, int min = 1}) =>
    AppRelease(versionCode: code, versionName: '1.0.$code', apkUrl: _url, minVersionCode: min, notes: '- Faster prices');

Future<void> _pump(WidgetTester tester, _FakeUpdates service) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark,
    builder: (context, child) => UpdateGate(service: service, child: child!),
    home: const Scaffold(body: Text('HOME')),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('updateKindFor', () {
    test('no release, no link or not newer -> none', () {
      expect(updateKindFor(2, null), UpdateKind.none);
      expect(updateKindFor(2, const AppRelease(versionCode: 5, versionName: '1.0.5')), UpdateKind.none);
      expect(updateKindFor(3, _release(code: 3)), UpdateKind.none);
      expect(updateKindFor(4, _release(code: 3)), UpdateKind.none);
    });

    test('newer -> optional; below the minimum -> required', () {
      expect(updateKindFor(2, _release(code: 3)), UpdateKind.optional);
      expect(updateKindFor(2, _release(code: 3, min: 3)), UpdateKind.required);
      expect(updateKindFor(3, _release(code: 4, min: 3)), UpdateKind.optional);
    });

    test('parses the server row', () {
      final r = AppRelease.fromMap({
        'version_code': 7,
        'version_name': '1.2.0',
        'apk_url': _url,
        'apk_sha256': 'ab' * 32,
        'min_version_code': 5,
        'notes': 'x',
      });
      expect((r.versionCode, r.versionName, r.minVersionCode, r.apkUrl), (7, '1.2.0', 5, _url));
    });
  });

  group('UpdateGate', () {
    testWidgets('up to date: nothing is shown', (tester) async {
      final s = _FakeUpdates(current: 3, release: _release(code: 3));
      await _pump(tester, s);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.textContaining('Update'), findsNothing);
    });

    testWidgets('optional on mobile data: asks first; Later hides it', (tester) async {
      final s = _FakeUpdates(current: 2, release: _release());
      await _pump(tester, s);
      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('- Faster prices'), findsOneWidget);
      expect(s.downloads, 0, reason: 'no download on mobile data without asking');

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('optional on Wi-Fi: downloads quietly, then one tap to install', (tester) async {
      final s = _FakeUpdates(current: 2, release: _release(), wifi: true);
      await _pump(tester, s);
      expect(s.downloads, 1);
      expect(find.text('Update ready'), findsOneWidget);

      await tester.tap(find.text('INSTALL'));
      await tester.pumpAndSettle();
      expect(s.installs.single, '/cache/updates/FXAsian-3.apk');
    });

    testWidgets('required: blocks the app, no Later', (tester) async {
      final s = _FakeUpdates(current: 2, release: _release(code: 3, min: 3), wifi: true);
      await _pump(tester, s);
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Later'), findsNothing);
      expect(s.downloads, 0, reason: 'required updates start when the user taps');

      await tester.tap(find.text('UPDATE NOW'));
      await tester.pumpAndSettle();
      expect(find.text('Update ready'), findsOneWidget);
      await tester.tap(find.text('INSTALL'));
      await tester.pumpAndSettle();
      expect(s.installs, hasLength(1));
    });
  });
}
