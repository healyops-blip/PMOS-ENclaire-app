import 'package:flutter/material.dart';

const pomiInk = Color(0xFF1C1C1E);
const pomiMuted = Color(0xFF8E8E93);
const pomiPurple = Color(0xFF6A4C93);
const pomiPurpleSoft = Color(0xFF9B8CC9);
const pomiLavender = Color(0xFFF5F0F9);
const pomiMint = Color(0xFF27D2BF);
const pomiSuccess = Color(0xFF2D8B4E);
const pomiCoral = Color(0xFFE8917C);
const pomiPaper = Color(0xFFF8F5FA);
const pomiLine = Color(0xFFECE6F1);

const pomiTeal = pomiPurple;

const pomiHeroGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFF6A4C93),
    Color(0xFF8B6FAD),
    Color(0xFFA78DC0),
    Color(0xFFC4B0D4),
  ],
  stops: [0, .4, .7, 1],
);

ThemeData buildPomiTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: pomiPurple,
    brightness: Brightness.light,
    primary: pomiPurple,
    secondary: pomiMint,
    surface: Colors.white,
    onSurface: pomiInk,
    error: const Color(0xFFC62828),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: pomiPaper,
    fontFamily: 'Noto Sans SC',
    fontFamilyFallback: const [
      'Source Han Sans SC',
      'Noto Sans CJK SC',
      'Noto Sans SC',
      'PingFang SC',
      'Microsoft YaHei',
      'sans-serif',
    ],
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 24,
        height: 32 / 24,
        fontWeight: FontWeight.w800,
        color: pomiInk,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        height: 26 / 18,
        fontWeight: FontWeight.w800,
        color: pomiInk,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 24 / 16,
        fontWeight: FontWeight.w700,
        color: pomiInk,
      ),
      bodyMedium: TextStyle(fontSize: 15, height: 24 / 15, color: pomiInk),
      bodySmall: TextStyle(fontSize: 13, height: 20 / 13, color: pomiMuted),
    ),
    cardTheme: const CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: pomiLine),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF9F9FB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: pomiLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: pomiLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: pomiPurple, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: const StadiumBorder(),
        side: const BorderSide(color: Color(0xFFD8CCE4)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: pomiPaper,
      foregroundColor: pomiInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: pomiInk,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: pomiLavender,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight:
              states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? pomiPurple : pomiMuted,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: pomiLine,
      thickness: 1,
      space: 1,
    ),
  );
}
