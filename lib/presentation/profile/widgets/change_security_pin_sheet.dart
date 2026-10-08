import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

class ChangeSecurityPinSheet extends StatefulWidget {
  final String userEmail;

  const ChangeSecurityPinSheet({
    super.key,
    required this.userEmail,
  });

  static Future<void> show(BuildContext context, String userEmail) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeSecurityPinSheet(userEmail: userEmail),
    );
  }

  @override
  State<ChangeSecurityPinSheet> createState() => _ChangeSecurityPinSheetState();
}

class _ChangeSecurityPinSheetState extends State<ChangeSecurityPinSheet> {
  final SecureStorageService _storage = SecureStorageService.instance;

  bool _isLoading = true;
  bool _hasExistingPin = false;

  // Steps: 0 = Current PIN (if exists), 1 = New PIN, 2 = Confirm New PIN, 3 = Success
  int _currentStep = 0;

  String _currentPinInput = '';
  String _newPinInput = '';
  String _confirmPinInput = '';

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkExistingPin();
  }

  Future<void> _checkExistingPin() async {
    final hasPin = await _storage.hasSecurityPin(widget.userEmail);
    if (!mounted) return;
    setState(() {
      _hasExistingPin = hasPin;
      _currentStep = hasPin ? 0 : 1;
      _isLoading = false;
    });
  }

  void _onDigitPressed(String digit) {
    HapticFeedback.lightImpact();
    setState(() {
      _errorMessage = null;
      if (_currentStep == 0) {
        if (_currentPinInput.length < 4) {
          _currentPinInput += digit;
          if (_currentPinInput.length == 4) {
            _verifyCurrentPin();
          }
        }
      } else if (_currentStep == 1) {
        if (_newPinInput.length < 4) {
          _newPinInput += digit;
          if (_newPinInput.length == 4) {
            _currentStep = 2;
          }
        }
      } else if (_currentStep == 2) {
        if (_confirmPinInput.length < 4) {
          _confirmPinInput += digit;
          if (_confirmPinInput.length == 4) {
            _saveNewPin();
          }
        }
      }
    });
  }

  void _onBackspacePressed() {
    HapticFeedback.selectionClick();
    setState(() {
      _errorMessage = null;
      if (_currentStep == 0 && _currentPinInput.isNotEmpty) {
        _currentPinInput = _currentPinInput.substring(0, _currentPinInput.length - 1);
      } else if (_currentStep == 1 && _newPinInput.isNotEmpty) {
        _newPinInput = _newPinInput.substring(0, _newPinInput.length - 1);
      } else if (_currentStep == 2 && _confirmPinInput.isNotEmpty) {
        _confirmPinInput = _confirmPinInput.substring(0, _confirmPinInput.length - 1);
      }
    });
  }

  Future<void> _verifyCurrentPin() async {
    final isCorrect = await _storage.verifySecurityPin(widget.userEmail, _currentPinInput);
    if (!mounted) return;
    if (isCorrect) {
      setState(() {
        _currentStep = 1;
        _errorMessage = null;
      });
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _currentPinInput = '';
        _errorMessage = 'Incorrect current PIN. Please try again.';
      });
    }
  }

  Future<void> _saveNewPin() async {
    if (_newPinInput != _confirmPinInput) {
      HapticFeedback.heavyImpact();
      setState(() {
        _confirmPinInput = '';
        _errorMessage = 'PINs do not match. Please try again.';
        _currentStep = 1;
        _newPinInput = '';
      });
      return;
    }

    await _storage.saveSecurityPin(widget.userEmail, _newPinInput);
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() {
      _currentStep = 3; // Success
    });
  }

  String get _activePin {
    if (_currentStep == 0) return _currentPinInput;
    if (_currentStep == 1) return _newPinInput;
    if (_currentStep == 2) return _confirmPinInput;
    return '';
  }

  String get _stepTitle {
    switch (_currentStep) {
      case 0:
        return 'Enter Current PIN';
      case 1:
        return _hasExistingPin ? 'Enter New 4-Digit PIN' : 'Create 4-Digit Security PIN';
      case 2:
        return 'Confirm New PIN';
      case 3:
        return 'PIN Updated Successfully';
      default:
        return 'Security PIN';
    }
  }

  String get _stepSubtitle {
    switch (_currentStep) {
      case 0:
        return 'Please authenticate with your existing security PIN to continue.';
      case 1:
        return 'Set a 4-digit numerical code for high-security actions and trading approval.';
      case 2:
        return 'Re-enter your new 4-digit PIN to confirm.';
      case 3:
        return 'Your new Security PIN is now active and protected.';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: context.scaffoldBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: context.borderColor),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag Handle
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.brandPrimary),
                ),
              )
            else if (_currentStep == 3)
              _buildSuccessState(context)
            else
              _buildPinEntryState(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessState(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 16),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF16C784).withAlpha(30),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF16C784), width: 2),
          ),
          child: const Icon(
            Icons.check_rounded,
            color: Color(0xFF16C784),
            size: 36,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _stepTitle,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: context.textPrimaryColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _stepSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: context.textSecondaryColor,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFDE02),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'Done',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildPinEntryState(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFDE02).withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.lock_outline_rounded, color: Color(0xFFFFDE02), size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  _stepTitle,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimaryColor,
                  ),
                ),
              ],
            ),
            IconButton(
              icon: Icon(Icons.close_rounded, color: context.textSecondaryColor),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _stepSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            color: context.textSecondaryColor,
          ),
        ),
        const SizedBox(height: 24),

        // 4 PIN Dots Indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (index) {
            final isFilled = index < _activePin.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.symmetric(horizontal: 10),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isFilled ? const Color(0xFFFFDE02) : Colors.transparent,
                border: Border.all(
                  color: isFilled ? const Color(0xFFFFDE02) : context.borderColor,
                  width: 2,
                ),
                boxShadow: isFilled
                    ? [
                        BoxShadow(
                          color: const Color(0xFFFFDE02).withAlpha(80),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
            );
          }),
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.redAccent.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.redAccent.withAlpha(80)),
            ),
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: Colors.redAccent,
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),

        // Custom Numeric Dialpad
        _buildNumericKeypad(context),
      ],
    );
  }

  Widget _buildNumericKeypad(BuildContext context) {
    return Column(
      children: [
        for (var row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', 'back'],
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((key) {
                if (key.isEmpty) {
                  return const SizedBox(width: 72, height: 52);
                }
                if (key == 'back') {
                  return InkWell(
                    onTap: _onBackspacePressed,
                    borderRadius: BorderRadius.circular(26),
                    child: SizedBox(
                      width: 72,
                      height: 52,
                      child: Center(
                        child: Icon(
                          Icons.backspace_outlined,
                          color: context.textPrimaryColor,
                          size: 22,
                        ),
                      ),
                    ),
                  );
                }
                return InkWell(
                  onTap: () => _onDigitPressed(key),
                  borderRadius: BorderRadius.circular(26),
                  child: Container(
                    width: 72,
                    height: 52,
                    decoration: BoxDecoration(
                      color: context.cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Center(
                      child: Text(
                        key,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimaryColor,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
