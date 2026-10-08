import 'package:decimal/decimal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/math/money_math.dart';
import 'supabase_deposit_service.dart';

/// Admin side of USDT withdrawals.
///
/// `rpc_request_withdrawal` records the request without touching the balance.
/// The admin sends the USDT by hand, then records the payment
/// (`rpc_admin_review_withdrawal` approve + payout TXID), which deducts the
/// amount from the user's balance, or rejects with a reason (nothing to return).
/// Requests made before deduct-on-approval were deducted when made
/// ([WithdrawalRequest.fundsHeld]): rejecting those refunds the amount.

enum WithdrawalStatus { pending, approved, rejected, cancelled }

class WithdrawalRequest {
  final String id;
  final String userId;
  final Decimal amount;
  final String? method;
  final String? destination;
  final WithdrawalStatus status;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? rejectReason;
  final String? payoutTxid;
  final String? adminNote;

  /// True when the amount was already deducted at request time (old requests).
  /// New requests are deducted only when approved.
  final bool fundsHeld;

  // Context for the decision (from rpc_admin_list_withdrawals).
  final String? userEmail;
  final String? fullName;
  final String kycStatus;
  final DateTime? userCreatedAt;
  final DateTime? lastSignInAt;
  final Decimal? walletBalance;
  final Decimal? heldMargin;
  final int openPositions;
  final Decimal realizedPnlTotal;
  final Decimal totalDeposited;
  final Decimal totalWithdrawn;
  final int previousWithdrawals;

  WithdrawalRequest({
    required this.id,
    required this.userId,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.method,
    this.destination,
    this.reviewedAt,
    this.reviewedBy,
    this.rejectReason,
    this.payoutTxid,
    this.adminNote,
    this.fundsHeld = false,
    this.userEmail,
    this.fullName,
    this.kycStatus = 'NOT_STARTED',
    this.userCreatedAt,
    this.lastSignInAt,
    this.walletBalance,
    this.heldMargin,
    this.openPositions = 0,
    Decimal? realizedPnlTotal,
    Decimal? totalDeposited,
    Decimal? totalWithdrawn,
    this.previousWithdrawals = 0,
  })  : realizedPnlTotal = realizedPnlTotal ?? Decimal.zero,
        totalDeposited = totalDeposited ?? Decimal.zero,
        totalWithdrawn = totalWithdrawn ?? Decimal.zero;

  bool get isPending => status == WithdrawalStatus.pending;

  /// Approving deducts the amount now, but the user's balance is lower.
  bool get balanceTooLow =>
      isPending && !fundsHeld && walletBalance != null && walletBalance! < amount;
  bool get kycApproved => kycStatus.toUpperCase() == 'APPROVED';
  bool get destinationLooksValid => DepositService.isValidTronAddress(destination ?? '');

  Uri? get destinationTronscanUrl => destinationLooksValid
      ? Uri.parse('https://tronscan.org/#/address/${destination!.trim()}')
      : null;
  Uri? get payoutTronscanUrl =>
      payoutTxid == null ? null : Uri.parse('https://tronscan.org/#/transaction/$payoutTxid');

  static DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v.toString());
  static Decimal? _dec(Object? v) => v == null ? null : MoneyMath.toDec(v);
  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  static WithdrawalStatus _status(Object? v) => switch ('${v ?? ''}'.toUpperCase()) {
        'APPROVED' => WithdrawalStatus.approved,
        'REJECTED' => WithdrawalStatus.rejected,
        'CANCELLED' => WithdrawalStatus.cancelled,
        _ => WithdrawalStatus.pending,
      };

  factory WithdrawalRequest.fromMap(Map<String, dynamic> m) => WithdrawalRequest(
        id: '${m['id']}',
        userId: '${m['user_id'] ?? ''}',
        amount: MoneyMath.toDec(m['amount'] ?? 0),
        method: m['method'] as String?,
        destination: m['destination'] as String?,
        status: _status(m['status']),
        createdAt: _date(m['created_at']) ?? DateTime.now(),
        reviewedAt: _date(m['reviewed_at']),
        reviewedBy: m['reviewed_by'] as String?,
        rejectReason: m['reject_reason'] as String?,
        payoutTxid: m['payout_txid'] as String?,
        adminNote: m['admin_note'] as String?,
        // Rows from before the column existed were all deducted at request time.
        fundsHeld: m.containsKey('funds_held') ? m['funds_held'] == true : true,
        userEmail: m['user_email'] as String?,
        fullName: m['full_name'] as String?,
        kycStatus: '${m['kyc_status'] ?? 'NOT_STARTED'}',
        userCreatedAt: _date(m['user_created_at']),
        lastSignInAt: _date(m['last_sign_in_at']),
        walletBalance: _dec(m['wallet_balance']),
        heldMargin: _dec(m['held_margin']),
        openPositions: _int(m['open_positions']),
        realizedPnlTotal: _dec(m['realized_pnl_total']),
        totalDeposited: _dec(m['total_deposited']),
        totalWithdrawn: _dec(m['total_withdrawn']),
        previousWithdrawals: _int(m['previous_withdrawals']),
      );
}

typedef RpcCall = Future<dynamic> Function(String function, Map<String, dynamic> params);

class WithdrawalAdminService {
  WithdrawalAdminService({RpcCall? rpc}) : _rpc = rpc ?? _supabaseRpc;

  static final WithdrawalAdminService instance = WithdrawalAdminService();

  final RpcCall _rpc;

  static Future<dynamic> _supabaseRpc(String function, Map<String, dynamic> params) =>
      Supabase.instance.client.rpc(function, params: params);

  /// Admin queue (PENDING first). [status] null = all.
  Future<List<WithdrawalRequest>> list({String? status, int limit = 200}) async {
    try {
      final res = await _rpc('rpc_admin_list_withdrawals', {'p_status': status, 'p_limit': limit});
      if (res is! List) return const [];
      return [for (final r in res) WithdrawalRequest.fromMap(Map<String, dynamic>.from(r as Map))];
    } catch (e) {
      throw DepositService.toException(e);
    }
  }

  /// Record a payment already sent on-chain. [payoutTxid] is that transfer's hash.
  Future<void> approve(String withdrawalId, {required String payoutTxid, String? adminNote}) async {
    if (!DepositService.isValidTxid(payoutTxid)) {
      throw const DepositServiceException(
          'BAD_TXID', 'Enter the 64-character TRON transaction ID of the payment you sent.');
    }
    await _review(withdrawalId, approve: true, payoutTxid: DepositService.normalizeTxid(payoutTxid), adminNote: adminNote);
  }

  /// Reject with a reason the user will see; the held amount is returned to them.
  Future<void> reject(String withdrawalId, {required String reason, String? adminNote}) async {
    if (reason.trim().isEmpty) {
      throw const DepositServiceException('REASON_REQUIRED', 'A reason is required to reject a withdrawal.');
    }
    await _review(withdrawalId, approve: false, reason: reason.trim(), adminNote: adminNote);
  }

  Future<void> _review(
    String withdrawalId, {
    required bool approve,
    String? reason,
    String? payoutTxid,
    String? adminNote,
  }) async {
    try {
      await _rpc('rpc_admin_review_withdrawal', {
        'p_withdrawal_id': withdrawalId,
        'p_approve': approve,
        'p_reason': reason,
        'p_payout_txid': payoutTxid,
        'p_admin_note': (adminNote == null || adminNote.trim().isEmpty) ? null : adminNote.trim(),
      });
    } catch (e) {
      throw DepositService.toException(e);
    }
  }
}
