import 'package:flutter/material.dart';

class AppTheme {
  // Palette pulled from the reference design:
  // #29262B (near-black background) -> #3C3541 (card/surface) ->
  // #AC5FDB (primary purple) -> #E3A2EE (light lilac accent)
  static const Color backgroundDark = Color(0xFF29262B);
  static const Color surfaceDark = Color(0xFF3C3541);
  static const Color primaryPurple = Color(0xFFAC5FDB);
  static const Color lightLilac = Color(0xFFE3A2EE);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark, // the whole app now follows this dark palette
    scaffoldBackgroundColor: backgroundDark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryPurple,
      brightness: Brightness.dark,
    ).copyWith(
      primary: primaryPurple,
      onPrimary: Colors.white,
      secondary: lightLilac,
      onSecondary: backgroundDark,
      surface: surfaceDark,
      onSurface: Colors.white,
      primaryContainer: primaryPurple.withOpacity(0.25),
      onPrimaryContainer: lightLilac,
      surfaceContainerHighest: surfaceDark,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: backgroundDark,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryPurple,
      foregroundColor: Colors.white,
    ),
    cardTheme: CardThemeData(
      color: surfaceDark,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surfaceDark,
      indicatorColor: primaryPurple.withOpacity(0.35),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? lightLilac : Colors.white60);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          color: selected ? lightLilac : Colors.white60,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        );
      }),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      hintStyle: TextStyle(color: Colors.white38),
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Colors.white70),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
  );
}