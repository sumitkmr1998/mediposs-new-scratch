import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // -- Color Palette --
  static const Color primary = Color(0xFF0D7377);
  static const Color primaryLight = Color(0xFF14A085);
  static const Color accent = Color(0xFFF2B705);
  static const Color danger = Color(0xFFE63946);
  static const Color success = Color(0xFF2DC653);
  static const Color warning = Color(0xFFF4A261);
  static const Color warningDark = Color(0xFFD97706);

  // Extended palette for uniform design language
  static const Color purple = Color(0xFF7C3AED);
  static const Color indigo = Color(0xFF6366F1);
  static const Color emerald = Color(0xFF10B981);
  static const Color emeraldDark = Color(0xFF059669);
  static const Color teal = Color(0xFF14B8A6);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color sky = Color(0xFF0EA5E9);
  static const Color orange = Color(0xFFF59E0B);
  static const Color redDark = Color(0xFFB91C1C);
  static const Color amberDark = Color(0xFFD97706);

  // Utility colors
  static const Color inputBg = Color(0xFFF7F9FB);
  static const Color inputBgDark = Color(0xFF1A2A3A);

  // Design Tokens
  static const double radiusCard = 16.0;
  static const double radiusInput = 12.0;
  static const double radiusButton = 12.0;
  static const double radiusDialog = 24.0;
  static const double radiusChip = 10.0;
  static const double radiusAvatar = 14.0;
  static const double paddingScreen = 16.0;
  static const double paddingCard = 20.0;
  static const double sectionSpacing = 16.0;

  // Spacing Scale
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 12.0;
  static const double spacingLg = 16.0;
  static const double spacingXl = 20.0;
  static const double spacingXxl = 24.0;
  static const double spacingXxxl = 32.0;

  // Shadow Presets
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 2),
        ),
      ];
  static List<BoxShadow> get elevatedShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 24,
          offset: const Offset(0, 4),
        ),
      ];
  static List<BoxShadow> get subtleShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.02),
          blurRadius: 8,
          offset: const Offset(0, 1),
        ),
      ];

  // Dark theme
  static const Color darkBg = Color(0xFF0F1923);
  static const Color darkSurface = Color(0xFF162130);
  static const Color darkCard = Color(0xFF1E2D3D);
  static const Color darkBorder = Color(0xFF263547);
  static const Color darkText = Color(0xFFE8EDF2);
  static const Color darkTextMuted = Color(0xFF8FA3B1);

  // Light theme
  static const Color lightBg = Color(0xFFF0F4F8);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFDDE3EC);
  static const Color lightText = Color(0xFF1A2332);
  static const Color lightTextMuted = Color(0xFF6B7B8D);

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: primaryLight,
        tertiary: accent,
        surface: darkSurface,
        error: danger,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: darkText,
      ),
      textTheme: GoogleFonts.outfitTextTheme(
        ThemeData.dark().textTheme.copyWith(
              bodySmall: const TextStyle(color: darkTextMuted),
            ),
      ).apply(bodyColor: darkText, displayColor: darkText),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        labelStyle: const TextStyle(color: darkTextMuted),
        hintStyle: const TextStyle(color: darkTextMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: darkText,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: darkText,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkBorder,
        selectedColor: primary,
        labelStyle: const TextStyle(color: darkText),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerColor: darkBorder,
      iconTheme: const IconThemeData(color: darkTextMuted),
    );
  }

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBg,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: primaryLight,
        tertiary: accent,
        surface: lightSurface,
        error: danger,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: lightText,
      ),
      textTheme: GoogleFonts.outfitTextTheme(
        ThemeData.light().textTheme,
      ).apply(bodyColor: lightText, displayColor: lightText),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: lightBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: lightSurface,
        foregroundColor: lightText,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: lightText,
        ),
      ),
      dividerColor: lightBorder,
    );
  }
}

extension ThemeExtension on BuildContext {
  Color get bgColor => Theme.of(this).scaffoldBackgroundColor;
  Color get surfaceColor => Theme.of(this).colorScheme.surface;
  Color get cardColor => Theme.of(this).cardColor;
  Color get borderColor => Theme.of(this).dividerColor;
  Color get textColor => Theme.of(this).colorScheme.onSurface;
  Color get textMutedColor =>
      Theme.of(this).colorScheme.onSurface.withValues(alpha: 0.6);
}
