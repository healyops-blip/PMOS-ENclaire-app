import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Primary text: Figma #141422 at 100%.
const pomiInk = Color(0xFF141422);

/// Greeting/supporting copy: Figma #39394E at 90%.
const pomiGreeting = Color(0xE639394E);

/// Secondary text, units, hints and navigation: Figma #4F4F66 at 80%.
const pomiSecondaryText = Color(0xCC4F4F66);
const pomiMuted = pomiSecondaryText;
const pomiPurple = Color(0xFF6A4C93);
const pomiPurpleSoft = Color(0xFF9B8CC9);
const pomiLavender = Color(0xFFF5F0F9);
const pomiMint = Color(0xFF27D2BF);
const pomiSuccess = Color(0xFF2D8B4E);
const pomiCoral = Color(0xFFE8917C);
const pomiPaper = Color(0xFFF8F5FA);
const pomiLine = Color(0xFFECE6F1);

const pomiTeal = pomiPurple;

class PomiAppBackground extends StatelessWidget {
  const PomiAppBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFFFFFEFA)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(1.05, -0.9),
              radius: 1.05,
              colors: [Color(0xB8DDF5FF), Color(0x00DDF5FF)],
              stops: [0, 1],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(1.05, -0.05),
              radius: 1.05,
              colors: [Color(0xB86E50E6), Color(0x3D9C82EC), Color(0x006E50E6)],
              stops: [0, .48, 1],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.35, 0.62),
              radius: 1.15,
              colors: [Color(0x99F29AD3), Color(0x38F4C5DF), Color(0x00F29AD3)],
              stops: [0, .52, 1],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-1.05, -1.05),
              radius: .95,
              colors: [Color(0x75FFF2BD), Color(0x00FFF2BD)],
              stops: [0, 1],
            ),
          ),
        ),
        BackdropGroup(child: child),
      ],
    );
  }
}

class PomiGlassCard extends StatelessWidget {
  const PomiGlassCard({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.borderRadius = 24,
    this.backgroundOpacity = .18,
    this.backgroundColor,
    this.blurSigma = 12,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double borderRadius;
  final double backgroundOpacity;
  final Color? backgroundColor;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final content = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            spreadRadius: 0,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter.grouped(
          filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color:
                  backgroundColor ??
                  Colors.white.withValues(alpha: backgroundOpacity),
              borderRadius: radius,
              border: Border.all(
                color: Colors.white.withValues(alpha: .40),
                width: 1,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child:
                  onTap == null
                      ? content
                      : InkWell(
                        borderRadius: radius,
                        onTap: onTap,
                        child: content,
                      ),
            ),
          ),
        ),
      ),
    );
  }
}

ThemeData buildPomiTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: pomiPurple,
    brightness: Brightness.light,
    primary: pomiPurple,
    secondary: pomiMint,
    surface: Colors.white,
    onSurface: pomiInk,
    error: const Color(0xFFC62828),
  ).copyWith(
    onSurfaceVariant: pomiSecondaryText,
    onPrimaryContainer: pomiInk,
    onSecondaryContainer: pomiInk,
    onTertiaryContainer: pomiInk,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
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
      displayLarge: TextStyle(color: pomiInk),
      displayMedium: TextStyle(color: pomiInk),
      displaySmall: TextStyle(color: pomiInk),
      headlineLarge: TextStyle(color: pomiInk),
      headlineMedium: TextStyle(
        fontSize: 24,
        height: 32 / 24,
        fontWeight: FontWeight.w800,
        color: pomiInk,
      ),
      headlineSmall: TextStyle(color: pomiInk),
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
      titleSmall: TextStyle(color: pomiInk),
      bodyLarge: TextStyle(color: pomiInk),
      bodyMedium: TextStyle(fontSize: 15, height: 24 / 15, color: pomiInk),
      bodySmall: TextStyle(fontSize: 13, height: 20 / 13, color: pomiMuted),
      labelLarge: TextStyle(color: pomiInk),
      labelMedium: TextStyle(color: pomiSecondaryText),
      labelSmall: TextStyle(color: pomiSecondaryText),
    ),
    cardTheme: const CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Color(0x2EFFFFFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
        side: BorderSide(color: Color(0x66FFFFFF), width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF9F9FB),
      labelStyle: const TextStyle(color: pomiSecondaryText),
      hintStyle: const TextStyle(color: pomiSecondaryText),
      helperStyle: const TextStyle(color: pomiSecondaryText),
      suffixStyle: const TextStyle(color: pomiSecondaryText),
      prefixIconColor: pomiSecondaryText,
      suffixIconColor: pomiSecondaryText,
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
        foregroundColor: pomiInk,
        minimumSize: const Size(48, 48),
        shape: const StadiumBorder(),
        side: const BorderSide(color: Color(0xFFD8CCE4)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: pomiInk),
    ),
    listTileTheme: const ListTileThemeData(
      textColor: pomiInk,
      titleTextStyle: TextStyle(color: pomiInk),
      subtitleTextStyle: TextStyle(color: pomiSecondaryText),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      textStyle: TextStyle(color: pomiInk),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
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
      iconTheme: const WidgetStatePropertyAll(
        IconThemeData(color: pomiSecondaryText),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight:
              states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
          color: pomiSecondaryText,
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
