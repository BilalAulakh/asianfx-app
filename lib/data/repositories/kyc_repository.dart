import 'dart:typed_data';
import '../datasources/kyc_datasource.dart';
import '../../domain/entities/kyc_entities.dart';

/// KYC Repository orchestrating user submission flows, compliance reviews, and audit trails
class KycRepository {
  final KycDatasource _datasource;

  KycRepository({KycDatasource? datasource}) : _datasource = datasource ?? KycDatasource.instance;

  static final KycRepository instance = KycRepository();

  /// Retrieve existing profile or initialize a fresh draft
  Future<KycProfileEntity> getOrCreateProfile(
    String userId, {
    String? fullName,
    String? email,
    String? country,
    String? phone,
  }) async {
    final existing = await _datasource.fetchKycProfile(userId);
    if (existing != null) return existing;

    // Parse full name into parts
    String fName = 'Trader';
    String lName = '';
    if (fullName != null && fullName.trim().isNotEmpty) {
      final parts = fullName.trim().split(' ');
      fName = parts.first;
      if (parts.length > 1) {
        lName = parts.sublist(1).join(' ');
      }
    }

    final newProfile = KycProfileEntity(
      id: 'kyc_${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      firstName: fName,
      lastName: lName,
      nationality: 'Pakistan',
      countryOfResidence: country ?? 'Pakistan',
      address: '',
      city: '',
      state: '',
      postalCode: '',
      status: KycVerificationStatus.notStarted,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _datasource.saveKycProfile(newProfile);
    return newProfile;
  }

  /// Save Personal Information (Step 1)
  Future<KycProfileEntity> savePersonalInfo({
    required String userId,
    required String firstName,
    String? middleName,
    required String lastName,
    required DateTime dateOfBirth,
    required String nationality,
    required String countryOfResidence,
    required String address,
    required String city,
    required String state,
    required String postalCode,
  }) async {
    // Backend validation
    if (firstName.trim().isEmpty) throw Exception('First name is required.');
    if (lastName.trim().isEmpty) throw Exception('Last name is required.');
    if (address.trim().isEmpty) throw Exception('Residential address is required.');
    if (city.trim().isEmpty) throw Exception('City is required.');
    if (countryOfResidence.trim().isEmpty) throw Exception('Country is required.');

    // Age validation (minimum 18 years)
    final age = DateTime.now().difference(dateOfBirth).inDays / 365.25;
    if (age < 18) {
      throw Exception('Traders must be at least 18 years old to open an institutional trading account.');
    }

    final current = await getOrCreateProfile(userId);

    // Prevent modifying sensitive verified information if approved
    if (current.isApproved) {
      throw Exception('Verified accounts cannot modify personal details without administrative re-verification.');
    }

    final nextStatus = current.status == KycVerificationStatus.notStarted
        ? KycVerificationStatus.inProgress
        : current.status;

    final updated = current.copyWith(
      firstName: firstName.trim(),
      middleName: middleName?.trim(),
      lastName: lastName.trim(),
      dateOfBirth: dateOfBirth,
      nationality: nationality.trim(),
      countryOfResidence: countryOfResidence.trim(),
      address: address.trim(),
      city: city.trim(),
      state: state.trim(),
      postalCode: postalCode.trim(),
      status: nextStatus,
      updatedAt: DateTime.now(),
    );

    await _datasource.saveKycProfile(updated);

    return updated;
  }

  /// Upload Document (POI or POA)
  Future<KycProfileEntity> uploadDocument({
    required String userId,
    required KycDocumentCategory category,
    required KycDocumentType documentType,
    required String fileName,
    required Uint8List bytes,
    String? documentSide, // 'FRONT', 'BACK', 'SINGLE'
    String? documentNumber,
  }) async {
    final profile = await getOrCreateProfile(userId);

    final storagePath = await _datasource.uploadDocumentFile(
      userId: userId,
      category: category,
      fileName: fileName,
      bytes: bytes,
    );

    final docId = 'doc_${DateTime.now().millisecondsSinceEpoch}_${category.code}';
    final ext = fileName.split('.').last.toLowerCase();
    final mimeType = ext == 'pdf' ? 'application/pdf' : 'image/$ext';

    final newDoc = KycDocumentEntity(
      id: docId,
      kycId: profile.id,
      userId: userId,
      category: category,
      documentType: documentType,
      storagePath: storagePath,
      originalFileName: fileName,
      mimeType: mimeType,
      fileSize: bytes.length,
      fileBytes: bytes,
      documentSide: documentSide ?? 'SINGLE',
      status: KycVerificationStatus.pendingReview,
      uploadedAt: DateTime.now(),
    );

    // Filter out previous version of this specific document side
    final existingDocs = profile.documents.where((d) {
      if (d.category != category) return true;
      if (documentSide != null && d.documentSide == documentSide) return false;
      return true;
    }).toList();

    final updatedDocs = [...existingDocs, newDoc];

    final updatedProfile = profile.copyWith(
      documents: updatedDocs,
      documentNumber: documentNumber ?? profile.documentNumber,
      identityDocType: category == KycDocumentCategory.identity ? documentType : profile.identityDocType,
      addressDocType: category == KycDocumentCategory.address ? documentType : profile.addressDocType,
      status: profile.status == KycVerificationStatus.notStarted
          ? KycVerificationStatus.inProgress
          : profile.status,
      updatedAt: DateTime.now(),
    );

    await _datasource.saveKycProfile(updatedProfile);

    // Audit log
    await _datasource.logAuditAction(KycAuditLogEntry(
      id: 'audit_${DateTime.now().millisecondsSinceEpoch}',
      kycId: profile.id,
      userId: userId,
      action: 'DOCUMENT_UPLOADED',
      performedBy: userId,
      timestamp: DateTime.now(),
      notes: '${category.code} document (${documentType.displayName}) uploaded: $fileName',
    ));

    return updatedProfile;
  }

  /// Remove an uploaded document draft before submission
  Future<KycProfileEntity> removeDocument({
    required String userId,
    required String documentId,
  }) async {
    final profile = await getOrCreateProfile(userId);
    final updatedDocs = profile.documents.where((d) => d.id != documentId).toList();
    final updated = profile.copyWith(documents: updatedDocs, updatedAt: DateTime.now());
    await _datasource.saveKycProfile(updated);

    return updated;
  }

  /// Submit KYC for compliance verification
  Future<KycProfileEntity> submitKycApplication(String userId, {bool autoApprove = false}) async {
    final profile = await getOrCreateProfile(userId);

    // Prevent duplicate submission while already under review
    if (profile.status == KycVerificationStatus.pendingReview) {
      throw Exception('Your verification request is already pending review.');
    }

    // Backend validation: Personal Information
    if (profile.firstName.trim().isEmpty || profile.lastName.trim().isEmpty) {
      throw Exception('Incomplete personal details. Please enter your full legal name.');
    }
    if (profile.address.trim().isEmpty || profile.city.trim().isEmpty) {
      throw Exception('Incomplete address details. Please provide your residential address.');
    }
    if (profile.dateOfBirth == null) {
      throw Exception('Date of birth is required for regulatory suitability.');
    }

    // Backend validation: POI document
    final hasPoi = profile.poiFrontDoc != null;
    if (!hasPoi) {
      throw Exception('Proof of Identity document is required. Please upload your CNIC or Passport.');
    }
    if (profile.identityDocType.requiresBackSide && profile.poiBackDoc == null) {
      throw Exception('Both Front and Back sides are required for ${profile.identityDocType.displayName}.');
    }

    // Persist the applicant's own data first, then ask the server to move the
    // status. The applicant never decides the verdict: rpc_submit_kyc only ever
    // produces PENDING_REVIEW, and a compliance officer takes it from there.
    //
    // `autoApprove` is retained for call-site compatibility but is ignored —
    // self-approval from the client is exactly what manual review replaces.
    final pending = profile.copyWith(
      submittedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _datasource.saveKycProfile(pending);
    final result = await _datasource.submitForReview();
    final serverApplied = result['status'] != 'offline';

    // Offline, the cached row still carries the old status, so only a genuine
    // server round trip is allowed to define the outcome.
    final confirmed = serverApplied ? await _datasource.fetchKycProfile(userId) : null;
    final submitted = confirmed ??
        pending.copyWith(
          status: KycVerificationStatus.pendingReview,
          rejectionReason: null,
          resubmissionNotes: null,
        );

    await _datasource.saveKycProfile(submitted);

    // Online, rpc_submit_kyc writes the audit row. Offline there is no server to
    // do it, so keep the local trail intact rather than losing the event.
    if (!serverApplied) {
      await _datasource.logAuditAction(KycAuditLogEntry(
        id: 'audit_${DateTime.now().millisecondsSinceEpoch}',
        kycId: profile.id,
        userId: userId,
        action: 'SUBMITTED',
        performedBy: profile.fullName,
        timestamp: DateTime.now(),
        notes: 'KYC application submitted for compliance review.',
      ));
    }

    return submitted;
  }

  /// Resubmit KYC after administrative correction request
  Future<KycProfileEntity> resubmitKycApplication(String userId, {bool autoApprove = false}) async {
    final profile = await getOrCreateProfile(userId);

    if (profile.status != KycVerificationStatus.resubmissionRequired &&
        profile.status != KycVerificationStatus.rejected) {
      return submitKycApplication(userId, autoApprove: autoApprove);
    }

    // Identical path to a first submission: the server records RESUBMITTED in
    // the audit trail and returns the application to the review queue.
    await _datasource.saveKycProfile(
      profile.copyWith(submittedAt: DateTime.now(), updatedAt: DateTime.now()),
    );
    final result = await _datasource.submitForReview();
    final confirmed =
        result['status'] != 'offline' ? await _datasource.fetchKycProfile(userId) : null;
    final resubmitted = confirmed ??
        profile.copyWith(
          status: KycVerificationStatus.pendingReview,
          submittedAt: DateTime.now(),
          rejectionReason: null,
          resubmissionNotes: null,
          updatedAt: DateTime.now(),
        );

    await _datasource.saveKycProfile(resubmitted);

    if (result['status'] == 'offline') {
      await _datasource.logAuditAction(KycAuditLogEntry(
        id: 'audit_${DateTime.now().millisecondsSinceEpoch}',
        kycId: profile.id,
        userId: userId,
        action: 'RESUBMITTED',
        performedBy: profile.fullName,
        timestamp: DateTime.now(),
        notes: 'Resubmitted corrected documents for compliance re-evaluation.',
      ));
    }

    return resubmitted;
  }

  // ── Admin Review Operations ────────────────────────────────────────────────

  /// List all requests with comprehensive filters
  Future<List<KycProfileEntity>> adminListRequests({
    KycVerificationStatus? statusFilter,
    String? searchQuery,
    String? countryFilter,
  }) async {
    final all = await _datasource.fetchAllKycProfiles();

    return all.where((p) {
      if (statusFilter != null && p.status != statusFilter) return false;
      if (countryFilter != null &&
          countryFilter.isNotEmpty &&
          countryFilter != 'All' &&
          p.countryOfResidence.toLowerCase() != countryFilter.toLowerCase()) {
        return false;
      }
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.toLowerCase().trim();
        final match = p.fullName.toLowerCase().contains(q) ||
            p.userId.toLowerCase().contains(q) ||
            p.id.toLowerCase().contains(q) ||
            p.city.toLowerCase().contains(q);
        if (!match) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => (b.submittedAt ?? b.createdAt).compareTo(a.submittedAt ?? a.createdAt));
  }

  /// Shared path for every administrator verdict.
  ///
  /// `rpc_review_kyc` is what actually decides: it verifies the caller is an
  /// administrator (a row in `broker_admins` or an admin JWT claim), requires a
  /// written reason for anything other than an approval, moves the status inside
  /// a transaction and writes the audit entry. This method only mirrors the
  /// result into the local cache.
  Future<KycProfileEntity> _applyReview({
    required String kycId,
    required String decision,
    required KycVerificationStatus resultingStatus,
    required String reviewerEmail,
    String? notes,
  }) async {
    final all = await _datasource.fetchAllKycProfiles();
    final profile = all.firstWhere(
      (p) => p.id == kycId,
      orElse: () => throw Exception('KYC profile $kycId not found.'),
    );

    // Throws when the caller is not an administrator, so a failed review can
    // never look like a successful one.
    final result = await _datasource.reviewProfile(
      kycId: kycId,
      decision: decision,
      notes: notes,
    );

    final reviewer = (result['reviewed_by'] as String?) ?? reviewerEmail;
    final serverApplied = result['status'] != 'offline';

    final refreshed =
        serverApplied ? await _datasource.fetchKycProfile(profile.userId) : null;
    final updated = refreshed ??
        profile.copyWith(
          status: resultingStatus,
          reviewedAt: DateTime.now(),
          reviewedBy: reviewer,
          rejectionReason:
              resultingStatus == KycVerificationStatus.rejected ? notes?.trim() : null,
          resubmissionNotes: resultingStatus ==
                  KycVerificationStatus.resubmissionRequired
              ? notes?.trim()
              : null,
          updatedAt: DateTime.now(),
        );

    await _datasource.saveKycProfile(updated);

    if (!serverApplied) {
      await _datasource.logAuditAction(KycAuditLogEntry(
        id: 'audit_${DateTime.now().millisecondsSinceEpoch}',
        kycId: kycId,
        userId: profile.userId,
        action: switch (decision) {
          'APPROVE' => 'APPROVED',
          'REJECT' => 'REJECTED',
          _ => 'RESUBMISSION_REQUESTED',
        },
        performedBy: reviewerEmail,
        timestamp: DateTime.now(),
        notes: notes?.trim().isNotEmpty == true
            ? notes!.trim()
            : 'Application reviewed by $reviewerEmail.',
      ));
    }

    return updated;
  }

  /// Admin approves a KYC application.
  Future<KycProfileEntity> adminApproveKyc({
    required String kycId,
    required String reviewerEmail,
  }) {
    return _applyReview(
      kycId: kycId,
      decision: 'APPROVE',
      reviewerEmail: reviewerEmail,
      resultingStatus: KycVerificationStatus.approved,
    );
  }

  /// Admin rejects a KYC application with a mandatory reason.
  Future<KycProfileEntity> adminRejectKyc({
    required String kycId,
    required String reviewerEmail,
    required String reason,
  }) {
    if (reason.trim().isEmpty) {
      throw Exception('A valid rejection reason is required by regulatory compliance rules.');
    }
    return _applyReview(
      kycId: kycId,
      decision: 'REJECT',
      reviewerEmail: reviewerEmail,
      resultingStatus: KycVerificationStatus.rejected,
      notes: reason.trim(),
    );
  }

  /// Admin asks the applicant to resubmit specific documents.
  Future<KycProfileEntity> adminRequestResubmission({
    required String kycId,
    required String reviewerEmail,
    required String notes,
  }) {
    if (notes.trim().isEmpty) {
      throw Exception('Please specify what documents or information need resubmission.');
    }
    return _applyReview(
      kycId: kycId,
      decision: 'RESUBMIT',
      reviewerEmail: reviewerEmail,
      resultingStatus: KycVerificationStatus.resubmissionRequired,
      notes: notes.trim(),
    );
  }

  /// Verification is manual: an application can only be queued from the client,
  /// never approved. Retained so existing call sites keep compiling, and now
  /// simply submits for compliance review.
  @Deprecated('Verification is reviewed by an administrator. Use submitKycApplication().')
  Future<KycProfileEntity> autoApproveKyc(String userId) {
    return submitKycApplication(userId);
  }

  /// Retrieve audit logs for compliance tracking
  Future<List<KycAuditLogEntry>> getAuditHistory(String kycId) async {
    return _datasource.fetchAuditLogs(kycId);
  }
}
