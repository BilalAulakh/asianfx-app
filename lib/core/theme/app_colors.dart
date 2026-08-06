import 'package:flutter/material.dart';

/// FXAsianApp — Complete Color Palette
/// Primary brand: Deep Teal → Gold gradient
/// Dark mode first design
abstract class AppColors {
  // ── Brand Gradient ──────────────────────────────────────────────────────────
  static const Color brandPrimary = Color(0xFF00C896);   // Teal Green
  static const Color brandSecondary = Color(0xFFFFB300); // Gold
  static const Color brandAccent = Color(0xFF5C6BC0);    // Indigo

  static const List<Color> brandGradient = [
    Color(0xFF00C896),
    Color(0xFF00B0CC),
  ];

  static const List<Color> goldGradient = [
    Color(0xFFFFB300),
    Color(0xFFFF8F00),
  ];

  // ── Dark Theme Backgrounds ──────────────────────────────────────────────────
  static const Color darkBackground = Color(0xFF080C14);
  static const Color darkSurface = Color(0xFF0F1520);
  static const Color darkCard = Color(0xFF151D2E);
  static const Color darkCardElevated = Color(0xFF1A2338);
  static const Color darkBorder = Color(0xFF222D42);
  static const Color darkDivider = Color(0xFF1C2535);

  // ── Light Theme Backgrounds ─────────────────────────────────────────────────
  static const Color lightBackground = Color(0xFFF0F4F8);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);

  // ── Text Colors ─────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF0F4FF);
  static const Color textSecondary = Color(0xFF8B95A8);
  static const Color textMuted = Color(0xFF4A5568);
  static const Color textLight = Color(0xFF1A202C);
  static const Color textDark = Color(0xFF2D3748);

  // ── Semantic Colors ─────────────────────────────────────────────────────────
  static const Color profit = Color(0xFF00D68F);       // Green for gains
  static const Color loss = Color(0xFFFF4757);          // Red for losses
  static const Color warning = Color(0xFFFFBD00);       // Amber
  static const Color info = Color(0xFF3D91FF);           // Blue
  static const Color pending = Color(0xFFFF8C00);        // Orange
  static const Color neutral = Color(0xFF8B95A8);        // Gray

  // ── Market Colors ───────────────────────────────────────────────────────────
  static const Color bullCandle = Color(0xFF00D68F);
  static const Color bearCandle = Color(0xFFFF4757);
  static const Color buyButton = Color(0xFF00D68F);
  static const Color sellButton = Color(0xFFFF4757);

  // ── Chart Colors ────────────────────────────────────────────────────────────
  static const Color chartGrid = Color(0xFF1E2A3A);
  static const Color chartLine = Color(0xFF00C896);
  static const Color chartArea = Color(0x2200C896);
  static const Color crosshair = Color(0xFF8B95A8);

  // ── Special Glows ───────────────────────────────────────────────────────────
  static const Color glowGreen = Color(0x4000D68F);
  static const Color glowRed = Color(0x40FF4757);
  static const Color glowGold = Color(0x40FFB300);
  static const Color glowBlue = Color(0x403D91FF);

  // ── Gradients ───────────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00C896), Color(0xFF00B0CC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient profitGradient = LinearGradient(
    colors: [Color(0xFF00D68F), Color(0xFF00B09B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient lossGradient = LinearGradient(
    colors: [Color(0xFFFF4757), Color(0xFFFF1744)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradientLinear = LinearGradient(
    colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkCardGradient = LinearGradient(
    colors: [Color(0xFF151D2E), Color(0xFF0F1520)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
