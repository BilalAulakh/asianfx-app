import 'package:equatable/equatable.dart';

/// Institutional RBAC Roles
enum UserRole {
  client,      // Multi-Asset & Gold Trader
  admin,       // Super Administrator
  compliance,  // AML & KYC Verification Officer
  operations,  // Operational hold & client lifecycle manager
  finance,     // Treasury & Double-Entry Ledger Auditor
  dealer,      // Chief Dealer & Risk Manager (Spread markup & B-Book)
}

/// KYC Verification Lifecycle
enum KycStatus {
  notSubmitted,
  pending,
  approved,
  rejected,
  restricted,
}

enum AccountStatus {
  active,
  frozen,
  restricted,
  suspended,
}

class UserEntity extends Equatable {
  final String id;
  final String email;
  final String? phone;
  final String fullName;
  final String? avatarUrl;
  final String? country;
  final String? nationality;
  final DateTime? dateOfBirth;
  final String preferredCurrency;
  final String preferredLanguage;
  final KycStatus kycStatus;
  final AccountStatus status;
  final UserRole role;
  final bool isTwoFactorEnabled;
  final bool isEmailVerified;
  final bool isPhoneVerified;
  final String? kycDocumentType;
  final String? kycDocumentNumber;
  final String? kycRejectionReason;
  final DateTime? kycSubmittedAt;
  final DateTime createdAt;

  const UserEntity({
    required this.id,
    required this.email,
    this.phone,
    required this.fullName,
    this.avatarUrl,
    this.country,
    this.nationality,
    this.dateOfBirth,
    this.preferredCurrency = 'USD',
    this.preferredLanguage = 'en',
    this.kycStatus = KycStatus.approved,
    this.status = AccountStatus.active,
    this.role = UserRole.client,
    this.isTwoFactorEnabled = false,
    this.isEmailVerified = true,
    this.isPhoneVerified = true,
    this.kycDocumentType,
    this.kycDocumentNumber,
    this.kycRejectionReason,
    this.kycSubmittedAt,
    required this.createdAt,
  });

  bool get isKycVerified => kycStatus == KycStatus.approved;
  bool get isActive => status == AccountStatus.active;
  bool get canTrade => isKycVerified && status == AccountStatus.active;
  bool get canWithdraw => isKycVerified && status == AccountStatus.active;

  String get roleDisplay {
    switch (role) {
      case UserRole.client:
        return 'Institutional Trader';
      case UserRole.admin:
        return 'Super Administrator';
      case UserRole.compliance:
        return 'Compliance & AML Officer';
      case UserRole.operations:
        return 'Operations Manager';
      case UserRole.finance:
        return 'Treasury & Finance Auditor';
      case UserRole.dealer:
        return 'Chief Dealer & Risk Manager';
    }
  }

  String get kycStatusDisplay {
    switch (kycStatus) {
      case KycStatus.notSubmitted:
        return 'Not Submitted';
      case KycStatus.pending:
        return 'Under Review';
      case KycStatus.approved:
        return 'Verified (Approved)';
      case KycStatus.rejected:
        return 'Verification Rejected';
      case KycStatus.restricted:
        return 'Account Restricted';
    }
  }

  UserEntity copyWith({
    String? id,
    String? email,
    String? phone,
    String? fullName,
    String? avatarUrl,
    String? country,
    String? nationality,
    DateTime? dateOfBirth,
    String? preferredCurrency,
    String? preferredLanguage,
    KycStatus? kycStatus,
    AccountStatus? status,
    UserRole? role,
    bool? isTwoFactorEnabled,
    bool? isEmailVerified,
    bool? isPhoneVerified,
    String? kycDocumentType,
    String? kycDocumentNumber,
    String? kycRejectionReason,
    DateTime? kycSubmittedAt,
    DateTime? createdAt,
  }) {
    return UserEntity(
      id: id ?? this.id,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      country: country ?? this.country,
      nationality: nationality ?? this.nationality,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      preferredCurrency: preferredCurrency ?? this.preferredCurrency,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      kycStatus: kycStatus ?? this.kycStatus,
      status: status ?? this.status,
      role: role ?? this.role,
      isTwoFactorEnabled: isTwoFactorEnabled ?? this.isTwoFactorEnabled,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      isPhoneVerified: isPhoneVerified ?? this.isPhoneVerified,
      kycDocumentType: kycDocumentType ?? this.kycDocumentType,
      kycDocumentNumber: kycDocumentNumber ?? this.kycDocumentNumber,
      kycRejectionReason: kycRejectionReason ?? this.kycRejectionReason,
      kycSubmittedAt: kycSubmittedAt ?? this.kycSubmittedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id, email, phone, fullName, avatarUrl, country, nationality,
        dateOfBirth, preferredCurrency, preferredLanguage, kycStatus,
        status, role, isTwoFactorEnabled, isEmailVerified, isPhoneVerified,
        kycDocumentType, kycDocumentNumber, kycRejectionReason, kycSubmittedAt,
        createdAt,
      ];
}
