import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure Storage Service — wraps FlutterSecureStorage
/// All sensitive data (tokens, user credentials) stored here
class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService instance = SecureStorageService._();

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
  static const String _keyPinHash = 'pin_hash';

  // ── Tokens ───────────────────────────────────────────────────────────────────
  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _keyAccessToken, value: token);

  Future<String?> getAccessToken() =>
      _storage.read(key: _keyAccessToken);

  Future<void> saveRefreshToken(String token) =>
      _storage.write(key: _keyRefreshToken, value: token);

  Future<String?> getRefreshToken() =>
      _storage.read(key: _keyRefreshToken);

  // ── User ─────────────────────────────────────────────────────────────────────
  Future<void> saveUserId(String id) =>
      _storage.write(key: _keyUserId, value: id);

  Future<String?> getUserId() =>
      _storage.read(key: _keyUserId);

  Future<void> saveUserEmail(String email) =>
      _storage.write(key: _keyUserEmail, value: email);

  Future<String?> getUserEmail() =>
      _storage.read(key: _keyUserEmail);

  // ── Biometric ─────────────────────────────────────────────────────────────────
  Future<void> setBiometricEnabled(bool enabled) =>
      _storage.write(key: _keyBiometricEnabled, value: enabled.toString());

  Future<bool> getBiometricEnabled() async {
    final val = await _storage.read(key: _keyBiometricEnabled);
    return val == 'true';
  }

  // ── Device ───────────────────────────────────────────────────────────────────
  Future<void> saveDeviceId(String id) =>
      _storage.write(key: _keyDeviceId, value: id);

  Future<String?> getDeviceId() =>
      _storage.read(key: _keyDeviceId);

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
  }

  Future<void> clearAll() async => _storage.deleteAll();

  // ── PIN ──────────────────────────────────────────────────────────────────────
  Future<void> savePinHash(String hash) =>
      _storage.write(key: _keyPinHash, value: hash);

  Future<String?> getPinHash() =>
      _storage.read(key: _keyPinHash);
}
