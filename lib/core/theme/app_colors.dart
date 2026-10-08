import 'package:flutter/material.dart';

/// FXAsianApp — Complete Color Palette
/// Exness-inspired: near-black surfaces, brand yellow accent,
/// blue for Buy / up candles and red for Sell / down candles.
abstract class AppColors {
  // ── Brand ───────────────────────────────────────────────────────────────────
  static const Color brandPrimary = Color(0xFFFFDE02);   // Brand yellow
  static const Color brandOnLight = Color(0xFF8A6A00);   // Yellow-family text on white
  static const Color brandSecondary = Color(0xFFFFB300); // Amber
  static const Color brandAccent = Color(0xFF2390F3);    // Blue

  static const List<Color> brandGradient = [
    Color(0xFFFFE53B),
    Color(0xFFFFCC00),
  ];

  static const List<Color> goldGradient = [
    Color(0xFFFFB300),
    Color(0xFFFF8F00),
  ];

  // ── Dark Theme Backgrounds ──────────────────────────────────────────────────
  static const Color darkBackground = Color(0xFF0B0E11);
  static const Color darkSurface = Color(0xFF12161A);
  static const Color darkCard = Color(0xFF161B20);
  static const Color darkCardElevated = Color(0xFF1E242A);
  static const Color darkBorder = Color(0xFF262D34);
  static const Color darkDivider = Color(0xFF1F252B);

  // ── Light Theme Backgrounds ─────────────────────────────────────────────────
  static const Color lightBackground = Color(0xFFF4F5F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE3E6EA);

  // ── Text Colors ─────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFE8EBEF);
  static const Color textSecondary = Color(0xFF8A919A);
  static const Color textMuted = Color(0xFF5F6670);
  static const Color textLight = Color(0xFF111418);
  static const Color textDark = Color(0xFF1B1F24);

  // ── Semantic Colors ─────────────────────────────────────────────────────────
  static const Color profit = Color(0xFF16C784);        // Green for gains
  static const Color loss = Color(0xFFE5484D);          // Red for losses
  static const Color warning = Color(0xFFFFBD00);       // Amber
  static const Color info = Color(0xFF2390F3);          // Blue
  static const Color pending = Color(0xFFFF8C00);       // Orange
  static const Color neutral = Color(0xFF8A919A);       // Gray

  // ── Market Colors (Exness: blue up / Buy, red down / Sell) ─────────────────
  static const Color bullCandle = Color(0xFF2390F3);
  static const Color bearCandle = Color(0xFFDB363D);
  static const Color buyButton = Color(0xFF2390F3);
  static const Color sellButton = Color(0xFFDB363D);

  // ── Chart Colors ────────────────────────────────────────────────────────────
  static const Color chartGrid = Color(0xFF232B33);
  static const Color chartLine = Color(0xFF2390F3);
  static const Color chartArea = Color(0x222390F3);
  static const Color crosshair = Color(0xFF8A919A);

  // ── Special Glows ───────────────────────────────────────────────────────────
  static const Color glowGreen = Color(0x4016C784);
  static const Color glowRed = Color(0x40E5484D);
  static const Color glowGold = Color(0x40FFDE02);
  static const Color glowBlue = Color(0x402390F3);

  // ── Gradients ───────────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: brandGradient,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient profitGradient = LinearGradient(
    colors: [Color(0xFF16C784), Color(0xFF0FA36B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient lossGradient = LinearGradient(
    colors: [Color(0xFFE5484D), Color(0xFFC62F35)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradientLinear = LinearGradient(
    colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkCardGradient = LinearGradient(
    colors: [Color(0xFF1A2026), Color(0xFF12161A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
