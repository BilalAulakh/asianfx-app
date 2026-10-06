import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device storage for the few things the app keeps locally.
///
/// Rules:
///  * Secrets live in [FlutterSecureStorage] ONLY — never SharedPreferences,
///    which is a plain-text file on Android and readable from backups.
///  * No password is ever stored. Authentication is Supabase-only, and the
///    Supabase SDK persists its own session.
///  * No access/refresh token or user JSON is written by this app.
///
/// [purgeLegacyAuthData] wipes what older builds left behind (plain-text
/// passwords, tokens, cached user JSON, fake 2FA secrets) from both stores.
class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService instance = SecureStorageService._();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ── Legacy cleanup ──────────────────────────────────────────────────────────
  static const _purgeMarker = 'legacy_auth_purge_v1';

  /// Exact keys older builds wrote.
  @visibleForTesting
  static const legacyKeys = <String>{
    'active_session_user_json',
    'access_token',
    'refresh_token',
    'user_id',
    'user_email',
    'device_id',
    'biometric_enabled',
  };

  /// Key prefixes older builds wrote, one key per e-mail / user id.
  @visibleForTesting
  static const legacyPrefixes = <String>[
    'user_pwd_',
    'user_fullname_',
    'user_role_',
    'user_phone_',
    '2fa_secret_',
    '2fa_enabled_',
    'trades_',
    'balance_',
  ];

  /// Keys that may stay in SECURE storage but must never remain in
  /// SharedPreferences (older builds mirrored them there in plain text).
  @visibleForTesting
  static const secureOnlyPrefixes = <String>['sec_pin_', _keyRegisteredTradersList];

  @visibleForTesting
  static bool isLegacyKey(String key) =>
      legacyKeys.contains(key) || legacyPrefixes.any(key.startsWith);

  static bool _mustLeavePrefs(String key) =>
      isLegacyKey(key) || secureOnlyPrefixes.any(key.startsWith);

  /// One-time (per install) removal of legacy credentials from BOTH stores.
  /// Safe to call on every launch; it no-ops after the first success.
  Future<void> purgeLegacyAuthData() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_purgeMarker) == true) return;
    } catch (_) {
      prefs = null;
    }

    try {
      if (prefs != null) {
        for (final key in prefs.getKeys().where(_mustLeavePrefs).toList()) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      debugPrint('Legacy SharedPreferences purge failed: $e');
    }

    var secureOk = true;
    try {
      final all = await _storage.readAll();
      for (final key in all.keys.where(isLegacyKey).toList()) {
        await _storage.delete(key: key);
      }
    } catch (e) {
      secureOk = false;
      debugPrint('Legacy secure-storage purge failed: $e');
    }

    if (secureOk) {
      try {
        await prefs?.setBool(_purgeMarker, true);
      } catch (_) {}
    }
  }

  /// Logout: make sure nothing user-identifying from older builds survives.
  Future<void> clearCurrentSessionUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in legacyKeys) {
        await prefs.remove(key);
      }
    } catch (_) {}
    try {
      for (final key in legacyKeys) {
        await _storage.delete(key: key);
      }
    } catch (_) {}
  }

  // ── Security PIN (app lock) — secure storage only ───────────────────────────
  Future<void> saveSecurityPin(String email, String pin) async {
    await _storage.write(key: 'sec_pin_${email.toLowerCase().trim()}', value: pin);
  }

  Future<String?> getSecurityPin(String email) async {
    try {
      return await _storage.read(key: 'sec_pin_${email.toLowerCase().trim()}');
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasSecurityPin(String email) async {
    final pin = await getSecurityPin(email);
    return pin != null && pin.isNotEmpty;
  }

  Future<bool> verifySecurityPin(String email, String pin) async {
    final saved = await getSecurityPin(email);
    if (saved == null || saved.isEmpty) return false;
    return saved == pin;
  }

  // ── Admin CRM cache (non-authoritative display list) — secure storage only ──
  static const String _keyRegisteredTradersList = 'registered_traders_list_json';

  Future<void> saveRegisteredTraderJson(Map<String, dynamic> userMap) async {
    try {
      final list = await getRegisteredTradersJsonList();
      final id = userMap['id']?.toString() ?? '';
      final email = (userMap['email']?.toString() ?? '').toLowerCase().trim();

      final index = list.indexWhere((u) =>
          (id.isNotEmpty && u['id']?.toString() == id) ||
          (email.isNotEmpty && (u['email']?.toString() ?? '').toLowerCase().trim() == email));

      if (index >= 0) {
        list[index] = userMap;
      } else {
        list.insert(0, userMap);
      }
      await _storage.write(key: _keyRegisteredTradersList, value: jsonEncode(list));
    } catch (e) {
      debugPrint('Error saving registered trader: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getRegisteredTradersJsonList() async {
    try {
      final jsonStr = await _storage.read(key: _keyRegisteredTradersList);
      if (jsonStr == null || jsonStr.isEmpty) return [];
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('Error loading registered traders: $e');
      return [];
    }
  }
}
