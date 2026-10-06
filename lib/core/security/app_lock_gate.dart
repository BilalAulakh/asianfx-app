import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import 'biometric_auth_service.dart';

/// Device lock (fingerprint / face / phone PIN) for a signed-in account.
///
/// The lock screen is drawn OVER the app instead of replacing it, so the
/// screen underneath keeps its state (e.g. a half-finished form) across a
/// lock / unlock. Nothing is locked while signed out (login, sign-up, forgot
/// password): there is no account to protect yet, and those flows send the
/// user to their e-mail app and back.
class AppLockGate extends StatefulWidget {
  final Widget child;
  final BiometricAuthService? service;

  /// Whether an account is signed in. Defaults to the Supabase session.
  final bool Function()? isSignedIn;

  const AppLockGate({
    super.key,
    required this.child,
    this.service,
    this.isSignedIn,
  });

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final BiometricAuthService _service = widget.service ?? BiometricAuthService.instance;

  bool get _signedIn {
    if (widget.isSignedIn != null) return widget.isSignedIn!();
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  bool _isChecking = true;
  bool _isSupported = false;
  bool _isLocked = false;
  bool _isAuthenticating = false;
  bool _wasBackgrounded = false;
  String? _errorMessage;

  List<BiometricType> _availableBiometrics = [];

  late AnimationController _pulseController;
  late Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initSecurity();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isSupported) return;

    if (state == AppLifecycleState.paused) {
      // User minimized the app or locked phone
      _wasBackgrounded = true;
    } else if (state == AppLifecycleState.resumed) {
      // User reopened the app
      if (_wasBackgrounded && !_isAuthenticating) {
        _wasBackgrounded = false;
        if (!_signedIn) return;
        setState(() {
          _isLocked = true;
          _errorMessage = null;
        });
        _requestAuth();
      }
    }
  }

  Future<void> _initSecurity() async {
    if (!_service.isMobile) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _isSupported = false;
          _isLocked = false;
        });
      }
      return;
    }

    final supported = await _service.isDeviceSecuritySupported();
    if (!mounted) return;

    if (!supported) {
      setState(() {
        _isChecking = false;
        _isSupported = false;
        _isLocked = false;
      });
      return;
    }

    final biometrics = await _service.getAvailableBiometrics();
    if (!mounted) return;

    final lockNow = _signedIn;
    setState(() {
      _isChecking = false;
      _isSupported = true;
      _isLocked = lockNow;
      _availableBiometrics = biometrics;
    });

    // Auto prompt on launch when a saved session would open the account.
    if (lockNow) _requestAuth();
  }

  Future<void> _requestAuth() async {
    if (_isAuthenticating) return;
    _isAuthenticating = true;

    if (mounted) {
      setState(() {
        _errorMessage = null;
      });
    }

    try {
      final success = await _service.authenticate(
        localizedReason: 'Verify your Fingerprint, Face ID, or PIN to access FXAsian',
      );

      if (!mounted) return;

      if (success) {
        setState(() {
          _isLocked = false;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _isLocked = true;
          _errorMessage = 'Authentication canceled or failed. Tap below to retry.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLocked = true;
          _errorMessage = 'Security verification failed. Please try again.';
        });
      }
    } finally {
      _isAuthenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final covered = _isChecking || _isLocked;
    // The app stays mounted underneath (keeps its state); while covered it is
    // hidden from touch and accessibility.
    return Stack(
      children: [
        IgnorePointer(
          ignoring: covered,
          child: ExcludeSemantics(excluding: covered, child: widget.child),
        ),
        if (_isChecking)
          // Brief loading indicator while checking device security capabilities
          const Positioned.fill(
            child: ColoredBox(
              color: AppColors.darkBackground,
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.brandPrimary,
                  strokeWidth: 2.5,
                ),
              ),
            ),
          )
        else if (_isLocked)
          Positioned.fill(child: _lockScreen()),
      ],
    );
  }

  Widget _lockScreen() {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF070B12),
                Color(0xFF0D1728),
                Color(0xFF070B12),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // Brand Badge
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: AppColors.primaryGradient,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brandPrimary.withAlpha(80),
                          blurRadius: 30,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'FX',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                          letterSpacing: -1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // App Title
                  RichText(
                    text: const TextSpan(
                      children: [
                        TextSpan(
                          text: 'FX',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brandPrimary,
                          ),
                        ),
                        TextSpan(
                          text: 'Asian',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 1),

                  // Animated Security Icon
                  ScaleTransition(
                    scale: _pulseScale,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.brandPrimary.withAlpha(20),
                        border: Border.all(
                          color: AppColors.brandPrimary.withAlpha(100),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brandPrimary.withAlpha(50),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          _getBiometricIcon(),
                          size: 48,
                          color: AppColors.brandPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Header Text
                  const Text(
                    'App Security Locked',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Text(
                    _getSecuritySubtitle(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.redAccent.withAlpha(70),
                        ),
                      ),
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ],

                  const Spacer(flex: 2),

                  // Unlock Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _requestAuth,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandPrimary,
                        foregroundColor: Colors.black,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _getBiometricIcon(),
                            size: 20,
                            color: Colors.black,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _getButtonLabel(),
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _hasFingerprint =>
      _availableBiometrics.contains(BiometricType.fingerprint) ||
      _availableBiometrics.contains(BiometricType.strong) ||
      _availableBiometrics.contains(BiometricType.weak);

  bool get _hasFace => _availableBiometrics.contains(BiometricType.face);

  IconData _getBiometricIcon() {
    if (_hasFingerprint) return Icons.fingerprint_rounded;
    if (_hasFace) return Icons.face_rounded;
    return Icons.lock_outline_rounded;
  }

  String _getSecuritySubtitle() {
    if (_hasFingerprint && _hasFace) {
      return 'Authenticate using Fingerprint, Face ID, or your phone lock PIN/Code.';
    } else if (_hasFingerprint) {
      return 'Authenticate using Fingerprint or your phone lock PIN/Code.';
    } else if (_hasFace) {
      return 'Authenticate using Face ID or your phone lock PIN/Code.';
    }
    return 'Enter your phone lock PIN, pattern, or code to access your trading app.';
  }

  String _getButtonLabel() {
    if (_hasFingerprint) return 'Unlock with Fingerprint / PIN';
    if (_hasFace) return 'Unlock with Face / PIN';
    return 'Unlock with Phone PIN / Code';
  }
}
