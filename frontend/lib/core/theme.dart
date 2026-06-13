import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const sidebar = Color(0xFF1B2A3B);
  static const sidebarSelected = Color(0xFF2563EB);
  static const sidebarHover = Color(0xFF243447);
  static const primary = Color(0xFF0077C5);
  static const primaryDark = Color(0xFF005A9C);
  static const accent = Color(0xFF2CA01C);
  static const background = Color(0xFFF0F2F5);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF1A202C);
  static const textSecondary = Color(0xFF718096);
  static const textLight = Color(0xFFFFFFFF);
  static const divider = Color(0xFFE2E8F0);
  static const error = Color(0xFFE53E3E);
  static const warning = Color(0xFFD69E2E);
  static const success = Color(0xFF38A169);
  static const info = Color(0xFF3182CE);

  // Status colors
  static const statusPaid = Color(0xFF38A169);
  static const statusPartial = Color(0xFFD69E2E);
  static const statusUnpaid = Color(0xFFE53E3E);
  static const statusPending = Color(0xFF718096);
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: AppColors.surface,
        background: AppColors.background,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.inter(
            fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        displayMedium: GoogleFonts.inter(
            fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        titleLarge: GoogleFonts.inter(
            fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        titleMedium: GoogleFonts.inter(
            fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        bodyLarge: GoogleFonts.inter(fontSize: 15, color: AppColors.textPrimary),
        bodyMedium: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
        bodySmall: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
        labelLarge: GoogleFonts.inter(
            fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
        labelStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.divider, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(
            fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        toolbarHeight: 64,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.background,
        labelStyle: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
    );
  }
}

// Status badge helper
Color statusColor(String status) {
  switch (status.toUpperCase()) {
    case 'PAID':
    case 'paid':
      return AppColors.statusPaid;
    case 'PARTIAL':
    case 'partial':
      return AppColors.statusPartial;
    case 'UNPAID':
    case 'unpaid':
    case 'pending':
    case 'PENDING':
      return AppColors.statusUnpaid;
    default:
      return AppColors.statusPending;
  }
}

String statusLabel(String status) {
  switch (status.toUpperCase()) {
    case 'PAID':
      return 'Payé';
    case 'PARTIAL':
      return 'Partiel';
    case 'UNPAID':
      return 'Impayé';
    case 'PENDING':
      return 'En attente';
    case 'CANCELLED':
      return 'Annulé';
    default:
      return status;
  }
}
