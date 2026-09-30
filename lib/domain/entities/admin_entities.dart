import 'package:flutter/foundation.dart';

// ── Admin Domain Models & Enums ───────────────────────────────────────────────
enum AdminTxStatus { pending, approved, rejected }
enum AdminKycStatus { pending, approved, rejected }
enum AdminUserStatus { active, frozen, suspended }

class AdminTransaction {
  final String id;
  final String userId;
  final String userName;
  final String userEmail;
  final String type; // 'DEPOSIT' or 'WITHDRAWAL'
  final double amount;
  final String currency;
  final String method; // 'USDT (TRC20)', 'Easypaisa', 'JazzCash', 'Bank Transfer'
  final String accountOrAddress;
  final AdminTxStatus status;
  final DateTime createdAt;
  final String? proofImageName;
  final Uint8List? proofImageBytes;
  final String? txHash;
  final bool isAutoApproved;

  const AdminTransaction({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.type,
    required this.amount,
    this.currency = 'USD',
    required this.method,
    required this.accountOrAddress,
    this.status = AdminTxStatus.pending,
    required this.createdAt,
    this.proofImageName,
    this.proofImageBytes,
    this.txHash,
    this.isAutoApproved = false,
  });

  AdminTransaction copyWith({
    AdminTxStatus? status,
    String? proofImageName,
    Uint8List? proofImageBytes,
    String? txHash,
    bool? isAutoApproved,
  }) {
    return AdminTransaction(
      id: id,
      userId: userId,
      userName: userName,
      userEmail: userEmail,
      type: type,
      amount: amount,
      currency: currency,
      method: method,
      accountOrAddress: accountOrAddress,
      status: status ?? this.status,
      createdAt: createdAt,
      proofImageName: proofImageName ?? this.proofImageName,
      proofImageBytes: proofImageBytes ?? this.proofImageBytes,
      txHash: txHash ?? this.txHash,
      isAutoApproved: isAutoApproved ?? this.isAutoApproved,
    );
  }
}

class AdminKycItem {
  final String id;
  final String userId;
  final String userName;
  final String userEmail;
  final String docType; // 'CNIC / National ID', 'Passport', 'Driving License'
  final String docNumber;
  final AdminKycStatus status;
  final DateTime submittedAt;

  const AdminKycItem({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.docType,
    required this.docNumber,
    this.status = AdminKycStatus.pending,
    required this.submittedAt,
  });

  AdminKycItem copyWith({AdminKycStatus? status}) {
    return AdminKycItem(
      id: id,
      userId: userId,
      userName: userName,
      userEmail: userEmail,
      docType: docType,
      docNumber: docNumber,
      status: status ?? this.status,
      submittedAt: submittedAt,
    );
  }
}

class AdminTraderUser {
  final String id;
  final String name;
  final String email;
  final String phone;
  final double balance;
  final double equity;
  final bool isKycVerified;
  final AdminUserStatus status;
  final DateTime joinedAt;

  const AdminTraderUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.balance,
    required this.equity,
    required this.isKycVerified,
    this.status = AdminUserStatus.active,
    required this.joinedAt,
  });

  AdminTraderUser copyWith({
    AdminUserStatus? status,
    double? balance,
    double? equity,
    bool? isKycVerified,
  }) {
    return AdminTraderUser(
      id: id,
      name: name,
      email: email,
      phone: phone,
      balance: balance ?? this.balance,
      equity: equity ?? this.equity,
      isKycVerified: isKycVerified ?? this.isKycVerified,
      status: status ?? this.status,
      joinedAt: joinedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'balance': balance,
      'equity': equity,
      'isKycVerified': isKycVerified,
      'status': status.name,
      'joinedAt': joinedAt.toIso8601String(),
    };
  }

  factory AdminTraderUser.fromMap(Map<String, dynamic> map) {
    return AdminTraderUser(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Trader',
      email: map['email']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
      equity: (map['equity'] as num?)?.toDouble() ?? 0.0,
      isKycVerified: map['isKycVerified'] as bool? ?? false,
      status: AdminUserStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => AdminUserStatus.active,
      ),
      joinedAt: DateTime.tryParse(map['joinedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class AdminState {
  final List<AdminTransaction> transactions;
  final List<AdminKycItem> kycRequests;
  final List<AdminTraderUser> users;
  final double spreadMultiplier;
  final int maxLeverage;
  final bool isTradingHalted;
  final bool isAdminModeActive;
  final bool autoApproveTransactions;

  const AdminState({
    this.transactions = const [],
    this.kycRequests = const [],
    this.users = const [],
    this.spreadMultiplier = 1.0,
    this.maxLeverage = 500,
    this.isTradingHalted = false,
    this.isAdminModeActive = true,
    this.autoApproveTransactions = false,
  });

  // KPI Computations
  int get totalUsersCount => users.length;

  int get activeUsersCount =>
      users.where((u) => u.status == AdminUserStatus.active).length;

  int get verifiedUsersCount =>
      users.where((u) => u.isKycVerified).length;

  int get pendingDepositsCount =>
      transactions.where((t) => t.type == 'DEPOSIT' && t.status == AdminTxStatus.pending).length;

  int get pendingWithdrawalsCount =>
      transactions.where((t) => t.type == 'WITHDRAWAL' && t.status == AdminTxStatus.pending).length;

  int get pendingKycCount =>
      kycRequests.where((k) => k.status == AdminKycStatus.pending).length;

  double get totalDeposited => transactions
      .where((t) => t.type == 'DEPOSIT' && t.status == AdminTxStatus.approved)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get totalWithdrawn => transactions
      .where((t) => t.type == 'WITHDRAWAL' && t.status == AdminTxStatus.approved)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get totalUserFunds =>
      users.fold(0.0, (sum, u) => sum + u.balance);

  AdminState copyWith({
    List<AdminTransaction>? transactions,
    List<AdminKycItem>? kycRequests,
    List<AdminTraderUser>? users,
    double? spreadMultiplier,
    int? maxLeverage,
    bool? isTradingHalted,
    bool? isAdminModeActive,
    bool? autoApproveTransactions,
  }) {
    return AdminState(
      transactions: transactions ?? this.transactions,
      kycRequests: kycRequests ?? this.kycRequests,
      users: users ?? this.users,
      spreadMultiplier: spreadMultiplier ?? this.spreadMultiplier,
      maxLeverage: maxLeverage ?? this.maxLeverage,
      isTradingHalted: isTradingHalted ?? this.isTradingHalted,
      isAdminModeActive: isAdminModeActive ?? this.isAdminModeActive,
      autoApproveTransactions: autoApproveTransactions ?? this.autoApproveTransactions,
    );
  }
}
