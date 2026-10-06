import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The latest build published by the admin (public.app_release).
class AppRelease {
  final int versionCode;
  final String versionName;
  final String? apkUrl;
  final String? apkSha256;
  final int minVersionCode;
  final String? notes;

  const AppRelease({
    required this.versionCode,
    required this.versionName,
    this.apkUrl,
    this.apkSha256,
    this.minVersionCode = 1,
    this.notes,
  });

  factory AppRelease.fromMap(Map<String, dynamic> m) => AppRelease(
        versionCode: (m['version_code'] as num?)?.toInt() ?? 1,
        versionName: (m['version_name'] as String?) ?? '',
        apkUrl: m['apk_url'] as String?,
        apkSha256: m['apk_sha256'] as String?,
        minVersionCode: (m['min_version_code'] as num?)?.toInt() ?? 1,
        notes: m['notes'] as String?,
      );
}

enum UpdateKind { none, optional, required }

/// What [current] (this build's versionCode) should do about [release].
UpdateKind updateKindFor(int current, AppRelease? release) {
  if (release == null || release.apkUrl == null || release.apkUrl!.isEmpty) return UpdateKind.none;
  if (release.versionCode <= current) return UpdateKind.none;
  return current < release.minVersionCode ? UpdateKind.required : UpdateKind.optional;
}

class AppUpdateException implements Exception {
  final String message;
  const AppUpdateException(this.message);
  @override
  String toString() => message;
}

/// In-app updates for the Android build distributed from the website:
/// read the published release, download the APK into the app's cache, check
/// its SHA-256 (when published) and hand it to the system installer. Android
/// only installs it if it is signed with the same key as the installed app.
class AppUpdateService {
  AppUpdateService();
  static final AppUpdateService instance = AppUpdateService();

  static const _channel = MethodChannel('fxasian/updater');

  /// In-app updates only make sense for the sideloaded Android app.
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Optional updates download quietly in the background only on Wi-Fi.
  Future<bool> isOnWifi() async =>
      (await Connectivity().checkConnectivity()).contains(ConnectivityResult.wifi);

  Future<int> currentVersionCode() async =>
      int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

  Future<AppRelease?> fetchLatest() async {
    final res = await Supabase.instance.client.rpc('rpc_get_app_release');
    if (res is! Map) return null;
    return AppRelease.fromMap(Map<String, dynamic>.from(res));
  }

  /// Admin: publish a new build. [force] makes it mandatory for older builds.
  Future<AppRelease> publish({
    required int versionCode,
    required String versionName,
    required String apkUrl,
    String? notes,
    bool force = false,
    String? apkSha256,
  }) async {
    try {
      final res = await Supabase.instance.client.rpc('rpc_admin_publish_app_release', params: {
        'p_version_code': versionCode,
        'p_version_name': versionName.trim(),
        'p_apk_url': apkUrl.trim(),
        'p_notes': notes?.trim(),
        'p_force': force,
        'p_apk_sha256': (apkSha256 == null || apkSha256.trim().isEmpty) ? null : apkSha256.trim().toLowerCase(),
      });
      final release = (res as Map)['release'];
      return AppRelease.fromMap(Map<String, dynamic>.from(release as Map));
    } on PostgrestException catch (e) {
      throw AppUpdateException(e.message.replaceFirst(RegExp(r'^[A-Z_]+:\s*'), ''));
    }
  }

  /// Downloads the APK (progress 0..1) and returns its local path.
  Future<String> download(AppRelease release, {void Function(double progress)? onProgress, CancelToken? cancel}) async {
    final url = release.apkUrl;
    if (url == null || !url.startsWith('https://')) throw const AppUpdateException('No download link published.');
    final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
    if (dir.existsSync()) dir.deleteSync(recursive: true); // drop older downloads
    dir.createSync(recursive: true);
    final path = '${dir.path}/FXAsian-${release.versionCode}.apk';
    try {
      await Dio().download(url, path, cancelToken: cancel, onReceiveProgress: (got, total) {
        if (total > 0) onProgress?.call(got / total);
      });
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw const AppUpdateException('Download failed. Check your internet connection and try again.');
    }
    final expected = release.apkSha256?.toLowerCase();
    if (expected != null && expected.isNotEmpty) {
      final actual = (await sha256.bind(File(path).openRead()).first).toString();
      if (actual != expected) {
        File(path).deleteSync();
        throw const AppUpdateException('The downloaded file is damaged. Please try again.');
      }
    }
    return path;
  }

  /// Opens the system installer. Returns false when the user first has to
  /// allow "Install unknown apps" for FXAsian (the settings page is opened).
  Future<bool> install(String path) async {
    final allowed = await _channel.invokeMethod<bool>('canInstall') ?? false;
    if (!allowed) {
      await _channel.invokeMethod('openInstallSettings');
      return false;
    }
    await _channel.invokeMethod('installApk', {'path': path});
    return true;
  }
}
