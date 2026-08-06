import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Generic FX card with consistent styling
class FxCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Color? borderColor;
  final BorderRadius? borderRadius;
  final bool hasBorder;
  final VoidCallback? onTap;

  FxCard({
    super.key,
    required this.child,
    this.padding,
    Color? color,
    Color? backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.hasBorder = true,
    this.onTap,
  }) : color = color ?? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final borderCol = borderColor ?? AppColors.darkBorder;
    final container = Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? AppColors.darkCard,
        borderRadius: borderRadius ?? BorderRadius.circular(16),
        border: hasBorder ? Border.all(color: borderCol) : null,
      ),
      child: child,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: borderRadius ?? BorderRadius.circular(16),
        child: container,
      );
    }
    return container;
  }
}

/// Gradient card
class FxGradientCard extends StatelessWidget {
  final Widget child;
  final LinearGradient gradient;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;

  const FxGradientCard({
    super.key,
    required this.child,
    required this.gradient,
    this.padding,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: borderRadius ?? BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}
