import 'package:flutter/material.dart';

class AppTheme {
  // Colores Base Material 3
  static const Color primaryTeal = Color(0xFF00796B); // Colors.teal.shade700
  static const Color backgroundWhite = Color(0xFFF8F9FA); // Blanco hueso (Anti-fatiga visual)
  static const Color secondaryAmber = Color(0xFFE65100); // Colors.amber.shade900
  
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
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
      cardTheme: CardTheme(
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
}
