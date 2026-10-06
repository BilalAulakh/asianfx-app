import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/kyc_entities.dart';

/// KYC Datasource handling Supabase Private Storage & Database operations
/// with rock-solid offline persistent fallback.
class KycDatasource {
  KycDatasource._();
  static final KycDatasource instance = KycDatasource._();

  static const String _bucketName = 'kyc-documents';
  static const int _maxFileSizeBytes = 10 * 1024 * 1024; // 10MB
  static const List<String> _allowedExtensions = ['jpg', 'jpeg', 'png', 'pdf'];

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  // ── File Validation & Security ──────────────────────────────────────────────

  /// Validates file size, extension, and MIME type to prevent dangerous uploads
  static void validateFile({
    required String fileName,
    required Uint8List bytes,
  }) {
    if (bytes.isEmpty) {
      throw ArgumentError('Uploaded file is empty.');
    }
    if (bytes.length > _maxFileSizeBytes) {
      throw ArgumentError('File exceeds the maximum allowed size of 10MB.');
    }

    final ext = fileName.split('.').last.toLowerCase().trim();
    if (!_allowedExtensions.contains(ext)) {
      throw ArgumentError('Invalid file type ".$ext". Only JPG, JPEG, PNG, and PDF files are permitted.');
    }

    // Header magic bytes check
    if (ext == 'pdf') {
      if (bytes.length < 4 ||
          bytes[0] != 0x25 || // %
          bytes[1] != 0x50 || // P
          bytes[2] != 0x44 || // D
          bytes[3] != 0x46) { // F
        throw ArgumentError('The uploaded file does not match a valid PDF document format.');
      }
    } else if (ext == 'png') {
      if (bytes.length < 4 ||
          bytes[0] != 0x89 ||
          bytes[1] != 0x50 ||
          bytes[2] != 0x4E ||
          bytes[3] != 0x47) {
        throw ArgumentError('The uploaded file does not match a valid PNG image format.');
      }
    } else if (ext == 'jpg' || ext == 'jpeg') {
      if (bytes.length < 2 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
        throw ArgumentError('The uploaded file does not match a valid JPEG image format.');
      }
    }
  }

  /// Instance method proxy for file validation
  void validateDocumentFile({
    required String fileName,
    required Uint8List bytes,
  }) {
    validateFile(fileName: fileName, bytes: bytes);
  }

  /// Sanitize file names to prevent path traversal attacks
  static String sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  // ── Document Storage Upload ────────────────────────────────────────────────

  Future<String?> uploadDocumentFile({
    required String userId,
    required KycDocumentCategory category,
    required String fileName,
    required Uint8List bytes,
  }) async {
    validateFile(fileName: fileName, bytes: bytes);

    final cleanName = sanitizeFileName(fileName);
    final ext = cleanName.split('.').last.toLowerCase();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath = '$userId/${category.code.toLowerCase()}/${timestamp}_$cleanName';

    final client = _client;
    if (client != null) {
      try {
        final mimeType = ext == 'pdf' ? 'application/pdf' : 'image/$ext';
        await client.storage.from(_bucketName).uploadBinary(
              storagePath,
              bytes,
              fileOptions: FileOptions(
                contentType: mimeType,
                upsert: true,
              ),
            );
        return storagePath;
      } catch (e) {
        debugPrint('Supabase storage upload fallback: $e');
      }
    }

    // Local / In-memory fallback
    await _cacheDocumentBytes(storagePath, bytes);
    return storagePath;
  }

  // ── Local Fallback Persistence ─────────────────────────────────────────────

  static final Map<String, Uint8List> _inMemoryByteStore = {};

  Future<void> _cacheDocumentBytes(String path, Uint8List bytes) async {
    _inMemoryByteStore[path] = bytes;
  }

  Uint8List? getDocumentBytes(String path) {
    return _inMemoryByteStore[path];
  }

  // ── Profile Operations ─────────────────────────────────────────────────────

  static const String _localKycProfilesKey = 'local_kyc_profiles_store_v1';
  static const String _localKycAuditKey = 'local_kyc_audit_logs_v1';

  Future<KycProfileEntity?> fetchKycProfile(String userId) async {
    final client = _client;
    if (client != null) {
      try {
        final res = await client
            .from('kyc_profiles')
            .select('*, documents:kyc_documents(*)')
            .eq('user_id', userId)
            .maybeSingle();

        if (res != null) {
          return KycProfileEntity.fromMap(res);
        }
      } catch (e) {
        debugPrint('Fetch KYC profile from Supabase error/fallback: $e');
      }
    }

    // Local Storage Fallback
    final prefs = await SharedPreferences.getInstance();
    final allJson = prefs.getString(_localKycProfilesKey);
    if (allJson != null && allJson.isNotEmpty) {
      try {
        final Map<String, dynamic> all = jsonDecode(allJson);
        if (all.containsKey(userId)) {
          final profileMap = all[userId] as Map<String, dynamic>;
          return KycProfileEntity.fromMap(profileMap);
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> saveKycProfile(KycProfileEntity profile) async {
    final client = _client;
    if (client != null) {
      try {
        // `documents` is a nested list for the local JSON cache, not a column on
        // kyc_profiles. Leaving it in made PostgREST reject the whole upsert
        // (PGRST204), which the catch below swallowed — so KYC records only ever
        // reached on-device storage and never Supabase.
        final row = Map<String, dynamic>.from(profile.toMap())..remove('documents');

        // Verdict columns are owned by the server (trigger fx_kyc_guard_verdict
        // ignores them anyway); sending them only invites confusion.
        row.remove('status');
        row.remove('submitted_at');
        row.remove('reviewed_at');
        row.remove('reviewed_by');
        row.remove('rejection_reason');
        row.remove('resubmission_notes');

        await client.from('kyc_profiles').upsert(row, onConflict: 'id');

        for (final doc in profile.documents) {
          await client.from('kyc_documents').upsert(doc.toMap(), onConflict: 'id');
        }
      } catch (e) {
        debugPrint('Save KYC profile to Supabase fallback: $e');
      }
    }

    // Save to Local Storage
    try {
      final prefs = await SharedPreferences.getInstance();
      final allJson = prefs.getString(_localKycProfilesKey);
      Map<String, dynamic> all = {};
      if (allJson != null && allJson.isNotEmpty) {
        all = jsonDecode(allJson) as Map<String, dynamic>;
      }
      all[profile.userId] = profile.toMap();
      await prefs.setString(_localKycProfilesKey, jsonEncode(all));
    } catch (e) {
      debugPrint('Local storage save KYC profile error: $e');
    }
  }

  Future<List<KycProfileEntity>> fetchAllKycProfiles() async {
    final client = _client;
    if (client != null) {
      try {
        final res = await client.from('kyc_profiles').select('*, documents:kyc_documents(*)');
        if (res.isNotEmpty) {
          return res.map((m) => KycProfileEntity.fromMap(m)).toList();
        }
      } catch (e) {
        debugPrint('Fetch all KYC profiles from Supabase fallback: $e');
      }
    }

    // Local Storage Fallback
    final prefs = await SharedPreferences.getInstance();
    final allJson = prefs.getString(_localKycProfilesKey);
    if (allJson != null && allJson.isNotEmpty) {
      try {
        final Map<String, dynamic> all = jsonDecode(allJson);
        return all.values.map((v) => KycProfileEntity.fromMap(v as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
    return [];
  }

  // ── Server-side verdict transitions ────────────────────────────────────────

  /// Submit the signed-in user's application for manual compliance review.
  ///
  /// The status transition happens inside `rpc_submit_kyc`, which checks that a
  /// profile exists, that at least one document was uploaded, and that it is not
  /// already approved or queued. The applicant cannot set the status directly.
  ///
  /// Throws with a readable message on rejection — deliberately, so a failed
  /// submission is never mistaken for a successful one.
  /// Returned when no Supabase client exists at all (offline preview, unit
  /// tests). Callers fall back to a local PENDING_REVIEW — never to APPROVED.
  static const Map<String, dynamic> offlineResult = {'status': 'offline'};

  Future<Map<String, dynamic>> submitForReview() async {
    final client = _client;
    if (client == null) return offlineResult;
    try {
      final res = await client.rpc('rpc_submit_kyc');
      return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    } on PostgrestException catch (e) {
      throw Exception(_readableRpcError(e.message));
    }
  }

  /// Administrator verdict. [decision] is `APPROVE`, `REJECT` or `RESUBMIT`.
  /// Requires a row in `broker_admins` (or an admin JWT claim) — the database
  /// checks, not the app.
  Future<Map<String, dynamic>> reviewProfile({
    required String kycId,
    required String decision,
    String? notes,
  }) async {
    final client = _client;
    if (client == null) return offlineResult;
    try {
      final res = await client.rpc('rpc_review_kyc', params: {
        'p_kyc_id': kycId,
        'p_decision': decision,
        'p_notes': notes,
      });
      return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    } on PostgrestException catch (e) {
      throw Exception(_readableRpcError(e.message));
    }
  }

  /// RPCs raise `CODE: explanation`; show the explanation, drop the code.
  static String _readableRpcError(String raw) {
    final m = RegExp(r'^[A-Z][A-Z0-9_]{2,}:\s*(.+)$', dotAll: true).firstMatch(raw.trim());
    return m != null ? m.group(1)!.trim() : raw;
  }

  // ── Audit Logging ──────────────────────────────────────────────────────────

  Future<void> logAuditAction(KycAuditLogEntry log) async {
    final client = _client;
    if (client != null) {
      try {
        await client.from('kyc_audit_logs').insert(log.toMap());
      } catch (e) {
        debugPrint('Supabase audit log fallback: $e');
      }
    }

    // Local Storage
    try {
      final prefs = await SharedPreferences.getInstance();
      final logsJson = prefs.getString(_localKycAuditKey);
      List<dynamic> logs = [];
      if (logsJson != null && logsJson.isNotEmpty) {
        logs = jsonDecode(logsJson) as List<dynamic>;
      }
      logs.insert(0, log.toMap());
      await prefs.setString(_localKycAuditKey, jsonEncode(logs));
    } catch (_) {}
  }

  Future<List<KycAuditLogEntry>> fetchAuditLogs(String kycId) async {
    final client = _client;
    if (client != null) {
      try {
        final res = await client
            .from('kyc_audit_logs')
            .select()
            .eq('kyc_id', kycId)
            .order('timestamp', ascending: false);
        if (res.isNotEmpty) {
          return res.map((m) => KycAuditLogEntry.fromMap(m)).toList();
        }
      } catch (e) {
        debugPrint('Fetch audit logs from Supabase fallback: $e');
      }
    }

    // Local Storage Fallback
    final prefs = await SharedPreferences.getInstance();
    final logsJson = prefs.getString(_localKycAuditKey);
    if (logsJson != null && logsJson.isNotEmpty) {
      try {
        final List<dynamic> logs = jsonDecode(logsJson);
        return logs
            .map((m) => KycAuditLogEntry.fromMap(m as Map<String, dynamic>))
            .where((l) => l.kycId == kycId)
            .toList();
      } catch (_) {}
    }
    return [];
  }
}
