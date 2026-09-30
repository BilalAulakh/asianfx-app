import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/security/secure_storage_service.dart';
import '../domain/entities/admin_entities.dart';

export '../domain/entities/admin_entities.dart';

class AdminCubit extends Cubit<AdminState> {
  AdminCubit() : super(const AdminState()) {
    _loadInitialData();
    pruneOldApprovedScreenshots();
  }

  Future<void> _loadInitialData() async {
    emit(state.copyWith(
      transactions: [],
      kycRequests: [],
      users: [],
    ));

    try {
      final storedJsonList = await SecureStorageService.instance.getRegisteredTradersJsonList();
      if (storedJsonList.isNotEmpty) {
        final loadedUsers = storedJsonList.map((m) => AdminTraderUser.fromMap(m)).toList();
        emit(state.copyWith(users: loadedUsers));
      }
    } catch (e) {
      debugPrint('Error loading saved traders in admin: $e');
    }

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
            final shortId = userId.length > 6 ? userId.substring(0, 6) : userId;
            currentUsers.insert(
              0,
              AdminTraderUser(
                id: userId,
                name: 'Trader #$shortId',
                email: 'trader_$shortId@asianfx.app',
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
        emit(state.copyWith(users: currentUsers));
      }
    } catch (_) {}
  }

  void addTraderUser(AdminTraderUser user) {
    final exists = state.users.any((u) => u.id == user.id || u.email.toLowerCase() == user.email.toLowerCase());
    if (!exists) {
      final updatedList = [user, ...state.users];
      emit(state.copyWith(users: updatedList));
      SecureStorageService.instance.saveRegisteredTraderJson(user.toMap());
    } else {
      final updatedList = state.users.map((u) {
        if (u.id == user.id || u.email.toLowerCase() == user.email.toLowerCase()) {
          return user;
        }
        return u;
      }).toList();
      emit(state.copyWith(users: updatedList));
      SecureStorageService.instance.saveRegisteredTraderJson(user.toMap());
    }
  }

  void addTransactionRequest(AdminTransaction tx) {
    final shouldAutoApprove = tx.isAutoApproved && (state.autoApproveTransactions || tx.status == AdminTxStatus.approved);
    final effectiveTx = shouldAutoApprove
        ? tx.copyWith(
            status: AdminTxStatus.approved,
            isAutoApproved: true,
          )
        : tx.copyWith(
            status: AdminTxStatus.pending,
            isAutoApproved: false,
          );

    if (shouldAutoApprove) {
      final delta = effectiveTx.type == 'DEPOSIT' ? effectiveTx.amount : -effectiveTx.amount;
      final updatedUsers = state.users.map((u) {
        if (u.id == effectiveTx.userId || u.email == effectiveTx.userEmail) {
          final newBal = (u.balance + delta).clamp(0.0, 10000000.0);
          return u.copyWith(balance: newBal, equity: newBal);
        }
        return u;
      }).toList();
      emit(state.copyWith(
        transactions: [effectiveTx, ...state.transactions],
        users: updatedUsers,
      ));
    } else {
      emit(state.copyWith(transactions: [effectiveTx, ...state.transactions]));
    }
  }

  void toggleAutoApproveTransactions() {
    emit(state.copyWith(autoApproveTransactions: !state.autoApproveTransactions));
  }

  void addKycRequest(AdminKycItem kyc) {
    final autoApprovedKyc = kyc.copyWith(status: AdminKycStatus.approved);
    final updatedUsers = state.users.map((u) {
      if (u.id == kyc.userId || u.email == kyc.userEmail) {
        return u.copyWith(isKycVerified: true);
      }
      return u;
    }).toList();
    emit(state.copyWith(
      kycRequests: [autoApprovedKyc, ...state.kycRequests],
      users: updatedUsers,
    ));
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

    if (targetTx != null) {
      final delta = targetTx!.type == 'DEPOSIT' ? targetTx!.amount : -targetTx!.amount;
      final updatedUsers = state.users.map((u) {
        if (u.id == targetTx!.userId || u.email == targetTx!.userEmail) {
          final newBal = (u.balance + delta).clamp(0.0, 10000000.0);
          return u.copyWith(balance: newBal, equity: newBal);
        }
        return u;
      }).toList();

      emit(state.copyWith(
        transactions: updatedList,
        users: updatedUsers,
      ));
    } else {
      emit(state.copyWith(transactions: updatedList));
    }
  }

  void rejectTransaction(String id) {
    emit(state.copyWith(
      transactions: state.transactions.map((tx) {
        if (tx.id == id) {
          return tx.copyWith(status: AdminTxStatus.rejected);
        }
        return tx;
      }).toList(),
    ));
  }

  void clearDemoTransactions() {
    emit(state.copyWith(
      transactions: state.transactions.where((tx) => !tx.id.startsWith('TX-948')).toList(),
    ));
  }

  void clearAllTransactions() {
    emit(state.copyWith(transactions: []));
  }

  Future<void> pruneOldApprovedScreenshots({int retentionDays = 3}) async {
    final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
    final List<String> filesToDelete = [];

    final updatedTxs = state.transactions.map((tx) {
      if (tx.status == AdminTxStatus.approved && tx.createdAt.isBefore(cutoff)) {
        if (tx.proofImageName != null && tx.proofImageName!.isNotEmpty) {
          filesToDelete.add(tx.proofImageName!);
        }
        return tx.copyWith(
          proofImageBytes: null,
          proofImageName: null,
        );
      }
      return tx;
    }).toList();

    emit(state.copyWith(transactions: updatedTxs));

    if (filesToDelete.isNotEmpty) {
      try {
        await Supabase.instance.client.storage
            .from('reciept-proof')
            .remove(filesToDelete);
      } catch (_) {}
    }
  }

  void approveKyc(String kycId, String userId) {
    emit(state.copyWith(
      kycRequests: state.kycRequests.map((k) {
        if (k.id == kycId) return k.copyWith(status: AdminKycStatus.approved);
        return k;
      }).toList(),
      users: state.users.map((u) {
        if (u.id == userId) return u.copyWith(isKycVerified: true);
        return u;
      }).toList(),
    ));
  }

  void setTraderKycVerified(String userId, bool isVerified) {
    emit(state.copyWith(
      users: state.users.map((u) {
        if (u.id == userId) return u.copyWith(isKycVerified: isVerified);
        return u;
      }).toList(),
    ));
  }

  void rejectKyc(String kycId) {
    emit(state.copyWith(
      kycRequests: state.kycRequests.map((k) {
        if (k.id == kycId) return k.copyWith(status: AdminKycStatus.rejected);
        return k;
      }).toList(),
    ));
  }

  void updateUserStatus(String userId, AdminUserStatus newStatus) {
    emit(state.copyWith(
      users: state.users.map((u) {
        if (u.id == userId) return u.copyWith(status: newStatus);
        return u;
      }).toList(),
    ));
  }

  void setSpreadMultiplier(double multiplier) {
    emit(state.copyWith(spreadMultiplier: multiplier));
  }

  void setMaxLeverage(int leverage) {
    emit(state.copyWith(maxLeverage: leverage));
  }

  void toggleTradingHalt() {
    emit(state.copyWith(isTradingHalted: !state.isTradingHalted));
  }

  void toggleUserFreeze(String userId) {
    emit(state.copyWith(
      users: state.users.map((u) {
        if (u.id == userId) {
          final newStatus = u.status == AdminUserStatus.active
              ? AdminUserStatus.frozen
              : AdminUserStatus.active;
          return u.copyWith(status: newStatus);
        }
        return u;
      }).toList(),
    ));
  }

  void adjustUserBalance(String userId, double delta) {
    emit(state.copyWith(
      users: state.users.map((u) {
        if (u.id == userId) {
          final newBal = (u.balance + delta).clamp(0.0, 10000000.0);
          return u.copyWith(balance: newBal, equity: newBal);
        }
        return u;
      }).toList(),
    ));
  }

  void setAdminMode(bool active) {
    emit(state.copyWith(isAdminModeActive: active));
  }
}

typedef AdminBloc = AdminCubit;
typedef AdminNotifier = AdminCubit;
