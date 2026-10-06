import 'dart:io';

import 'package:asianfxapp/blocs/auth_bloc.dart';
import 'package:asianfxapp/core/security/secure_storage_service.dart';
import 'package:asianfxapp/domain/entities/user_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

User _supaUser({
  String id = 'uid-1',
  String email = 'someone@example.com',
  Map<String, dynamic> userMetadata = const {},
}) =>
    User(
      id: id,
      email: email,
      appMetadata: const {},
      userMetadata: userMetadata,
      aud: 'authenticated',
      createdAt: '2026-10-01T00:00:00Z',
    );

void main() {
  group('admin is decided by the server (rpc_whoami), not by the client', () {
    test('the old built-in admin e-mail gets NO admin role on its own', () async {
      final cubit = AuthCubit(
        autoInit: false,
        whoAmI: () async => (userId: 'uid-1', isAdmin: false),
      );
      final user = await cubit.buildUser(_supaUser(email: 'admin@asianfx.com'));
      expect(user.role, UserRole.client);
      await cubit.close();
    });

    test('user_metadata.role = admin is ignored', () async {
      final cubit = AuthCubit(
        autoInit: false,
        whoAmI: () async => (userId: 'uid-1', isAdmin: false),
      );
      final user = await cubit.buildUser(_supaUser(userMetadata: {'role': 'admin', 'full_name': 'Eve'}));
      expect(user.role, UserRole.client);
      expect(user.fullName, 'Eve');
      await cubit.close();
    });

    test('a server-confirmed admin gets the admin UI', () async {
      final cubit = AuthCubit(
        autoInit: false,
        whoAmI: () async => (userId: 'uid-1', isAdmin: true),
      );
      final user = await cubit.buildUser(_supaUser());
      expect(user.role, UserRole.admin);
      await cubit.close();
    });

    test('a whoami answer for a different user is not trusted', () async {
      final cubit = AuthCubit(
        autoInit: false,
        whoAmI: () async => (userId: 'someone-else', isAdmin: true),
      );
      final user = await cubit.buildUser(_supaUser());
      expect(user.role, UserRole.client);
      await cubit.close();
    });
  });

  test('sign-up metadata never carries role / KYC fields', () {
    final meta = AuthCubit.signUpMetadata(fullName: '  Ali Khan ', phone: ' +92 300 ');
    expect(meta.keys.toSet(), {'full_name', 'phone'});
    expect(meta['full_name'], 'Ali Khan');
    expect(meta['phone'], '+92 300');
  });

  group('legacy credential purge', () {
    test('recognises every key older builds wrote', () {
      for (final key in [
        'user_pwd_bob@example.com',
        '2fa_secret_bob@example.com',
        '2fa_enabled_bob@example.com',
        'user_role_bob@example.com',
        'active_session_user_json',
        'access_token',
        'refresh_token',
        'trades_uid-1',
        'balance_uid-1',
      ]) {
        expect(SecureStorageService.isLegacyKey(key), isTrue, reason: key);
      }
    });

    test('keeps the things that are allowed to stay in secure storage', () {
      expect(SecureStorageService.isLegacyKey('sec_pin_bob@example.com'), isFalse);
      expect(SecureStorageService.isLegacyKey('registered_traders_list_json'), isFalse);
      expect(SecureStorageService.isLegacyKey('isDarkMode'), isFalse);
    });
  });

  test('no hard-coded admin credentials or offline login remain in lib/', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (src.contains('Admin@123') ||
          src.contains("'admin@asianfx.com'") ||
          src.contains('_loginFallback') ||
          src.contains('saveUserCredentials') ||
          src.contains('getUserPassword')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty);
  });
}
