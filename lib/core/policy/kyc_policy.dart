import 'package:flutter/material.dart';
import '../../domain/entities/kyc_entities.dart';
import '../../domain/entities/user_entity.dart';

/// Centralized Institutional Compliance & Verification Policy
/// Guarantees consistent rules across Trading, Vault, Wallet, and Admin modules.
class KycPolicy {
  KycPolicy._();

  /// Tier limits
  static const double unverifiedDailyDepositLimit = 2000.0;
  static const double verifiedDailyDepositLimit = double.infinity;

  /// Central permission checks
  static bool canTrade(UserEntity? user) {
    if (user == null) return false;
    if (user.role == UserRole.admin) return true;
    // Approved users can trade freely
    if (user.isKycVerified) return user.status == AccountStatus.active;
    // Tier 0 unverified traders have simulated/trial trading permissions
    return user.status == AccountStatus.active;
  }

  static bool canWithdraw(UserEntity? user) {
    if (user == null) return false;
    if (user.role == UserRole.admin) return true;
    // Withdrawals strictly require Level 2 KYC approval for AML compliance
    return user.isKycVerified && user.status == AccountStatus.active;
  }

  static bool canDeposit(UserEntity? user, double amount) {
    if (user == null) return false;
    if (user.role == UserRole.admin) return true;
    if (user.isKycVerified) return true;
    // Unverified limit check
    return amount <= unverifiedDailyDepositLimit;
  }

  /// Status badge colors
  static Color getStatusColor(KycVerificationStatus status) {
    switch (status) {
      case KycVerificationStatus.notStarted:
        return const Color(0xFF848E9C);
      case KycVerificationStatus.inProgress:
        return const Color(0xFF3B82F6); // Blue
      case KycVerificationStatus.pendingReview:
        return const Color(0xFFFFC700); // Amber
      case KycVerificationStatus.approved:
        return const Color(0xFF0ECB81); // Emerald Green
      case KycVerificationStatus.rejected:
        return const Color(0xFFFF4757); // Coral Red
      case KycVerificationStatus.resubmissionRequired:
        return const Color(0xFFFF9800); // Deep Orange
    }
  }

  /// Status explanation messaging
  static String getStatusExplanation(
    KycVerificationStatus status, {
    String? rejectionReason,
    String? resubmissionNotes,
  }) {
    switch (status) {
      case KycVerificationStatus.notStarted:
        return 'Your verification has not been started. Complete your identity verification profile to unlock unlimited withdrawals and Tier 2 leverage.';
      case KycVerificationStatus.inProgress:
        return 'Your KYC verification draft is in progress. Complete all steps and submit for compliance review.';
      case KycVerificationStatus.pendingReview:
        return 'Your verification request has been submitted and is currently under review by our compliance team. Verification is typically completed within 24 hours.';
      case KycVerificationStatus.approved:
        return 'Your account is Fully Verified (Level 2). Zero deposit or withdrawal restrictions apply.';
      case KycVerificationStatus.rejected:
        return rejectionReason != null && rejectionReason.isNotEmpty
            ? 'Verification Rejected: $rejectionReason. You may correct your profile and re-apply.'
            : 'Your verification request could not be approved due to compliance criteria. Please review your details and re-apply.';
      case KycVerificationStatus.resubmissionRequired:
        return resubmissionNotes != null && resubmissionNotes.isNotEmpty
            ? 'Action Required: $resubmissionNotes. Please replace the requested document(s) and resubmit.'
            : 'Some documents require re-upload. Please update the flagged documents and submit again.';
    }
  }

  /// Map old KycStatus to modern KycVerificationStatus
  static KycVerificationStatus mapFromUser(UserEntity? user) {
    if (user == null) return KycVerificationStatus.notStarted;
    if (user.role == UserRole.admin) return KycVerificationStatus.approved;
    if (user.isKycVerified) return KycVerificationStatus.approved;

    switch (user.kycStatus) {
      case KycStatus.notSubmitted:
        return KycVerificationStatus.notStarted;
      case KycStatus.pending:
        return KycVerificationStatus.pendingReview;
      case KycStatus.approved:
        return KycVerificationStatus.approved;
      case KycStatus.rejected:
        return KycVerificationStatus.rejected;
      case KycStatus.restricted:
        return KycVerificationStatus.resubmissionRequired;
    }
  }
}
