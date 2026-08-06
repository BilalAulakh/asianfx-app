import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../common/widgets/fx_button.dart';
import '../common/widgets/fx_card.dart';

class KycScreen extends StatefulWidget {
  const KycScreen({super.key});

  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  int _currentStep = 0;
  bool _isUploading = false;
  String _selectedDocType = 'Passport';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Identity Verification (KYC)', style: TextStyle(color: AppColors.textPrimary)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Status Banner
            FxCard(
              backgroundColor: AppColors.brandPrimary.withOpacity(0.1),
              borderColor: AppColors.brandPrimary,
              child: const Row(
                children: [
                  Icon(Icons.verified_user, color: AppColors.brandPrimary, size: 36),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'KYC Level 2 Verified',
                          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Your limits: Unlimited deposits & \$50,000/day withdrawal',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Document Selection
            FxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Document Type',
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  _buildDocOption('Passport', Icons.menu_book),
                  _buildDocOption('National ID / CNIC', Icons.credit_card),
                  _buildDocOption('Driver License', Icons.directions_car),
                  const SizedBox(height: 20),

                  // Upload Zone
                  Container(
                    width: double.infinity,
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppColors.darkSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.darkBorder, style: BorderStyle.solid),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_upload_outlined, color: AppColors.brandPrimary, size: 40),
                        const SizedBox(height: 8),
                        Text(
                          'Upload Front Side of $_selectedDocType',
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        const Text('JPG, PNG or PDF (Max 10MB)', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  FxButton(
                    text: 'Submit Document',
                    isLoading: _isUploading,
                    onPressed: () async {
                      setState(() => _isUploading = true);
                      await Future.delayed(const Duration(seconds: 1));
                      setState(() => _isUploading = false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Document submitted for review!')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocOption(String title, IconData icon) {
    final isSelected = _selectedDocType == title;
    return RadioListTile<String>(
      value: title,
      groupValue: _selectedDocType,
      onChanged: (val) => setState(() => _selectedDocType = val!),
      activeColor: AppColors.brandPrimary,
      title: Row(
        children: [
          Icon(icon, color: isSelected ? AppColors.brandPrimary : AppColors.textSecondary, size: 20),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
