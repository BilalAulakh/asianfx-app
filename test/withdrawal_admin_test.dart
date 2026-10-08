import 'package:asianfxapp/blocs/theme_cubit.dart';
import 'package:asianfxapp/core/theme/app_theme.dart';
import 'package:asianfxapp/data/datasources/supabase_deposit_service.dart';
import 'package:asianfxapp/data/datasources/withdrawal_admin_service.dart';
import 'package:asianfxapp/presentation/admin/widgets/withdrawal_requests_tab.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dest = 'TQn9Y2khEsLJW1ChVWFMSMeRDow5KcbLSE';
const _payout = 'ABCDEF0123456789abcdef0123456789ABCDEF0123456789abcdef0123456789';

Map<String, dynamic> _row({String status = 'PENDING', String kyc = 'APPROVED', String? dest = _dest}) => {
      'id': 'wd-1',
      'user_id': 'user-1',
      'amount': 10,
      'method': 'USDT (TRC-20)',
      'destination': dest,
      'status': status,
      'created_at': '2026-10-06T02:00:00Z',
      'user_email': 'sem123@gmail.com',
      'full_name': 'Sem Huhui',
      'kyc_status': kyc,
      'wallet_balance': 89.67,
      'held_margin': 0,
      'open_positions': 0,
      'realized_pnl_total': 1.9,
      'total_deposited': 100,
      'total_withdrawn': 0,
      'previous_withdrawals': 0,
    };

class _FakeRpc {
  final calls = <(String, Map<String, dynamic>)>[];
  List<Map<String, dynamic>> rows = [_row()];
  Object? reviewError;

  Future<dynamic> call(String fn, Map<String, dynamic> p) async {
    calls.add((fn, p));
    if (fn == 'rpc_admin_list_withdrawals') return rows;
    if (fn == 'rpc_admin_review_withdrawal') {
      if (reviewError != null) throw reviewError!;
      rows = [];
      return {'status': 'success'};
    }
    return null;
  }

  List<Map<String, dynamic>> reviews() =>
      [for (final c in calls) if (c.$1 == 'rpc_admin_review_withdrawal') c.$2];
}

Future<_FakeRpc> _pump(WidgetTester tester, {List<Map<String, dynamic>>? rows}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(1200, 2200));
  final fake = _FakeRpc();
  if (rows != null) fake.rows = rows;
  await tester.pumpWidget(BlocProvider(
    create: (_) => ThemeCubit(),
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: WithdrawalRequestsTab(service: WithdrawalAdminService(rpc: fake.call))),
    ),
  ));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  group('service', () {
    test('maps the admin row, including decision context', () {
      final w = WithdrawalRequest.fromMap(_row());
      expect(w.amount, Decimal.fromInt(10));
      expect(w.destinationLooksValid, isTrue);
      expect(w.kycApproved, isTrue);
      expect(w.totalDeposited, Decimal.fromInt(100));
      expect(w.isPending, isTrue);
    });

    test('approve needs a valid payout TXID and sends it normalised', () async {
      final fake = _FakeRpc();
      final service = WithdrawalAdminService(rpc: fake.call);
      await expectLater(service.approve('wd-1', payoutTxid: 'abc'),
          throwsA(isA<DepositServiceException>().having((e) => e.code, 'code', 'BAD_TXID')));
      expect(fake.reviews(), isEmpty);

      await service.approve('wd-1', payoutTxid: ' $_payout ');
      expect(fake.reviews().single, {
        'p_withdrawal_id': 'wd-1',
        'p_approve': true,
        'p_reason': null,
        'p_payout_txid': _payout.toLowerCase(),
        'p_admin_note': null,
      });
    });

    test('reject needs a reason', () async {
      final fake = _FakeRpc();
      final service = WithdrawalAdminService(rpc: fake.call);
      await expectLater(service.reject('wd-1', reason: '  '),
          throwsA(isA<DepositServiceException>().having((e) => e.code, 'code', 'REASON_REQUIRED')));
      await service.reject('wd-1', reason: 'Wrong network');
      expect(fake.reviews().single['p_approve'], isFalse);
      expect(fake.reviews().single['p_reason'], 'Wrong network');
    });

    test('server errors surface as typed exceptions', () async {
      final fake = _FakeRpc()..reviewError = Exception('FORBIDDEN: administrator privileges required');
      await expectLater(WithdrawalAdminService(rpc: fake.call).reject('wd-1', reason: 'x'),
          throwsA(isA<DepositServiceException>().having((e) => e.code, 'code', 'FORBIDDEN')));
    });
  });

  group('admin tab (real app theme)', () {
    testWidgets('shows the details an admin needs to pay out', (tester) async {
      await _pump(tester);
      expect(tester.takeException(), isNull);
      for (final text in [
        'Sem Huhui',
        'sem123@gmail.com',
        _dest,
        'APPROVED', // KYC
        'Total deposited',
        'Open positions',
        'MARK AS PAID',
        'REJECT & REFUND',
      ]) {
        expect(find.textContaining(text), findsWidgets, reason: text);
      }
    });

    testWidgets('warns about unverified KYC and an invalid address', (tester) async {
      await _pump(tester, rows: [_row(kyc: 'PENDING_REVIEW', dest: 'not-a-tron-address')]);
      expect(find.textContaining('identity not verified'), findsOneWidget);
      expect(find.textContaining('not a valid TRC-20 address'), findsOneWidget);
    });

    testWidgets('mark as paid: TXID required, confirm, recorded', (tester) async {
      final fake = await _pump(tester);
      await tester.tap(find.text('MARK AS PAID'));
      await tester.pumpAndSettle();
      expect(find.text('Mark as paid?'), findsNothing);
      expect(find.textContaining('Paste the TXID'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, _payout);
      await tester.pump();
      await tester.tap(find.text('MARK AS PAID'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, paid'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(fake.reviews().single['p_approve'], isTrue);
      expect(fake.reviews().single['p_payout_txid'], _payout.toLowerCase());
      expect(find.text('Withdrawal marked as paid.'), findsOneWidget);
    });

    testWidgets('reject: reason required, funds returned message', (tester) async {
      final fake = await _pump(tester);
      await tester.tap(find.text('REJECT & REFUND'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Wallet is not TRC-20');
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(fake.reviews().single['p_reason'], 'Wallet is not TRC-20');
      expect(find.textContaining('Funds returned to the user'), findsOneWidget);
    });
  });

  group('deduct on approval (new requests, funds_held = false)', () {
    Map<String, dynamic> newRow({num balance = 89.67, num amount = 10}) =>
        {..._row(), 'funds_held': false, 'wallet_balance': balance, 'amount': amount};

    test('old rows without the column count as already deducted', () {
      expect(WithdrawalRequest.fromMap(_row()).fundsHeld, isTrue);
      expect(WithdrawalRequest.fromMap(newRow()).fundsHeld, isFalse);
    });

    test('balanceTooLow only for undeducted requests above the current balance', () {
      expect(WithdrawalRequest.fromMap(newRow(balance: 5, amount: 10)).balanceTooLow, isTrue);
      expect(WithdrawalRequest.fromMap(newRow(balance: 50, amount: 10)).balanceTooLow, isFalse);
      expect(WithdrawalRequest.fromMap({..._row(), 'wallet_balance': 5}).balanceTooLow, isFalse);
    });

    testWidgets('card says nothing is held; reject does not mention a refund', (tester) async {
      final fake = await _pump(tester, rows: [newRow()]);
      expect(find.text('Balance now'), findsOneWidget);
      expect(find.text('REJECT & REFUND'), findsNothing);

      await tester.tap(find.text('REJECT'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nothing was deducted'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Wrong address');
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await tester.pumpAndSettle();
      expect(fake.reviews().single['p_approve'], isFalse);
      expect(find.textContaining('balance was not changed'), findsOneWidget);
    });

    testWidgets('warns not to pay when the balance dropped below the request', (tester) async {
      await _pump(tester, rows: [newRow(balance: 4, amount: 10)]);
      expect(find.textContaining('less than this withdrawal. Do not pay'), findsOneWidget);
    });
  });
}
