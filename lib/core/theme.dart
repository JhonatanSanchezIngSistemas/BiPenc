import 'package:flutter/material.dart';

class AppTheme {
  // Colores Base Material 3
  static const Color primaryTeal = Color(0xFF00796B); // Colors.teal.shade700
  static const Color backgroundWhite = Color(0xFFF8F9FA); // Blanco hueso (Anti-fatiga visual)
  static const Color secondaryAmber = Color(0xFFE65100); // Colors.amber.shade900

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryTeal,
        primary: primaryTeal,
        secondary: secondaryAmber,
        surface: backgroundWhite,
        onSurfaceVariant: Colors.black54,
      ),
      scaffoldBackgroundColor: backgroundWhite,
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryTeal,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryTeal,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryTeal,
        brightness: Brightness.dark,
        primary: const Color(0xFF4DB6AC), // teal.shade300 para dark mode
        secondary: const Color(0xFFFFB74D), // amber.shade300
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF00695C), // teal.shade800
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF4DB6AC),
          foregroundColor: Colors.black,
        ),
      ),
    );
  }
}
