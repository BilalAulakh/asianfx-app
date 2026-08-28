import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Models ────────────────────────────────────────────────────────────────────
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
  });

  AdminTransaction copyWith({AdminTxStatus? status}) {
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
}

// ── Admin State ───────────────────────────────────────────────────────────────
class AdminState {
  final List<AdminTransaction> transactions;
  final List<AdminKycItem> kycRequests;
  final List<AdminTraderUser> users;
  final double spreadMultiplier;
  final int maxLeverage;
  final bool isTradingHalted;
  final bool isAdminModeActive;

  const AdminState({
    this.transactions = const [],
    this.kycRequests = const [],
    this.users = const [],
    this.spreadMultiplier = 1.0,
    this.maxLeverage = 500,
    this.isTradingHalted = false,
    this.isAdminModeActive = true,
  });

  // KPI Computations
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
  }) {
    return AdminState(
      transactions: transactions ?? this.transactions,
      kycRequests: kycRequests ?? this.kycRequests,
      users: users ?? this.users,
      spreadMultiplier: spreadMultiplier ?? this.spreadMultiplier,
      maxLeverage: maxLeverage ?? this.maxLeverage,
      isTradingHalted: isTradingHalted ?? this.isTradingHalted,
      isAdminModeActive: isAdminModeActive ?? this.isAdminModeActive,
    );
  }
}

// ── Admin Notifier ────────────────────────────────────────────────────────────
class AdminNotifier extends StateNotifier<AdminState> {
  AdminNotifier() : super(const AdminState()) {
    _loadInitialData();
  }

  void _loadInitialData() {
    final now = DateTime.now();
    state = AdminState(
      transactions: [
        AdminTransaction(
          id: 'TX-9482',
          userId: 'usr_101',
          userName: 'Muhammad Ali',
          userEmail: 'ali.trader@gmail.com',
          type: 'DEPOSIT',
          amount: 500.0,
          method: 'Easypaisa / Bank',
          accountOrAddress: '0300-1234567 (TID: 8847291)',
          status: AdminTxStatus.pending,
          createdAt: now.subtract(const Duration(minutes: 15)),
        ),
        AdminTransaction(
          id: 'TX-9481',
          userId: 'usr_102',
          userName: 'Hamza Tariq',
          userEmail: 'hamza.fx@outlook.com',
          type: 'DEPOSIT',
          amount: 1250.0,
          method: 'USDT (TRC20)',
          accountOrAddress: 'TXz7aQ...98f4K (TxHash Verified)',
          status: AdminTxStatus.pending,
          createdAt: now.subtract(const Duration(hours: 1)),
        ),
        AdminTransaction(
          id: 'TX-9480',
          userId: 'usr_103',
          userName: 'Zubair Khan',
          userEmail: 'zubair.khan@gmail.com',
          type: 'WITHDRAWAL',
          amount: 350.0,
          method: 'JazzCash',
          accountOrAddress: '0321-9876543',
          status: AdminTxStatus.pending,
          createdAt: now.subtract(const Duration(hours: 3)),
        ),
        AdminTransaction(
          id: 'TX-9475',
          userId: 'usr_104',
          userName: 'Bilal Ahmed',
          userEmail: 'bilal@asianfx.com',
          type: 'DEPOSIT',
          amount: 3000.0,
          method: 'Bank Wire (Meezan Bank)',
          accountOrAddress: 'PK82MEZN0001092837482',
          status: AdminTxStatus.approved,
          createdAt: now.subtract(const Duration(days: 1)),
        ),
      ],
      kycRequests: [
        AdminKycItem(
          id: 'KYC-501',
          userId: 'usr_101',
          userName: 'Muhammad Ali',
          userEmail: 'ali.trader@gmail.com',
          docType: 'CNIC / National ID',
          docNumber: '35201-8392019-1',
          status: AdminKycStatus.pending,
          submittedAt: now.subtract(const Duration(minutes: 45)),
        ),
        AdminKycItem(
          id: 'KYC-502',
          userId: 'usr_105',
          userName: 'Usman Farooq',
          userEmail: 'usman.f@gmail.com',
          docType: 'Passport',
          docNumber: 'PK89230192',
          status: AdminKycStatus.pending,
          submittedAt: now.subtract(const Duration(hours: 4)),
        ),
      ],
      users: [
        AdminTraderUser(
          id: 'usr_101',
          name: 'Muhammad Ali',
          email: 'ali.trader@gmail.com',
          phone: '+92 300 1234567',
          balance: 2450.00,
          equity: 2510.50,
          isKycVerified: false,
          status: AdminUserStatus.active,
          joinedAt: now.subtract(const Duration(days: 14)),
        ),
        AdminTraderUser(
          id: 'usr_102',
          name: 'Hamza Tariq',
          email: 'hamza.fx@outlook.com',
          phone: '+92 321 5554321',
          balance: 5820.00,
          equity: 6100.00,
          isKycVerified: true,
          status: AdminUserStatus.active,
          joinedAt: now.subtract(const Duration(days: 30)),
        ),
        AdminTraderUser(
          id: 'usr_103',
          name: 'Zubair Khan',
          email: 'zubair.khan@gmail.com',
          phone: '+92 333 7891234',
          balance: 890.00,
          equity: 890.00,
          isKycVerified: true,
          status: AdminUserStatus.active,
          joinedAt: now.subtract(const Duration(days: 45)),
        ),
        AdminTraderUser(
          id: 'usr_104',
          name: 'Bilal Ahmed',
          email: 'bilal@asianfx.com',
          phone: '+92 301 9998877',
          balance: 14500.00,
          equity: 15120.00,
          isKycVerified: true,
          status: AdminUserStatus.active,
          joinedAt: now.subtract(const Duration(days: 60)),
        ),
      ],
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────────────
  void addTraderUser(AdminTraderUser user) {
    // Check if user already exists
    final exists = state.users.any((u) => u.id == user.id || u.email.toLowerCase() == user.email.toLowerCase());
    if (!exists) {
      state = state.copyWith(users: [user, ...state.users]);
    }
  }

  void addTransactionRequest(AdminTransaction tx) {
    state = state.copyWith(transactions: [tx, ...state.transactions]);
  }

  void addKycRequest(AdminKycItem kyc) {
    state = state.copyWith(kycRequests: [kyc, ...state.kycRequests]);
  }

  void approveTransaction(String id) {
    AdminTransaction? targetTx;
    final updatedList = state.transactions.map((tx) {
      if (tx.id == id) {
        targetTx = tx;
        return tx.copyWith(status: AdminTxStatus.approved);
      }
      return tx;
    }).toList();

    // If it was a deposit or withdrawal, adjust the user's balance in the admin user record
    if (targetTx != null) {
      final delta = targetTx!.type == 'DEPOSIT' ? targetTx!.amount : -targetTx!.amount;
      final updatedUsers = state.users.map((u) {
        if (u.id == targetTx!.userId || u.email == targetTx!.userEmail) {
          final newBal = (u.balance + delta).clamp(0.0, 10000000.0);
          return u.copyWith(balance: newBal, equity: newBal);
        }
        return u;
      }).toList();

      state = state.copyWith(
        transactions: updatedList,
        users: updatedUsers,
      );
    } else {
      state = state.copyWith(transactions: updatedList);
    }
  }

  void rejectTransaction(String id) {
    state = state.copyWith(
      transactions: state.transactions.map((tx) {
        if (tx.id == id) {
          return tx.copyWith(status: AdminTxStatus.rejected);
        }
        return tx;
      }).toList(),
    );
  }

  void approveKyc(String kycId, String userId) {
    state = state.copyWith(
      kycRequests: state.kycRequests.map((k) {
        if (k.id == kycId) return k.copyWith(status: AdminKycStatus.approved);
        return k;
      }).toList(),
      users: state.users.map((u) {
        if (u.id == userId) return u.copyWith(isKycVerified: true);
        return u;
      }).toList(),
    );
  }

  void rejectKyc(String kycId) {
    state = state.copyWith(
      kycRequests: state.kycRequests.map((k) {
        if (k.id == kycId) return k.copyWith(status: AdminKycStatus.rejected);
        return k;
      }).toList(),
    );
  }

  void toggleUserFreeze(String userId) {
    state = state.copyWith(
      users: state.users.map((u) {
        if (u.id == userId) {
          final newStatus = u.status == AdminUserStatus.active
              ? AdminUserStatus.frozen
              : AdminUserStatus.active;
          return u.copyWith(status: newStatus);
        }
        return u;
      }).toList(),
    );
  }

  void adjustUserBalance(String userId, double delta) {
    state = state.copyWith(
      users: state.users.map((u) {
        if (u.id == userId) {
          final newBal = (u.balance + delta).clamp(0.0, 1000000.0);
          return u.copyWith(balance: newBal, equity: newBal);
        }
        return u;
      }).toList(),
    );
  }

  void setSpreadMultiplier(double multiplier) {
    state = state.copyWith(spreadMultiplier: multiplier);
  }

  void setMaxLeverage(int leverage) {
    state = state.copyWith(maxLeverage: leverage);
  }

  void toggleTradingHalt() {
    state = state.copyWith(isTradingHalted: !state.isTradingHalted);
  }
}

final adminProvider = StateNotifierProvider<AdminNotifier, AdminState>((ref) {
  return AdminNotifier();
});

