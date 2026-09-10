import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import '../../domain/entities/user_entity.dart';
import '../../providers/auth_provider.dart';
import '../../providers/kyc_compliance_provider.dart';

class KycFlowScreen extends ConsumerStatefulWidget {
  const KycFlowScreen({super.key});

  @override
  ConsumerState<KycFlowScreen> createState() => _KycFlowScreenState();
}

class _KycFlowScreenState extends ConsumerState<KycFlowScreen> {
  String _selectedDocType = 'Passport';
  final _docNumberController = TextEditingController(text: 'GB88234199');
  bool _isSubmitting = false;

  final List<String> _docTypes = [
    'Passport',
    'National ID / CNIC',
    'Driving License',
    'Trade License',
  ];

  @override
  void dispose() {
    _docNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authProvider).user;
    final kycStatus = authUser?.kycStatus ?? KycStatus.notSubmitted;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151D28),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'KYC Verification',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Current KYC Status Banner ──────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getStatusColor(kycStatus).withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _getStatusColor(kycStatus)),
              ),
              child: Row(
                children: [
                  Icon(_getStatusIcon(kycStatus), color: _getStatusColor(kycStatus), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'KYC STATUS: ${authUser?.kycStatusDisplay.toUpperCase() ?? "NOT SUBMITTED"}',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: _getStatusColor(kycStatus),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getStatusDescription(kycStatus),
                          style: const TextStyle(fontSize: 11, color: Color(0xFF848E9C)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Document Submission Form ───────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF151D28),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1C2535)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Identity Document Submission',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Document Type Selector
                  const Text(
                    'Document Type',
                    style: TextStyle(fontSize: 12, color: Color(0xFF848E9C), fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _selectedDocType,
                    dropdownColor: const Color(0xFF151D28),
                    style: const TextStyle(color: Colors.white, fontFamily: 'Inter'),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      fillColor: const Color(0xFF0F141C),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: _docTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedDocType = val);
                    },
                  ),
                  const SizedBox(height: 14),

                  // Document Number Input
                  const Text(
                    'Document Identification Number',
                    style: TextStyle(fontSize: 12, color: Color(0xFF848E9C), fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _docNumberController,
                    style: const TextStyle(color: Colors.white, fontFamily: 'Inter'),
                    decoration: const InputDecoration(
                      hintText: 'e.g. Passport or National ID Number',
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Document Upload Boxes Simulation
                  Row(
                    children: [
                      _uploadBox('Front of ID / Passport'),
                      const SizedBox(width: 12),
                      _uploadBox('Proof of Residence'),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Submit Button
                  ElevatedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () async {
                            setState(() => _isSubmitting = true);
                            await Future.delayed(const Duration(milliseconds: 600));

                            ref.read(kycComplianceProvider.notifier).submitNewKyc(
                                  documentType: _selectedDocType,
                                  documentNumber: _docNumberController.text,
                                );

                            setState(() => _isSubmitting = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: Color(0xFF00D68F),
                                  content: Text('✓ KYC Application submitted to Compliance Review queue.'),
                                ),
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD600),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isSubmitting
                        ? const CircularProgressIndicator(color: Colors.black)
                        : const Text('SUBMIT FOR AML & KYC APPROVAL', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _uploadBox(String label) {
    return Expanded(
      child: Container(
        height: 90,
        decoration: BoxDecoration(
          color: const Color(0xFF0F141C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2B384E), style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_upload_outlined, color: Color(0xFFFFD600), size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Color(0xFF848E9C)),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(KycStatus status) {
    switch (status) {
      case KycStatus.approved:
        return const Color(0xFF00D68F);
      case KycStatus.pending:
        return const Color(0xFFFFB300);
      case KycStatus.rejected:
      case KycStatus.restricted:
        return const Color(0xFFFF4757);
      case KycStatus.notSubmitted:
        return const Color(0xFF848E9C);
    }
  }

  IconData _getStatusIcon(KycStatus status) {
    switch (status) {
      case KycStatus.approved:
        return Icons.verified_rounded;
      case KycStatus.pending:
        return Icons.hourglass_top_rounded;
      case KycStatus.rejected:
        return Icons.cancel_rounded;
      case KycStatus.restricted:
        return Icons.block_rounded;
      case KycStatus.notSubmitted:
        return Icons.info_outline_rounded;
    }
  }

  String _getStatusDescription(KycStatus status) {
    switch (status) {
      case KycStatus.approved:
        return 'Full live trading & withdrawal capabilities enabled.';
      case KycStatus.pending:
        return 'Application under AML compliance review. Verification typically takes 10-15 mins.';
      case KycStatus.rejected:
        return 'Documents could not be verified. Please resubmit clear official identification.';
      case KycStatus.restricted:
        return 'Account on temporary operational hold. Contact support.';
      case KycStatus.notSubmitted:
        return 'Please submit identity proof to unlock trading and vault disbursements.';
    }
  }
}
