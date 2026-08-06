import 'package:equatable/equatable.dart';

enum UserRole { user, vip, admin }
enum KycStatus { notSubmitted, pending, approved, rejected }
enum AccountStatus { active, suspended, restricted }

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
    this.role = UserRole.user,
    this.isTwoFactorEnabled = false,
    this.isEmailVerified = false,
    this.isPhoneVerified = false,
    required this.createdAt,
  });

  bool get isKycVerified => kycStatus == KycStatus.approved;
  bool get isActive => status == AccountStatus.active;

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
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id, email, phone, fullName, avatarUrl, country, nationality,
        dateOfBirth, preferredCurrency, preferredLanguage, kycStatus,
        status, role, isTwoFactorEnabled, isEmailVerified, isPhoneVerified,
        createdAt,
      ];
}
