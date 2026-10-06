import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Reusable FX-branded text field
class FxTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;
  final void Function(String)? onChanged;
  final int maxLines;
  final bool enabled;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;

  const FxTextField({
    super.key,
    this.controller,
    String? label,
    String? labelText,
    String? hint,
    String? hintText,
    this.prefixIcon,
    this.suffixIcon,
    bool obscureText = false,
    bool isPassword = false,
    this.keyboardType,
    this.validator,
    this.onFieldSubmitted,
    this.onChanged,
    this.maxLines = 1,
    this.enabled = true,
    this.textInputAction,
    this.focusNode,
  })  : label = label ?? labelText ?? '',
        hint = hint ?? hintText,
        obscureText = obscureText || isPassword;

  static OutlineInputBorder _border(Color color, {double width = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      onChanged: onChanged,
      maxLines: maxLines,
      enabled: enabled,
      textInputAction: textInputAction,
      focusNode: focusNode,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 15,
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w400,
      ),
      cursorColor: AppColors.brandPrimary,
      // The auth screens are always dark, so the field is styled here instead
      // of inheriting the app theme (a light theme made it a white box with
      // white text).
      decoration: InputDecoration(
        labelText: label.isNotEmpty ? label : null,
        hintText: hint,
        filled: true,
        fillColor: AppColors.darkCard,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.textSecondary),
        floatingLabelStyle: const TextStyle(
            fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brandPrimary),
        hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, size: 20, color: AppColors.textSecondary)
            : null,
        suffixIcon: suffixIcon,
        border: _border(AppColors.darkBorder),
        enabledBorder: _border(AppColors.darkBorder),
        disabledBorder: _border(AppColors.darkBorder),
        focusedBorder: _border(AppColors.brandPrimary, width: 1.5),
        errorBorder: _border(AppColors.loss),
        focusedErrorBorder: _border(AppColors.loss, width: 1.5),
        errorStyle: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.loss),
      ),
    );
  }
}
