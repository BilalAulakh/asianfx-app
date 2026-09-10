import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

final biometricAuthServiceProvider = Provider<BiometricAuthService>((ref) {
  return BiometricAuthService.instance;
});

class BiometricAuthService {
  BiometricAuthService._();
  static final BiometricAuthService instance = BiometricAuthService._();

  final LocalAuthentication _auth = LocalAuthentication();

  bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Checks if device has biometric hardware or lock screen credentials (PIN, pattern, passcode)
  Future<bool> isDeviceSecuritySupported() async {
    if (!isMobile) return false;
    try {
      final isSupported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return isSupported || canCheck;
    } catch (e) {
      debugPrint('[BiometricAuthService] Error checking device security support: $e');
      return false;
    }
  }

  /// Lists available biometric hardware on device (face, fingerprint, etc.)
  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (!isMobile) return [];
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      debugPrint('[BiometricAuthService] Error retrieving available biometrics: $e');
      return [];
    }
  }

  /// Prompts the user to authenticate using Fingerprint, Face ID, or Device PIN / Code / Pattern
  Future<bool> authenticate({
    String? localizedReason,
  }) async {
    if (!isMobile) return true;
    try {
      final didAuthenticate = await _auth.authenticate(
        localizedReason: localizedReason ??
            'Authenticate with Fingerprint, Face, or PIN/Code to access FXAsian',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allows device PIN / Passcode / Pattern fallback or primary
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );
      return didAuthenticate;
    } on PlatformException catch (e) {
      debugPrint('[BiometricAuthService] PlatformException: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[BiometricAuthService] Error during authentication: $e');
      return false;
    }
  }

  /// Stops any in-flight authentication
  Future<void> cancelAuthentication() async {
    if (!isMobile) return;
    try {
      await _auth.stopAuthentication();
    } catch (_) {}
  }
}
