import 'dart:async';
import 'package:flutter/foundation.dart';
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

/// Server's view of the caller, from `rpc_whoami()` -> `fx_is_admin()`.
typedef WhoAmIResult = ({String? userId, bool isAdmin});
typedef WhoAmIFetcher = Future<WhoAmIResult> Function();

/// Authentication is Supabase-only.
///
/// * A user is "authenticated" only while Supabase holds a session. There is no
///   offline / cached-credential login: a network error is an error.
/// * Whether the UI shows admin screens is decided by the DATABASE
///   (`rpc_whoami`), never by the e-mail address or by `user_metadata`, which
///   the user can edit themselves. The UI gate is cosmetic; every admin RPC
///   re-checks `fx_is_admin()` server-side.
/// * No password, token or user record is ever written to device storage.
class AuthCubit extends Cubit<AuthState> {
  TradingEngineCubit? _tradingEngineCubit;
  AdminCubit? _adminCubit;
  final WhoAmIFetcher _whoAmI;
  StreamSubscription<dynamic>? _authSub;

  /// True while a password-recovery OTP session is being used to set a new
  /// password; that temporary session must not log the user into the app.
  bool _recoveryInProgress = false;

  AuthCubit({
    this._tradingEngineCubit,
    this._adminCubit,
    WhoAmIFetcher? whoAmI,
    bool autoInit = true,
  })  : _whoAmI = whoAmI ?? _rpcWhoAmI,
        super(const AuthState()) {
    if (autoInit) _initAuth();
  }

  void updateDependencies({
    TradingEngineCubit? tradingEngineCubit,
    AdminCubit? adminCubit,
  }) {
    if (tradingEngineCubit != null) _tradingEngineCubit = tradingEngineCubit;
    if (adminCubit != null) _adminCubit = adminCubit;
  }

  static SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Fails closed: any error means "not an admin".
  static Future<WhoAmIResult> _rpcWhoAmI() async {
    try {
      final res = await _client?.rpc('rpc_whoami');
      if (res is Map) {
        return (userId: res['user_id']?.toString(), isAdmin: res['is_admin'] == true);
      }
    } catch (e) {
      debugPrint('rpc_whoami failed (treating as non-admin): $e');
    }
    return (userId: null, isAdmin: false);
  }

  Future<void> _initAuth() async {
    // One-time removal of credentials / user JSON older builds left on device.
    await SecureStorageService.instance.purgeLegacyAuthData();
    await _checkSession();
    _listenAuthChanges();
  }

  void _listenAuthChanges() {
    final client = _client;
    if (client == null) return;
    _authSub = client.auth.onAuthStateChange.listen((data) {
      if (_recoveryInProgress) return;
      final session = data.session;
      final supaUser = session?.user;
      if (data.event == AuthChangeEvent.signedOut || session == null) {
        if (state.status == AuthStatus.authenticated) {
          emit(const AuthState(status: AuthStatus.unauthenticated));
        }
        return;
      }
      // Events are delivered asynchronously: only act on a session that is
      // still current (e.g. not one already signed out after recovery).
      if (client.auth.currentSession == null) return;
      if (supaUser != null &&
          (state.status != AuthStatus.authenticated || state.user?.id != supaUser.id)) {
        _handleSupabaseUser(supaUser);
      }
    }, onError: (_) {});
  }

  Future<void> _checkSession() async {
    final client = _client;
    final session = client?.auth.currentSession;
    final supaUser = client?.auth.currentUser;
    if (session != null && supaUser != null) {
      await _handleSupabaseUser(supaUser);
      return;
    }
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  /// Build the in-app user from a live Supabase user plus the server's verdict
  /// on admin rights. Profile fields from metadata are display-only.
  @visibleForTesting
  Future<UserEntity> buildUser(User supaUser) async {
    final who = await _whoAmI();
    final isAdmin = who.isAdmin && (who.userId == null || who.userId == supaUser.id);
    final meta = supaUser.userMetadata ?? const {};
    final email = supaUser.email ?? '';
    final name = (meta['full_name'] as String?)?.trim();
    final phone = (meta['phone'] as String?)?.trim() ?? '';

    return UserEntity(
      id: supaUser.id,
      email: email,
      fullName: (name == null || name.isEmpty)
          ? (email.contains('@') ? email.split('@').first.toUpperCase() : 'Trader')
          : name,
      phone: phone.isNotEmpty ? phone : null,
      country: 'Pakistan',
      nationality: 'Pakistani',
      preferredCurrency: 'USD',
      preferredLanguage: 'en',
      // The authoritative KYC verdict lives in kyc_profiles (KycCubit).
      kycStatus: KycStatus.notSubmitted,
      status: AccountStatus.active,
      role: isAdmin ? UserRole.admin : UserRole.client,
      isTwoFactorEnabled: false,
      isEmailVerified: supaUser.emailConfirmedAt != null,
      isPhoneVerified: false,
      kycTier: 0,
      createdAt: DateTime.tryParse(supaUser.createdAt) ?? DateTime.now(),
    );
  }

  Future<void> _handleSupabaseUser(User supaUser) async {
    final user = await buildUser(supaUser);
    if (isClosed) return;

    emit(AuthState(status: AuthStatus.authenticated, user: user));
    _tradingEngineCubit?.switchUser(supaUser.id);

    if (user.role != UserRole.admin) {
      _adminCubit?.addTraderUser(
        AdminTraderUser(
          id: user.id,
          name: user.fullName,
          email: user.email,
          phone: user.phone ?? '',
          balance: 0.00,
          equity: 0.00,
          isKycVerified: false,
          status: AdminUserStatus.active,
          joinedAt: user.createdAt,
        ),
      );
    }
  }

  static String _messageFor(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials') || msg.contains('invalid_grant')) {
      return 'Incorrect email or password. Please check your credentials.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Please confirm your email address first — check your inbox.';
    }
    if (msg.contains('already registered') || msg.contains('user already exists')) {
      return 'An account with this email already exists. Please log in.';
    }
    if (msg.contains('rate limit') || msg.contains('too many')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (msg.contains('error sending') || msg.contains('smtp')) {
      // The project's e-mail service (custom SMTP) rejected the message.
      return 'We could not send the email right now. Please try again in a few minutes or contact support.';
    }
    if (msg.contains('signups not allowed') || msg.contains('signup is disabled')) {
      // "Allow new users to sign up" is off in Supabase Auth settings.
      return 'New registrations are currently closed. Please try again later or contact support.';
    }
    if (msg.contains('for security purposes')) {
      return 'Please wait a minute before requesting another email.';
    }
    return e.message;
  }

  /// Sign-up and password reset wait for Supabase to send an e-mail; never
  /// leave the user on a spinner if the mail server hangs.
  static const _emailRequestTimeout = Duration(seconds: 30);
  static const _emailTimeoutError =
      'The server took too long to send the email. Please check your inbox, then try again.';

  static const _networkError =
      'Could not reach the server. Please check your internet connection and try again.';

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

    final client = _client;
    if (client == null) {
      emit(const AuthState(status: AuthStatus.unauthenticated, error: _networkError));
      return false;
    }

    try {
      final res = await client.auth.signInWithPassword(
        email: normalizedEmail,
        password: password,
      );
      final supaUser = res.user;
      if (res.session == null || supaUser == null) {
        emit(const AuthState(
          status: AuthStatus.unauthenticated,
          error: 'Sign-in did not complete. Please try again.',
        ));
        return false;
      }
      await _handleSupabaseUser(supaUser);
      return state.status == AuthStatus.authenticated;
    } on AuthException catch (e) {
      emit(AuthState(status: AuthStatus.unauthenticated, error: _messageFor(e)));
      return false;
    } catch (_) {
      emit(const AuthState(status: AuthStatus.unauthenticated, error: _networkError));
      return false;
    }
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

    final client = _client;
    if (client == null) {
      emit(const AuthState(status: AuthStatus.unauthenticated, error: _networkError));
      return false;
    }

    try {
      final res = await client.auth.signUp(
        email: normalizedEmail,
        password: password,
        // Display-only profile fields. Never role / KYC / tier: user_metadata
        // is user-editable and must not carry anything that grants access.
        data: signUpMetadata(fullName: fullName, phone: phone),
      ).timeout(_emailRequestTimeout);

      final supaUser = res.user;
      if (supaUser == null) {
        emit(const AuthState(
          status: AuthStatus.unauthenticated,
          error: 'Registration failed. Please try again.',
        ));
        return false;
      }
      if (res.session == null) {
        // Email confirmation is enabled on the project: no session yet.
        emit(const AuthState(
          status: AuthStatus.unauthenticated,
          error: 'Account created. Please confirm your email address, then log in.',
        ));
        return false;
      }

      await _handleSupabaseUser(supaUser);
      return state.status == AuthStatus.authenticated;
    } on AuthException catch (e) {
      emit(AuthState(status: AuthStatus.unauthenticated, error: _messageFor(e)));
      return false;
    } on TimeoutException {
      emit(const AuthState(status: AuthStatus.unauthenticated, error: _emailTimeoutError));
      return false;
    } catch (_) {
      emit(const AuthState(status: AuthStatus.unauthenticated, error: _networkError));
      return false;
    }
  }

  /// The only keys a client may put in auth `user_metadata` at sign-up.
  @visibleForTesting
  static Map<String, dynamic> signUpMetadata({required String fullName, String? phone}) => {
        'full_name': fullName.trim(),
        'phone': (phone ?? '').trim(),
      };

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
    _adminCubit?.setTraderKycVerified(updated.id, kycStatus == KycStatus.approved);
  }

  void updateUserAccountStatus(AccountStatus status) {
    if (state.user == null) return;
    emit(state.copyWith(user: state.user!.copyWith(status: status)));
  }

  void resetKycForTesting() {
    if (state.user == null) return;
    emit(state.copyWith(user: state.user!.resetKyc()));
  }

  Future<void> logout() async {
    try {
      await _client?.auth.signOut();
    } catch (_) {}
    try {
      await SecureStorageService.instance.clearCurrentSessionUser();
    } catch (_) {}
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  /// Step 1 of password recovery: Supabase e-mails a one-time code.
  Future<bool> requestPasswordReset(String email) async {
    emit(state.copyWith(error: null));
    final client = _client;
    if (client == null) {
      emit(state.copyWith(error: _networkError));
      return false;
    }
    try {
      await client.auth.resetPasswordForEmail(email.trim().toLowerCase()).timeout(_emailRequestTimeout);
      return true;
    } on AuthException catch (e) {
      emit(state.copyWith(error: _messageFor(e)));
      return false;
    } on TimeoutException {
      emit(state.copyWith(error: _emailTimeoutError));
      return false;
    } catch (_) {
      emit(state.copyWith(error: _networkError));
      return false;
    }
  }

  /// Step 2: the e-mailed code must be verified BY SUPABASE before the password
  /// changes. The temporary recovery session is signed out afterwards so the
  /// user logs in normally with the new password.
  Future<bool> completePasswordRecovery({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    emit(state.copyWith(error: null));
    final client = _client;
    if (client == null) {
      emit(state.copyWith(error: _networkError));
      return false;
    }

    _recoveryInProgress = true;
    String? error;
    var ok = false;
    try {
      final res = await client.auth.verifyOTP(
        email: email.trim().toLowerCase(),
        token: code.trim(),
        type: OtpType.recovery,
      );
      if (res.session == null) {
        error = 'Invalid or expired verification code.';
      } else {
        await client.auth.updateUser(UserAttributes(password: newPassword));
        ok = true;
      }
    } on AuthException catch (e) {
      error = e.message.toLowerCase().contains('expired') || e.message.toLowerCase().contains('invalid')
          ? 'Invalid or expired verification code.'
          : _messageFor(e);
    } catch (_) {
      error = _networkError;
    } finally {
      try {
        await client.auth.signOut();
      } catch (_) {}
      _recoveryInProgress = false;
    }

    emit(AuthState(status: AuthStatus.unauthenticated, error: error));
    return ok;
  }

  void clearError() => emit(state.copyWith(error: null));

  @override
  Future<void> close() {
    _authSub?.cancel();
    return super.close();
  }
}

typedef AuthBloc = AuthCubit;
