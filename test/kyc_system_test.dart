import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asianfxapp/core/policy/kyc_policy.dart';
import 'package:asianfxapp/data/datasources/kyc_datasource.dart';
import 'package:asianfxapp/data/repositories/kyc_repository.dart';
import 'package:asianfxapp/domain/entities/kyc_entities.dart';
import 'package:asianfxapp/domain/entities/user_entity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('1. KycPolicy Institutional Compliance Rules', () {
    final unverifiedUser = UserEntity(
      id: 'usr_001',
      email: 'trader@asianfx.com',
      fullName: 'John Trader',
      preferredCurrency: 'USD',
      preferredLanguage: 'en',
      kycStatus: KycStatus.notSubmitted,
      status: AccountStatus.active,
      role: UserRole.client,
      isTwoFactorEnabled: false,
      isEmailVerified: true,
      isPhoneVerified: false,
      createdAt: DateTime.now(),
    );

    final verifiedUser = UserEntity(
      id: 'usr_002',
      email: 'verified@asianfx.com',
      fullName: 'Verified Trader',
      preferredCurrency: 'USD',
      preferredLanguage: 'en',
      kycStatus: KycStatus.approved,
      status: AccountStatus.active,
      role: UserRole.client,
      isTwoFactorEnabled: true,
      isEmailVerified: true,
      isPhoneVerified: true,
      kycTier: 2,
      createdAt: DateTime.now(),
    );

    final suspendedUser = UserEntity(
      id: 'usr_003',
      email: 'suspended@asianfx.com',
      fullName: 'Suspended Trader',
      preferredCurrency: 'USD',
      preferredLanguage: 'en',
      kycStatus: KycStatus.approved,
      status: AccountStatus.suspended,
      role: UserRole.client,
      isTwoFactorEnabled: false,
      isEmailVerified: true,
      isPhoneVerified: false,
      createdAt: DateTime.now(),
    );

    final adminUser = UserEntity(
      id: 'admin_001',
      email: 'admin@asianfx.com',
      fullName: 'Super Admin',
      preferredCurrency: 'USD',
      preferredLanguage: 'en',
      kycStatus: KycStatus.approved,
      status: AccountStatus.active,
      role: UserRole.admin,
      isTwoFactorEnabled: true,
      isEmailVerified: true,
      isPhoneVerified: true,
      kycTier: 2,
      createdAt: DateTime.now(),
    );

    test('Withdrawal Policy: Strictly blocked without Level 2 KYC approval', () {
      expect(KycPolicy.canWithdraw(unverifiedUser), isFalse,
          reason: 'Unverified user must NOT be permitted to withdraw funds.');
      expect(KycPolicy.canWithdraw(suspendedUser), isFalse,
          reason: 'Suspended user cannot withdraw even if KYC was approved.');
      expect(KycPolicy.canWithdraw(verifiedUser), isTrue,
          reason: 'Active Tier 2 verified user has full withdrawal clearance.');
      expect(KycPolicy.canWithdraw(adminUser), isTrue,
          reason: 'Admin has operational override privileges.');
      expect(KycPolicy.canWithdraw(null), isFalse);
    });

    test('Deposit Policy: Enforces \$2,000 threshold on unverified clients', () {
      // Unverified <= 2000 is allowed
      expect(KycPolicy.canDeposit(unverifiedUser, 500.0), isTrue);
      expect(KycPolicy.canDeposit(unverifiedUser, 2000.0), isTrue);
      // Unverified > 2000 is blocked
      expect(KycPolicy.canDeposit(unverifiedUser, 2000.01), isFalse,
          reason: 'Deposits exceeding unverified threshold must be blocked.');

      // Verified has unrestricted deposits
      expect(KycPolicy.canDeposit(verifiedUser, 100000.0), isTrue);
      expect(KycPolicy.canDeposit(adminUser, 500000.0), isTrue);
    });

    test('Status Mapping & Messages: Accurate mapping from legacy UserEntity', () {
      expect(KycPolicy.mapFromUser(unverifiedUser), equals(KycVerificationStatus.notStarted));
      expect(KycPolicy.mapFromUser(verifiedUser), equals(KycVerificationStatus.approved));

      final pendingUser = unverifiedUser.copyWith(kycStatus: KycStatus.pending);
      expect(KycPolicy.mapFromUser(pendingUser), equals(KycVerificationStatus.pendingReview));

      final restrictedUser = unverifiedUser.copyWith(kycStatus: KycStatus.restricted);
      expect(KycPolicy.mapFromUser(restrictedUser), equals(KycVerificationStatus.resubmissionRequired));

      final rejectedUser = unverifiedUser.copyWith(kycStatus: KycStatus.rejected);
      expect(KycPolicy.mapFromUser(rejectedUser), equals(KycVerificationStatus.rejected));
    });

    test('Status Explanations and Color Palettes are consistent', () {
      for (final status in KycVerificationStatus.values) {
        final color = KycPolicy.getStatusColor(status);
        final explanation = KycPolicy.getStatusExplanation(status);
        expect(color, isNotNull);
        expect(explanation.isNotEmpty, isTrue);
      }
    });
  });

  group('2. File & Security Validation (Magic Bytes & Extensions)', () {
    final datasource = KycDatasource.instance;

    test('Accepts valid PDF bytes with %PDF magic header', () {
      final pdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x35]);
      expect(() => datasource.validateDocumentFile(fileName: 'passport.pdf', bytes: pdfBytes), returnsNormally);
    });

    test('Accepts valid PNG bytes with PNG signature', () {
      final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(() => datasource.validateDocumentFile(fileName: 'cnic_front.png', bytes: pngBytes), returnsNormally);
    });

    test('Accepts valid JPEG bytes with SOI marker', () {
      final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      expect(() => datasource.validateDocumentFile(fileName: 'license.jpeg', bytes: jpegBytes), returnsNormally);
    });

    test('Rejects executable or disguised files with mismatched extensions/headers', () {
      // Fake PDF with executable content
      final fakePdf = Uint8List.fromList([0x4D, 0x5A, 0x90, 0x00]); // MZ executable header
      expect(
        () => datasource.validateDocumentFile(fileName: 'malicious.pdf', bytes: fakePdf),
        throwsA(isA<ArgumentError>()),
      );

      // Disallowed extension
      final validPng = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(
        () => datasource.validateDocumentFile(fileName: 'script.exe', bytes: validPng),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Rejects files exceeding 10MB limit', () {
      // 10MB + 1 byte
      final oversizedBytes = Uint8List(10 * 1024 * 1024 + 1);
      // Give it valid PNG header
      oversizedBytes[0] = 0x89;
      oversizedBytes[1] = 0x50;
      oversizedBytes[2] = 0x4E;
      oversizedBytes[3] = 0x47;

      expect(
        () => datasource.validateDocumentFile(fileName: 'huge_document.png', bytes: oversizedBytes),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('3. End-to-End KYC Application & Review Lifecycle', () {
    late KycRepository repository;

    setUp(() {
      repository = KycRepository();
    });

    test('Full Lifecycle: Init -> Personal Info -> POI/POA Upload -> Submit -> Admin Resubmit -> Re-upload -> Approve', () async {
      const testUserId = 'trader_999';
      const testEmail = 'trader999@asianfx.com';

      // 1. Initial Profile Creation
      final initialProfile = await repository.getOrCreateProfile(
        testUserId,
        email: testEmail,
      );
      expect(initialProfile.status, equals(KycVerificationStatus.notStarted));

      // 2. Personal Info Submission with >= 18 Age Validation
      final validDob = DateTime(1995, 5, 20);
      final profileWithInfo = await repository.savePersonalInfo(
        userId: testUserId,
        firstName: 'Tariq',
        lastName: 'Mahmood',
        dateOfBirth: validDob,
        countryOfResidence: 'Pakistan',
        nationality: 'Pakistani',
        address: 'House 42, Street 7, Sector F-8/2',
        city: 'Islamabad',
        state: 'ICT',
        postalCode: '44000',
      );

      expect(profileWithInfo.status, equals(KycVerificationStatus.inProgress));
      expect(profileWithInfo.fullName, equals('Tariq Mahmood'));
      expect(profileWithInfo.city, equals('Islamabad'));

      // Test under 18 rejection
      final underageDob = DateTime.now().subtract(const Duration(days: 365 * 16));
      expect(
        () => repository.savePersonalInfo(
          userId: testUserId,
          firstName: 'Minor',
          lastName: 'User',
          dateOfBirth: underageDob,
          countryOfResidence: 'Pakistan',
          nationality: 'Pakistani',
          address: 'Street 1',
          city: 'Karachi',
          state: 'Sindh',
          postalCode: '74000',
        ),
        throwsA(isA<Exception>()),
      );

      // 3. Upload POI and POA Documents
      final samplePng = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00]);
      final samplePdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x35, 0x0A]);

      final profileWithPoiFront = await repository.uploadDocument(
        userId: testUserId,
        category: KycDocumentCategory.identity,
        documentType: KycDocumentType.cnic,
        fileName: 'cnic_front.png',
        bytes: samplePng,
        documentSide: 'FRONT',
      );
      expect(profileWithPoiFront.poiFrontDoc, isNotNull);

      final profileWithPoiBack = await repository.uploadDocument(
        userId: testUserId,
        category: KycDocumentCategory.identity,
        documentType: KycDocumentType.cnic,
        fileName: 'cnic_back.png',
        bytes: samplePng,
        documentSide: 'BACK',
      );
      expect(profileWithPoiBack.poiBackDoc, isNotNull);

      final profileWithPoa = await repository.uploadDocument(
        userId: testUserId,
        category: KycDocumentCategory.address,
        documentType: KycDocumentType.utilityBill,
        fileName: 'electric_bill.pdf',
        bytes: samplePdf,
      );
      expect(profileWithPoa.poaDoc, isNotNull);

      // 4. Submit Application -> Transitions to PENDING_REVIEW
      final submittedProfile = await repository.submitKycApplication(testUserId);
      expect(submittedProfile.status, equals(KycVerificationStatus.pendingReview));
      expect(submittedProfile.submittedAt, isNotNull);

      // 5. Admin Queue Inspection
      final adminQueue = await repository.adminListRequests();
      final targetInQueue = adminQueue.firstWhere((p) => p.userId == testUserId);
      expect(targetInQueue.status, equals(KycVerificationStatus.pendingReview));

      // 6. Admin Requests Resubmission (e.g. Utility bill too old)
      const resubmitNotes = 'Utility bill date is older than 90 days. Please provide recent bill.';
      final resubmitProfile = await repository.adminRequestResubmission(
        kycId: submittedProfile.id,
        reviewerEmail: 'compliance@asianfx.com',
        notes: resubmitNotes,
      );
      expect(resubmitProfile.status, equals(KycVerificationStatus.resubmissionRequired));
      expect(resubmitProfile.resubmissionNotes, equals(resubmitNotes));

      // 7. User Replaces Flagged POA and Resubmits
      final newBillPdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x35, 0x0A, 0x01]);
      await repository.uploadDocument(
        userId: testUserId,
        category: KycDocumentCategory.address,
        documentType: KycDocumentType.utilityBill,
        fileName: 'recent_electric_bill.pdf',
        bytes: newBillPdf,
      );

      final resubmittedUser = await repository.resubmitKycApplication(testUserId);
      expect(resubmittedUser.status, equals(KycVerificationStatus.pendingReview));

      // 8. Admin Final Approval
      final approvedProfile = await repository.adminApproveKyc(
        kycId: resubmittedUser.id,
        reviewerEmail: 'compliance@asianfx.com',
      );
      expect(approvedProfile.status, equals(KycVerificationStatus.approved));
      expect(approvedProfile.reviewedAt, isNotNull);
      expect(approvedProfile.reviewedBy, equals('compliance@asianfx.com'));

      // 9. Verify Comprehensive Audit Trail
      final auditLogs = await repository.getAuditHistory(approvedProfile.id);
      expect(auditLogs.length, greaterThanOrEqualTo(3));
      final actions = auditLogs.map((l) => l.action).toList();
      expect(actions.contains('SUBMITTED'), isTrue);
      expect(actions.contains('RESUBMISSION_REQUESTED'), isTrue);
      expect(actions.contains('APPROVED'), isTrue);
    });

    test('Rejection Flow: Admin rejects with mandatory compliance reason', () async {
      const testUserId = 'trader_reject_01';
      const testEmail = 'fraud_trader@asianfx.com';

      await repository.getOrCreateProfile(testUserId, email: testEmail);
      await repository.savePersonalInfo(
        userId: testUserId,
        firstName: 'Suspicious',
        lastName: 'Applicant',
        dateOfBirth: DateTime(1990, 1, 1),
        countryOfResidence: 'Other',
        nationality: 'Other',
        address: '123 Fake Street',
        city: 'Nowhere',
        state: 'Unknown',
        postalCode: '00000',
      );

      final samplePdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x35, 0x0A]);
      await repository.uploadDocument(
        userId: testUserId,
        category: KycDocumentCategory.identity,
        documentType: KycDocumentType.passport,
        fileName: 'fake_passport.pdf',
        bytes: samplePdf,
      );
      await repository.uploadDocument(
        userId: testUserId,
        category: KycDocumentCategory.address,
        documentType: KycDocumentType.bankStatement,
        fileName: 'fake_statement.pdf',
        bytes: samplePdf,
      );

      final submitted = await repository.submitKycApplication(testUserId);

      const rejectReason = 'Invalid or fraudulent document - Mismatch in biometric details';
      final rejected = await repository.adminRejectKyc(
        kycId: submitted.id,
        reviewerEmail: 'compliance@asianfx.com',
        reason: rejectReason,
      );

      expect(rejected.status, equals(KycVerificationStatus.rejected));
      expect(rejected.rejectionReason, equals(rejectReason));

      final auditLogs = await repository.getAuditHistory(rejected.id);
      expect(auditLogs.any((l) => l.action == 'REJECTED' && l.notes!.contains(rejectReason)), isTrue);
    });

    test('Automated Fast-Track KYC AI Verification approves profile immediately (Exness-Speed)', () async {
      const testUserId = 'user_fast_track_ai_99';
      const testEmail = 'fasttrack@asianfx.com';

      await repository.getOrCreateProfile(testUserId, email: testEmail);
      await repository.savePersonalInfo(
        userId: testUserId,
        firstName: 'Ali',
        lastName: 'Raza',
        dateOfBirth: DateTime(1998, 3, 15),
        countryOfResidence: 'Pakistan',
        nationality: 'Pakistani',
        address: 'DHA Phase 5, Commercial Area',
        city: 'Lahore',
        state: 'Punjab',
        postalCode: '54000',
      );

      final samplePdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x35, 0x0A]);
      await repository.uploadDocument(
        userId: testUserId,
        category: KycDocumentCategory.identity,
        documentType: KycDocumentType.cnic,
        fileName: 'cnic.pdf',
        bytes: samplePdf,
      );

      final autoApproved = await repository.autoApproveKyc(testUserId);
      expect(autoApproved.status, equals(KycVerificationStatus.approved));
      expect(autoApproved.reviewedBy, contains('AI Auto-Engine'));

      final auditLogs = await repository.getAuditHistory(autoApproved.id);
      expect(auditLogs.any((l) => l.action == 'AUTO_APPROVED_AI'), isTrue);
    });

    test('Identity-Only KYC Flow: Submits successfully with POI and without POA', () async {
      const testUserId = 'trader_poi_only_01';
      const testEmail = 'poi_only@asianfx.com';

      await repository.getOrCreateProfile(testUserId, email: testEmail);
      await repository.savePersonalInfo(
        userId: testUserId,
        firstName: 'Farhan',
        lastName: 'Khan',
        dateOfBirth: DateTime(1994, 8, 20),
        countryOfResidence: 'Pakistan',
        nationality: 'Pakistani',
        address: 'F-7 Markaz',
        city: 'Islamabad',
        state: 'ICT',
        postalCode: '44000',
      );

      final samplePng = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00]);

      // Upload Front and Back POI (CNIC)
      await repository.uploadDocument(
        userId: testUserId,
        category: KycDocumentCategory.identity,
        documentType: KycDocumentType.cnic,
        fileName: 'cnic_front.png',
        bytes: samplePng,
        documentSide: 'FRONT',
      );
      await repository.uploadDocument(
        userId: testUserId,
        category: KycDocumentCategory.identity,
        documentType: KycDocumentType.cnic,
        fileName: 'cnic_back.png',
        bytes: samplePng,
        documentSide: 'BACK',
      );

      // Verify no POA was uploaded
      final currentProfile = await repository.getOrCreateProfile(testUserId);
      expect(currentProfile.poaDoc, isNull);

      // Submit application without POA - must succeed into PENDING_REVIEW
      final submitted = await repository.submitKycApplication(testUserId);
      expect(submitted.status, equals(KycVerificationStatus.pendingReview));
      expect(submitted.submittedAt, isNotNull);
      expect(submitted.poaDoc, isNull);
      expect(submitted.poiFrontDoc, isNotNull);
    });
  });
}
