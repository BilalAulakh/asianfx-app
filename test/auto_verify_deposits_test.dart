import 'dart:typed_data';

import 'package:asianfxapp/blocs/theme_cubit.dart';
import 'package:asianfxapp/core/theme/app_theme.dart';
import 'package:asianfxapp/core/utils/tron_address.dart';
import 'package:asianfxapp/data/datasources/supabase_deposit_service.dart';
import 'package:asianfxapp/presentation/admin/widgets/address_a_card.dart';
import 'package:asianfxapp/presentation/admin/widgets/deposit_requests_tab.dart';
import 'package:asianfxapp/presentation/wallet/widgets/deposit_panel.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deposit_service_test.dart' show FakeDepositBackend;

const _a = 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV'; // configured Address A (checksum invalid)
const _b = 'TNK1ngQW59zsu5iHntaGKiuUJ9PmSYJYtS'; // Address B (valid)
const _usdt = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
const _txid = 'ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12';

Map<String, dynamic> _deposit({
  String id = 'dep-1',
  String status = 'PENDING',
  String address = _b,
  String verification = 'WAITING',
  String? error,
  String? proof,
  Object? credited,
  Object? onchain,
  bool system = false,
  String? txid,
}) =>
    {
      'id': id,
      'user_id': 'user-1',
      'amount_claimed': 100,
      'network': 'TRC20',
      'token': 'USDT',
      'txid': txid,
      'status': status,
      'address_used': address,
      'deposit_address': address,
      'verification_status': verification,
      'verification_error': error,
      'proof_path': proof,
      'amount_credited': credited,
      'onchain_amount': onchain,
      'approved_by_system': system,
      'created_at': '2026-10-06T10:00:00Z',
      'reviewed_at': system ? '2026-10-06T10:03:00Z' : null,
      'reviewed_by': system ? 'system:auto-verify' : null,
      'user_email': 'sem123@gmail.com',
    };

Map<String, dynamic> _addr(String address, {int weight = 1, int order = 1, bool auto = false}) => {
      'id': 'id-$address',
      'address': address,
      'label': auto ? 'Address B (automatic)' : 'Address A (manual)',
      'weight': weight,
      'sort_order': order,
      'is_active': true,
      'auto_verify': auto,
      'max_auto_approve_usd': 1000,
    };

Future<void> _pumpThemed(WidgetTester tester, Widget child, {Size size = const Size(1200, 2400)}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(BlocProvider(
    create: (_) => ThemeCubit(),
    child: MaterialApp(theme: AppTheme.dark, home: Scaffold(body: SingleChildScrollView(child: child))),
  ));
}

void main() {
  group('TRON address checksum', () {
    test('real addresses pass, the configured Address A fails', () {
      expect(TronAddress.isValid(_b), isTrue);
      expect(TronAddress.isValid(_usdt), isTrue);
      expect(TronAddress.hasValidFormat(_a), isTrue, reason: 'looks right...');
      expect(TronAddress.isValid(_a), isFalse, reason: '...but TronGrid rejects it: checksum fails');
      expect(TronAddress.isValid('T123'), isFalse);
      expect(TronAddress.isValid('${_b.substring(0, 33)}T'), isFalse);
    });
  });

  group('service', () {
    late FakeDepositBackend backend;
    late DepositService service;
    setUp(() {
      backend = FakeDepositBackend();
      service = DepositService(backend: backend);
    });

    test('createRequest: server assigns the address; client sends only amount', () async {
      backend.onRpc = (fn, p) => {'status': 'success', 'deposit': _deposit()};
      final r = await service.createRequest(amount: Decimal.fromInt(100), minDeposit: Decimal.fromInt(10));
      final call = backend.rpcCalls.single;
      expect(call.$1, 'rpc_create_deposit_request');
      expect(call.$2.keys.toSet(), {'p_amount', 'p_request_id'}, reason: 'no address can be sent by the client');
      expect(r.payToAddress, _b);
      expect(r.isAutoVerifying, isTrue);
      expect(r.awaitingProof, isTrue, reason: 'every address asks for the screenshot, like a normal deposit');
    });

    test('createRequest enforces the minimum before calling the server', () async {
      await expectLater(service.createRequest(amount: Decimal.fromInt(5), minDeposit: Decimal.fromInt(10)),
          throwsA(isA<DepositServiceException>().having((e) => e.code, 'code', 'AMOUNT_TOO_SMALL')));
      expect(backend.rpcCalls, isEmpty);
    });

    test('attachProof uploads to the user folder, then attaches', () async {
      backend.onRpc = (fn, p) => {'status': 'success', 'deposit': _deposit(address: _a, verification: 'NOT_REQUIRED', proof: p['p_proof_path'] as String?)};
      final r = await service.attachProof(depositId: 'dep-1', proofBytes: Uint8List.fromList([1, 2, 3]), proofFileName: 'p.png');
      expect(backend.uploads.single.$1, startsWith('user-1/'));
      expect(backend.rpcCalls.single.$1, 'rpc_attach_deposit_proof');
      expect(r.awaitingProof, isFalse);
    });

    test('model: manual request without proof is "awaiting payment", not admin work', () {
      final r = DepositRequest.fromMap(_deposit(address: _a, verification: 'NOT_REQUIRED'));
      expect(r.awaitingProof, isTrue);
      expect(r.isAutoVerifying, isFalse);
    });

    test('model: failure reasons have readable labels', () {
      expect(DepositRequest.fromMap(_deposit(verification: 'FAILED', error: 'TIMEOUT')).verificationErrorLabel, 'timeout');
      expect(DepositRequest.fromMap(_deposit(verification: 'FAILED', error: 'ABOVE_AUTO_LIMIT')).verificationErrorLabel,
          'above auto limit');
      expect(DepositRequest.fromMap(_deposit(verification: 'FAILED', error: 'WRONG_RECIPIENT')).verificationErrorLabel,
          'wrong recipient');
    });

    test('admin address update refuses a bad checksum without calling the server', () async {
      await expectLater(service.adminUpsertAddress(address: _a, autoVerify: false),
          throwsA(isA<DepositServiceException>().having((e) => e.code, 'code', 'BAD_ADDRESS')));
      expect(backend.rpcCalls, isEmpty);

      backend.onRpc = (fn, p) => {'status': 'success', 'address': _addr(_b, auto: true)};
      final saved = await service.adminUpsertAddress(address: _b, autoVerify: true, maxAutoApproveUsd: Decimal.fromInt(1000));
      expect(saved.autoVerify, isTrue);
      expect(backend.rpcCalls.single.$2['p_max_auto_approve_usd'], '1000');
    });
  });

  group('admin', () {
    testWidgets('Pending shows failed auto-verify with a reason; auto-approved ones are read-only under Approved',
        (tester) async {
      final backend = FakeDepositBackend();
      final calls = <String?>[];
      backend.onRpc = (fn, p) {
        if (fn == 'rpc_admin_list_deposit_addresses') return [_addr(_a, weight: 3, order: 1), _addr(_b, order: 2, auto: true)];
        if (fn == 'rpc_admin_list_deposit_requests') {
          calls.add(p['p_status'] as String?);
          return p['p_status'] == 'APPROVED'
              ? [_deposit(id: 'auto', status: 'APPROVED', verification: 'VERIFIED', system: true, credited: 98.5, onchain: 98.5, txid: _txid)]
              : [_deposit(id: 'f1', verification: 'FAILED', error: 'TIMEOUT'), _deposit(id: 'm1', address: _a, verification: 'NOT_REQUIRED', proof: 'user-1/p.png')];
        }
        return null;
      };
      await _pumpThemed(tester, SizedBox(height: 2300, child: DepositRequestsTab(service: DepositService(backend: backend))));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(calls.first, 'PENDING', reason: 'the server filters out WAITING / auto-approved rows');
      expect(find.text('Auto-verify failed: timeout'), findsOneWidget);
      expect(find.textContaining('Advanced rotation settings'), findsNothing, reason: 'removed from the admin UI');
      expect(find.textContaining('checksum failed'), findsWidgets, reason: 'configured Address A is flagged');

      expect(find.text('Auto-approved'), findsNothing, reason: 'the separate tab was removed');
      await tester.tap(find.text('Approved'));
      await tester.pumpAndSettle();
      expect(calls.last, 'APPROVED');
      expect(find.textContaining('Auto-approved by the system'), findsOneWidget);
      expect(find.textContaining('On-chain amount'), findsOneWidget);
      expect(find.text('APPROVE'), findsNothing, reason: 'no approve button on completed auto deposits');
      expect(find.text('REJECT'), findsNothing);
    });
  });

  group('admin delete', () {
    testWidgets('pending request can be deleted (with its screenshot); approved ones cannot', (tester) async {
      final backend = FakeDepositBackend();
      final deleted = <Object?>[];
      var rows = [
        _deposit(id: 'p1', address: _a, verification: 'NOT_REQUIRED', proof: 'user-1/p1.png'),
        _deposit(id: 'ok', status: 'APPROVED', address: _a, verification: 'NOT_REQUIRED', credited: 100),
      ];
      backend.onRpc = (fn, p) {
        if (fn == 'rpc_admin_list_deposit_addresses') return [_addr(_a, weight: 3), _addr(_b, order: 2, auto: true)];
        if (fn == 'rpc_admin_list_deposit_requests') return rows;
        if (fn == 'rpc_admin_delete_deposit_request') {
          deleted.add(p['p_deposit_id']);
          rows = rows.where((r) => r['id'] != p['p_deposit_id']).toList();
          return {'status': 'success', 'deleted': p['p_deposit_id'], 'proof_path': 'user-1/p1.png'};
        }
        return null;
      };
      await _pumpThemed(tester, SizedBox(height: 2300, child: DepositRequestsTab(service: DepositService(backend: backend))));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Delete request'), findsOneWidget, reason: 'only the pending one; approved was credited');
      await tester.tap(find.byTooltip('Delete request'));
      await tester.pumpAndSettle();
      expect(find.text('Delete deposit request?'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(deleted, ['p1']);
      expect(backend.removedProofs, ['user-1/p1.png'], reason: 'screenshot removed from storage');
      expect(find.text('Deposit request deleted.'), findsOneWidget);
      expect(find.byTooltip('Delete request'), findsNothing, reason: 'list reloaded without it');
    });
  });

  group('user deposit panel (automatic verification is invisible to users)', () {
    void expectNothingAutomatic() {
      for (final hidden in ['blockchain', 'AUTO', 'automatic', 'on-chain', 'no screenshot', 'VERIFYING']) {
        expect(find.textContaining(hidden), findsNothing, reason: '"$hidden" must not be shown to users');
      }
    }

    for (final (name, address, verification) in [
      ('manual address', _a, 'NOT_REQUIRED'),
      ('automatic address', _b, 'WAITING'),
    ]) {
      testWidgets('get address -> $name asks for the screenshot like any deposit', (tester) async {
        final backend = FakeDepositBackend()..ownRows = [];
        backend.onRpc = (fn, p) {
          // The server stores the request, so later refreshes return it.
          backend.ownRows = [_deposit(address: address, verification: verification)];
          return {'status': 'success', 'deposit': _deposit(address: address, verification: verification)};
        };
        await _pumpThemed(tester, DepositPanel(service: DepositService(backend: backend)));
        await tester.pumpAndSettle();

        await tester.tap(find.text('GET DEPOSIT ADDRESS'));
        await tester.pumpAndSettle();
        expect(find.text(address), findsOneWidget, reason: 'the server-assigned address is shown');
        expect(find.textContaining('Attach screenshot'), findsOneWidget);
        expect(find.text('I HAVE SENT THE PAYMENT'), findsOneWidget);
        expectNothingAutomatic();
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('open request: one amount field, no separate update button', (tester) async {
      final backend = FakeDepositBackend()..ownRows = [_deposit(address: _a, verification: 'NOT_REQUIRED')];
      await _pumpThemed(tester, DepositPanel(service: DepositService(backend: backend)));
      await tester.pumpAndSettle();

      final field = find.byKey(const Key('deposit_amount'));
      expect(tester.widget<TextField>(field).controller!.text, '100', reason: 'shows the open amount');
      await tester.enterText(field, '25');
      await tester.pump();

      expect(find.text('UPDATE AMOUNT'), findsNothing, reason: 'saved together with "I have sent the payment"');
      expect(find.textContaining('Send exactly'), findsNothing, reason: 'the amount is shown only in the field');
      expect(find.text('I HAVE SENT THE PAYMENT'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('submitted automatic deposit: "Under review", then credited as plain "Approved"', (tester) async {
      final backend = FakeDepositBackend()..ownRows = [_deposit(proof: 'user-1/p.png')];
      await _pumpThemed(
        tester,
        DepositPanel(service: DepositService(backend: backend), pollEvery: const Duration(seconds: 2)),
      );
      await tester.pumpAndSettle();
      expect(find.text('UNDER REVIEW'), findsOneWidget);
      expect(find.text('GET DEPOSIT ADDRESS'), findsOneWidget, reason: 'a new deposit can be started');
      expectNothingAutomatic();

      // Verified on-chain in the background (98.50 received, 100 entered).
      backend.ownRows = [
        _deposit(status: 'APPROVED', verification: 'VERIFIED', system: true, credited: 98.5, onchain: 98.5, txid: _txid, proof: 'user-1/p.png'),
      ];
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('APPROVED'), findsOneWidget);
      expect(find.textContaining('98.50 USDT credited'), findsWidgets);
      expectNothingAutomatic();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('failed automatic verification is just "Under review" to the user', (tester) async {
      final backend = FakeDepositBackend()
        ..ownRows = [_deposit(verification: 'FAILED', error: 'TIMEOUT', proof: 'user-1/p.png')];
      await _pumpThemed(tester, DepositPanel(service: DepositService(backend: backend)));
      await tester.pumpAndSettle();
      expect(find.text('UNDER REVIEW'), findsOneWidget);
      expect(find.textContaining('TIMEOUT'), findsNothing, reason: 'internal codes are not shown to users');
      expectNothingAutomatic();
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Address A card (admin wallet = Address A)', () {
    testWidgets('shows A and B; blocks a bad checksum; saves a valid address as Address A', (tester) async {
      const newA = 'TQn9Y2khEsLJW1ChVWFMSMeRDow5KcbLSE';
      final backend = FakeDepositBackend();
      backend.onRpc = (fn, p) {
        if (fn == 'rpc_admin_list_deposit_addresses') return [_addr(_a, weight: 3, order: 1), _addr(_b, order: 2, auto: true)];
        if (fn == 'rpc_admin_set_deposit_address') return {'status': 'success', 'deposit_address': p['p_address']};
        return null;
      };
      await _pumpThemed(tester, AddressACard(service: DepositService(backend: backend)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(_a), findsOneWidget);
      expect(find.text(_b), findsNothing, reason: 'Address B is not shown on this card');
      expect(find.textContaining('checksum failed'), findsOneWidget, reason: 'current A is flagged');

      // Typo (bad checksum) is refused before anything is sent.
      await tester.enterText(find.byType(TextField), '${newA.substring(0, 33)}F');
      await tester.pump();
      expect(find.textContaining('Checksum failed'), findsOneWidget);
      await tester.tap(find.text('Save / Update Address'));
      await tester.pumpAndSettle();
      expect(find.text('Change Address A?'), findsNothing);

      // B cannot become A.
      await tester.enterText(find.byType(TextField), _b);
      await tester.pump();
      expect(find.textContaining('already in use for automatic deposits'), findsOneWidget);

      await tester.enterText(find.byType(TextField), newA);
      await tester.pump();
      await tester.tap(find.text('Save / Update Address'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, update'));
      await tester.pumpAndSettle();

      final save = backend.rpcCalls.where((c) => c.$1 == 'rpc_admin_set_deposit_address').single;
      expect(save.$2, {'p_address': newA});
      expect(find.text('Deposit address updated.'), findsOneWidget);
      expect(find.text(newA), findsOneWidget, reason: 'shown as the active Address A');
    });
  });
}
