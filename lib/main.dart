import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'core/keys.dart';
import 'utils/app_logger.dart';
import 'core/theme.dart';
import 'features/home/home_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/inventario/inventario_screen.dart';
import 'features/inventario/producto_form_screen.dart';
import 'features/pedidos/order_list_screen.dart';
import 'features/pos/pos_provider.dart';
import 'features/pos/pos_screen.dart';
import 'features/reports/cierre_caja_screen.dart';
import 'features/reports/boletas_screen.dart';
import 'features/settings/config_dashboard_screen.dart';
import 'features/settings/printer_config_screen.dart';
import 'features/settings/profile_settings_screen.dart';
import 'features/settings/settings_screen.dart';
import 'services/local_db_service.dart';
import 'services/encryption_service.dart';
import 'services/print_queue.dart';
import 'services/security_service.dart';
import 'services/session_manager.dart';
import 'services/sync_service.dart';
import 'widgets/main_layout.dart';
import 'widgets/session_guard.dart';
// =====================================================
// GLOBAL ERROR CATCHER (Modo Debug Extremo)
// =====================================================
void _setupErrorHandlers() {
  /// Captura TODOS los errores Flutter no manejados
  FlutterError.onError = (FlutterErrorDetails details) {
    final String msg = '🔴 [CRITICAL FLUTTER ERROR] ${details.exceptionAsString()}';
    debugPrint('═' * 80);
    debugPrint(msg);
    debugPrint('Stack Trace:');
    debugPrint(details.stack.toString());
    debugPrint('═' * 80);
    
    // Log también a AppLogger para persistencia
    AppLogger.critical(
      msg,
      tag: 'FLUTTER_ERROR',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  /// Captura errores asincronos no manejados (zonas)
  PlatformDispatcher.instance.onError = (error, stack) {
    final String msg = '🔴 [CRITICAL ASYNC ERROR] $error';
    debugPrint('═' * 80);
    debugPrint(msg);
    debugPrint('Stack Trace:');
    debugPrint(stack.toString());
    debugPrint('═' * 80);
    
    // Log a AppLogger
    AppLogger.critical(
      msg,
      tag: 'ASYNC_ERROR',
      error: error,
      stackTrace: stack,
    );
    
    return true; // Se ha manejado el error
  };

  /// Captura errores no manejados - Zone es inmutable
  /// Usar PlatformDispatcher.instance.onError es la forma correcta en Dart 3+
  // Zone.handleUncaughtError no es asignable, removido
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _setupErrorHandlers();

  runZonedGuarded(() async {
    final init = await _bootstrapApp();
    if (!init.ok) {
      runApp(FatalErrorApp(message: init.message));
      return;
    }
    runApp(const BiPencApp());
  }, (error, stackTrace) {
    final String msg = '🔴 [CRITICAL MAIN ERROR] $error';
    debugPrint('═' * 80);
    debugPrint(msg);
    debugPrint(stackTrace.toString());
    debugPrint('═' * 80);
    AppLogger.critical(
      msg,
      tag: 'MAIN_ERROR',
      error: error,
      stackTrace: stackTrace,
    );
  });
}

class _InitResult {
  final bool ok;
  final String message;
  const _InitResult(this.ok, this.message);
}

Future<_InitResult> _bootstrapApp() async {
  try {
    // 1. Variables de entorno
    await dotenv.load();
    final url = dotenv.env['SUPABASE_URL'] ?? '';
    final anon = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
    if (url.isEmpty || anon.isEmpty) {
      return const _InitResult(false,
          'Falta configurar SUPABASE_URL y SUPABASE_ANON_KEY en .env o dart-define.');
    }

    // 2. Supabase
    await Supabase.initialize(url: url, anonKey: anon);

    // 3. Seguridad y cifrado
    await SecurityService().init();
    await EncryptionService().init();

    // 4. Base local y colas
    await LocalDbService.seedIfEmpty();
    await PrintQueue.procesarCola();
    await PrintQueue.limpiarColaAntigua();

    // 5. Sincronización
    SyncService().start();
    return const _InitResult(true, 'OK');
  } catch (e, st) {
    final msg = 'Error de arranque: $e';
    debugPrint(msg);
    AppLogger.critical(msg, tag: 'BOOT', error: e, stackTrace: st);
    return _InitResult(false, msg);
  }
}

// ========================================
// ROUTER CONFIGURATION
// ========================================

final GoRouter _router = GoRouter(
  initialLocation: '/login', // Iniciamos en login para activar chequeo de sesión/biometría
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    // Rutas protegidas por SessionGuard (Art 1)
    ShellRoute(
      builder: (context, state, child) => SessionGuard(
        child: MainLayout(child: child),
      ),
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
              builder: (context, state) {
                final extra = state.extra;
                String? initialSku;
                if (extra is String) {
                  initialSku = extra;
                } else if (extra is Map && extra['initialSku'] is String) {
                  initialSku = extra['initialSku'] as String;
                } else if (extra is Map<String, dynamic> && extra['initialSku'] is String) {
                  initialSku = extra['initialSku'] as String;
                }
                return ProductoFormScreen(initialSku: initialSku);
              },
            ),
            GoRoute(
              path: 'editar',
              builder: (context, state) => ProductoFormScreen(producto: state.extra as Producto?),
            ),
          ],
        ),
        GoRoute(
          path: '/pos',
          builder: (context, state) => const PosScreen(),
        ),
        GoRoute(
          path: '/pedidos',
          builder: (context, state) => const OrderListScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
          routes: [
            GoRoute(
              path: 'printer',
              builder: (context, state) => const PrinterConfigScreen(),
            ),
            GoRoute(
              path: 'profile',
              builder: (context, state) => const ProfileSettingsScreen(),
            ),
          ],
        ),
        GoRoute(
          path: '/cierre_caja',
          builder: (context, state) => const CierreCajaScreen(),
        ),
        GoRoute(
          path: '/boletas',
          builder: (context, state) => const BoletasScreen(),
        ),
        GoRoute(
          path: '/config_dashboard',
          builder: (context, state) => const ConfigDashboardScreen(),
        ),
      ],
    ),
  ],
);

// ========================================
// MAIN APP WIDGET
// ========================================

class BiPencApp extends StatelessWidget {
  const BiPencApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PosProvider()),
        ChangeNotifierProvider(create: (_) => SessionManager()),
      ],
      child: MaterialApp.router(
        scaffoldMessengerKey: scaffoldMessengerKey,
        title: 'BiPenc - Sistema POS',
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
      ),
    );
  }
}

/// Pantalla mínima para mostrar fallos de arranque en release
class FatalErrorApp extends StatelessWidget {
  final String message;
  const FatalErrorApp({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0F0F1A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 72, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text('No se pudo iniciar BiPenc',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 16),
                const Text('Revisa tu .env o conexión e intenta de nuevo.',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
