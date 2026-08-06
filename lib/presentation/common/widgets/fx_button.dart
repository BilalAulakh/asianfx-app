import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Reusable FX-branded button with loading state, gradient and outlined variants
class FxButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isOutlined;
  final bool isSmall;
  final Color? backgroundColor;
  final Color? textColor;
  final IconData? icon;
  final double? width;

  FxButton({
    super.key,
    String? label,
    String? text,
    this.onPressed,
    this.isLoading = false,
    this.isOutlined = false,
    this.isSmall = false,
    this.backgroundColor,
    this.textColor,
    this.icon,
    this.width,
  }) : label = label ?? text ?? '';

  @override
  Widget build(BuildContext context) {
    final height = isSmall ? 40.0 : 52.0;
    final fontSize = isSmall ? 13.0 : 16.0;

    if (isOutlined) {
      return SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: backgroundColor ?? AppColors.brandPrimary,
              width: 1.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _buildContent(fontSize, backgroundColor ?? AppColors.brandPrimary),
        ),
      );
    }

    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: onPressed != null && !isLoading
              ? LinearGradient(
                  colors: backgroundColor != null
                      ? [backgroundColor!, backgroundColor!]
                      : [const Color(0xFF00C896), const Color(0xFF00B0CC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: onPressed == null || isLoading ? AppColors.darkBorder : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: onPressed != null && !isLoading
              ? [
                  BoxShadow(
                    color: (backgroundColor ?? AppColors.brandPrimary).withAlpha(50),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: textColor ?? Colors.black,
            minimumSize: Size(width ?? double.infinity, height),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _buildContent(fontSize, textColor ?? Colors.black),
        ),
      ),
    );
  }

  Widget _buildContent(double fontSize, Color color) {
    if (isLoading) {
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: isOutlined ? AppColors.brandPrimary : Colors.black,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

/// Buy button (green gradient)
class BuyButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  const BuyButton({super.key, this.onPressed, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    return FxButton(
      label: 'BUY',
      onPressed: onPressed,
      isLoading: isLoading,
      backgroundColor: AppColors.buyButton,
      textColor: Colors.white,
    );
  }
}

/// Sell button (red gradient)
class SellButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  const SellButton({super.key, this.onPressed, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.lossGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.loss.withAlpha(50),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : const Text(
                  'SELL',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}
