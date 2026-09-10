import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/security/secure_storage_service.dart';

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
  final String? proofImageName;
  final Uint8List? proofImageBytes;
  final String? txHash;

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
  });

  AdminTransaction copyWith({
    AdminTxStatus? status,
    String? proofImageName,
    Uint8List? proofImageBytes,
    String? txHash,
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
    pruneOldApprovedScreenshots();
  }

  static List<AdminTraderUser> get _defaultBrokersUsers => [
        AdminTraderUser(
          id: 'USR-8921',
          name: 'Ahmad Khan',
          email: 'ahmad.khan@gmail.com',
          phone: '+92 300 1234567',
          balance: 1450.00,
          equity: 1520.40,
          isKycVerified: true,
          status: AdminUserStatus.active,
          joinedAt: DateTime.now().subtract(const Duration(days: 14)),
        ),
        AdminTraderUser(
          id: 'USR-7734',
          name: 'Zeeshan Ali',
          email: 'zeeshan.ali@yahoo.com',
          phone: '+92 321 9876543',
          balance: 820.50,
          equity: 810.00,
          isKycVerified: true,
          status: AdminUserStatus.active,
          joinedAt: DateTime.now().subtract(const Duration(days: 8)),
        ),
        AdminTraderUser(
          id: 'USR-6190',
          name: 'Sara Tariq',
          email: 'sara.tariq@outlook.com',
          phone: '+92 333 4567890',
          balance: 3100.00,
          equity: 3240.10,
          isKycVerified: true,
          status: AdminUserStatus.active,
          joinedAt: DateTime.now().subtract(const Duration(days: 5)),
        ),
        AdminTraderUser(
          id: 'USR-5042',
          name: 'Hamza Malik',
          email: 'hamza.malik@gmail.com',
          phone: '+92 345 7890123',
          balance: 65.64,
          equity: 65.64,
          isKycVerified: false,
          status: AdminUserStatus.active,
          joinedAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
        AdminTraderUser(
          id: 'USR-4819',
          name: 'Usman Farooq',
          email: 'usman.trader@gmail.com',
          phone: '+92 312 3456789',
          balance: 500.00,
          equity: 495.20,
          isKycVerified: false,
          status: AdminUserStatus.active,
          joinedAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ];

  Future<void> _loadInitialData() async {
    // 1. Initial baseline
    state = state.copyWith(
      transactions: [],
      kycRequests: [],
      users: _defaultBrokersUsers,
    );

    // 2. Load any persistent registered users from storage
    try {
      final storedJsonList = await SecureStorageService.instance.getRegisteredTradersJsonList();
      if (storedJsonList.isNotEmpty) {
        final loadedUsers = storedJsonList.map((m) => AdminTraderUser.fromMap(m)).toList();
        final combined = [...loadedUsers];
        for (final def in _defaultBrokersUsers) {
          if (!combined.any((u) => u.email.toLowerCase() == def.email.toLowerCase())) {
            combined.add(def);
          }
        }
        state = state.copyWith(users: combined);
      }
    } catch (e) {
      debugPrint('Error loading saved traders in admin: $e');
    }

    // 3. Query Supabase wallets table for live synced users
    _syncUsersFromSupabase();
  }

  Future<void> _syncUsersFromSupabase() async {
    try {
      final List<dynamic> walletRows = await Supabase.instance.client
          .from('wallets')
          .select('user_id, balance, currency, updated_at');
      
      if (walletRows.isNotEmpty) {
        final currentUsers = List<AdminTraderUser>.from(state.users);
        for (final row in walletRows) {
          final userId = row['user_id']?.toString() ?? '';
          if (userId.isEmpty) continue;
          final bal = (row['balance'] as num?)?.toDouble() ?? 0.0;
          final idx = currentUsers.indexWhere((u) => u.id == userId);
          if (idx >= 0) {
            currentUsers[idx] = currentUsers[idx].copyWith(balance: bal, equity: bal);
          } else {
            currentUsers.insert(
              0,
              AdminTraderUser(
                id: userId,
                name: 'Trader (${userId.substring(0, userId.length > 6 ? 6 : userId.length)})',
                email: 'trader_$userId@asianfx.app',
                phone: '+92 300 0000000',
                balance: bal,
                equity: bal,
                isKycVerified: false,
                status: AdminUserStatus.active,
                joinedAt: DateTime.now(),
              ),
            );
          }
        }
        state = state.copyWith(users: currentUsers);
      }
    } catch (_) {}
  }

  // ── Actions ─────────────────────────────────────────────────────────────────
  void addTraderUser(AdminTraderUser user) {
    // Check if user already exists
    final exists = state.users.any((u) => u.id == user.id || u.email.toLowerCase() == user.email.toLowerCase());
    if (!exists) {
      final updatedList = [user, ...state.users];
      state = state.copyWith(users: updatedList);
      SecureStorageService.instance.saveRegisteredTraderJson(user.toMap());
    } else {
      final updatedList = state.users.map((u) {
        if (u.id == user.id || u.email.toLowerCase() == user.email.toLowerCase()) {
          return user;
        }
        return u;
      }).toList();
      state = state.copyWith(users: updatedList);
      SecureStorageService.instance.saveRegisteredTraderJson(user.toMap());
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

  /// Remove built-in sample demo transactions so admin can see only fresh trader requests
  void clearDemoTransactions() {
    state = state.copyWith(
      transactions: state.transactions.where((tx) => !tx.id.startsWith('TX-948')).toList(),
    );
  }

  /// Clear all transaction list
  void clearAllTransactions() {
    state = state.copyWith(transactions: []);
  }

  /// Automatically prune/delete screenshots of approved transactions older than 3 days
  Future<void> pruneOldApprovedScreenshots({int retentionDays = 3}) async {
    final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
    final List<String> filesToDelete = [];

    final updatedTxs = state.transactions.map((tx) {
      if (tx.status == AdminTxStatus.approved && tx.createdAt.isBefore(cutoff)) {
        if (tx.proofImageName != null && tx.proofImageName!.isNotEmpty) {
          filesToDelete.add(tx.proofImageName!);
        }
        // Remove binary bytes and file name from memory/state to free up space
        return tx.copyWith(
          proofImageBytes: null,
          proofImageName: null,
        );
      }
      return tx;
    }).toList();

    state = state.copyWith(transactions: updatedTxs);

    // Delete matching files from Supabase Storage 'reciept-proof' bucket
    if (filesToDelete.isNotEmpty) {
      try {
        await Supabase.instance.client.storage
            .from('reciept-proof')
            .remove(filesToDelete);
        debugPrint('Auto-pruned ${filesToDelete.length} deposit screenshots older than $retentionDays days.');
      } catch (e) {
        debugPrint('Supabase Storage auto-prune error: $e');
      }
    }
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

