import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/entities/user_entity.dart';
import 'auth_provider.dart';

class KycApplication {
  final String id;
  final String userId;
  final String fullName;
  final String email;
  final String country;
  final String documentType; // 'Passport', 'National ID (CNIC)', 'Driving License'
  final String documentNumber;
  final String? frontDocUrl;
  final String? backDocUrl;
  final String? proofOfAddressUrl;
  final KycStatus status;
  final String? rejectionReason;
  final DateTime submittedAt;

  const KycApplication({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.country,
    required this.documentType,
    required this.documentNumber,
    this.frontDocUrl,
    this.backDocUrl,
    this.proofOfAddressUrl,
    this.status = KycStatus.pending,
    this.rejectionReason,
    required this.submittedAt,
  });

  KycApplication copyWith({
    KycStatus? status,
    String? rejectionReason,
  }) {
    return KycApplication(
      id: id,
      userId: userId,
      fullName: fullName,
      email: email,
      country: country,
      documentType: documentType,
      documentNumber: documentNumber,
      frontDocUrl: frontDocUrl,
      backDocUrl: backDocUrl,
      proofOfAddressUrl: proofOfAddressUrl,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      submittedAt: submittedAt,
    );
  }
}

class ComplianceState {
  final List<KycApplication> pendingApplications;
  final List<KycApplication> processedApplications;
  final List<String> highRiskAmlAlerts;

  const ComplianceState({
    this.pendingApplications = const [],
    this.processedApplications = const [],
    this.highRiskAmlAlerts = const [],
  });

  ComplianceState copyWith({
    List<KycApplication>? pendingApplications,
    List<KycApplication>? processedApplications,
    List<String>? highRiskAmlAlerts,
  }) {
    return ComplianceState(
      pendingApplications: pendingApplications ?? this.pendingApplications,
      processedApplications: processedApplications ?? this.processedApplications,
      highRiskAmlAlerts: highRiskAmlAlerts ?? this.highRiskAmlAlerts,
    );
  }
}

class KycComplianceNotifier extends StateNotifier<ComplianceState> {
  final Ref _ref;

  KycComplianceNotifier(this._ref)
      : super(
          ComplianceState(
            pendingApplications: [
              KycApplication(
                id: 'KYC-APP-901',
                userId: 'usr_client_02',
                fullName: 'Alexander Wright',
                email: 'a.wright@hedgefund.uk',
                country: 'United Kingdom',
                documentType: 'Passport',
                documentNumber: 'GB98234101',
                status: KycStatus.pending,
                submittedAt: DateTime.now().subtract(const Duration(minutes: 45)),
              ),
              KycApplication(
                id: 'KYC-APP-902',
                userId: 'usr_client_03',
                fullName: 'Mei-Ling Chen',
                email: 'chen.trader@singapore.sg',
                country: 'Singapore',
                documentType: 'National ID (NRIC)',
                documentNumber: 'S8834921D',
                status: KycStatus.pending,
                submittedAt: DateTime.now().subtract(const Duration(hours: 2)),
              ),
            ],
            processedApplications: [
              KycApplication(
                id: 'KYC-APP-900',
                userId: 'usr_institutional_01',
                fullName: 'Institutional Master Account',
                email: 'desk@asianfx.institutional',
                country: 'United Arab Emirates',
                documentType: 'Institutional Trade License',
                documentNumber: 'DMCC-982140',
                status: KycStatus.approved,
                submittedAt: DateTime.now().subtract(const Duration(days: 10)),
              ),
            ],
            highRiskAmlAlerts: [
              'AML Alert: High velocity deposits detected on Account #9802 (\$100k aggregate in 2h)',
              'PEP Screening Match: Cleared Tier-1 background verification for Client #900',
            ],
          ),
        );

  void approveKyc(String applicationId) {
    final idx = state.pendingApplications.indexWhere((a) => a.id == applicationId);
    if (idx == -1) return;

    final app = state.pendingApplications[idx];
    final updatedApp = app.copyWith(status: KycStatus.approved);

    final updatedPending = List<KycApplication>.from(state.pendingApplications)..removeAt(idx);
    state = state.copyWith(
      pendingApplications: updatedPending,
      processedApplications: [updatedApp, ...state.processedApplications],
    );

    // If current logged-in user matches, update their KYC status in authProvider
    final currentUser = _ref.read(authProvider).user;
    if (currentUser != null && currentUser.id == app.userId) {
      _ref.read(authProvider.notifier).updateUserKyc(KycStatus.approved);
    }
  }

  void rejectKyc(String applicationId, String reason) {
    final idx = state.pendingApplications.indexWhere((a) => a.id == applicationId);
    if (idx == -1) return;

    final app = state.pendingApplications[idx];
    final updatedApp = app.copyWith(
      status: KycStatus.rejected,
      rejectionReason: reason,
    );

    final updatedPending = List<KycApplication>.from(state.pendingApplications)..removeAt(idx);
    state = state.copyWith(
      pendingApplications: updatedPending,
      processedApplications: [updatedApp, ...state.processedApplications],
    );

    final currentUser = _ref.read(authProvider).user;
    if (currentUser != null && currentUser.id == app.userId) {
      _ref.read(authProvider.notifier).updateUserKyc(KycStatus.rejected);
    }
  }

  void restrictAccount(String applicationId) {
    final idx = state.pendingApplications.indexWhere((a) => a.id == applicationId);
    if (idx != -1) {
      final app = state.pendingApplications[idx];
      final updatedApp = app.copyWith(status: KycStatus.restricted);
      final updatedPending = List<KycApplication>.from(state.pendingApplications)..removeAt(idx);
      state = state.copyWith(
        pendingApplications: updatedPending,
        processedApplications: [updatedApp, ...state.processedApplications],
      );
    }
  }

  void submitNewKyc({
    required String documentType,
    required String documentNumber,
  }) {
    final currentUser = _ref.read(authProvider).user;
    if (currentUser == null) return;

    final newApp = KycApplication(
      id: 'KYC-APP-${DateTime.now().millisecondsSinceEpoch}',
      userId: currentUser.id,
      fullName: currentUser.fullName,
      email: currentUser.email,
      country: currentUser.country ?? 'United Arab Emirates',
      documentType: documentType,
      documentNumber: documentNumber,
      status: KycStatus.pending,
      submittedAt: DateTime.now(),
    );

    state = state.copyWith(
      pendingApplications: [newApp, ...state.pendingApplications],
    );

    _ref.read(authProvider.notifier).updateUserKyc(KycStatus.pending);
  }
}

final kycComplianceProvider =
    StateNotifierProvider<KycComplianceNotifier, ComplianceState>((ref) {
  return KycComplianceNotifier(ref);
});
