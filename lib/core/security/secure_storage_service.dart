import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/user_entity.dart';

/// Secure Storage Service — wraps FlutterSecureStorage with SharedPreferences fallback
/// All sensitive data (tokens, user credentials) stored with rock-solid persistence
class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService instance = SecureStorageService._();

  static const String _keyActiveSessionUser = 'active_session_user_json';

  Future<void> saveCurrentSessionUser(UserEntity user) async {
    try {
      final jsonStr = jsonEncode(user.toMap());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyActiveSessionUser, jsonStr);
      await prefs.setString(_keyUserId, user.id);
      await prefs.setString(_keyUserEmail, user.email);

      if (!kIsWeb) {
        try {
          await _storage.write(key: _keyActiveSessionUser, value: jsonStr);
          await _storage.write(key: _keyUserId, value: user.id);
          await _storage.write(key: _keyUserEmail, value: user.email);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Error saving session user: $e');
    }
  }

  Future<UserEntity?> getCurrentSessionUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? jsonStr = prefs.getString(_keyActiveSessionUser);
      if ((jsonStr == null || jsonStr.isEmpty) && !kIsWeb) {
        try {
          jsonStr = await _storage.read(key: _keyActiveSessionUser);
        } catch (_) {}
      }
      if (jsonStr == null || jsonStr.isEmpty) return null;
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return UserEntity.fromMap(map);
    } catch (e) {
      debugPrint('Error restoring session user: $e');
      return null;
    }
  }

  Future<void> clearCurrentSessionUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyActiveSessionUser);
      await prefs.remove(_keyUserId);
      await prefs.remove(_keyUserEmail);
      if (!kIsWeb) {
        try {
          await _storage.delete(key: _keyActiveSessionUser);
          await _storage.delete(key: _keyUserId);
          await _storage.delete(key: _keyUserEmail);
        } catch (_) {}
      }
      await clearSession();
    } catch (_) {}
  }

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // ── Keys ─────────────────────────────────────────────────────────────────────
  static const String _keyAccessToken = 'access_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyUserId = 'user_id';
  static const String _keyUserEmail = 'user_email';
  static const String _keyBiometricEnabled = 'biometric_enabled';
  static const String _keyDeviceId = 'device_id';

  // ── Tokens ───────────────────────────────────────────────────────────────────
  Future<void> saveAccessToken(String token) async {
    await _storage.write(key: _keyAccessToken, value: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccessToken, token);
  }

  Future<String?> getAccessToken() async {
    final val = await _storage.read(key: _keyAccessToken);
    if (val != null && val.isNotEmpty) return val;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAccessToken);
  }

  Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _keyRefreshToken, value: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRefreshToken, token);
  }

  Future<String?> getRefreshToken() async {
    final val = await _storage.read(key: _keyRefreshToken);
    if (val != null && val.isNotEmpty) return val;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRefreshToken);
  }

  // ── User ─────────────────────────────────────────────────────────────────────
  Future<void> saveUserId(String id) async {
    await _storage.write(key: _keyUserId, value: id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, id);
  }

  Future<String?> getUserId() async {
    final val = await _storage.read(key: _keyUserId);
    if (val != null && val.isNotEmpty) return val;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserId);
  }

  Future<void> saveUserEmail(String email) async {
    await _storage.write(key: _keyUserEmail, value: email);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserEmail, email);
  }

  Future<String?> getUserEmail() async {
    final val = await _storage.read(key: _keyUserEmail);
    if (val != null && val.isNotEmpty) return val;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserEmail);
  }

  // ── Biometric ─────────────────────────────────────────────────────────────────
  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(key: _keyBiometricEnabled, value: enabled.toString());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBiometricEnabled, enabled);
  }

  Future<bool> getBiometricEnabled() async {
    final val = await _storage.read(key: _keyBiometricEnabled);
    if (val != null) return val == 'true';
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBiometricEnabled) ?? false;
  }

  // ── Device ───────────────────────────────────────────────────────────────────
  Future<void> saveDeviceId(String id) async {
    await _storage.write(key: _keyDeviceId, value: id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDeviceId, id);
  }

  Future<String?> getDeviceId() async {
    final val = await _storage.read(key: _keyDeviceId);
    if (val != null && val.isNotEmpty) return val;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDeviceId);
  }

  // ── Session ──────────────────────────────────────────────────────────────────
  Future<bool> hasValidSession() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keyUserId);
    await _storage.delete(key: _keyUserEmail);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyUserEmail);
  }

  // ── User Profile & Credentials Persistence ───────────────────────────────────
  Future<void> saveUserProfile({
    required String id,
    required String email,
    required String fullName,
    required String role,
    String? phone,
  }) async {
    final normalized = email.toLowerCase().trim();
    await saveUserId(id);
    await saveUserEmail(normalized);
    await _storage.write(key: 'user_fullname_$normalized', value: fullName);
    await _storage.write(key: 'user_role_$normalized', value: role);
    if (phone != null) {
      await _storage.write(key: 'user_phone_$normalized', value: phone);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_fullname_$normalized', fullName);
    await prefs.setString('user_role_$normalized', role);
    if (phone != null) {
      await prefs.setString('user_phone_$normalized', phone);
    }
  }

  Future<void> saveUserCredentials(String email, String password) async {
    final normalized = email.toLowerCase().trim();
    await _storage.write(key: 'user_pwd_$normalized', value: password);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_pwd_$normalized', password);
  }

  Future<String?> getUserPassword(String email) async {
    final normalized = email.toLowerCase().trim();
    final val = await _storage.read(key: 'user_pwd_$normalized');
    if (val != null && val.isNotEmpty) return val;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_pwd_$normalized');
  }

  Future<Map<String, String?>> getUserData(String email) async {
    final normalized = email.toLowerCase().trim();
    final prefs = await SharedPreferences.getInstance();
    String? name = await _storage.read(key: 'user_fullname_$normalized') ?? prefs.getString('user_fullname_$normalized');
    String? role = await _storage.read(key: 'user_role_$normalized') ?? prefs.getString('user_role_$normalized');
    String? phone = await _storage.read(key: 'user_phone_$normalized') ?? prefs.getString('user_phone_$normalized');
    return {
      'fullName': name,
      'role': role,
      'phone': phone,
    };
  }

  // ── User Trades Persistence ──────────────────────────────────────────────────
  Future<void> saveUserTradesData(String userId, String tradesJson) async {
    await _storage.write(key: 'trades_$userId', value: tradesJson);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('trades_$userId', tradesJson);
  }

  Future<String?> getUserTradesData(String userId) async {
    final val = await _storage.read(key: 'trades_$userId');
    if (val != null && val.isNotEmpty) return val;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('trades_$userId');
  }

  // ── User Balance Persistence ─────────────────────────────────────────────────
  Future<void> saveUserBalance(String userId, double balance) async {
    await _storage.write(key: 'balance_$userId', value: balance.toString());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('balance_$userId', balance);
  }

  Future<double?> getUserBalance(String userId) async {
    final val = await _storage.read(key: 'balance_$userId');
    if (val != null) {
      return double.tryParse(val);
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('balance_$userId');
  }

  // ── Security PIN Persistence ────────────────────────────────────────────────
  Future<void> saveSecurityPin(String email, String pin) async {
    final normalized = email.toLowerCase().trim();
    await _storage.write(key: 'sec_pin_$normalized', value: pin);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sec_pin_$normalized', pin);
  }

  Future<String?> getSecurityPin(String email) async {
    final normalized = email.toLowerCase().trim();
    final val = await _storage.read(key: 'sec_pin_$normalized');
    if (val != null && val.isNotEmpty) return val;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('sec_pin_$normalized');
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

  // ── Two-Factor Authentication (2FA) Persistence ────────────────────────────
  Future<void> setTwoFactorEnabledForUser(String email, bool enabled) async {
    final normalized = email.toLowerCase().trim();
    await _storage.write(key: '2fa_enabled_$normalized', value: enabled.toString());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('2fa_enabled_$normalized', enabled);
  }

  Future<bool> isTwoFactorEnabledForUser(String email) async {
    final normalized = email.toLowerCase().trim();
    final val = await _storage.read(key: '2fa_enabled_$normalized');
    if (val != null) return val == 'true';
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('2fa_enabled_$normalized') ?? false;
  }

  Future<String> getOrGenerateTwoFactorSecret(String email) async {
    final normalized = email.toLowerCase().trim();
    final prefs = await SharedPreferences.getInstance();
    final secret = await _storage.read(key: '2fa_secret_$normalized') ?? prefs.getString('2fa_secret_$normalized');
    if (secret != null && secret.isNotEmpty) return secret;
    final generated = 'FXA-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}-${normalized.hashCode.abs().toString().padLeft(4, '0').substring(0, 4)}';
    await _storage.write(key: '2fa_secret_$normalized', value: generated);
    await prefs.setString('2fa_secret_$normalized', generated);
    return generated;
  }

  // ── Registered Traders Persistence ─────────────────────────────────────────
  static const String _keyRegisteredTradersList = 'registered_traders_list_json';

  Future<void> saveRegisteredTraderJson(Map<String, dynamic> userMap) async {
    try {
      final list = await getRegisteredTradersJsonList();
      final id = userMap['id']?.toString() ?? '';
      final email = (userMap['email']?.toString() ?? '').toLowerCase().trim();

      // Replace if exists, else append
      final index = list.indexWhere((u) =>
          (id.isNotEmpty && u['id']?.toString() == id) ||
          (email.isNotEmpty && (u['email']?.toString() ?? '').toLowerCase().trim() == email));

      if (index >= 0) {
        list[index] = userMap;
      } else {
        list.insert(0, userMap);
      }

      final jsonStr = jsonEncode(list);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyRegisteredTradersList, jsonStr);
      if (!kIsWeb) {
        try {
          await _storage.write(key: _keyRegisteredTradersList, value: jsonStr);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Error saving registered trader: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getRegisteredTradersJsonList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? jsonStr = prefs.getString(_keyRegisteredTradersList);
      if ((jsonStr == null || jsonStr.isEmpty) && !kIsWeb) {
        try {
          jsonStr = await _storage.read(key: _keyRegisteredTradersList);
        } catch (_) {}
      }
      if (jsonStr == null || jsonStr.isEmpty) return [];
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('Error loading registered traders: $e');
      return [];
    }
  }
}

