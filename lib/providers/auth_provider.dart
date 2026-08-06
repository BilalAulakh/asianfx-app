import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/entities/user_entity.dart';
import '../core/security/secure_storage_service.dart';

// ── Auth State ───────────────────────────────────────────────────────────────
enum AuthStatus { loading, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final UserEntity? user;
  final String? error;

  const AuthState({
    this.status = AuthStatus.loading,
    this.user,
    this.error,
  });

  AuthState copyWith({AuthStatus? status, UserEntity? user, String? error}) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _checkSession();
  }

  Future<void> _checkSession() async {
    final hasSession = await SecureStorageService.instance.hasValidSession();
    if (hasSession) {
      // In production: fetch user from API using stored token
      // For now: use mock user
      state = AuthState(
        status: AuthStatus.authenticated,
        user: _mockUser,
      );
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> login({required String email, required String password}) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 1));

      // Mock validation
      if (email.isEmpty || password.isEmpty) {
        state = AuthState(
          status: AuthStatus.unauthenticated,
          error: 'Invalid credentials',
        );
        return false;
      }

      // Store token
      await SecureStorageService.instance.saveAccessToken('mock_token_${DateTime.now().millisecondsSinceEpoch}');
      await SecureStorageService.instance.saveUserEmail(email);

      state = AuthState(
        status: AuthStatus.authenticated,
        user: _mockUser.copyWith(email: email),
      );
      return true;
    } catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: e.toString(),
      );
      return false;
    }
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
    String? phone,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await Future.delayed(const Duration(seconds: 1));

      await SecureStorageService.instance.saveAccessToken('mock_token_new');
      await SecureStorageService.instance.saveUserEmail(email);

      state = AuthState(
        status: AuthStatus.authenticated,
        user: _mockUser.copyWith(
          email: email,
          fullName: fullName,
          phone: phone,
        ),
      );
      return true;
    } catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: e.toString(),
      );
      return false;
    }
  }

  Future<void> logout() async {
    await SecureStorageService.instance.clearSession();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  void clearError() => state = state.copyWith(error: null);

  // Mock user for development
  static final _mockUser = UserEntity(
    id: 'usr_001',
    email: 'trader@fxasianapp.com',
    phone: '+92 300 1234567',
    fullName: 'Alex Rahman',
    country: 'Pakistan',
    nationality: 'Pakistani',
    preferredCurrency: 'USD',
    preferredLanguage: 'en',
    kycStatus: KycStatus.approved,
    status: AccountStatus.active,
    role: UserRole.user,
    isTwoFactorEnabled: true,
    isEmailVerified: true,
    isPhoneVerified: true,
    createdAt: DateTime(2024, 1, 15),
  );
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
