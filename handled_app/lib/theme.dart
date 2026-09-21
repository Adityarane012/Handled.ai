import 'package:flutter/material.dart';

/// Typeface. Inter is vendored in assets/fonts/ and declared in pubspec.yaml
/// rather than pulled through google_fonts — that package's transitive
/// path_provider/objective_c hook breaks on spaces in the home path, which is
/// why it was removed. Set to null to fall back to the platform default.
///
/// Deliberately nullable: ThemeData.fontFamily takes String?, and null is a
/// supported setting here, so the nullability is the point rather than an
/// oversight.
// ignore: unnecessary_nullable_for_final_variable_declarations
const String? _fontFamily = 'Inter';

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

      // Typography: crisp, high-density SaaS look. fontFamily is _fontFamily
      // (null = bundled default) applied via ThemeData.fontFamily below.
      textTheme: ThemeData.dark().textTheme.copyWith(
        displayLarge: const TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: const TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: const TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: const TextStyle(
          color: textSecondary,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: const TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      fontFamily: _fontFamily,

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
        hintStyle: const TextStyle(color: textSecondary),
        labelStyle: const TextStyle(color: textSecondary),
      ),

      // Buttons: Solid but minimal
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryAction,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: textSecondary,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
