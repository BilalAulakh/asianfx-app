import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/security/secure_storage_service.dart';
import '../domain/entities/user_entity.dart';
import 'admin_bloc.dart';
import 'trading_engine_bloc.dart';

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

class AuthCubit extends Cubit<AuthState> {
  TradingEngineCubit? _tradingEngineCubit;
  AdminCubit? _adminCubit;
  StreamSubscription? _subaAuthSub;

  AuthCubit({
    TradingEngineCubit? tradingEngineCubit,
    AdminCubit? adminCubit,
  })  : _tradingEngineCubit = tradingEngineCubit,
        _adminCubit = adminCubit,
        super(const AuthState()) {
    _initAuth();
  }

  void updateDependencies({
    TradingEngineCubit? tradingEngineCubit,
    AdminCubit? adminCubit,
  }) {
    if (tradingEngineCubit != null) _tradingEngineCubit = tradingEngineCubit;
    if (adminCubit != null) _adminCubit = adminCubit;
  }

  Future<void> _initAuth() async {
    await _checkSession();
    _listenAuthChanges();
  }

  void _listenAuthChanges() {
    try {
      _subaAuthSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        final session = data.session;
        final supaUser = session?.user;
        if (session != null && supaUser != null && supaUser.email != null) {
          if (state.status != AuthStatus.authenticated || state.user?.id != supaUser.id) {
            _handleSupabaseUser(supaUser);
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _handleSupabaseUser(User supaUser) async {
    final email = supaUser.email!;
    final meta = supaUser.userMetadata ?? {};
    final isAdmin = email.toLowerCase() == 'admin@asianfx.com' || meta['role'] == 'admin';
    final name = meta['full_name'] as String? ?? (isAdmin ? 'AsianFX Admin' : email.split('@').first.toUpperCase());
    final phone = meta['phone'] as String? ?? '';
    final UserRole assignedRole = isAdmin ? UserRole.admin : UserRole.client;
    final is2Fa = await SecureStorageService.instance.isTwoFactorEnabledForUser(email);

    final user = UserEntity(
      id: supaUser.id,
      email: email,
      fullName: name,
      phone: phone.isNotEmpty ? phone : null,
      country: 'Pakistan',
      nationality: 'Pakistani',
      preferredCurrency: 'USD',
      preferredLanguage: 'en',
      kycStatus: assignedRole == UserRole.admin ? KycStatus.approved : KycStatus.notSubmitted,
      status: AccountStatus.active,
      role: assignedRole,
      isTwoFactorEnabled: is2Fa,
      isEmailVerified: supaUser.emailConfirmedAt != null,
      isPhoneVerified: true,
      kycTier: assignedRole == UserRole.admin ? 2 : 0,
      createdAt: DateTime.tryParse(supaUser.createdAt) ?? DateTime.now(),
    );

    SecureStorageService.instance.saveCurrentSessionUser(user);
    emit(AuthState(
      status: AuthStatus.authenticated,
      user: user,
    ));

    _tradingEngineCubit?.switchUser(supaUser.id);
    _syncUserWalletToSupabase(supaUser.id);
  }

  Future<void> _syncUserWalletToSupabase(String userId) async {
    try {
      final existing = await Supabase.instance.client
          .from('wallets')
          .select('balance')
          .eq('user_id', userId)
          .maybeSingle();
      if (existing == null) {
        await Supabase.instance.client.from('wallets').insert({
          'user_id': userId,
          'currency': 'USD',
          'balance': 0.00,
          'held_margin': 0.00,
        });
      }
    } catch (_) {}
  }

  Future<void> _checkSession() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final supaUser = Supabase.instance.client.auth.currentUser;

      if (session != null && supaUser != null && supaUser.email != null) {
        await _handleSupabaseUser(supaUser);
        return;
      }
    } catch (_) {}

    try {
      final cachedUser = await SecureStorageService.instance.getCurrentSessionUser();
      if (cachedUser != null) {
        var userToEmit = cachedUser;
        // If regular user was previously auto-approved without actually submitting KYC docs, reset to unverified
        if (cachedUser.email != 'admin@asianfx.com' &&
            cachedUser.kycDocumentNumber == null &&
            cachedUser.kycSubmittedAt == null) {
          userToEmit = cachedUser.resetKyc();
          await SecureStorageService.instance.saveCurrentSessionUser(userToEmit);
        }

        emit(AuthState(
          status: AuthStatus.authenticated,
          user: userToEmit,
        ));
        _tradingEngineCubit?.switchUser(userToEmit.id);
        _syncUserWalletToSupabase(userToEmit.id);
        return;
      }
    } catch (_) {}

    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  Future<bool> _loginFallback({
    required String email,
    required String password,
    String? fullName,
    String? phone,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    final savedPwd = await SecureStorageService.instance.getUserPassword(normalizedEmail);
    if (savedPwd != null && savedPwd.isNotEmpty && savedPwd != password) {
      emit(const AuthState(
        status: AuthStatus.unauthenticated,
        error: 'Incorrect email or password. Please check your credentials.',
      ));
      return false;
    }

    if (normalizedEmail == 'admin@asianfx.com' && password != 'Admin@123' && savedPwd != password) {
      emit(const AuthState(
        status: AuthStatus.unauthenticated,
        error: 'Incorrect email or password. Please check your credentials.',
      ));
      return false;
    }

    await SecureStorageService.instance.saveUserCredentials(normalizedEmail, password);

    final isAdmin = normalizedEmail == 'admin@asianfx.com';
    final UserRole assignedRole = isAdmin ? UserRole.admin : UserRole.client;
    final savedData = await SecureStorageService.instance.getUserData(normalizedEmail);

    final name = fullName ?? (isAdmin ? 'AsianFX Admin' : savedData['fullName'] ?? normalizedEmail.split('@').first.toUpperCase());
    final userPhone = phone ?? savedData['phone'] ?? '+92 300 1234567';
    final userId = isAdmin ? 'usr_admin_asianfx' : 'usr_${normalizedEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';

    final is2Fa = await SecureStorageService.instance.isTwoFactorEnabledForUser(normalizedEmail);

    KycStatus initialKyc = KycStatus.notSubmitted;
    int initialTier = 0;
    if (isAdmin) {
      initialKyc = KycStatus.approved;
      initialTier = 2;
    } else if (savedData['kycDocumentNumber'] != null && savedData['kycSubmittedAt'] != null) {
      if (savedData['kycStatus'] != null) {
        initialKyc = KycStatus.values.firstWhere(
          (k) => k.name == savedData['kycStatus'],
          orElse: () => KycStatus.notSubmitted,
        );
      }
      initialTier = (savedData['kycTier'] as int?) ?? (initialKyc == KycStatus.approved ? 2 : 0);
    }

    final loggedInUser = UserEntity(
      id: userId,
      email: normalizedEmail,
      fullName: name,
      phone: userPhone,
      country: 'Pakistan',
      nationality: 'Pakistani',
      preferredCurrency: 'USD',
      preferredLanguage: 'en',
      kycStatus: initialKyc,
      status: AccountStatus.active,
      role: assignedRole,
      isTwoFactorEnabled: is2Fa,
      isEmailVerified: true,
      isPhoneVerified: true,
      kycTier: initialTier,
      createdAt: DateTime.now(),
    );

    await SecureStorageService.instance.saveCurrentSessionUser(loggedInUser);
    await SecureStorageService.instance.saveUserProfile(
      id: userId,
      email: normalizedEmail,
      fullName: name,
      role: assignedRole.name,
      phone: userPhone,
    );

    emit(AuthState(
      status: AuthStatus.authenticated,
      user: loggedInUser,
    ));

    _tradingEngineCubit?.switchUser(userId);
    _syncUserWalletToSupabase(userId);

    if (!isAdmin && _adminCubit != null) {
      _adminCubit!.addTraderUser(
        AdminTraderUser(
          id: userId,
          name: name,
          email: normalizedEmail,
          phone: userPhone,
          balance: 0.00,
          equity: 0.00,
          isKycVerified: false,
          status: AdminUserStatus.active,
          joinedAt: DateTime.now(),
        ),
      );
    }

    return true;
  }

  Future<bool> login({required String email, required String password}) async {
    emit(state.copyWith(status: AuthStatus.loading, error: null));
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      emit(const AuthState(
        status: AuthStatus.unauthenticated,
        error: 'Please enter both email and password',
      ));
      return false;
    }

    final isMasterAdmin = normalizedEmail == 'admin@asianfx.com';

    if (isMasterAdmin && password != 'Admin@123') {
      final savedPwd = await SecureStorageService.instance.getUserPassword(normalizedEmail);
      if (savedPwd != null && savedPwd != password) {
        emit(const AuthState(
          status: AuthStatus.unauthenticated,
          error: 'Incorrect email or password. Please check your credentials.',
        ));
        return false;
      }
    }

    try {
      AuthResponse? authResponse;
      try {
        authResponse = await Supabase.instance.client.auth.signInWithPassword(
          email: normalizedEmail,
          password: password,
        );
      } catch (e) {
        if (isMasterAdmin && password == 'Admin@123') {
          try {
            await Supabase.instance.client.auth.signUp(
              email: normalizedEmail,
              password: password,
              data: {
                'full_name': 'AsianFX Admin',
                'role': 'admin',
              },
            );
            authResponse = await Supabase.instance.client.auth.signInWithPassword(
              email: normalizedEmail,
              password: password,
            );
          } catch (_) {}
        } else {
          rethrow;
        }
      }

      final supaUser = authResponse?.user;
      if (supaUser != null) {
        final meta = supaUser.userMetadata ?? {};
        final isAdmin = isMasterAdmin || meta['role'] == 'admin';
        final name = meta['full_name'] as String? ?? (isAdmin ? 'AsianFX Admin' : normalizedEmail.split('@').first.toUpperCase());
        final phone = meta['phone'] as String? ?? '';
        final UserRole assignedRole = isAdmin ? UserRole.admin : UserRole.client;

        final loggedInUser = UserEntity(
          id: supaUser.id,
          email: normalizedEmail,
          fullName: name,
          phone: phone.isNotEmpty ? phone : null,
          country: 'Pakistan',
          nationality: 'Pakistani',
          preferredCurrency: 'USD',
          preferredLanguage: 'en',
          kycStatus: isAdmin ? KycStatus.approved : KycStatus.notSubmitted,
          status: AccountStatus.active,
          role: assignedRole,
          isTwoFactorEnabled: false,
          isEmailVerified: supaUser.emailConfirmedAt != null,
          isPhoneVerified: true,
          kycTier: isAdmin ? 2 : 0,
          createdAt: DateTime.tryParse(supaUser.createdAt) ?? DateTime.now(),
        );

        await SecureStorageService.instance.saveCurrentSessionUser(loggedInUser);
        await SecureStorageService.instance.saveUserCredentials(normalizedEmail, password);

        emit(AuthState(
          status: AuthStatus.authenticated,
          user: loggedInUser,
        ));

        _tradingEngineCubit?.switchUser(supaUser.id);
        await _syncUserWalletToSupabase(supaUser.id);

        if (!isAdmin && _adminCubit != null) {
          _adminCubit!.addTraderUser(
            AdminTraderUser(
              id: supaUser.id,
              name: name,
              email: normalizedEmail,
              phone: phone.isNotEmpty ? phone : '+92 300 1234567',
              balance: 0.00,
              equity: 0.00,
              isKycVerified: false,
              status: AdminUserStatus.active,
              joinedAt: DateTime.now(),
            ),
          );
        }

        return true;
      }
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid login credentials') || msg.contains('invalid_grant')) {
        if (isMasterAdmin && password == 'Admin@123') {
          return _loginFallback(
            email: normalizedEmail,
            password: password,
            fullName: 'AsianFX Admin',
          );
        }
        final savedPwd = await SecureStorageService.instance.getUserPassword(normalizedEmail);
        if (savedPwd != null && savedPwd == password) {
          return _loginFallback(email: normalizedEmail, password: password);
        }
        emit(const AuthState(
          status: AuthStatus.unauthenticated,
          error: 'Incorrect email or password. Please check your credentials.',
        ));
        return false;
      }

      if (isMasterAdmin && password == 'Admin@123') {
        return _loginFallback(
          email: normalizedEmail,
          password: password,
          fullName: 'AsianFX Admin',
        );
      }

      return _loginFallback(email: normalizedEmail, password: password);
    } catch (_) {
      if (isMasterAdmin && password == 'Admin@123') {
        return _loginFallback(
          email: normalizedEmail,
          password: password,
          fullName: 'AsianFX Admin',
        );
      }
      return _loginFallback(email: normalizedEmail, password: password);
    }

    if (isMasterAdmin && password == 'Admin@123') {
      return _loginFallback(
        email: normalizedEmail,
        password: password,
        fullName: 'AsianFX Admin',
      );
    }
    return _loginFallback(email: normalizedEmail, password: password);
  }

  void switchRole(UserRole role) {
    if (state.user == null) return;
    final updated = state.user!.copyWith(role: role);
    emit(state.copyWith(user: updated));
    SecureStorageService.instance.saveCurrentSessionUser(updated);
  }

  void updateUserKyc(
    KycStatus kycStatus, {
    int? kycTier,
    String? documentType,
    String? documentNumber,
    String? employmentStatus,
    String? tradingExperience,
    String? annualIncome,
    String? streetAddress,
    String? city,
    String? postalCode,
    String? rejectionReason,
  }) {
    if (state.user == null) return;
    final updated = state.user!.copyWith(
      kycStatus: kycStatus,
      kycTier: kycTier ?? (kycStatus == KycStatus.approved ? 2 : state.user!.kycTier),
      kycDocumentType: documentType ?? state.user!.kycDocumentType,
      kycDocumentNumber: documentNumber ?? state.user!.kycDocumentNumber,
      employmentStatus: employmentStatus ?? state.user!.employmentStatus,
      tradingExperience: tradingExperience ?? state.user!.tradingExperience,
      annualIncome: annualIncome ?? state.user!.annualIncome,
      streetAddress: streetAddress ?? state.user!.streetAddress,
      city: city ?? state.user!.city,
      postalCode: postalCode ?? state.user!.postalCode,
      kycRejectionReason: rejectionReason ?? state.user!.kycRejectionReason,
      kycSubmittedAt: DateTime.now(),
    );
    emit(state.copyWith(user: updated));
    SecureStorageService.instance.saveCurrentSessionUser(updated);
    if (_adminCubit != null) {
      _adminCubit!.setTraderKycVerified(updated.id, kycStatus == KycStatus.approved);
    }
  }

  void updateUserAccountStatus(AccountStatus status) {
    if (state.user == null) return;
    final updated = state.user!.copyWith(status: status);
    emit(state.copyWith(user: updated));
    SecureStorageService.instance.saveCurrentSessionUser(updated);
  }

  void resetKycForTesting() {
    if (state.user == null) return;
    final updated = state.user!.resetKyc();
    emit(state.copyWith(user: updated));
    SecureStorageService.instance.saveCurrentSessionUser(updated);
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
    String? phone,
  }) async {
    emit(state.copyWith(status: AuthStatus.loading, error: null));
    final normalizedEmail = email.trim().toLowerCase();

    if (normalizedEmail.isEmpty || password.isEmpty) {
      emit(const AuthState(
        status: AuthStatus.unauthenticated,
        error: 'Please enter all required fields.',
      ));
      return false;
    }

    if (normalizedEmail == 'admin@asianfx.com') {
      emit(const AuthState(
        status: AuthStatus.unauthenticated,
        error: 'This email is reserved for Admin. Please login with your credentials.',
      ));
      return false;
    }

    try {
      const roleString = 'client';

      final authRes = await Supabase.instance.client.auth.signUp(
        email: normalizedEmail,
        password: password,
        data: {
          'full_name': fullName,
          'phone': phone ?? '',
          'role': roleString,
        },
      );

      final supaUser = authRes.user;
      if (supaUser != null) {
        const assignedRole = UserRole.client;

        final newUser = UserEntity(
          id: supaUser.id,
          email: normalizedEmail,
          fullName: fullName,
          phone: phone,
          country: 'Pakistan',
          nationality: 'Pakistani',
          preferredCurrency: 'USD',
          preferredLanguage: 'en',
          kycStatus: KycStatus.notSubmitted,
          status: AccountStatus.active,
          role: assignedRole,
          isTwoFactorEnabled: false,
          isEmailVerified: supaUser.emailConfirmedAt != null,
          isPhoneVerified: true,
          kycTier: 0,
          createdAt: DateTime.now(),
        );

        await SecureStorageService.instance.saveCurrentSessionUser(newUser);
        await SecureStorageService.instance.saveUserCredentials(normalizedEmail, password);

        emit(AuthState(
          status: AuthStatus.authenticated,
          user: newUser,
        ));

        _tradingEngineCubit?.switchUser(supaUser.id);
        await _syncUserWalletToSupabase(supaUser.id);

        if (_adminCubit != null) {
          _adminCubit!.addTraderUser(
            AdminTraderUser(
              id: supaUser.id,
              name: fullName,
              email: normalizedEmail,
              phone: phone ?? '+92 300 1234567',
              balance: 0.00,
              equity: 0.00,
              isKycVerified: false,
              status: AdminUserStatus.active,
              joinedAt: DateTime.now(),
            ),
          );
        }

        return true;
      }
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('already registered') || msg.contains('user already exists')) {
        emit(const AuthState(
          status: AuthStatus.unauthenticated,
          error: 'An account with this email already exists. Please log in.',
        ));
        return false;
      }
      if (msg.contains('weak') || msg.contains('password should be at least')) {
        emit(AuthState(
          status: AuthStatus.unauthenticated,
          error: e.message,
        ));
        return false;
      }
      return _loginFallback(
        email: normalizedEmail,
        password: password,
        fullName: fullName,
        phone: phone,
      );
    } catch (_) {
      return _loginFallback(
        email: normalizedEmail,
        password: password,
        fullName: fullName,
        phone: phone,
      );
    }

    return _loginFallback(
      email: normalizedEmail,
      password: password,
      fullName: fullName,
      phone: phone,
    );
  }

  Future<void> logout() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    try {
      await SecureStorageService.instance.clearCurrentSessionUser();
    } catch (_) {}
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  Future<void> toggleTwoFactor(bool enabled) async {
    if (state.user == null) return;
    final updated = state.user!.copyWith(isTwoFactorEnabled: enabled);
    emit(state.copyWith(user: updated));
    await SecureStorageService.instance.saveCurrentSessionUser(updated);
    await SecureStorageService.instance.setTwoFactorEnabledForUser(updated.email, enabled);
  }

  Future<bool> resetPassword({
    required String email,
    required String newPassword,
  }) async {
    emit(state.copyWith(status: AuthStatus.loading, error: null));
    final normalizedEmail = email.trim().toLowerCase();
    try {
      await SecureStorageService.instance.saveUserCredentials(normalizedEmail, newPassword);
      try {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(password: newPassword),
        );
      } catch (_) {}
      emit(state.copyWith(status: AuthStatus.unauthenticated, error: null));
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.unauthenticated,
        error: 'Failed to reset password. Please try again.',
      ));
      return false;
    }
  }

  void clearError() => emit(state.copyWith(error: null));

  @override
  Future<void> close() {
    _subaAuthSub?.cancel();
    return super.close();
  }
}

typedef AuthBloc = AuthCubit;
