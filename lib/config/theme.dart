import 'package:flutter/material.dart';

/// Tema global de BiPenc con paleta Teal y estilos oscuros premium.
/// 
/// Centraliza todos los estilos visuales para mantener consistencia
/// y facilitar cambios de diseño en toda la aplicación.
class BiPencTheme {
  // ── Colores principales ──
  static const Color primaryTeal = Colors.tealAccent;
  static const Color backgroundDark = Color(0xFF0F0F1A);
  static const Color surfaceDark = Color(0xFF1E1E2C);
  static const Color cardDark = Color(0xFF1A1A1A);
  static const Color successGreen = Color(0xFF2ECC71);
  static const Color warningOrange = Colors.orangeAccent;
  static const Color errorRed = Colors.redAccent;

  // ── Tema oscuro principal ──
  static ThemeData get darkTheme => ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
          primary: primaryTeal,
          secondary: Colors.teal,
          surface: surfaceDark,
        ),
        scaffoldBackgroundColor: backgroundDark,
        appBarTheme: const AppBarTheme(
          backgroundColor: backgroundDark,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: surfaceDark,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryTeal.withOpacity(0.1),
            foregroundColor: primaryTeal,
            side: const BorderSide(color: primaryTeal),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );

  // ── Decoraciones reutilizables ──
  
  /// Input decoration estándar para TextField
  static InputDecoration inputDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey.shade500),
      prefixIcon: icon != null ? Icon(icon, color: primaryTeal, size: 22) : null,
      filled: true,
      fillColor: cardDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primaryTeal, width: 1.5),
      ),
      errorStyle: const TextStyle(color: errorRed),
    );
  }

  /// Badge con borde teal para mostrar alias
  static Widget aliasBadge(String alias) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: primaryTeal.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primaryTeal.withOpacity(0.3)),
      ),
      child: Text(
        alias,
        style: const TextStyle(
          color: primaryTeal,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  /// Contenedor con efecto "halo" teal
  static BoxDecoration haloDecoration({double opacity = 0.3}) {
    return BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: primaryTeal.withOpacity(opacity),
          blurRadius: 40,
          spreadRadius: 8,
        ),
      ],
    );
  }
}
