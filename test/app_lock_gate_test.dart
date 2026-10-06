import 'package:asianfxapp/core/security/app_lock_gate.dart';
import 'package:asianfxapp/core/security/biometric_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

class _FakeBiometrics implements BiometricAuthService {
  bool approve = true;
  int prompts = 0;

  @override
  bool get isMobile => true;
  @override
  Future<bool> isDeviceSecuritySupported() async => true;
  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => const [BiometricType.fingerprint];
  @override
  Future<bool> authenticate({String? localizedReason}) async {
    prompts++;
    return approve;
  }

  @override
  Future<void> cancelAuthentication() async {}
}

/// A form whose typed text is lost if the widget is ever rebuilt from scratch.
class _Form extends StatefulWidget {
  const _Form();
  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final controller = TextEditingController();
  @override
  Widget build(BuildContext context) => Scaffold(body: TextField(key: const Key('code'), controller: controller));
}

Future<void> _background(WidgetTester tester) async {
  final binding = tester.binding;
  binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  // The lock icon pulses forever, so pump fixed frames instead of settling.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pump(WidgetTester tester, _FakeBiometrics service, {required bool signedIn}) async {
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => AppLockGate(service: service, isSignedIn: () => signedIn, child: child!),
    home: const _Form(),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('signed out (forgot password): leaving for the e-mail app never locks', (tester) async {
    final service = _FakeBiometrics();
    await _pump(tester, service, signedIn: false);
    await tester.enterText(find.byKey(const Key('code')), 'user@mail.com');

    await _background(tester);

    expect(service.prompts, 0, reason: 'no account is open, so no biometric prompt');
    expect(find.text('App Security Locked'), findsNothing);
    expect(find.text('user@mail.com'), findsOneWidget);
  });

  testWidgets('signed in: locks on return, and unlocking keeps the screen as it was', (tester) async {
    final service = _FakeBiometrics()..approve = false;
    await _pump(tester, service, signedIn: true);
    expect(find.text('App Security Locked'), findsOneWidget, reason: 'locked on launch');

    service.approve = true;
    await tester.tap(find.text('Unlock with Fingerprint / PIN'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('code')), '48392017');

    service.approve = false;
    await _background(tester);
    expect(find.text('App Security Locked'), findsOneWidget);

    service.approve = true;
    await tester.tap(find.text('Unlock with Fingerprint / PIN'));
    await tester.pump();
    expect(find.text('App Security Locked'), findsNothing);
    expect(find.text('48392017'), findsOneWidget, reason: 'the half-filled form survived the lock');
  });
}
