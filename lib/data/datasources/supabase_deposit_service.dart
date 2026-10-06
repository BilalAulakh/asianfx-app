import 'dart:async';
import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/math/money_math.dart';
import '../../core/utils/tron_address.dart';

/// Manual USDT (TRC-20) deposits.
///
/// There is no automatic on-chain verification any more. A user files a claim
/// (amount + payment screenshot, TXID optional) through `rpc_submit_deposit_request`;
/// an administrator checks the transfer on Tronscan by hand and settles it through
/// `rpc_review_deposit`. The wallet is credited only by that admin RPC.

enum DepositStatus { pending, approved, rejected }

/// Deposit settings published by the broker in `broker_config`.
class DepositConfig {
  /// Company TRC-20 address. `null` means deposits are not configured yet.
  final String? depositAddress;
  final Decimal minDeposit;

  const DepositConfig({required this.depositAddress, required this.minDeposit});

  bool get isEnabled => depositAddress != null && depositAddress!.isNotEmpty;

  factory DepositConfig.fromRow(Map<String, dynamic>? row) {
    final address = (row?['deposit_address_trc20'] as String?)?.trim();
    return DepositConfig(
      depositAddress: (address == null || address.isEmpty) ? null : address,
      minDeposit: row?['min_deposit_usd'] == null
          ? Decimal.fromInt(10)
          : MoneyMath.toDec(row!['min_deposit_usd']),
    );
  }
}

class DepositRequest {
  final String id;
  final String userId;
  final Decimal amountClaimed;
  final String network;
  final String token;
  /// Empty when the user filed the claim without a TXID.
  final String txid;
  final String? fromAddress;
  final String? depositAddress;
  final String? proofPath;
  final DepositStatus status;
  final Decimal? amountCredited;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? rejectReason;
  final String? adminNote;
  final DateTime createdAt;

  /// Only present on rows returned by the admin queue RPC.
  final String? userEmail;

  /// Company address assigned by the server's rotation (shown to the user).
  final String? addressUsed;
  /// NOT_REQUIRED (manual address), WAITING / VERIFIED / FAILED (automatic address).
  final String verificationStatus;
  final String? verificationError;
  /// Amount found on-chain by the automatic verifier (authoritative).
  final Decimal? onchainAmount;
  final bool approvedBySystem;
  final int verificationAttempts;

  const DepositRequest({
    required this.id,
    required this.userId,
    required this.amountClaimed,
    required this.network,
    required this.token,
    required this.txid,
    required this.status,
    required this.createdAt,
    this.fromAddress,
    this.depositAddress,
    this.proofPath,
    this.amountCredited,
    this.reviewedAt,
    this.reviewedBy,
    this.rejectReason,
    this.adminNote,
    this.userEmail,
    this.addressUsed,
    this.verificationStatus = 'NOT_REQUIRED',
    this.verificationError,
    this.onchainAmount,
    this.approvedBySystem = false,
    this.verificationAttempts = 0,
  });

  bool get isPending => status == DepositStatus.pending;

  /// The address the user must pay: the rotation's choice, or the legacy column.
  String? get payToAddress => addressUsed ?? depositAddress;

  /// Being verified on-chain by the system; no admin or user action needed.
  bool get isAutoVerifying => isPending && verificationStatus == 'WAITING';
  bool get autoVerifyFailed => verificationStatus == 'FAILED';
  /// Created but the payment screenshot is not attached yet (any address: users
  /// see one flow; automatic verification runs server-side regardless).
  bool get awaitingProof =>
      isPending &&
      (verificationStatus == 'NOT_REQUIRED' || verificationStatus == 'WAITING') &&
      (proofPath == null || proofPath!.isEmpty) &&
      !hasTxid;

  /// Human label for [verificationError], e.g. "above auto limit".
  String get verificationErrorLabel => switch (verificationError) {
        'TIMEOUT' => 'timeout',
        'ABOVE_AUTO_LIMIT' => 'above auto limit',
        'WRONG_RECIPIENT' => 'wrong recipient',
        'AUTO_VERIFY_DISABLED' => 'auto-verify disabled',
        null || '' => 'unknown',
        final other => other.toLowerCase().replaceAll('_', ' '),
      };

  bool get hasTxid => txid.isNotEmpty;

  Uri get tronscanUrl => DepositService.tronscanUrl(txid);

  static DepositStatus statusFrom(dynamic raw) {
    switch ((raw as String?)?.toUpperCase()) {
      case 'APPROVED':
        return DepositStatus.approved;
      case 'REJECTED':
        return DepositStatus.rejected;
      default:
        return DepositStatus.pending;
    }
  }

  factory DepositRequest.fromMap(Map<String, dynamic> m) {
    DateTime? time(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
    return DepositRequest(
      id: m['id'].toString(),
      userId: m['user_id']?.toString() ?? '',
      amountClaimed: MoneyMath.toDec(m['amount_claimed'] ?? 0),
      network: m['network']?.toString() ?? 'TRC20',
      token: m['token']?.toString() ?? 'USDT',
      txid: m['txid']?.toString() ?? '',
      fromAddress: m['from_address'] as String?,
      depositAddress: m['deposit_address'] as String?,
      proofPath: m['proof_path'] as String?,
      status: statusFrom(m['status']),
      amountCredited: m['amount_credited'] == null ? null : MoneyMath.toDec(m['amount_credited']),
      reviewedAt: time(m['reviewed_at']),
      reviewedBy: m['reviewed_by'] as String?,
      rejectReason: m['reject_reason'] as String?,
      adminNote: m['admin_note'] as String?,
      createdAt: time(m['created_at']) ?? DateTime.now(),
      userEmail: m['user_email'] as String?,
      addressUsed: m['address_used'] as String?,
      verificationStatus: (m['verification_status'] as String?) ?? 'NOT_REQUIRED',
      verificationError: m['verification_error'] as String?,
      onchainAmount: m['onchain_amount'] == null ? null : MoneyMath.toDec(m['onchain_amount']),
      approvedBySystem: m['approved_by_system'] == true,
      verificationAttempts: (m['verification_attempts'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A company USDT (TRC-20) receiving address in the weighted rotation.
class CompanyDepositAddress {
  final String id;
  final String address;
  final String? label;
  /// Share of new deposit requests (A=3, B=1 gives A,A,A,B).
  final int weight;
  final int sortOrder;
  final bool isActive;
  /// true: deposits are verified on-chain and credited automatically.
  final bool autoVerify;
  final Decimal maxAutoApproveUsd;

  const CompanyDepositAddress({
    required this.id,
    required this.address,
    required this.weight,
    required this.sortOrder,
    required this.isActive,
    required this.autoVerify,
    required this.maxAutoApproveUsd,
    this.label,
  });

  /// Base58Check checksum OK (a typo makes wallets refuse to send).
  bool get checksumValid => TronAddress.isValid(address);

  factory CompanyDepositAddress.fromMap(Map<String, dynamic> m) => CompanyDepositAddress(
        id: '${m['id']}',
        address: '${m['address'] ?? ''}',
        label: m['label'] as String?,
        weight: (m['weight'] as num?)?.toInt() ?? 0,
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        isActive: m['is_active'] != false,
        autoVerify: m['auto_verify'] == true,
        maxAutoApproveUsd: MoneyMath.toDec(m['max_auto_approve_usd'] ?? 0),
      );
}

class DepositReviewResult {
  /// `success` or `already_reviewed`.
  final String status;
  final DepositRequest deposit;
  final Decimal? newBalance;
  final String? message;

  const DepositReviewResult({
    required this.status,
    required this.deposit,
    this.newBalance,
    this.message,
  });

  bool get alreadyReviewed => status == 'already_reviewed';
}

/// Raised for any rejected or failed deposit call. [code] is the machine prefix
/// the RPC raises (`TXID_ALREADY_USED`, `FORBIDDEN`, ...).
class DepositServiceException implements Exception {
  final String code;
  final String message;

  const DepositServiceException(this.code, this.message);

  @override
  String toString() => message;
}

/// The I/O the service needs, behind an interface so tests can run without a
/// Supabase project.
abstract class DepositBackend {
  String? get currentUserId;
  Future<dynamic> rpc(String function, Map<String, dynamic> params);
  Future<Map<String, dynamic>?> fetchBrokerConfig();
  Future<List<Map<String, dynamic>>> fetchOwnRequests(String userId);
  Future<void> uploadProof(String path, Uint8List bytes, String contentType);
  Future<String> signedProofUrl(String path, {int expiresInSeconds});
}

class SupabaseDepositBackend implements DepositBackend {
  static const proofBucket = 'deposit-proofs';

  SupabaseClient get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw const DepositServiceException(
          'OFFLINE', 'Deposit service is unavailable. Please check your connection.');
    }
  }

  @override
  String? get currentUserId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<dynamic> rpc(String function, Map<String, dynamic> params) =>
      _client.rpc(function, params: params);

  @override
  Future<Map<String, dynamic>?> fetchBrokerConfig() => _client
      .from('broker_config')
      .select('deposit_address_trc20, min_deposit_usd')
      .eq('id', 1)
      .maybeSingle();

  @override
  Future<List<Map<String, dynamic>>> fetchOwnRequests(String userId) async {
    // Explicit column list: admin_note / reviewed_by are not readable by clients.
    const base = 'id, user_id, amount_claimed, network, token, txid, from_address, '
        'deposit_address, proof_path, status, amount_credited, reviewed_at, '
        'reject_reason, created_at, updated_at';
    const verification = ', address_used, verification_status, verification_error, '
        'onchain_amount, approved_by_system';
    Future<List<Map<String, dynamic>>> query(String columns) async {
      final rows = await _client
          .from('deposit_requests')
          .select(columns)
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
      return [for (final r in rows) Map<String, dynamic>.from(r)];
    }

    try {
      return await query(base + verification);
    } on PostgrestException catch (e) {
      // Auto-verify migration not applied yet: fall back to the original columns.
      if (e.message.contains('does not exist')) return query(base);
      rethrow;
    }
  }

  @override
  Future<void> uploadProof(String path, Uint8List bytes, String contentType) async {
    await _client.storage.from(proofBucket).uploadBinary(
          path,
          bytes,
          // upsert=false: a stored proof can never be overwritten.
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
  }

  @override
  Future<String> signedProofUrl(String path, {int expiresInSeconds = 600}) =>
      _client.storage.from(proofBucket).createSignedUrl(path, expiresInSeconds);
}

class DepositService {
  DepositService({DepositBackend? backend, Uuid? uuid})
      : _backend = backend ?? SupabaseDepositBackend(),
        _uuid = uuid ?? const Uuid();

  static final DepositService instance = DepositService();

  final DepositBackend _backend;
  final Uuid _uuid;

  static const int maxProofBytes = 10 * 1024 * 1024;

  static final RegExp _txidPattern = RegExp(r'^[0-9a-fA-F]{64}$');
  static final RegExp _tronAddressPattern = RegExp(r'^T[1-9A-HJ-NP-Za-km-z]{33}$');

  static String normalizeTxid(String raw) => raw.trim().toLowerCase();
  static bool isValidTxid(String raw) => _txidPattern.hasMatch(raw.trim());
  static bool isValidTronAddress(String raw) => _tronAddressPattern.hasMatch(raw.trim());

  static Uri tronscanUrl(String txid) =>
      Uri.parse('https://tronscan.org/#/transaction/${normalizeTxid(txid)}');

  /// `CODE: human readable` (as raised by the RPCs) -> typed exception.
  static DepositServiceException toException(Object error) {
    if (error is DepositServiceException) return error;
    var raw = error is PostgrestException ? error.message : error.toString();
    raw = raw.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    final match = RegExp(r'^([A-Z][A-Z0-9_]{2,}):\s*(.+)$', dotAll: true).firstMatch(raw);
    if (match != null) {
      return DepositServiceException(match.group(1)!, match.group(2)!.trim());
    }
    return DepositServiceException(
        'RPC_FAILED', raw.isEmpty ? 'Deposit request failed. Please try again.' : raw);
  }

  Map<String, dynamic> _asMap(dynamic res) {
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    throw const DepositServiceException('RPC_FAILED', 'Unexpected response from the server.');
  }

  String _requireUser() {
    final uid = _backend.currentUserId;
    if (uid == null || uid.isEmpty) {
      throw const DepositServiceException('AUTH_REQUIRED', 'Please sign in again to continue.');
    }
    return uid;
  }

  static String _contentTypeFor(String? fileName) {
    final ext = (fileName ?? '').split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  static String _extFor(String contentType) => switch (contentType) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'jpg',
      };

  /// Deposit settings. The company address is the one the admin set in
  /// `broker_config.deposit_address_trc20` (Finance Desk > USDT Deposits), which
  /// is also what rpc_submit_deposit_request records. If the row has no valid
  /// address, or the database cannot be reached, the panel still shows the
  /// built-in [AppConstants.usdtTrc20DepositAddress] instead of an error.
  Future<DepositConfig> loadConfig() async {
    Map<String, dynamic>? row;
    try {
      row = await _backend.fetchBrokerConfig();
    } catch (_) {
      row = null;
    }
    final cfg = DepositConfig.fromRow(row);
    final address = cfg.depositAddress;
    return DepositConfig(
      depositAddress: (address != null && isValidTronAddress(address))
          ? address
          : AppConstants.usdtTrc20DepositAddress,
      minDeposit: cfg.minDeposit,
    );
  }

  /// Live deposit settings for an open deposit screen: emits the current
  /// config, then again whenever the admin changes the address (or minimum).
  /// Polls one small row every [every]; stops when the listener cancels.
  Stream<DepositConfig> watchConfig({Duration every = const Duration(seconds: 10)}) {
    late final StreamController<DepositConfig> controller;
    Timer? timer;
    DepositConfig? last;

    Future<void> poll() async {
      final cfg = await loadConfig();
      if (controller.isClosed) return;
      if (last == null || cfg.depositAddress != last!.depositAddress || cfg.minDeposit != last!.minDeposit) {
        last = cfg;
        controller.add(cfg);
      }
    }

    controller = StreamController<DepositConfig>(
      onListen: () {
        poll();
        timer = Timer.periodic(every, (_) => poll());
      },
      onCancel: () {
        timer?.cancel();
        return controller.close();
      },
    );
    return controller.stream;
  }

  /// Admin: set ADDRESS A, the manual address that receives 3 of every 4
  /// deposit requests (the automatic Address B keeps every 4th).
  /// `rpc_admin_set_deposit_address` re-checks admin rights, updates the rotation
  /// under its lock, deactivates the previous Address A and audits the change.
  /// Checked here with the Base58Check checksum, which catches typos.
  Future<String> adminSetDepositAddress(String address) async {
    final trimmed = address.trim();
    if (!TronAddress.isValid(trimmed)) {
      throw const DepositServiceException(
          'BAD_ADDRESS', 'Not a valid TRON address (checksum failed). Copy it again from your wallet.');
    }
    try {
      final res = _asMap(await _backend.rpc('rpc_admin_set_deposit_address', {'p_address': trimmed}));
      return (res['deposit_address'] as String?) ?? trimmed;
    } catch (e) {
      throw toException(e);
    }
  }

  // ── Rotation-based flow (address assigned before the user pays) ──────────

  /// Step 1: create (or resume) the user's open deposit request. The server
  /// assigns the company address by weighted rotation and stores it in
  /// `address_used`; the client never chooses it.
  Future<DepositRequest> createRequest({required Decimal amount, Decimal? minDeposit, String? requestId}) async {
    _requireUser();
    if (amount <= Decimal.zero || (minDeposit != null && amount < minDeposit)) {
      throw DepositServiceException('AMOUNT_TOO_SMALL', 'The minimum deposit is ${minDeposit ?? Decimal.one} USD.');
    }
    try {
      final res = _asMap(await _backend.rpc('rpc_create_deposit_request', {
        'p_amount': amount.toString(),
        'p_request_id': requestId ?? 'dep-${_uuid.v4()}',
      }));
      final deposit = res['deposit'];
      if (deposit is! Map) {
        throw const DepositServiceException('RPC_FAILED', 'Unexpected response from the server.');
      }
      return DepositRequest.fromMap(Map<String, dynamic>.from(deposit));
    } catch (e) {
      throw toException(e);
    }
  }

  /// Step 2: upload the payment screenshot and attach it. Manual requests enter
  /// the admin Pending queue; automatic ones keep being verified server-side.
  Future<DepositRequest> attachProof({
    required String depositId,
    required Uint8List proofBytes,
    String? proofFileName,
  }) async {
    final uid = _requireUser();
    if (proofBytes.isEmpty) {
      throw const DepositServiceException('PROOF_REQUIRED', 'Please attach a screenshot of your payment.');
    }
    if (proofBytes.lengthInBytes > maxProofBytes) {
      throw const DepositServiceException('PROOF_TOO_LARGE', 'The screenshot must be 10 MB or smaller.');
    }
    try {
      final contentType = _contentTypeFor(proofFileName);
      final proofPath = '$uid/${_uuid.v4()}.${_extFor(contentType)}';
      await _backend.uploadProof(proofPath, proofBytes, contentType);
      final res = _asMap(await _backend.rpc('rpc_attach_deposit_proof', {
        'p_deposit_id': depositId,
        'p_proof_path': proofPath,
      }));
      final deposit = res['deposit'];
      if (deposit is! Map) {
        throw const DepositServiceException('RPC_FAILED', 'Unexpected response from the server.');
      }
      return DepositRequest.fromMap(Map<String, dynamic>.from(deposit));
    } catch (e) {
      throw toException(e);
    }
  }

  /// Admin: every company address with its rotation weight and auto-verify settings.
  Future<List<CompanyDepositAddress>> adminListAddresses() async {
    try {
      final res = await _backend.rpc('rpc_admin_list_deposit_addresses', const {});
      if (res is! List) return const [];
      return [for (final r in res) CompanyDepositAddress.fromMap(Map<String, dynamic>.from(r as Map))];
    } catch (e) {
      throw toException(e);
    }
  }

  /// Admin: add or update a company address. Only the given fields change.
  /// New addresses must pass the Base58Check checksum (catches typos).
  Future<CompanyDepositAddress> adminUpsertAddress({
    required String address,
    String? label,
    int? weight,
    bool? isActive,
    bool? autoVerify,
    Decimal? maxAutoApproveUsd,
  }) async {
    final trimmed = address.trim();
    if (!TronAddress.isValid(trimmed)) {
      throw const DepositServiceException(
          'BAD_ADDRESS', 'Not a valid TRON address (checksum failed). Copy it again from your wallet.');
    }
    if (weight != null && (weight < 0 || weight > 100)) {
      throw const DepositServiceException('BAD_WEIGHT', 'Weight must be between 0 and 100.');
    }
    if (maxAutoApproveUsd != null && maxAutoApproveUsd < Decimal.zero) {
      throw const DepositServiceException('BAD_LIMIT', 'The automatic approval limit cannot be negative.');
    }
    try {
      final res = _asMap(await _backend.rpc('rpc_admin_upsert_deposit_address', {
        'p_address': trimmed,
        'p_label': label,
        'p_weight': weight,
        'p_is_active': isActive,
        'p_auto_verify': autoVerify,
        'p_max_auto_approve_usd': maxAutoApproveUsd?.toString(),
        'p_sort_order': null,
      }));
      final row = res['address'];
      if (row is! Map) {
        throw const DepositServiceException('RPC_FAILED', 'Unexpected response from the server.');
      }
      return CompanyDepositAddress.fromMap(Map<String, dynamic>.from(row));
    } catch (e) {
      throw toException(e);
    }
  }

  /// File a deposit claim. Uploads the required screenshot into the caller's own
  /// folder of the private bucket first, then calls the RPC. Does not move money.
  Future<DepositRequest> submit({
    required Decimal amount,
    required Uint8List? proofBytes,
    String? txid,
    String? fromAddress,
    String? proofFileName,
    String? requestId,
    Decimal? minDeposit,
  }) async {
    final uid = _requireUser();

    final hash = txid?.trim() ?? '';
    if (hash.isNotEmpty && !isValidTxid(hash)) {
      throw const DepositServiceException(
          'BAD_TXID', 'A TRON transaction ID must be 64 hexadecimal characters.');
    }
    if (proofBytes == null || proofBytes.isEmpty) {
      throw const DepositServiceException(
          'PROOF_REQUIRED', 'Please attach a screenshot of your payment.');
    }
    if (amount <= Decimal.zero || (minDeposit != null && amount < minDeposit)) {
      throw DepositServiceException('AMOUNT_TOO_SMALL',
          'The minimum deposit is ${minDeposit ?? Decimal.one} USD.');
    }
    final sender = fromAddress?.trim();
    if (sender != null && sender.isNotEmpty && !isValidTronAddress(sender)) {
      throw const DepositServiceException(
          'BAD_ADDRESS', 'The sender address is not a valid TRON (TRC-20) address.');
    }
    if (proofBytes.lengthInBytes > maxProofBytes) {
      throw const DepositServiceException('PROOF_TOO_LARGE', 'The screenshot must be 10 MB or smaller.');
    }

    try {
      final contentType = _contentTypeFor(proofFileName);
      final proofPath = '$uid/${_uuid.v4()}.${_extFor(contentType)}';
      await _backend.uploadProof(proofPath, proofBytes, contentType);

      final res = _asMap(await _backend.rpc('rpc_submit_deposit_request', {
        'p_amount': amount.toString(),
        'p_txid': hash.isEmpty ? null : normalizeTxid(hash),
        'p_from_address': (sender == null || sender.isEmpty) ? null : sender,
        'p_proof_path': proofPath,
        'p_request_id': requestId ?? 'dep-${_uuid.v4()}',
      }));

      final deposit = res['deposit'];
      if (deposit is! Map) {
        throw const DepositServiceException('RPC_FAILED', 'Unexpected response from the server.');
      }
      return DepositRequest.fromMap(Map<String, dynamic>.from(deposit));
    } catch (e) {
      throw toException(e);
    }
  }

  /// The signed-in user's own requests, newest first.
  Future<List<DepositRequest>> myRequests() async {
    final uid = _requireUser();
    try {
      final rows = await _backend.fetchOwnRequests(uid);
      return rows.map(DepositRequest.fromMap).toList();
    } catch (e) {
      // deposit_requests table not deployed yet -> simply no requests to show.
      final msg = e.toString();
      if (msg.contains('deposit_requests') &&
          (msg.contains('schema cache') || msg.contains('does not exist'))) {
        return const [];
      }
      throw toException(e);
    }
  }

  /// Admin queue (PENDING first). The server refuses non-admin callers.
  Future<List<DepositRequest>> adminList({String? status, int limit = 200}) async {
    try {
      final res = await _backend.rpc('rpc_admin_list_deposit_requests', {
        'p_status': status,
        'p_limit': limit,
      });
      if (res is! List) return const [];
      return [for (final r in res) DepositRequest.fromMap(Map<String, dynamic>.from(r as Map))];
    } catch (e) {
      throw toException(e);
    }
  }

  /// Approve (crediting [amountCredited], the amount actually seen on-chain) or
  /// reject (with a mandatory [reason]).
  Future<DepositReviewResult> review({
    required String depositId,
    required bool approve,
    Decimal? amountCredited,
    String? reason,
    String? adminNote,
  }) async {
    if (approve && (amountCredited == null || amountCredited <= Decimal.zero)) {
      throw const DepositServiceException(
          'BAD_AMOUNT', 'Enter the amount actually received on-chain (greater than zero).');
    }
    if (!approve && (reason == null || reason.trim().isEmpty)) {
      throw const DepositServiceException(
          'REASON_REQUIRED', 'A written reason is required to reject a deposit.');
    }

    try {
      final res = _asMap(await _backend.rpc('rpc_review_deposit', {
        'p_deposit_id': depositId,
        'p_approve': approve,
        'p_amount_credited': approve ? amountCredited.toString() : null,
        'p_reason': approve ? null : reason!.trim(),
        'p_admin_note': (adminNote == null || adminNote.trim().isEmpty) ? null : adminNote.trim(),
      }));
      final deposit = res['deposit'];
      if (deposit is! Map) {
        throw const DepositServiceException('RPC_FAILED', 'Unexpected response from the server.');
      }
      return DepositReviewResult(
        status: res['status']?.toString() ?? 'success',
        deposit: DepositRequest.fromMap(Map<String, dynamic>.from(deposit)),
        newBalance: res['new_balance'] == null ? null : MoneyMath.toDec(res['new_balance']),
        message: res['message']?.toString(),
      );
    } catch (e) {
      throw toException(e);
    }
  }

  /// Short-lived signed URL for a proof in the private bucket.
  Future<String?> proofUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      return await _backend.signedProofUrl(path, expiresInSeconds: 600);
    } catch (_) {
      return null;
    }
  }
}
