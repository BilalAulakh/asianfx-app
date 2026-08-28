import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../domain/entities/user_entity.dart';
import '../core/security/secure_storage_service.dart';
import 'admin_provider.dart';
import 'trading_engine_provider.dart';
import 'wallet_provider.dart';

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
  final Ref _ref;
  final _uuid = const Uuid();

  AuthNotifier(this._ref) : super(const AuthState()) {
    _checkSession();
  }

  Future<void> _checkSession() async {
    try {
      final storedUserId = await SecureStorageService.instance.getUserId();
      final storedEmail = await SecureStorageService.instance.getUserEmail();

      if (storedUserId != null && storedEmail != null && storedEmail.isNotEmpty) {
        final userData = await SecureStorageService.instance.getUserData(storedEmail);
        final restoredUser = _defaultMasterUser.copyWith(
          id: storedUserId,
          email: storedEmail,
          fullName: userData['fullName'] ?? storedEmail.split('@').first.toUpperCase(),
          phone: userData['phone'] ?? '+92 300 1234567',
        );

        state = AuthState(
          status: AuthStatus.authenticated,
          user: restoredUser,
        );

        // Sync trading engine
        _ref.read(tradingEngineProvider.notifier).switchUser(storedUserId);
        return;
      }
    } catch (_) {}

    // First time or logged out: go to unauthenticated state so user can login/register
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<bool> login({required String email, required String password}) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await Future.delayed(const Duration(milliseconds: 350));

      if (email.isEmpty || password.isEmpty) {
        state = const AuthState(
          status: AuthStatus.unauthenticated,
          error: 'Please enter both email and password',
        );
        return false;
      }

      final normalizedEmail = email.trim().toLowerCase();
      String? supabaseUserId;
      bool isSupabaseAuthSuccess = false;

      // 1. Try Supabase Auth Login
      try {
        final authResponse = await Supabase.instance.client.auth.signInWithPassword(
          email: normalizedEmail,
          password: password,
        );
        if (authResponse.user != null) {
          isSupabaseAuthSuccess = true;
          supabaseUserId = authResponse.user!.id;
        }
      } catch (_) {
        // Not registered on Supabase or offline
      }

      // Predefined default accounts
      final isDemoTrader = normalizedEmail == 'client@asianfx.com' ||
          normalizedEmail == 'trader@asianfx.com' ||
          normalizedEmail == 'trader@asianfx.institutional' ||
          normalizedEmail == 'customer@asianfx.com';
      final isDemoAdmin = normalizedEmail == 'admin@asianfx.com';

      // 2. Validate saved local password if registered locally
      final savedPwd = await SecureStorageService.instance.getUserPassword(normalizedEmail);

      // If NOT logged in via Supabase, NOT a predefined demo account, and NOT registered locally -> REJECT!
      if (!isSupabaseAuthSuccess && !isDemoTrader && !isDemoAdmin && savedPwd == null) {
        state = const AuthState(
          status: AuthStatus.unauthenticated,
          error: 'Account not found. Please click "Sign Up" below to create an account first.',
        );
        return false;
      }

      // If registered locally or demo account, check password matches
      if (!isSupabaseAuthSuccess) {
        if (isDemoAdmin && password != 'Admin@12345' && savedPwd != password) {
          // If demo admin, accept Admin@12345 or saved pwd
          state = const AuthState(
            status: AuthStatus.unauthenticated,
            error: 'Incorrect password for Admin.',
          );
          return false;
        } else if (isDemoTrader && password != 'Client@12345' && password != '123456' && savedPwd != null && savedPwd != password) {
          state = const AuthState(
            status: AuthStatus.unauthenticated,
            error: 'Incorrect password for Trader.',
          );
          return false;
        } else if (savedPwd != null && savedPwd != password) {
          state = const AuthState(
            status: AuthStatus.unauthenticated,
            error: 'Incorrect password. Please verify and try again.',
          );
          return false;
        }
      }

      UserRole assignedRole = UserRole.client;
      if (normalizedEmail.contains('admin')) assignedRole = UserRole.admin;
      if (normalizedEmail.contains('dealer')) assignedRole = UserRole.dealer;
      if (normalizedEmail.contains('compliance') || normalizedEmail.contains('aml')) {
        assignedRole = UserRole.compliance;
      }
      if (normalizedEmail.contains('finance') || normalizedEmail.contains('audit')) {
        assignedRole = UserRole.finance;
      }

      // Check saved user data or create new
      final savedData = await SecureStorageService.instance.getUserData(normalizedEmail);
      final userId = supabaseUserId ?? savedData['id'] ?? 'usr_${normalizedEmail.hashCode.abs().toString().padLeft(6, '0')}';
      final name = savedData['fullName'] ?? (isDemoAdmin ? 'Chief Administrator' : email.split('@').first.toUpperCase());
      final phone = savedData['phone'] ?? '+92 300 0000000';

      final loggedInUser = _defaultMasterUser.copyWith(
        id: userId,
        email: email,
        fullName: name,
        phone: phone,
        role: assignedRole,
        kycStatus: KycStatus.approved,
      );

      // Save user session in secure storage
      await SecureStorageService.instance.saveUserProfile(
        id: userId,
        email: normalizedEmail,
        fullName: name,
        role: assignedRole.name,
        phone: phone,
      );
      await SecureStorageService.instance.saveUserCredentials(normalizedEmail, password);

      state = AuthState(
        status: AuthStatus.authenticated,
        user: loggedInUser,
      );

      // Switch trading engine & wallet to this user's profile
      _ref.read(tradingEngineProvider.notifier).switchUser(userId);

      // Ensure user is in Admin panel trader list
      _ref.read(adminProvider.notifier).addTraderUser(
        AdminTraderUser(
          id: userId,
          name: name,
          email: normalizedEmail,
          phone: phone,
          balance: 10000.00,
          equity: 10000.00,
          isKycVerified: true,
          status: AdminUserStatus.active,
          joinedAt: DateTime.now(),
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

  /// 1-Click Role Switcher for instant demonstration & testing of RBAC capabilities
  void switchRole(UserRole role) {
    if (state.user == null) return;
    state = state.copyWith(
      user: state.user!.copyWith(role: role),
    );
  }

  /// Update KYC Status
  void updateUserKyc(KycStatus kycStatus) {
    if (state.user == null) return;
    state = state.copyWith(
      user: state.user!.copyWith(kycStatus: kycStatus),
    );
  }

  /// Update Account Status (e.g. frozen/active)
  void updateUserAccountStatus(AccountStatus status) {
    if (state.user == null) return;
    state = state.copyWith(
      user: state.user!.copyWith(status: status),
    );
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
    String? phone,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await Future.delayed(const Duration(milliseconds: 350));

      final normalizedEmail = email.trim().toLowerCase();
      String effectiveUserId = 'usr_${_uuid.v4().substring(0, 8)}';

      // 1. Try Supabase Auth SignUp
      try {
        final authRes = await Supabase.instance.client.auth.signUp(
          email: normalizedEmail,
          password: password,
          data: {
            'full_name': fullName,
            'phone': phone ?? '',
          },
        );
        if (authRes.user?.id != null) {
          effectiveUserId = authRes.user!.id;
        }
      } catch (_) {
        // Fallback to local secure store
      }

      final newUser = UserEntity(
        id: effectiveUserId,
        email: normalizedEmail,
        fullName: fullName,
        phone: phone ?? '+92 300 1234567',
        country: 'Pakistan',
        nationality: 'Pakistani',
        preferredCurrency: 'USD',
        preferredLanguage: 'en',
        kycStatus: KycStatus.approved,
        status: AccountStatus.active,
        role: UserRole.client,
        isTwoFactorEnabled: false,
        isEmailVerified: true,
        isPhoneVerified: true,
        createdAt: DateTime.now(),
      );

      // 2. Save profile & credentials securely
      await SecureStorageService.instance.saveUserProfile(
        id: effectiveUserId,
        email: normalizedEmail,
        fullName: fullName,
        role: UserRole.client.name,
        phone: phone,
      );
      await SecureStorageService.instance.saveUserCredentials(normalizedEmail, password);

      // 3. Add newly registered trader to Admin Portal
      _ref.read(adminProvider.notifier).addTraderUser(
        AdminTraderUser(
          id: effectiveUserId,
          name: fullName,
          email: normalizedEmail,
          phone: phone ?? '+92 300 1234567',
          balance: 10000.00,
          equity: 10000.00,
          isKycVerified: true,
          status: AdminUserStatus.active,
          joinedAt: DateTime.now(),
        ),
      );

      // 4. Switch trading engine to fresh new user portfolio
      _ref.read(tradingEngineProvider.notifier).switchUser(effectiveUserId);

      state = AuthState(
        status: AuthStatus.authenticated,
        user: newUser,
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
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    await SecureStorageService.instance.clearSession();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  void clearError() => state = state.copyWith(error: null);

  static final _defaultMasterUser = UserEntity(
    id: 'usr_institutional_01',
    email: 'trader@asianfx.institutional',
    phone: '+971 50 892 4100',
    fullName: 'Institutional Master Desk',
    country: 'United Arab Emirates',
    nationality: 'Emirati',
    preferredCurrency: 'USD',
    preferredLanguage: 'en',
    kycStatus: KycStatus.approved,
    status: AccountStatus.active,
    role: UserRole.client,
    isTwoFactorEnabled: true,
    isEmailVerified: true,
    isPhoneVerified: true,
    kycDocumentType: 'Institutional Trade License',
    kycDocumentNumber: 'DMCC-982140',
    createdAt: DateTime(2025, 6, 1),
  );
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});

