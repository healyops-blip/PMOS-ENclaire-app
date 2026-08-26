import 'package:flutter/material.dart';

abstract final class PomiColors {
  static const primary = Color(0xFF6A4C93);
  static const primarySoft = Color(0xFFB5A5D6);
  static const primaryPale = Color(0xFFF5F0F9);
  static const text = Color(0xFF1C1C1E);
  static const textMuted = Color(0xFF8E8E93);
  static const success = Color(0xFF2D8B4E);
  static const warning = Color(0xFFE8917C);
  static const accent = Color(0xFF27D2BF);
  static const glowPink = Color(0xFFD250F7);
  static const glowYellow = Color(0xFFF1E584);
  static const surfaceMuted = Color(0xFFF9F9FB);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF6A4C93),
      Color(0xFF8B6FAD),
      Color(0xFFA78DC0),
      Color(0xFFC4B0D4),
    ],
  );
}

abstract final class PomiTheme {
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: PomiColors.primary,
      brightness: Brightness.light,
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.white,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: PomiColors.text,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        titleLarge: TextStyle(
          color: PomiColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: PomiColors.text,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: TextStyle(
          color: PomiColors.text,
          fontSize: 14,
          height: 1.45,
        ),
        bodySmall: TextStyle(
          color: PomiColors.textMuted,
          fontSize: 12,
          height: 1.4,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PomiColors.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0x226A4C93)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0x226A4C93)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: PomiColors.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: PomiColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
