import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/repositories/kyc_repository.dart';
import '../domain/entities/kyc_entities.dart';
import '../domain/entities/user_entity.dart';

// ── Backward-Compatible Legacy Application Record ────────────────────────────
class KycApplication {
  final String id;
  final String userId;
  final String fullName;
  final String email;
  final String country;
  final String documentType;
  final String documentNumber;
  final String? frontDocUrl;
  final String? backDocUrl;
  final String? proofOfAddressUrl;
  final KycStatus status;
  final String? rejectionReason;
  final DateTime submittedAt;
  final int kycTier;
  final String? employmentStatus;
  final String? tradingExperience;
  final String? annualIncome;
  final String? streetAddress;
  final String? city;
  final String? postalCode;
  final String? addressDocType;
  final bool isAutoApproved;

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
    this.kycTier = 2,
    this.employmentStatus,
    this.tradingExperience,
    this.annualIncome,
    this.streetAddress,
    this.city,
    this.postalCode,
    this.addressDocType,
    this.isAutoApproved = false,
  });

  KycApplication copyWith({
    KycStatus? status,
    String? rejectionReason,
    int? kycTier,
    bool? isAutoApproved,
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
      kycTier: kycTier ?? this.kycTier,
      employmentStatus: employmentStatus,
      tradingExperience: tradingExperience,
      annualIncome: annualIncome,
      streetAddress: streetAddress,
      city: city,
      postalCode: postalCode,
      addressDocType: addressDocType,
      isAutoApproved: isAutoApproved ?? this.isAutoApproved,
    );
  }
}

// ── State ────────────────────────────────────────────────────────────────────
class KycState {
  final List<KycApplication> pendingApplications;
  final List<KycApplication> processedApplications;
  final List<String> highRiskAmlAlerts;
  final bool isSubmitting;
  final bool isUploadingDocument;
  final double uploadProgress;
  final String? error;
  final String? successMessage;

  // Modern KYC Profile & Compliance Queue
  final KycProfileEntity? currentProfile;
  final List<KycProfileEntity> adminProfiles;
  final KycVerificationStatus? adminFilterStatus;
  final String? adminSearchQuery;
  final String? adminCountryFilter;
  final KycProfileEntity? selectedAdminProfile;
  final List<KycAuditLogEntry> auditLogs;

  const KycState({
    this.pendingApplications = const [],
    this.processedApplications = const [],
    this.highRiskAmlAlerts = const [],
    this.isSubmitting = false,
    this.isUploadingDocument = false,
    this.uploadProgress = 0.0,
    this.error,
    this.successMessage,
    this.currentProfile,
    this.adminProfiles = const [],
    this.adminFilterStatus,
    this.adminSearchQuery,
    this.adminCountryFilter,
    this.selectedAdminProfile,
    this.auditLogs = const [],
  });

  KycProfileEntity? get activeProfile => currentProfile;

  KycState copyWith({
    List<KycApplication>? pendingApplications,
    List<KycApplication>? processedApplications,
    List<String>? highRiskAmlAlerts,
    bool? isSubmitting,
    bool? isUploadingDocument,
    double? uploadProgress,
    String? error,
    String? successMessage,
    KycProfileEntity? currentProfile,
    List<KycProfileEntity>? adminProfiles,
    KycVerificationStatus? adminFilterStatus,
    bool clearAdminStatusFilter = false,
    String? adminSearchQuery,
    String? adminCountryFilter,
    KycProfileEntity? selectedAdminProfile,
    bool clearSelectedAdminProfile = false,
    List<KycAuditLogEntry>? auditLogs,
  }) {
    return KycState(
      pendingApplications: pendingApplications ?? this.pendingApplications,
      processedApplications: processedApplications ?? this.processedApplications,
      highRiskAmlAlerts: highRiskAmlAlerts ?? this.highRiskAmlAlerts,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isUploadingDocument: isUploadingDocument ?? this.isUploadingDocument,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      error: error,
      successMessage: successMessage,
      currentProfile: currentProfile ?? this.currentProfile,
      adminProfiles: adminProfiles ?? this.adminProfiles,
      adminFilterStatus: clearAdminStatusFilter ? null : (adminFilterStatus ?? this.adminFilterStatus),
      adminSearchQuery: adminSearchQuery ?? this.adminSearchQuery,
      adminCountryFilter: adminCountryFilter ?? this.adminCountryFilter,
      selectedAdminProfile: clearSelectedAdminProfile
          ? null
          : (selectedAdminProfile ?? this.selectedAdminProfile),
      auditLogs: auditLogs ?? this.auditLogs,
    );
  }
}

// ── Cubit ────────────────────────────────────────────────────────────────────
class KycCubit extends Cubit<KycState> {
  final KycRepository _repository;

  KycCubit({KycRepository? repository})
      : _repository = repository ?? KycRepository.instance,
        super(const KycState()) {
    _initData();
  }

  Future<void> _initData() async {
    _loadSampleApplications();
    await loadAdminQueue();
  }

  void _loadSampleApplications() {
    emit(state.copyWith(
      pendingApplications: [
        KycApplication(
          id: 'KYC-001',
          userId: 'usr_t1',
          fullName: 'Muhammad Usman',
          email: 'usman@asianfx.com',
          country: 'Pakistan',
          documentType: 'National ID (CNIC)',
          documentNumber: '35201-1234567-1',
          submittedAt: DateTime.now().subtract(const Duration(hours: 3)),
        ),
      ],
    ));
  }

  // ── User KYC Actions ───────────────────────────────────────────────────────

  Future<void> loadUserProfile(
    String userId, {
    String? fullName,
    String? email,
    String? country,
    String? phone,
  }) async {
    try {
      final profile = await _repository.getOrCreateProfile(
        userId,
        fullName: fullName,
        email: email,
        country: country,
        phone: phone,
      );
      emit(state.copyWith(currentProfile: profile, error: null));
    } catch (e) {
      emit(state.copyWith(error: e.toString().replaceAll('Exception: ', '')));
    }
  }

  Future<bool> savePersonalInfo({
    required String userId,
    required String firstName,
    String? middleName,
    required String lastName,
    required DateTime dateOfBirth,
    required String nationality,
    required String countryOfResidence,
    required String address,
    required String city,
    required String stateName,
    required String postalCode,
  }) async {
    emit(state.copyWith(isSubmitting: true, error: null));
    try {
      final updated = await _repository.savePersonalInfo(
        userId: userId,
        firstName: firstName,
        middleName: middleName,
        lastName: lastName,
        dateOfBirth: dateOfBirth,
        nationality: nationality,
        countryOfResidence: countryOfResidence,
        address: address,
        city: city,
        state: stateName,
        postalCode: postalCode,
      );
      emit(state.copyWith(
        currentProfile: updated,
        isSubmitting: false,
        successMessage: 'Personal information saved.',
      ));
      return true;
    } catch (e) {
      emit(state.copyWith(
        isSubmitting: false,
        error: e.toString().replaceAll('Exception: ', ''),
      ));
      return false;
    }
  }

  Future<bool> uploadDocument({
    required String userId,
    required KycDocumentCategory category,
    required KycDocumentType documentType,
    required String fileName,
    required Uint8List bytes,
    String? documentSide,
    String? documentNumber,
  }) async {
    emit(state.copyWith(isUploadingDocument: true, uploadProgress: 0.2, error: null));
    try {
      // Simulate progress feedback for good UX
      emit(state.copyWith(uploadProgress: 0.6));
      final updated = await _repository.uploadDocument(
        userId: userId,
        category: category,
        documentType: documentType,
        fileName: fileName,
        bytes: bytes,
        documentSide: documentSide,
        documentNumber: documentNumber,
      );
      emit(state.copyWith(
        currentProfile: updated,
        isUploadingDocument: false,
        uploadProgress: 1.0,
        successMessage: '${category.code} document uploaded successfully.',
      ));
      return true;
    } catch (e) {
      emit(state.copyWith(
        isUploadingDocument: false,
        uploadProgress: 0.0,
        error: e.toString().replaceAll('Exception: ', ''),
      ));
      return false;
    }
  }

  Future<void> removeDocument({
    required String userId,
    required String documentId,
  }) async {
    try {
      final updated = await _repository.removeDocument(
        userId: userId,
        documentId: documentId,
      );
      emit(state.copyWith(currentProfile: updated, successMessage: 'Document removed.'));
    } catch (e) {
      emit(state.copyWith(error: e.toString().replaceAll('Exception: ', '')));
    }
  }

  Future<bool> submitKycApplication(String userId, {bool autoApprove = false}) async {
    emit(state.copyWith(isSubmitting: true, error: null));
    try {
      final submitted = await _repository.submitKycApplication(userId, autoApprove: autoApprove);
      emit(state.copyWith(
        currentProfile: submitted,
        isSubmitting: false,
        successMessage: 'Application submitted. A compliance officer will review it shortly.',
      ));
      await loadAdminQueue();
      return true;
    } catch (e) {
      emit(state.copyWith(
        isSubmitting: false,
        error: e.toString().replaceAll('Exception: ', ''),
      ));
      return false;
    }
  }

  Future<bool> resubmitKycApplication(String userId, {bool autoApprove = false}) async {
    emit(state.copyWith(isSubmitting: true, error: null));
    try {
      final resubmitted = await _repository.resubmitKycApplication(userId, autoApprove: autoApprove);
      emit(state.copyWith(
        currentProfile: resubmitted,
        isSubmitting: false,
        successMessage: 'Documents resubmitted. Your application is back in the review queue.',
      ));
      await loadAdminQueue();
      return true;
    } catch (e) {
      emit(state.copyWith(
        isSubmitting: false,
        error: e.toString().replaceAll('Exception: ', ''),
      ));
      return false;
    }
  }

  /// Verification is manual. This used to approve the applicant's own KYC from
  /// the device, which meant anyone could grant themselves Level 2 access; it
  /// now queues the application for an administrator instead.
  @Deprecated('Use submitKycApplication(); approval is an administrator action.')
  Future<bool> autoApproveKyc(String userId) => submitKycApplication(userId);

  // ── Admin Queue & Compliance Operations ────────────────────────────────────

  Future<void> loadAdminQueue() async {
    try {
      final profiles = await _repository.adminListRequests(
        statusFilter: state.adminFilterStatus,
        searchQuery: state.adminSearchQuery,
        countryFilter: state.adminCountryFilter,
      );
      emit(state.copyWith(adminProfiles: profiles, error: null));
    } catch (e) {
      emit(state.copyWith(error: e.toString().replaceAll('Exception: ', '')));
    }
  }

  void setAdminFilters({
    KycVerificationStatus? status,
    bool clearStatus = false,
    String? search,
    String? country,
  }) {
    emit(state.copyWith(
      adminFilterStatus: status,
      clearAdminStatusFilter: clearStatus,
      adminSearchQuery: search ?? state.adminSearchQuery,
      adminCountryFilter: country ?? state.adminCountryFilter,
    ));
    loadAdminQueue();
  }

  void selectAdminProfile(KycProfileEntity? profile) {
    emit(state.copyWith(
      selectedAdminProfile: profile,
      clearSelectedAdminProfile: profile == null,
    ));
    if (profile != null) {
      loadAuditLogs(profile.id);
    }
  }

  Future<void> loadAuditLogs(String kycId) async {
    try {
      final logs = await _repository.getAuditHistory(kycId);
      emit(state.copyWith(auditLogs: logs));
    } catch (_) {}
  }

  Future<bool> adminApproveProfile({
    required String kycId,
    required String reviewerEmail,
  }) async {
    try {
      final approved = await _repository.adminApproveKyc(
        kycId: kycId,
        reviewerEmail: reviewerEmail,
      );
      emit(state.copyWith(
        selectedAdminProfile: approved,
        successMessage: '${approved.fullName} KYC Approved.',
      ));
      await loadAdminQueue();
      return true;
    } catch (e) {
      emit(state.copyWith(error: e.toString().replaceAll('Exception: ', '')));
      return false;
    }
  }

  Future<bool> adminRejectProfile({
    required String kycId,
    required String reviewerEmail,
    required String reason,
  }) async {
    try {
      final rejected = await _repository.adminRejectKyc(
        kycId: kycId,
        reviewerEmail: reviewerEmail,
        reason: reason,
      );
      emit(state.copyWith(
        selectedAdminProfile: rejected,
        successMessage: '${rejected.fullName} KYC Rejected.',
      ));
      await loadAdminQueue();
      return true;
    } catch (e) {
      emit(state.copyWith(error: e.toString().replaceAll('Exception: ', '')));
      return false;
    }
  }

  Future<bool> adminRequestProfileResubmission({
    required String kycId,
    required String reviewerEmail,
    required String notes,
  }) async {
    try {
      final updated = await _repository.adminRequestResubmission(
        kycId: kycId,
        reviewerEmail: reviewerEmail,
        notes: notes,
      );
      emit(state.copyWith(
        selectedAdminProfile: updated,
        successMessage: 'Resubmission requested from ${updated.fullName}.',
      ));
      await loadAdminQueue();
      return true;
    } catch (e) {
      emit(state.copyWith(error: e.toString().replaceAll('Exception: ', '')));
      return false;
    }
  }

  // ── Backward-Compatible Legacy Methods ─────────────────────────────────────

  void submitApplication(KycApplication app) {
    emit(state.copyWith(
      pendingApplications: [app, ...state.pendingApplications],
    ));
  }

  void submitNewKyc({
    required String documentType,
    required String documentNumber,
    String? userId,
    String? fullName,
    String? email,
    String? country,
  }) {
    final newApp = KycApplication(
      id: 'KYC-APP-${DateTime.now().millisecondsSinceEpoch}',
      userId: userId ?? 'usr_current',
      fullName: fullName ?? 'Trader',
      email: email ?? '',
      country: country ?? 'Pakistan',
      documentType: documentType,
      documentNumber: documentNumber,
      status: KycStatus.pending,
      submittedAt: DateTime.now(),
    );
    emit(state.copyWith(
      pendingApplications: [newApp, ...state.pendingApplications],
    ));
  }

  void autoVerifyExnessKyc({
    required String documentType,
    required String documentNumber,
    String? userId,
    String? fullName,
    String? email,
    String? country,
    String? employmentStatus,
    String? tradingExperience,
    String? annualIncome,
    String? streetAddress,
    String? city,
    String? postalCode,
    String? addressDocType,
    String? frontDocUrl,
    String? backDocUrl,
    String? proofOfAddressUrl,
    int kycTier = 2,
  }) {
    final app = KycApplication(
      id: 'KYC-EXN-${DateTime.now().millisecondsSinceEpoch}',
      userId: userId ?? 'usr_current',
      fullName: fullName ?? 'Trader',
      email: email ?? '',
      country: country ?? 'Pakistan',
      documentType: documentType,
      documentNumber: documentNumber,
      status: KycStatus.approved,
      isAutoApproved: true,
      kycTier: kycTier,
      employmentStatus: employmentStatus,
      tradingExperience: tradingExperience,
      annualIncome: annualIncome,
      streetAddress: streetAddress,
      city: city,
      postalCode: postalCode,
      addressDocType: addressDocType,
      frontDocUrl: frontDocUrl,
      backDocUrl: backDocUrl,
      proofOfAddressUrl: proofOfAddressUrl,
      submittedAt: DateTime.now(),
    );
    emit(state.copyWith(
      processedApplications: [app, ...state.processedApplications],
    ));
  }

  void approveApplication(String appId) {
    final idx = state.pendingApplications.indexWhere((a) => a.id == appId);
    if (idx == -1) return;

    final app = state.pendingApplications[idx];
    final updated = app.copyWith(status: KycStatus.approved);

    final newPending = List<KycApplication>.from(state.pendingApplications)..removeAt(idx);
    final newProcessed = [updated, ...state.processedApplications];

    emit(state.copyWith(
      pendingApplications: newPending,
      processedApplications: newProcessed,
    ));
  }

  void rejectApplication(String appId, String reason) {
    final idx = state.pendingApplications.indexWhere((a) => a.id == appId);
    if (idx == -1) return;

    final app = state.pendingApplications[idx];
    final updated = app.copyWith(
      status: KycStatus.rejected,
      rejectionReason: reason,
    );

    final newPending = List<KycApplication>.from(state.pendingApplications)..removeAt(idx);
    final newProcessed = [updated, ...state.processedApplications];

    emit(state.copyWith(
      pendingApplications: newPending,
      processedApplications: newProcessed,
    ));
  }

  void approveKyc(String appId) => approveApplication(appId);
  void rejectKyc(String appId, String reason) => rejectApplication(appId, reason);

  void clearError() => emit(state.copyWith(error: null));
  void clearSuccess() => emit(state.copyWith(successMessage: null));
}

typedef KycBloc = KycCubit;
typedef ComplianceState = KycState;
typedef KycComplianceNotifier = KycCubit;
