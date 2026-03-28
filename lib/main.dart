import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'base/llaves.dart';
import 'utilidades/registro_app.dart';
import 'base/tema.dart';
import 'modulos/inicio/pantalla_inicio.dart';
import 'modulos/autenticacion/pantalla_login.dart';
import 'modulos/arranque/pantalla_arranque.dart';
import 'modulos/inventario/pantalla_inventario.dart';
import 'modulos/inventario/pantalla_formulario_producto.dart';
import 'modulos/pedidos/pantalla_lista_pedidos.dart';
import 'modulos/caja/proveedor_caja.dart';
import 'modulos/caja/pantalla_caja.dart';
import 'modulos/reportes/pantalla_cierre_caja.dart';
import 'modulos/reportes/pantalla_boletas.dart';
import 'modulos/ajustes/pantalla_panel_configuracion.dart';
import 'package:bipenc/modulos/ajustes/pantalla_config_empresa.dart';
import 'package:bipenc/modulos/ajustes/pantalla_config_impresora.dart';
import 'modulos/ajustes/pantalla_correlativos.dart';
import 'modulos/ajustes/pantalla_perfil.dart';
import 'modulos/ajustes/pantalla_ajustes.dart';
import 'modulos/administracion/pantalla_tablero_admin.dart';
import 'servicios/servicio_db_local.dart';
import 'servicios/servicio_cifrado.dart';
import 'servicios/cola_impresion.dart';
import 'servicios/servicio_seguridad.dart';
import 'servicios/gestor_sesion.dart';
import 'servicios/servicio_sincronizacion.dart';
import 'servicios/servicio_sesion.dart';
import 'servicios/servicio_actualizacion.dart';
import 'ui/modales/dialogo_actualizacion.dart';
import 'ui/layout_principal.dart';
import 'ui/guardia_sesion.dart';
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
    
    // Log también a RegistroApp para persistencia
    RegistroApp.critical(
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
    
    // Log a RegistroApp
    RegistroApp.critical(
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
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    _setupErrorHandlers();

    final init = await _bootstrapApp();
    if (!init.ok) {
      runApp(AplicacionErrorFatal(message: init.message));
      return;
    }
    runApp(const AplicacionBiPenc());
  }, (error, stackTrace) {
    final String msg = '🔴 [CRITICAL MAIN ERROR] $error';
    debugPrint('═' * 80);
    debugPrint(msg);
    debugPrint(stackTrace.toString());
    debugPrint('═' * 80);
    RegistroApp.critical(
      msg,
      tag: 'MAIN_ERROR',
      error: error,
      stackTrace: stackTrace,
    );
  });
}

class _ResultadoInicio {
  final bool ok;
  final String message;
  const _ResultadoInicio(this.ok, this.message);
}

String _readEnv(String key) {
  final fromDefine = String.fromEnvironment(key);
  if (fromDefine.isNotEmpty) return fromDefine;
  if (!dotenv.isInitialized) return '';
  return dotenv.env[key] ?? '';
}

Future<void> _safeLoadDotenv() async {
  try {
    if (kIsWeb) {
      await dotenv.load(fileName: 'assets/.env');
      return;
    }
    await dotenv.load(fileName: '.env');
  } catch (e) {
    try {
      await dotenv.load(fileName: 'assets/.env');
      return;
    } catch (e2) {
      if (kDebugMode) {
        debugPrint('⚠️ [BOOT] dotenv no cargado: $e2');
      }
    }
    if (kDebugMode) {
      debugPrint('⚠️ [BOOT] dotenv no cargado: $e');
    }
  }
}

Future<_ResultadoInicio> _bootstrapApp() async {
  try {
    debugPrint('🚀 [BOOT] Iniciando bootstrap...');

    // 0. SQLite para desktop (Linux/Windows/macOS)
    if (!kIsWeb) {
      try {
        if (defaultTargetPlatform == TargetPlatform.linux || 
            defaultTargetPlatform == TargetPlatform.windows || 
            defaultTargetPlatform == TargetPlatform.macOS) {
          sqfliteFfiInit();
          databaseFactory = databaseFactoryFfi;
          debugPrint('✅ [BOOT] Sqflite FFI inicializado correctamente vía TargetPlatform');
        }
      } catch (e) {
        debugPrint('⚠️ [BOOT] FFI Falló pero se capturó: $e');
      }
    }
    
    // 1. Variables de entorno
    debugPrint('🚀 [BOOT] Cargando dotenv...');
    await _safeLoadDotenv();
    final url = _readEnv('SUPABASE_URL');
    final anon = _readEnv('SUPABASE_ANON_KEY');
    if (url.isEmpty || anon.isEmpty) {
      debugPrint('❌ [BOOT] Error: Faltan variables de entorno');
      return const _ResultadoInicio(false,
          'Falta configurar SUPABASE_URL y SUPABASE_ANON_KEY en .env o dart-define.');
    }

    // 2. Supabase
    debugPrint('🚀 [BOOT] Inicializando Supabase...');
    await Supabase.initialize(url: url, anonKey: anon);

    // 3. Seguridad y cifrado
    debugPrint('🚀 [BOOT] Inicializando ServicioSeguridad...');
    await ServicioSeguridad().init();
    debugPrint('🚀 [BOOT] Inicializando ServicioCifrado...');
    await ServicioCifrado().init();

    // 4. Base local (rápido). Tareas pesadas se difieren post-boot.
    debugPrint('🚀 [BOOT] Sembrando DB local si está vacía...');
    await ServicioDbLocal.seedIfEmpty();
    
    debugPrint('✅ [BOOT] Bootstrap completado con éxito');
    return const _ResultadoInicio(true, 'OK');
  } catch (e, st) {
    final msg = '❌ Error de arranque: $e';
    debugPrint(msg);
    RegistroApp.critical(msg, tag: 'BOOT', error: e, stackTrace: st);
    return _ResultadoInicio(false, msg);
  }
}

// ========================================
// ROUTER CONFIGURATION
// ========================================

final GoRouter _router = GoRouter(
  redirect: (context, state) {
    final session = ServicioSesion();
    final isAdmin = session.rol == RolesApp.admin;
    final path = state.matchedLocation;

    // Único cordón sanitario: dashboard admin
    if ((path == '/admin/dashboard' || path.startsWith('/admin/dashboard')) &&
        !isAdmin) {
      debugPrint('⛔ ADMIN ONLY: $path');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('Ruta exclusiva Admin'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
      return '/pos';
    }
    return null;
  },
  initialLocation: '/splash', // Mostramos logo mientras cargamos
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const PantallaArranque(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const PantallaLogin(),
    ),
    // Rutas protegidas por GuardiaSesion (Art 1)
    ShellRoute(
      builder: (context, state, child) => GuardiaSesion(
        child: LayoutPrincipal(child: child),
      ),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const PantallaInicio(),
        ),
        GoRoute(
          path: '/inventario',
          builder: (context, state) => const PantallaInventario(),
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
                return PantallaFormularioProducto(initialSku: initialSku);
              },
            ),
            GoRoute(
              path: 'editar',
              builder: (context, state) => PantallaFormularioProducto(producto: state.extra as Producto?),
            ),
          ],
        ),
        GoRoute(
          path: '/pos',
          builder: (context, state) {
            String? orderId;
            String? fotoUrl;
            if (state.extra is Map) {
              final map = Map.from(state.extra as Map);
              if (map['orderId'] is String) orderId = map['orderId'] as String;
              if (map['fotoUrl'] is String) fotoUrl = map['fotoUrl'] as String;
            }
            return PantallaCaja(orderId: orderId, orderFotoUrl: fotoUrl);
          },
        ),
        GoRoute(
          path: '/pedidos',
          builder: (context, state) => const PantallaListaPedidos(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const PantallaAjustes(),
          routes: [
            GoRoute(
              path: 'printer',
              builder: (context, state) => const PantallaConfigImpresora(),
            ),
            GoRoute(
              path: 'profile',
              builder: (context, state) => const PantallaPerfil(),
            ),
            GoRoute(
              path: 'empresa',
              builder: (context, state) => const PantallaConfigEmpresa(),
            ),
            GoRoute(
              path: 'correlativos',
              builder: (context, state) => const PantallaCorrelativos(),
            ),
          ],
        ),
        GoRoute(
          path: '/cierre_caja',
          builder: (context, state) => const PantallaCierreCaja(),
        ),
        GoRoute(
          path: '/boletas',
          builder: (context, state) => const PantallaBoletas(),
        ),
        GoRoute(
          path: '/config_dashboard',
          builder: (context, state) => const PantallaPanelConfiguracion(),
        ),
        GoRoute(
          path: '/admin/dashboard',
          builder: (context, state) => const PantallaTableroAdmin(),
        ),
      ],
    ),
  ],
);

// ========================================
// MAIN APP WIDGET
// ========================================

class AplicacionBiPenc extends StatefulWidget {
  const AplicacionBiPenc({super.key});

  @override
  State<AplicacionBiPenc> createState() => _AplicacionBiPencState();
}

class _AplicacionBiPencState extends State<AplicacionBiPenc> {
  bool _postBootStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runPostBootstrap());
  }

  Future<void> _runPostBootstrap() async {
    if (_postBootStarted) return;
    _postBootStarted = true;

    // Tareas pesadas diferidas para no bloquear el arranque visual.
    Future.microtask(() async {
      try {
        await ColaImpresion.procesarCola()
            .timeout(const Duration(seconds: 5), onTimeout: () {
          RegistroApp.warn('Timeout procesando cola de impresión (post-boot)',
              tag: 'BOOT');
        });
      } catch (e, st) {
        RegistroApp.error('Error post-boot al procesar cola',
            tag: 'BOOT', error: e, stackTrace: st);
      }

      try {
        await ColaImpresion.limpiarColaAntigua();
      } catch (e, st) {
        RegistroApp.error('Error limpiando cola antigua',
            tag: 'BOOT', error: e, stackTrace: st);
      }

      try {
        ServicioSincronizacion().start();
      } catch (e, st) {
        RegistroApp.error('Error iniciando ServicioSincronizacion (post-boot)',
            tag: 'BOOT', error: e, stackTrace: st);
      }

      // Check for updates
      try {
        final updateData = await ServicioActualizacion().checkForUpdate();
        if (updateData != null && mounted) {
          showDialog(
            context: context,
            barrierDismissible: !(updateData['es_obligatoria'] ?? false),
            builder: (context) => DialogoActualizacion(versionData: updateData),
          );
        }
      } catch (e) {
        RegistroApp.error('Error checking for OTA update', tag: 'BOOT', error: e);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProveedorCaja()),
        ChangeNotifierProvider(create: (_) => GestorSesion()),
      ],
      child: MaterialApp.router(
        scaffoldMessengerKey: scaffoldMessengerKey,
        title: 'BiPenc - Sistema POS',
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
        theme: TemaApp.lightTheme,
        darkTheme: TemaApp.darkTheme,
        themeMode: ThemeMode.system,
      ),
    );
  }
}

/// Pantalla mínima para mostrar fallos de arranque en release
class AplicacionErrorFatal extends StatelessWidget {
  final String message;
  const AplicacionErrorFatal({super.key, required this.message});

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
