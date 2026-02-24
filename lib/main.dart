import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/home/home_screen.dart';
import 'features/inventario/inventario_screen.dart';
import 'features/inventario/producto_form_screen.dart';
import 'features/pos/pos_screen.dart';
import 'features/pos/pos_provider.dart';
import 'features/settings/settings_screen.dart';
import 'features/reports/cierre_caja_screen.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';

// GlobalKey maestro para controlar SnackBars fuera del contexto (Ej. PosProvider sin UI)
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Inicializar Supabase
  await Supabase.initialize(
    url: 'https://srxvjhzsvfpytwrjjtlz.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNyeHZqaHpzdmZweXR3cmpqdGx6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEzNjQ1NzcsImV4cCI6MjA4Njk0MDU3N30.ZAAe_z0q1H1SfANpy_mwUHrQiGd6owdPvkUAwPZVIow',
  );

  // 2. Lógica de Master Reset (Nube)
  await _verificarMasterReset();

  runApp(const BiPencApp());
}

/// Consulta a la nube si el cajero olvidó su clave para forzar un reseteo
Future<void> _verificarMasterReset() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    
    // Asumimos que hemos creado una tabla 'store_config' con una fila única (id=1) 
    // que contiene el campo booleano 'force_reset'.
    // Si falla la conexión, la excepción es cazada sin afectar el arranque local.
    final response = await Supabase.instance.client
        .from('store_config')
        .select('force_reset')
        .eq('id', 1)
        .maybeSingle();

    if (response != null && response['force_reset'] == true) {
      // 240be5... (Hash SHA-256 de "admin123")
      const defaultHash = '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9';
      await prefs.setString('admin_password_hash', defaultHash);
      
      // Opcional: Apagar la bandera en la nube tras resetear exitosamente.
      await Supabase.instance.client
          .from('store_config')
          .update({'force_reset': false})
          .eq('id', 1);
          
      debugPrint('⚠️ Alerta: Master Reset ejecutado vía Supabase. Clave restaurada a admin123.');
    }
  } catch (e) {
    // Ejecución offline / Modo Avión: Tolera errores en conexión.
    debugPrint('Check de Master Reset saltado (sin internet o config no lista): $e');
  }
}

// Configuración inicial de GoRouter
final GoRouter _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/inventario',
      builder: (context, state) => const InventarioScreen(),
      routes: [
        GoRoute(
          path: 'nuevo',
          builder: (context, state) => const ProductoFormScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/pos',
      builder: (context, state) => const PosScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/cierre_caja',
      builder: (context, state) => const CierreCajaScreen(),
    ),
  ],
);

class BiPencApp extends StatelessWidget {
  const BiPencApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PosProvider()),
      ],
      child: MaterialApp.router(
        scaffoldMessengerKey: scaffoldMessengerKey,
        title: 'BiPenc',
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
        theme: AppTheme.lightTheme,
      ),
    );
  }
}
