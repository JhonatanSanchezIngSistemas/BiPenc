import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_page.dart';
import 'screens/venta_page.dart';
import 'screens/carrito_page.dart';
import 'screens/producto_form_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: 'https://srxvjhzsvfpytwrjjtlz.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNyeHZqaHpzdmZweXR3cmpqdGx6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEzNjQ1NzcsImV4cCI6MjA4Njk0MDU3N30.ZAAe_z0q1H1SfANpy_mwUHrQiGd6owdPvkUAwPZVIow',
  );

  runApp(const BiPencApp());
}

/// Aplicación principal BiPenc — Sistema de Ventas para Librería.
class BiPencApp extends StatelessWidget {
  const BiPencApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BiPenc',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,

      // ── Tema oscuro ──
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
          primary: Colors.tealAccent,
          secondary: Colors.teal,
          surface: const Color(0xFF1E1E2C),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F0F1A),
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E2C),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.tealAccent.withValues(alpha: 0.1),
            foregroundColor: Colors.tealAccent,
            side: const BorderSide(color: Colors.tealAccent),
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
      ),

      // ── Tema claro (respaldo) ──
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),

      // ── Rutas ──
      initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginPage(),
        '/venta': (_) => const VentaPage(),
        '/carrito': (_) => const CarritoPage(),
        '/producto_form': (_) => const ProductoFormPage(),
      },
    );
  }
}
