import 'package:asianfxapp/domain/entities/admin_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rpc_admin_list_users row -> AdminTraderUser', () {
    final u = AdminTraderUser.fromServerRow({
      'id': 'a1b2',
      'email': 'ali@example.com',
      'full_name': 'Ali Khan',
      'phone': '+92 300 1234567',
      'created_at': '2026-10-05T10:00:00Z',
      'balance': '125.5000',
      'is_frozen': false,
      'kyc_status': 'APPROVED',
    });
    expect(u.id, 'a1b2');
    expect(u.name, 'Ali Khan');
    expect(u.phone, '+92 300 1234567');
    expect(u.balance, 125.5);
    expect(u.isKycVerified, isTrue);
    expect(u.status, AdminUserStatus.active);
    expect(u.joinedAt.toUtc(), DateTime.utc(2026, 10, 5, 10));
  });

  test('missing name falls back to the e-mail; frozen wallet and pending KYC map through', () {
    final u = AdminTraderUser.fromServerRow({
      'id': 'x',
      'email': 'sara@example.com',
      'full_name': null,
      'balance': 0,
      'is_frozen': true,
      'kyc_status': 'PENDING_REVIEW',
    });
    expect(u.name, 'sara');
    expect(u.phone, '');
    expect(u.status, AdminUserStatus.frozen);
    expect(u.isKycVerified, isFalse);
  });

  test('counts come from the server list', () {
    final users = [
      for (var i = 0; i < 5; i++)
        AdminTraderUser.fromServerRow({
          'id': '$i',
          'email': 'u$i@x.com',
          'is_frozen': i == 4,
          'kyc_status': i < 2 ? 'APPROVED' : 'NOT_STARTED',
        }),
    ];
    final state = AdminState(users: users);
    expect(state.totalUsersCount, 5);
    expect(state.activeUsersCount, 4);
    expect(state.verifiedUsersCount, 2);
  });
}
