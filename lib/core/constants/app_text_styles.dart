import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  // ── Display / Hero ────────────────────────────────────────────────────────
  static TextStyle get displayLarge => GoogleFonts.poppins(
        fontSize: 44,
        fontWeight: FontWeight.w800,
        color: AppColors.white,
        letterSpacing: -0.5,
        height: 1.0,
      );

  static TextStyle get displayMedium => GoogleFonts.poppins(
        fontSize: 36,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        letterSpacing: -0.3,
        height: 1.1,
      );

  static TextStyle get displaySmall => GoogleFonts.poppins(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: -0.2,
        height: 1.2,
      );

  // ── Headings ──────────────────────────────────────────────────────────────
  static TextStyle get headingLarge => GoogleFonts.poppins(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  static TextStyle get headingMedium => GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  static TextStyle get headingSmall => GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  // ── Body ──────────────────────────────────────────────────────────────────
  static TextStyle get bodyLarge => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        height: 1.6,
      );

  static TextStyle get bodyMedium => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        height: 1.5,
      );

  static TextStyle get bodySmall => GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        height: 1.5,
      );

  // ── Labels ────────────────────────────────────────────────────────────────
  static TextStyle get labelLarge => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: 0.2,
      );

  static TextStyle get labelMedium => GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: 0.3,
      );

  static TextStyle get labelSmall => GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        letterSpacing: 1.2,
      );

  // ── Buttons ───────────────────────────────────────────────────────────────
  static TextStyle get buttonLarge => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.white,
        letterSpacing: 0.3,
      );

  static TextStyle get buttonMedium => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.white,
        letterSpacing: 0.2,
      );

  // ── Caption / Badge ───────────────────────────────────────────────────────
  static TextStyle get caption => GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppColors.textHint,
        letterSpacing: 0.5,
      );

  static TextStyle get badge => GoogleFonts.poppins(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.white,
        letterSpacing: 1.5,
      );

  // ── Tagline (used on splash) ───────────────────────────────────────────────
  static TextStyle get tagline => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.white.withOpacity(0.85),
        letterSpacing: 0.3,
      );

  // ── Privacy pill / uppercase labels ──────────────────────────────────────
  static TextStyle get pillLabel => GoogleFonts.poppins(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: AppColors.white.withOpacity(0.9),
        letterSpacing: 1.2,
      );

  // ── Timer display (session screen) ───────────────────────────────────────
  static TextStyle get timerDisplay => GoogleFonts.poppins(
        fontSize: 52,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
        letterSpacing: -1.0,
        height: 1.0,
      );

  // ── SOS screen ────────────────────────────────────────────────────────────
  static TextStyle get sosHeading => GoogleFonts.poppins(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        color: AppColors.white,
        height: 1.2,
      );

  static TextStyle get sosCountdown => GoogleFonts.poppins(
        fontSize: 72,
        fontWeight: FontWeight.w800,
        color: AppColors.white,
        height: 1.0,
      );

  // ── Helpers: copy style with color override ───────────────────────────────
  static TextStyle withColor(TextStyle style, Color color) =>
      style.copyWith(color: color);

  static TextStyle withSize(TextStyle style, double size) =>
      style.copyWith(fontSize: size);
}