import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Reusable shimmer placeholder loading skeleton for FXAsianApp
class FxShimmer extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final ShapeBorder? shapeBorder;

  const FxShimmer({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8.0,
    this.shapeBorder,
  });

  const FxShimmer.circular({
    super.key,
    required double size,
  })  : width = size,
        height = size,
        borderRadius = size / 2,
        shapeBorder = const CircleBorder();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF1E293B) : Colors.grey[300]!;
    final highlightColor = isDark ? const Color(0xFF334155) : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        width: width,
        height: height,
        decoration: ShapeDecoration(
          color: baseColor,
          shape: shapeBorder ??
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(borderRadius),
              ),
        ),
      ),
    );
  }
}
