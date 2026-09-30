import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Structured result returned from the verify-trc20-deposit Edge Function.
class DepositVerificationResult {
  final bool success;
  final bool verified;
  final String message;
  final String? txid;
  final double? amount;
  final String? currency;
  final String? network;
  final double? newBalance;

  const DepositVerificationResult({
    required this.success,
    required this.verified,
    required this.message,
    this.txid,
    this.amount,
    this.currency,
    this.network,
    this.newBalance,
  });

  factory DepositVerificationResult.fromJson(Map<String, dynamic> json) {
    return DepositVerificationResult(
      success: json['success'] == true,
      verified: json['verified'] == true,
      message: json['message']?.toString() ?? 'Verification processed.',
      txid: json['txid']?.toString(),
      amount: (json['amount'] as num?)?.toDouble(),
      currency: json['currency']?.toString(),
      network: json['network']?.toString(),
      newBalance: (json['newBalance'] as num?)?.toDouble(),
    );
  }

  factory DepositVerificationResult.failure(String message) {
    return DepositVerificationResult(
      success: false,
      verified: false,
      message: message,
    );
  }

  @override
  String toString() =>
      'DepositVerificationResult(success: $success, verified: $verified, message: $message, amount: $amount, newBalance: $newBalance)';
}

/// Client-side Service to trigger server-side Tatum TRON USDT TRC-20 verification.
///
/// SECURITY ARCHITECTURE:
/// - NEVER includes the TATUM_API_KEY in Dart/client code.
/// - The Tatum API key resides strictly in the Supabase Edge Function environment.
/// - Passes only the user's verification claim: [txid], [expectedAmount], [depositAddress], and [userId].
/// - The Edge Function independently queries TRON mainnet via Tatum and performs atomic database settlement.
class SupabaseDepositService {
  static final SupabaseDepositService instance = SupabaseDepositService._();
  SupabaseDepositService._();

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Call Supabase Edge Function: `verify-trc20-deposit`
  Future<DepositVerificationResult> verifyTrc20Deposit({
    required String txid,
    required double expectedAmount,
    required String depositAddress,
    required String userId,
  }) async {
    final client = _client;
    if (client == null) {
      return DepositVerificationResult.failure(
        'Supabase client is not initialized.',
      );
    }

    final cleanTxid = txid.trim();
    if (cleanTxid.isEmpty || cleanTxid.length != 64) {
      return DepositVerificationResult.failure(
        'Invalid TXID format. TRON transaction hashes must be 64 hexadecimal characters.',
      );
    }

    if (expectedAmount <= 0) {
      return DepositVerificationResult.failure(
        'Expected deposit amount must be greater than zero.',
      );
    }

    try {
      final response = await client.functions.invoke(
        'verify-trc20-deposit',
        body: {
          'txid': cleanTxid,
          'expectedAmount': expectedAmount,
          'depositAddress': depositAddress.trim(),
          'userId': userId,
        },
      );

      final dynamic responseData = response.data;
      if (responseData is Map<String, dynamic>) {
        return DepositVerificationResult.fromJson(responseData);
      } else if (responseData is String) {
        try {
          final decoded = jsonDecode(responseData) as Map<String, dynamic>;
          return DepositVerificationResult.fromJson(decoded);
        } catch (_) {
          return DepositVerificationResult.failure(responseData);
        }
      }

      return DepositVerificationResult.failure(
        'Unexpected response format from verification server.',
      );
    } on FunctionException catch (e) {
      debugPrint('[SupabaseDepositService] FunctionException: status=${e.status}, details=${e.details}');
      String errorMessage = 'Verification failed (${e.status}).';

      final details = e.details;
      if (details is Map<String, dynamic> && details.containsKey('message')) {
        errorMessage = details['message'].toString();
      } else if (details is String && details.isNotEmpty) {
        try {
          final decoded = jsonDecode(details);
          if (decoded is Map && decoded.containsKey('message')) {
            errorMessage = decoded['message'].toString();
          } else {
            errorMessage = details;
          }
        } catch (_) {
          errorMessage = details;
        }
      }

      return DepositVerificationResult.failure(errorMessage);
    } catch (e) {
      debugPrint('[SupabaseDepositService] Unexpected error: $e');
      return DepositVerificationResult.failure(
        'Network error while verifying deposit. Please check your internet connection.',
      );
    }
  }
}
