import 'dart:typed_data';

import 'package:asianfxapp/data/datasources/supabase_deposit_service.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// In-memory stand-in for Supabase: records every call and replays canned
/// responses, so the service layer can be tested without a project.
class FakeDepositBackend implements DepositBackend {
  FakeDepositBackend({this.userId = 'user-1'});

  String? userId;
  final List<(String, Map<String, dynamic>)> rpcCalls = [];
  final List<(String, int, String)> uploads = [];
  Object? Function(String fn, Map<String, dynamic> params)? onRpc;
  Map<String, dynamic>? config = {'deposit_address_trc20': 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV', 'min_deposit_usd': 10};
  List<Map<String, dynamic>> ownRows = [];

  @override
  String? get currentUserId => userId;

  @override
  Future<dynamic> rpc(String function, Map<String, dynamic> params) async {
    rpcCalls.add((function, params));
    final res = onRpc?.call(function, params);
    if (res is Exception) throw res;
    return res;
  }

  Object? configError;

  @override
  Future<Map<String, dynamic>?> fetchBrokerConfig() async {
    if (configError != null) throw configError!;
    return config;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchOwnRequests(String userId) async => ownRows;

  @override
  Future<void> uploadProof(String path, Uint8List bytes, String contentType) async {
    uploads.add((path, bytes.length, contentType));
  }

  @override
  Future<String> signedProofUrl(String path, {int expiresInSeconds = 600}) async =>
      'https://signed.example/$path?ttl=$expiresInSeconds';
}

final _proof = Uint8List.fromList(List.filled(16, 1));
const _txid = 'ABCDEF0123456789abcdef0123456789ABCDEF0123456789abcdef0123456789';

Map<String, dynamic> _row({
  String id = 'dep-1',
  String status = 'PENDING',
  Object? credited,
  String? reason,
}) =>
    {
      'id': id,
      'user_id': 'user-1',
      'amount_claimed': 150.5,
      'network': 'TRC20',
      'token': 'USDT',
      'txid': _txid.toLowerCase(),
      'status': status,
      'amount_credited': credited,
      'reject_reason': reason,
      'created_at': '2026-10-02T10:00:00Z',
    };

void main() {
  late FakeDepositBackend backend;
  late DepositService service;

  setUp(() {
    backend = FakeDepositBackend();
    service = DepositService(backend: backend);
  });

  group('validation helpers', () {
    test('TXID must be exactly 64 hex chars', () {
      expect(DepositService.isValidTxid(_txid), isTrue);
      expect(DepositService.isValidTxid('  $_txid  '), isTrue);
      expect(DepositService.isValidTxid(_txid.substring(1)), isFalse);
      expect(DepositService.isValidTxid('${_txid.substring(1)}g'), isFalse);
      expect(DepositService.isValidTxid(''), isFalse);
    });

    test('TRON address format', () {
      expect(DepositService.isValidTronAddress('TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV'), isTrue);
      expect(DepositService.isValidTronAddress('0x1234'), isFalse);
      // base58 excludes 0, O, I, l
      expect(DepositService.isValidTronAddress('TA199GDmT2ybpMKdHwZkjMgo2awuk1N1f0'), isFalse);
    });

    test('Tronscan link uses the lower-cased TXID', () {
      expect(DepositService.tronscanUrl(_txid).toString(),
          'https://tronscan.org/#/transaction/${_txid.toLowerCase()}');
    });
  });

  group('deposit address comes from broker_config (admin-managed)', () {
    const adminSet = 'TQn9Y2khEsLJW1ChVWFMSMeRDow5KcbLSE';

    test('the address the admin saved is what users see', () async {
      backend.config = {'deposit_address_trc20': ' $adminSet ', 'min_deposit_usd': '25.5'};
      final cfg = await service.loadConfig();
      expect(cfg.depositAddress, adminSet);
      expect(cfg.minDeposit, Decimal.parse('25.5'));
    });

    test('no row / no address / unreachable DB falls back to the built-in address', () async {
      backend.config = null;
      expect((await service.loadConfig()).depositAddress, 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV');
      backend.config = {'deposit_address_trc20': null};
      expect((await service.loadConfig()).depositAddress, 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV');
      backend.configError = Exception('column broker_config.deposit_address_trc20 does not exist');
      final cfg = await service.loadConfig();
      expect(cfg.depositAddress, 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV');
      expect(cfg.minDeposit, Decimal.fromInt(10));
    });

    test('a malformed stored address is never shown to users', () async {
      backend.config = {'deposit_address_trc20': 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1ff0'};
      expect((await service.loadConfig()).depositAddress, 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV');
    });

    test('admin update calls the RPC with the trimmed address', () async {
      backend.onRpc = (fn, p) => {'status': 'success', 'deposit_address': p['p_address']};
      final stored = await service.adminSetDepositAddress('  $adminSet ');
      expect(stored, adminSet);
      expect(backend.rpcCalls.single.$1, 'rpc_admin_set_deposit_address');
      expect(backend.rpcCalls.single.$2, {'p_address': adminSet});
    });

    test('admin update rejects malformed addresses before calling the server', () async {
      for (final bad in ['', 'XA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV', 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1f', 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N10']) {
        await expectLater(
          service.adminSetDepositAddress(bad),
          throwsA(isA<DepositServiceException>().having((e) => e.code, 'code', 'BAD_ADDRESS')),
        );
      }
      expect(backend.rpcCalls, isEmpty);
    });

    test('a non-admin gets FORBIDDEN from the server', () async {
      backend.onRpc = (fn, p) => Exception('FORBIDDEN: administrator privileges required');
      await expectLater(
        service.adminSetDepositAddress(adminSet),
        throwsA(isA<DepositServiceException>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });
  });

  group('submit', () {
    test('uploads the proof into the caller\'s folder and calls the RPC', () async {
      backend.onRpc = (fn, p) => {'status': 'success', 'deposit': _row()};

      final dep = await service.submit(
        amount: Decimal.parse('150.5'),
        txid: _txid,
        fromAddress: 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV',
        proofBytes: Uint8List.fromList(List.filled(100, 1)),
        proofFileName: 'receipt.PNG',
        requestId: 'req-42',
      );

      expect(backend.uploads, hasLength(1));
      final (path, size, type) = backend.uploads.single;
      expect(path, startsWith('user-1/'));
      expect(path, endsWith('.png'));
      expect(size, 100);
      expect(type, 'image/png');

      final (fn, params) = backend.rpcCalls.single;
      expect(fn, 'rpc_submit_deposit_request');
      expect(params['p_txid'], _txid.toLowerCase());
      expect(params['p_amount'], '150.5');
      expect(params['p_proof_path'], path);
      expect(params['p_request_id'], 'req-42');

      expect(dep.status, DepositStatus.pending);
      expect(dep.amountClaimed, Decimal.parse('150.5'));
    });

    test('generates an idempotency key and sends no TXID when none is given', () async {
      backend.onRpc = (fn, p) => {'status': 'success', 'deposit': _row()};
      await service.submit(amount: Decimal.fromInt(20), proofBytes: _proof);
      final params = backend.rpcCalls.single.$2;
      expect(params['p_request_id'], startsWith('dep-'));
      expect(params['p_txid'], isNull);
      expect(params['p_proof_path'], startsWith('user-1/'));
      expect(backend.uploads, hasLength(1));
    });

    test('requires a payment screenshot', () async {
      await expectLater(
        service.submit(amount: Decimal.fromInt(20), proofBytes: null),
        throwsA(isA<DepositServiceException>().having((e) => e.code, 'code', 'PROOF_REQUIRED')),
      );
      expect(backend.rpcCalls, isEmpty);
      expect(backend.uploads, isEmpty);
    });

    test('rejects a malformed TXID before any network call', () async {
      await expectLater(
        service.submit(amount: Decimal.fromInt(20), txid: 'not-a-hash', proofBytes: _proof),
        throwsA(isA<DepositServiceException>().having((e) => e.code, 'code', 'BAD_TXID')),
      );
      expect(backend.rpcCalls, isEmpty);
    });

    test('rejects amounts below the configured minimum', () async {
      await expectLater(
        service.submit(amount: Decimal.fromInt(5), proofBytes: _proof, minDeposit: Decimal.fromInt(10)),
        throwsA(isA<DepositServiceException>().having((e) => e.code, 'code', 'AMOUNT_TOO_SMALL')),
      );
      expect(backend.rpcCalls, isEmpty);
    });

    test('rejects an invalid sender address', () async {
      await expectLater(
        service.submit(amount: Decimal.fromInt(20), proofBytes: _proof, fromAddress: '0xdeadbeef'),
        throwsA(isA<DepositServiceException>().having((e) => e.code, 'code', 'BAD_ADDRESS')),
      );
    });

    test('requires a signed-in user', () async {
      backend.userId = null;
      await expectLater(
        service.submit(amount: Decimal.fromInt(20), proofBytes: _proof),
        throwsA(isA<DepositServiceException>().having((e) => e.code, 'code', 'AUTH_REQUIRED')),
      );
    });

    test('maps server errors (duplicate TXID) to a typed exception', () async {
      backend.onRpc = (fn, p) => const PostgrestException(
          message: 'TXID_ALREADY_USED: this transaction ID has already been submitted');
      await expectLater(
        service.submit(amount: Decimal.fromInt(20), txid: _txid, proofBytes: _proof),
        throwsA(isA<DepositServiceException>()
            .having((e) => e.code, 'code', 'TXID_ALREADY_USED')
            .having((e) => e.message, 'message', contains('already been submitted'))),
      );
    });
  });

  group('my requests', () {
    test('maps rows including review outcome', () async {
      backend.ownRows = [
        _row(id: 'a', status: 'APPROVED', credited: '149.0000'),
        _row(id: 'b', status: 'REJECTED', reason: 'Not found on chain'),
      ];
      final list = await service.myRequests();
      expect(list.map((d) => d.status), [DepositStatus.approved, DepositStatus.rejected]);
      expect(list.first.amountCredited, Decimal.parse('149'));
      expect(list.last.rejectReason, 'Not found on chain');
    });
  });

  group('admin review', () {
    test('approve sends the on-chain amount and parses the new balance', () async {
      backend.onRpc = (fn, p) => {
            'status': 'success',
            'deposit': _row(status: 'APPROVED', credited: 149) ..['reviewed_by'] = 'admin-9',
            'new_balance': '1149.0000',
          };
      final res = await service.review(
        depositId: 'dep-1',
        approve: true,
        amountCredited: Decimal.fromInt(149),
        adminNote: '  fee deducted ',
      );
      final (fn, params) = backend.rpcCalls.single;
      expect(fn, 'rpc_review_deposit');
      expect(params['p_approve'], isTrue);
      expect(params['p_amount_credited'], '149');
      expect(params['p_reason'], isNull);
      expect(params['p_admin_note'], 'fee deducted');
      expect(res.deposit.status, DepositStatus.approved);
      expect(res.deposit.reviewedBy, 'admin-9');
      expect(res.newBalance, Decimal.parse('1149'));
      expect(res.alreadyReviewed, isFalse);
    });

    test('approve without an amount is refused locally', () async {
      await expectLater(
        service.review(depositId: 'dep-1', approve: true),
        throwsA(isA<DepositServiceException>().having((e) => e.code, 'code', 'BAD_AMOUNT')),
      );
      expect(backend.rpcCalls, isEmpty);
    });

    test('reject requires a reason', () async {
      await expectLater(
        service.review(depositId: 'dep-1', approve: false, reason: '   '),
        throwsA(isA<DepositServiceException>().having((e) => e.code, 'code', 'REASON_REQUIRED')),
      );
      expect(backend.rpcCalls, isEmpty);
    });

    test('reject sends no amount', () async {
      backend.onRpc = (fn, p) => {
            'status': 'success',
            'deposit': _row(status: 'REJECTED', reason: 'wrong network'),
          };
      final res = await service.review(depositId: 'dep-1', approve: false, reason: ' wrong network ');
      expect(backend.rpcCalls.single.$2['p_amount_credited'], isNull);
      expect(backend.rpcCalls.single.$2['p_reason'], 'wrong network');
      expect(res.deposit.status, DepositStatus.rejected);
    });

    test('a double review is reported, not treated as a fresh approval', () async {
      backend.onRpc = (fn, p) => {
            'status': 'already_reviewed',
            'deposit': _row(status: 'APPROVED', credited: 150),
            'message': 'This deposit was already approved.',
          };
      final res = await service.review(depositId: 'dep-1', approve: true, amountCredited: Decimal.fromInt(150));
      expect(res.alreadyReviewed, isTrue);
      expect(res.message, contains('already approved'));
    });

    test('self-approval and non-admin errors surface their codes', () async {
      backend.onRpc = (fn, p) => const PostgrestException(
          message: 'SELF_REVIEW_FORBIDDEN: an administrator cannot review their own deposit');
      await expectLater(
        service.review(depositId: 'dep-1', approve: true, amountCredited: Decimal.one),
        throwsA(isA<DepositServiceException>().having((e) => e.code, 'code', 'SELF_REVIEW_FORBIDDEN')),
      );

      backend.onRpc = (fn, p) =>
          const PostgrestException(message: 'FORBIDDEN: administrator privileges are required');
      await expectLater(
        service.adminList(),
        throwsA(isA<DepositServiceException>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });

    test('admin list maps e-mails and passes the status filter', () async {
      backend.onRpc = (fn, p) => [
            _row(id: 'x')..['user_email'] = 'trader@example.com',
          ];
      final list = await service.adminList(status: 'PENDING');
      expect(backend.rpcCalls.single.$1, 'rpc_admin_list_deposit_requests');
      expect(backend.rpcCalls.single.$2['p_status'], 'PENDING');
      expect(list.single.userEmail, 'trader@example.com');
    });

    test('proof URLs are short-lived signed URLs', () async {
      expect(await service.proofUrl('user-1/a.png'), 'https://signed.example/user-1/a.png?ttl=600');
      expect(await service.proofUrl(null), isNull);
    });
  });
}
