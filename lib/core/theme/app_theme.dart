import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: GoogleFonts.poppins().fontFamily,
      scaffoldBackgroundColor: AppColors.background,

      // ── Color scheme ──────────────────────────────────────────────────────
      colorScheme: const ColorScheme.light(
        primary:      AppColors.primary,
        secondary:    AppColors.primaryLight,
        surface:      AppColors.surface,
        error:        AppColors.sos,
        onPrimary:    AppColors.white,
        onSecondary:  AppColors.white,
        onSurface:    AppColors.textPrimary,
        onError:      AppColors.white,
      ),

      // ── AppBar ────────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor:  AppColors.background,
        elevation:        0,
        centerTitle:      true,
        iconTheme:        const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle:   GoogleFonts.poppins(
          fontSize:     18,
          fontWeight:   FontWeight.w700,
          color:        AppColors.textPrimary,
        ),
      ),

      // ── Elevated Button ───────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor:  AppColors.primary,
          foregroundColor:  AppColors.white,
          minimumSize:      const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          textStyle: GoogleFonts.poppins(
            fontSize:   16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),

      // ── Outlined Button ───────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize:     const Size(double.infinity, 56),
          side: const BorderSide(color: AppColors.border, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize:   16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Text Button ───────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.poppins(
            fontSize:   14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Input / TextField ─────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled:      true,
        fillColor:   AppColors.surfaceGrey,
        hintStyle:   GoogleFonts.poppins(
          color:      AppColors.textHint,
          fontSize:   14,
          fontWeight: FontWeight.w400,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   const BorderSide(color: AppColors.sos, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),

      // ── Card ──────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color:     AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.all(0),
      ),

      // ── Bottom Navigation Bar ─────────────────────────────────────────────
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor:      AppColors.surface,
        selectedItemColor:    AppColors.primary,
        unselectedItemColor:  AppColors.textSecondary,
        showSelectedLabels:   true,
        showUnselectedLabels: true,
        type:                 BottomNavigationBarType.fixed,
        elevation:            8,
        selectedLabelStyle: GoogleFonts.poppins(
          fontSize:   10,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.poppins(
          fontSize:   10,
          fontWeight: FontWeight.w400,
        ),
      ),

      // ── Switch ────────────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.white;
          return AppColors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return AppColors.border;
        }),
      ),

      // ── Divider ───────────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color:     AppColors.border,
        thickness: 1,
        space:     1,
      ),

      // ── SnackBar ──────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: GoogleFonts.poppins(
          color:     AppColors.white,
          fontSize:  14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Dialog ────────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: GoogleFonts.poppins(
          fontSize:   20,
          fontWeight: FontWeight.w700,
          color:      AppColors.textPrimary,
        ),
        contentTextStyle: GoogleFonts.poppins(
          fontSize:   14,
          fontWeight: FontWeight.w400,
          color:      AppColors.textSecondary,
        ),
      ),
    );
  }
}