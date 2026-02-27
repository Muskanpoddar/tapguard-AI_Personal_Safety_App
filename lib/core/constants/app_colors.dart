import 'package:flutter/material.dart';

class AppColors {
  AppColors._(); // prevent instantiation

  // ── Primary Purple ────────────────────────────────────────────────────────
  static const Color primary        = Color(0xFF7C4DFF);
  static const Color primaryLight   = Color(0xFF9B6DFF);
  static const Color primaryDark    = Color(0xFF5B2FD4);
  static const Color primarySoft    = Color(0xFFEDE7FF); // light bg tint

  // ── Gradient stops ────────────────────────────────────────────────────────
  static const List<Color> splashGradient = [
    Color(0xFF9B3FF7),
    Color(0xFF7C4DFF),
    Color(0xFF6E3FE8),
    Color(0xFF5B2FD4),
  ];

  static const List<Color> primaryGradient = [
    Color(0xFF9B6DFF),
    Color(0xFF7C4DFF),
  ];

  // ── Emergency / SOS ───────────────────────────────────────────────────────
  static const Color sos            = Color(0xFFFF3B30);
  static const Color sosDark        = Color(0xFFCC2A21);
  static const Color sosLight       = Color(0xFFFFECEB);

  // ── Status colors ─────────────────────────────────────────────────────────
  static const Color success        = Color(0xFF34C759); // safe / connected
  static const Color warning        = Color(0xFFFF9500); // caution
  static const Color error          = Color(0xFFFF3B30); // danger
  static const Color info           = Color(0xFF007AFF); // info

  // ── Neutrals ──────────────────────────────────────────────────────────────
  static const Color white          = Color(0xFFFFFFFF);
  static const Color background     = Color(0xFFF4F3F8); // app bg
  static const Color surface        = Color(0xFFFFFFFF); // card bg
  static const Color surfaceGrey    = Color(0xFFF0EFF5); // subtle card

  // ── Text ──────────────────────────────────────────────────────────────────
  static const Color textPrimary    = Color(0xFF1A1A2E); // headings
  static const Color textSecondary  = Color(0xFF6B6B8A); // body / subtext
  static const Color textHint       = Color(0xFFAAAAAC); // placeholder

  // ── Borders ───────────────────────────────────────────────────────────────
  static const Color border         = Color(0xFFE8E6F0);
  static const Color borderFocus    = Color(0xFF7C4DFF);

  // ── Map overlay ───────────────────────────────────────────────────────────
  static const Color mapOverlay     = Color(0x337C4DFF); // purple zone fill
  static const Color mapRoute       = Color(0xFF7C4DFF); // dashed route line

  // ── Transparency helpers ──────────────────────────────────────────────────
  static Color primaryWithOpacity(double opacity) =>
      primary.withOpacity(opacity);

  static Color whiteWithOpacity(double opacity) =>
      white.withOpacity(opacity);

  static Color sosWithOpacity(double opacity) =>
      sos.withOpacity(opacity);
}