import 'package:flutter/material.dart';

/// TarikNa design tokens. Light, clean, blue-first palette.
/// Use these everywhere instead of hard-coded Color(0x...) values.
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF2563EB); // main blue (buttons, icons)
  static const Color primaryDark = Color(0xFF1D4ED8); // gradient end / pressed
  static const Color primaryLight = Color(0xFF3B82F6); // gradient start / hover
  static const Color primarySoft = Color(0xFFEAF0FE); // icon tile backgrounds
  static const Color brandNavy = Color(0xFF1E5AA8); // logo wordmark blue

  // Surfaces
  static const Color background = Color(0xFFF3F6FD); // screen background
  static const Color surface = Color(0xFFFFFFFF); // cards, sheets
  static const Color surfaceAlt = Color(0xFFF1F5FD); // inputs, nested tiles
  static const Color border = Color(0xFFE3E9F5); // hairline card borders

  // Text
  static const Color textPrimary = Color(0xFF0F172A); // headings
  static const Color textSecondary = Color(0xFF64748B); // subtitles
  static const Color textMuted = Color(0xFF94A3B8); // hints, disabled
  static const Color onPrimary = Color(0xFFFFFFFF); // text on blue

  // Semantic
  static const Color success = Color(0xFF16A34A);
  static const Color danger = Color(0xFFE53935);
  static const Color warning = Color(0xFFF59E0B);

  // Effects
  static const Color shadow = Color(0x1A1E3A8A); // soft blue-tinted shadow

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryLight, primary, primaryDark],
  );
}

