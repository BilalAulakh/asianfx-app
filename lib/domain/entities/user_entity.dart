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
  final int kycTier;
  final String? employmentStatus;
  final String? tradingExperience;
  final String? annualIncome;
  final String? streetAddress;
  final String? city;
  final String? postalCode;
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
    this.kycStatus = KycStatus.notSubmitted,
    this.status = AccountStatus.active,
    this.role = UserRole.client,
    this.isTwoFactorEnabled = false,
    this.isEmailVerified = true,
    this.isPhoneVerified = true,
    this.kycDocumentType,
    this.kycDocumentNumber,
    this.kycRejectionReason,
    this.kycSubmittedAt,
    this.kycTier = 0,
    this.employmentStatus,
    this.tradingExperience,
    this.annualIncome,
    this.streetAddress,
    this.city,
    this.postalCode,
    required this.createdAt,
  });

  bool get isKycVerified => kycStatus == KycStatus.approved;
  bool get isActive => status == AccountStatus.active;
  bool get canTrade => isKycVerified && status == AccountStatus.active;
  bool get canWithdraw => status == AccountStatus.active;

  int get effectiveKycTier => kycTier > 0 ? kycTier : (isKycVerified ? 2 : 0);

  String get kycTierDisplay {
    switch (effectiveKycTier) {
      case 2:
        return 'Level 2 (Fully Verified)';
      case 1:
        return 'Level 1 (Identity Verified)';
      default:
        return 'Unverified';
    }
  }

  String get depositLimitDisplay {
    switch (effectiveKycTier) {
      case 2:
        return 'Unlimited';
      case 1:
        return '\$10,000 / day';
      default:
        return '\$2,000 / day';
    }
  }

  String get withdrawalLimitDisplay {
    switch (effectiveKycTier) {
      case 2:
        return 'Unlimited';
      case 1:
        return '\$5,000 / day';
      default:
        return 'KYC Required';
    }
  }

  String get roleDisplay {
    switch (role) {
      case UserRole.client:
        return 'Trader';
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
    int? kycTier,
    String? employmentStatus,
    String? tradingExperience,
    String? annualIncome,
    String? streetAddress,
    String? city,
    String? postalCode,
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
      kycTier: kycTier ?? this.kycTier,
      employmentStatus: employmentStatus ?? this.employmentStatus,
      tradingExperience: tradingExperience ?? this.tradingExperience,
      annualIncome: annualIncome ?? this.annualIncome,
      streetAddress: streetAddress ?? this.streetAddress,
      city: city ?? this.city,
      postalCode: postalCode ?? this.postalCode,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  UserEntity resetKyc() {
    return UserEntity(
      id: id,
      email: email,
      phone: phone,
      fullName: fullName,
      avatarUrl: avatarUrl,
      country: country,
      nationality: nationality,
      dateOfBirth: dateOfBirth,
      preferredCurrency: preferredCurrency,
      preferredLanguage: preferredLanguage,
      kycStatus: KycStatus.notSubmitted,
      status: status,
      role: role,
      isTwoFactorEnabled: isTwoFactorEnabled,
      isEmailVerified: isEmailVerified,
      isPhoneVerified: isPhoneVerified,
      kycDocumentType: null,
      kycDocumentNumber: null,
      kycRejectionReason: null,
      kycSubmittedAt: null,
      kycTier: 0,
      employmentStatus: null,
      tradingExperience: null,
      annualIncome: null,
      streetAddress: null,
      city: null,
      postalCode: null,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'phone': phone,
      'fullName': fullName,
      'avatarUrl': avatarUrl,
      'country': country,
      'nationality': nationality,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'preferredCurrency': preferredCurrency,
      'preferredLanguage': preferredLanguage,
      'kycStatus': kycStatus.name,
      'status': status.name,
      'role': role.name,
      'isTwoFactorEnabled': isTwoFactorEnabled,
      'isEmailVerified': isEmailVerified,
      'isPhoneVerified': isPhoneVerified,
      'kycDocumentType': kycDocumentType,
      'kycDocumentNumber': kycDocumentNumber,
      'kycRejectionReason': kycRejectionReason,
      'kycSubmittedAt': kycSubmittedAt?.toIso8601String(),
      'kycTier': kycTier,
      'employmentStatus': employmentStatus,
      'tradingExperience': tradingExperience,
      'annualIncome': annualIncome,
      'streetAddress': streetAddress,
      'city': city,
      'postalCode': postalCode,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory UserEntity.fromMap(Map<String, dynamic> map) {
    return UserEntity(
      id: map['id'] as String? ?? 'usr_001',
      email: map['email'] as String? ?? '',
      phone: map['phone'] as String?,
      fullName: map['fullName'] as String? ?? 'Trader',
      avatarUrl: map['avatarUrl'] as String?,
      country: map['country'] as String? ?? 'Pakistan',
      nationality: map['nationality'] as String? ?? 'Pakistani',
      dateOfBirth: map['dateOfBirth'] != null ? DateTime.tryParse(map['dateOfBirth'] as String) : null,
      preferredCurrency: map['preferredCurrency'] as String? ?? 'USD',
      preferredLanguage: map['preferredLanguage'] as String? ?? 'en',
      kycStatus: KycStatus.values.firstWhere(
        (k) => k.name == map['kycStatus'],
        orElse: () => KycStatus.notSubmitted,
      ),
      status: AccountStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => AccountStatus.active,
      ),
      role: UserRole.values.firstWhere(
        (r) => r.name == map['role'],
        orElse: () => UserRole.client,
      ),
      isTwoFactorEnabled: map['isTwoFactorEnabled'] as bool? ?? false,
      isEmailVerified: map['isEmailVerified'] as bool? ?? true,
      isPhoneVerified: map['isPhoneVerified'] as bool? ?? true,
      kycDocumentType: map['kycDocumentType'] as String?,
      kycDocumentNumber: map['kycDocumentNumber'] as String?,
      kycRejectionReason: map['kycRejectionReason'] as String?,
      kycSubmittedAt: map['kycSubmittedAt'] != null ? DateTime.tryParse(map['kycSubmittedAt'] as String) : null,
      kycTier: map['kycTier'] as int? ?? 0,
      employmentStatus: map['employmentStatus'] as String?,
      tradingExperience: map['tradingExperience'] as String?,
      annualIncome: map['annualIncome'] as String?,
      streetAddress: map['streetAddress'] as String?,
      city: map['city'] as String?,
      postalCode: map['postalCode'] as String?,
      createdAt: map['createdAt'] != null ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now() : DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
        id, email, phone, fullName, avatarUrl, country, nationality,
        dateOfBirth, preferredCurrency, preferredLanguage, kycStatus,
        status, role, isTwoFactorEnabled, isEmailVerified, isPhoneVerified,
        kycDocumentType, kycDocumentNumber, kycRejectionReason, kycSubmittedAt,
        kycTier, employmentStatus, tradingExperience, annualIncome, streetAddress, city, postalCode,
        createdAt,
      ];
}
