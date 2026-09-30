import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// KYC Verification Lifecycle Statuses
enum KycVerificationStatus {
  notStarted,
  inProgress,
  pendingReview,
  approved,
  rejected,
  resubmissionRequired;

  String get code {
    switch (this) {
      case KycVerificationStatus.notStarted:
        return 'NOT_STARTED';
      case KycVerificationStatus.inProgress:
        return 'IN_PROGRESS';
      case KycVerificationStatus.pendingReview:
        return 'PENDING_REVIEW';
      case KycVerificationStatus.approved:
        return 'APPROVED';
      case KycVerificationStatus.rejected:
        return 'REJECTED';
      case KycVerificationStatus.resubmissionRequired:
        return 'RESUBMISSION_REQUIRED';
    }
  }

  String get displayName {
    switch (this) {
      case KycVerificationStatus.notStarted:
        return 'Not Started';
      case KycVerificationStatus.inProgress:
        return 'In Progress';
      case KycVerificationStatus.pendingReview:
        return 'Under Review';
      case KycVerificationStatus.approved:
        return 'Approved';
      case KycVerificationStatus.rejected:
        return 'Rejected';
      case KycVerificationStatus.resubmissionRequired:
        return 'Resubmission Required';
    }
  }

  static KycVerificationStatus fromString(String? val) {
    if (val == null) return KycVerificationStatus.notStarted;
    final normalized = val.trim().toUpperCase().replaceAll(' ', '_');
    for (final status in KycVerificationStatus.values) {
      if (status.code == normalized || status.name.toUpperCase() == normalized) {
        return status;
      }
    }
    return KycVerificationStatus.notStarted;
  }
}

/// Document Categories
enum KycDocumentCategory {
  identity,
  address;

  String get code => name.toUpperCase();

  static KycDocumentCategory fromString(String? val) {
    if (val == null) return KycDocumentCategory.identity;
    return val.toUpperCase() == 'ADDRESS' ? KycDocumentCategory.address : KycDocumentCategory.identity;
  }
}

/// Supported Document Types
enum KycDocumentType {
  cnic,
  passport,
  driversLicense,
  utilityBill,
  bankStatement,
  residenceDocument;

  String get code {
    switch (this) {
      case KycDocumentType.cnic:
        return 'CNIC';
      case KycDocumentType.passport:
        return 'PASSPORT';
      case KycDocumentType.driversLicense:
        return 'DRIVERS_LICENSE';
      case KycDocumentType.utilityBill:
        return 'UTILITY_BILL';
      case KycDocumentType.bankStatement:
        return 'BANK_STATEMENT';
      case KycDocumentType.residenceDocument:
        return 'RESIDENCE_DOCUMENT';
    }
  }

  String get displayName {
    switch (this) {
      case KycDocumentType.cnic:
        return 'National ID / CNIC';
      case KycDocumentType.passport:
        return 'Passport';
      case KycDocumentType.driversLicense:
        return "Driver's License";
      case KycDocumentType.utilityBill:
        return 'Utility Bill';
      case KycDocumentType.bankStatement:
        return 'Bank Statement';
      case KycDocumentType.residenceDocument:
        return 'Government Residence Document';
    }
  }

  bool get isIdentity =>
      this == KycDocumentType.cnic ||
      this == KycDocumentType.passport ||
      this == KycDocumentType.driversLicense;

  bool get isAddress => !isIdentity;

  bool get requiresBackSide => this == KycDocumentType.cnic || this == KycDocumentType.driversLicense;

  static KycDocumentType fromString(String? val) {
    if (val == null) return KycDocumentType.cnic;
    final normalized = val.trim().toUpperCase().replaceAll(' ', '_');
    for (final type in KycDocumentType.values) {
      if (type.code == normalized || type.name.toUpperCase() == normalized) {
        return type;
      }
    }
    return KycDocumentType.cnic;
  }
}

/// KYC Uploaded Document Record
class KycDocumentEntity extends Equatable {
  final String id;
  final String kycId;
  final String userId;
  final KycDocumentCategory category;
  final KycDocumentType documentType;
  final String? storagePath;
  final String originalFileName;
  final String mimeType;
  final int fileSize;
  final Uint8List? fileBytes;
  final String? documentSide; // 'FRONT', 'BACK', 'SINGLE'
  final KycVerificationStatus status;
  final String? rejectionReason;
  final DateTime uploadedAt;
  final DateTime? reviewedAt;

  const KycDocumentEntity({
    required this.id,
    required this.kycId,
    required this.userId,
    required this.category,
    required this.documentType,
    this.storagePath,
    required this.originalFileName,
    required this.mimeType,
    required this.fileSize,
    this.fileBytes,
    this.documentSide = 'SINGLE',
    this.status = KycVerificationStatus.pendingReview,
    this.rejectionReason,
    required this.uploadedAt,
    this.reviewedAt,
  });

  KycDocumentEntity copyWith({
    String? storagePath,
    KycVerificationStatus? status,
    String? rejectionReason,
    DateTime? reviewedAt,
    Uint8List? fileBytes,
  }) {
    return KycDocumentEntity(
      id: id,
      kycId: kycId,
      userId: userId,
      category: category,
      documentType: documentType,
      storagePath: storagePath ?? this.storagePath,
      originalFileName: originalFileName,
      mimeType: mimeType,
      fileSize: fileSize,
      fileBytes: fileBytes ?? this.fileBytes,
      documentSide: documentSide,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      uploadedAt: uploadedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'kyc_id': kycId,
      'user_id': userId,
      'document_category': category.code,
      'document_type': documentType.code,
      'storage_path': storagePath,
      'original_file_name': originalFileName,
      'mime_type': mimeType,
      'file_size': fileSize,
      'document_side': documentSide,
      'status': status.code,
      'rejection_reason': rejectionReason,
      'uploaded_at': uploadedAt.toIso8601String(),
      'reviewed_at': reviewedAt?.toIso8601String(),
    };
  }

  factory KycDocumentEntity.fromMap(Map<String, dynamic> map, {Uint8List? fileBytes}) {
    return KycDocumentEntity(
      id: map['id'] as String? ?? 'doc_${DateTime.now().millisecondsSinceEpoch}',
      kycId: map['kyc_id'] as String? ?? '',
      userId: map['user_id'] as String? ?? '',
      category: KycDocumentCategory.fromString(map['document_category'] as String?),
      documentType: KycDocumentType.fromString(map['document_type'] as String?),
      storagePath: map['storage_path'] as String?,
      originalFileName: map['original_file_name'] as String? ?? 'document',
      mimeType: map['mime_type'] as String? ?? 'image/jpeg',
      fileSize: (map['file_size'] as num?)?.toInt() ?? 0,
      fileBytes: fileBytes,
      documentSide: map['document_side'] as String? ?? 'SINGLE',
      status: KycVerificationStatus.fromString(map['status'] as String?),
      rejectionReason: map['rejection_reason'] as String?,
      uploadedAt: map['uploaded_at'] != null
          ? DateTime.tryParse(map['uploaded_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      reviewedAt: map['reviewed_at'] != null ? DateTime.tryParse(map['reviewed_at'] as String) : null,
    );
  }

  @override
  List<Object?> get props => [
        id,
        kycId,
        userId,
        category,
        documentType,
        storagePath,
        originalFileName,
        mimeType,
        fileSize,
        documentSide,
        status,
        rejectionReason,
        uploadedAt,
        reviewedAt,
      ];
}

/// Comprehensive KYC Profile Entity
class KycProfileEntity extends Equatable {
  final String id;
  final String userId;
  final String firstName;
  final String? middleName;
  final String lastName;
  final DateTime? dateOfBirth;
  final String nationality;
  final String countryOfResidence;
  final String address;
  final String city;
  final String state;
  final String postalCode;
  final KycVerificationStatus status;
  final String? rejectionReason;
  final String? resubmissionNotes;
  final String? documentNumber;
  final KycDocumentType identityDocType;
  final KycDocumentType addressDocType;
  final List<KycDocumentEntity> documents;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const KycProfileEntity({
    required this.id,
    required this.userId,
    required this.firstName,
    this.middleName,
    required this.lastName,
    this.dateOfBirth,
    required this.nationality,
    required this.countryOfResidence,
    required this.address,
    required this.city,
    required this.state,
    required this.postalCode,
    this.status = KycVerificationStatus.notStarted,
    this.rejectionReason,
    this.resubmissionNotes,
    this.documentNumber,
    this.identityDocType = KycDocumentType.cnic,
    this.addressDocType = KycDocumentType.utilityBill,
    this.documents = const [],
    this.submittedAt,
    this.reviewedAt,
    this.reviewedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  String get fullName {
    if (middleName != null && middleName!.trim().isNotEmpty) {
      return '$firstName $middleName $lastName'.trim();
    }
    return '$firstName $lastName'.trim();
  }

  bool get isApproved => status == KycVerificationStatus.approved;
  bool get isPendingReview => status == KycVerificationStatus.pendingReview;
  bool get isRejected => status == KycVerificationStatus.rejected;
  bool get isResubmissionRequired => status == KycVerificationStatus.resubmissionRequired;

  KycDocumentEntity? get poiFrontDoc {
    try {
      return documents.firstWhere(
        (d) => d.category == KycDocumentCategory.identity && (d.documentSide == 'FRONT' || d.documentSide == 'SINGLE'),
      );
    } catch (_) {
      return null;
    }
  }

  KycDocumentEntity? get poiBackDoc {
    try {
      return documents.firstWhere(
        (d) => d.category == KycDocumentCategory.identity && d.documentSide == 'BACK',
      );
    } catch (_) {
      return null;
    }
  }

  KycDocumentEntity? get poaDoc {
    try {
      return documents.firstWhere((d) => d.category == KycDocumentCategory.address);
    } catch (_) {
      return null;
    }
  }

  KycProfileEntity copyWith({
    String? firstName,
    String? middleName,
    String? lastName,
    DateTime? dateOfBirth,
    String? nationality,
    String? countryOfResidence,
    String? address,
    String? city,
    String? state,
    String? postalCode,
    KycVerificationStatus? status,
    String? rejectionReason,
    String? resubmissionNotes,
    String? documentNumber,
    KycDocumentType? identityDocType,
    KycDocumentType? addressDocType,
    List<KycDocumentEntity>? documents,
    DateTime? submittedAt,
    DateTime? reviewedAt,
    String? reviewedBy,
    DateTime? updatedAt,
  }) {
    return KycProfileEntity(
      id: id,
      userId: userId,
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      lastName: lastName ?? this.lastName,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      nationality: nationality ?? this.nationality,
      countryOfResidence: countryOfResidence ?? this.countryOfResidence,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      postalCode: postalCode ?? this.postalCode,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      resubmissionNotes: resubmissionNotes ?? this.resubmissionNotes,
      documentNumber: documentNumber ?? this.documentNumber,
      identityDocType: identityDocType ?? this.identityDocType,
      addressDocType: addressDocType ?? this.addressDocType,
      documents: documents ?? this.documents,
      submittedAt: submittedAt ?? this.submittedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'first_name': firstName,
      'middle_name': middleName,
      'last_name': lastName,
      'date_of_birth': dateOfBirth?.toIso8601String(),
      'nationality': nationality,
      'country_of_residence': countryOfResidence,
      'address': address,
      'city': city,
      'state': state,
      'postal_code': postalCode,
      'status': status.code,
      'rejection_reason': rejectionReason,
      'resubmission_notes': resubmissionNotes,
      'document_number': documentNumber,
      'identity_doc_type': identityDocType.code,
      'address_doc_type': addressDocType.code,
      'documents': documents.map((d) => d.toMap()).toList(),
      'submitted_at': submittedAt?.toIso8601String(),
      'reviewed_at': reviewedAt?.toIso8601String(),
      'reviewed_by': reviewedBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory KycProfileEntity.fromMap(Map<String, dynamic> map, {List<KycDocumentEntity>? docs}) {
    List<KycDocumentEntity> parsedDocs = docs ?? [];
    if (parsedDocs.isEmpty && map['documents'] is List) {
      parsedDocs = (map['documents'] as List)
          .whereType<Map<String, dynamic>>()
          .map((m) => KycDocumentEntity.fromMap(m))
          .toList();
    }

    return KycProfileEntity(
      id: map['id'] as String? ?? 'kyc_${DateTime.now().millisecondsSinceEpoch}',
      userId: map['user_id'] as String? ?? '',
      firstName: map['first_name'] as String? ?? '',
      middleName: map['middle_name'] as String?,
      lastName: map['last_name'] as String? ?? '',
      dateOfBirth: map['date_of_birth'] != null ? DateTime.tryParse(map['date_of_birth'] as String) : null,
      nationality: map['nationality'] as String? ?? 'Pakistan',
      countryOfResidence: map['country_of_residence'] as String? ?? 'Pakistan',
      address: map['address'] as String? ?? '',
      city: map['city'] as String? ?? '',
      state: map['state'] as String? ?? '',
      postalCode: map['postal_code'] as String? ?? '',
      status: KycVerificationStatus.fromString(map['status'] as String?),
      rejectionReason: map['rejection_reason'] as String?,
      resubmissionNotes: map['resubmission_notes'] as String?,
      documentNumber: map['document_number'] as String?,
      identityDocType: KycDocumentType.fromString(map['identity_doc_type'] as String?),
      addressDocType: KycDocumentType.fromString(map['address_doc_type'] as String?),
      documents: parsedDocs,
      submittedAt: map['submitted_at'] != null ? DateTime.tryParse(map['submitted_at'] as String) : null,
      reviewedAt: map['reviewed_at'] != null ? DateTime.tryParse(map['reviewed_at'] as String) : null,
      reviewedBy: map['reviewed_by'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        firstName,
        middleName,
        lastName,
        dateOfBirth,
        nationality,
        countryOfResidence,
        address,
        city,
        state,
        postalCode,
        status,
        rejectionReason,
        resubmissionNotes,
        documentNumber,
        identityDocType,
        addressDocType,
        documents,
        submittedAt,
        reviewedAt,
        reviewedBy,
        createdAt,
        updatedAt,
      ];
}

/// Audit Trail Log Record for Institutional Compliance
class KycAuditLogEntry extends Equatable {
  final String id;
  final String kycId;
  final String userId;
  final String action; // 'SUBMITTED', 'DOCUMENT_UPLOADED', 'DOCUMENT_REPLACED', 'APPROVED', 'REJECTED', 'RESUBMISSION_REQUESTED'
  final String performedBy;
  final DateTime timestamp;
  final String? notes;

  const KycAuditLogEntry({
    required this.id,
    required this.kycId,
    required this.userId,
    required this.action,
    required this.performedBy,
    required this.timestamp,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'kyc_id': kycId,
      'user_id': userId,
      'action': action,
      'performed_by': performedBy,
      'timestamp': timestamp.toIso8601String(),
      'notes': notes,
    };
  }

  factory KycAuditLogEntry.fromMap(Map<String, dynamic> map) {
    return KycAuditLogEntry(
      id: map['id'] as String? ?? 'audit_${DateTime.now().millisecondsSinceEpoch}',
      kycId: map['kyc_id'] as String? ?? '',
      userId: map['user_id'] as String? ?? '',
      action: map['action'] as String? ?? 'ACTION',
      performedBy: map['performed_by'] as String? ?? 'SYSTEM',
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      notes: map['notes'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, kycId, userId, action, performedBy, timestamp, notes];
}
