import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Linear-inspired minimal dark palette
  static const Color background = Color(0xFF09090B); // Deep near-black
  static const Color surface = Color(0xFF121214); // Slightly elevated
  static const Color surfaceHighlight = Color(0xFF1E1E20); // Hover states
  static const Color border = Color(0xFF27272A); // Subtle dividers

  static const Color textPrimary = Color(0xFFFAFAFA); // High contrast text
  static const Color textSecondary = Color(0xFFA1A1AA); // Muted text

  // A muted, sophisticated primary action color, avoiding loud gradients
  static const Color primaryAction = Color(0xFF5E6AD2);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primaryAction,

      // Typography: Inter for a crisp, high-density SaaS look
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme)
          .copyWith(
            displayLarge: GoogleFonts.inter(
              color: textPrimary,
              fontWeight: FontWeight.w700,
            ),
            titleLarge: GoogleFonts.inter(
              color: textPrimary,
              fontWeight: FontWeight.w600,
            ),
            bodyLarge: GoogleFonts.inter(
              color: textPrimary,
              fontWeight: FontWeight.w400,
            ),
            bodyMedium: GoogleFonts.inter(
              color: textSecondary,
              fontWeight: FontWeight.w400,
            ),
            labelLarge: GoogleFonts.inter(
              color: textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),

      // Input fields: clean, bordered, no heavy fills
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: primaryAction, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: GoogleFonts.inter(color: textSecondary),
        labelStyle: GoogleFonts.inter(color: textSecondary),
      ),

      // Buttons: Solid but minimal
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryAction,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: textSecondary,
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
