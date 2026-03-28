import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:bipenc/servicios/cola_impresion.dart';
import 'package:bipenc/servicios/servicio_backend.dart';
import 'package:bipenc/servicios/servicio_db_local.dart';
import 'package:bipenc/utilidades/registro_app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// T1.5: Servicio de sincronización incremental cada 30 segundos.
///
/// Reemplaza el antiguo "batch sync en cierre de caja" con un flujo
/// continuo que sube datos pendientes tan pronto como hay conexión.
///
/// Flujo:
/// ```
/// Venta → LocalDB → Encolar en SyncQueue →
/// [Background Timer cada 30s] → Upload incremental
/// ```
class ServicioSincronizacion {
  static final ServicioSincronizacion _instance = ServicioSincronizacion._();
  factory ServicioSincronizacion() => _instance;
  ServicioSincronizacion._();

  Timer? _syncTimer;
  bool _isSyncing = false;
  bool _isRunning = false;

  static const int _intervalSeconds = 30;
  static const int _maxRetries = 3;

  // Inyección para tests (por defecto usa servicios reales).
  Future<List<ConnectivityResult>> Function()? connectivityCheckOverride;
  Future<void> Function()? subirVentasPendientesOverride;
  Future<void> Function()? procesarSyncQueueV2Override;
  Future<bool> Function()? sincronizarProductosOverride;
  Future<void> Function()? procesarColaImpresionOverride;
  Future<void> Function()? limpiarSyncQueueV2Override;
  Duration Function(int attempt)? retryBackoffOverride;
  Future<bool> Function()? internetCheckOverride;

  bool get isRunning => _isRunning;
  bool get isSyncing => _isSyncing;

  /// Inicia el servicio de sincronización background.
  /// Llamar desde `main.dart` después de inicializar Supabase.
  void start() {
    if (_isRunning) return;
    _isRunning = true;

    RegistroApp.info(
      'ServicioSincronizacion iniciado (cada ${_intervalSeconds}s)',
      tag: 'SYNC_BG',
    );

    // Ejecutar inmediatamente al arrancar
    _syncCycle();

    // Timer periódico
    _syncTimer = Timer.periodic(
      const Duration(seconds: _intervalSeconds),
      (_) => _syncCycle(),
    );
  }

  /// Detiene el servicio de sincronización.
  void stop() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _isRunning = false;
    RegistroApp.info('ServicioSincronizacion detenido', tag: 'SYNC_BG');
  }

  /// Fuerza una sincronización inmediata (pull-to-refresh, etc.)
  Future<ResultadoSincronizacion> syncNow() async {
    return await _syncCycle();
  }

  /// Ciclo de sincronización principal.
  Future<ResultadoSincronizacion> _syncCycle() async {
    if (_isSyncing) {
      return ResultadoSincronizacion(skipped: true, reason: 'Ya hay un sync en curso');
    }

    _isSyncing = true;
    final result = ResultadoSincronizacion();

    try {
      // 1. Verificar conectividad
      final connectivityResult = await (connectivityCheckOverride != null
          ? connectivityCheckOverride!()
          : Connectivity().checkConnectivity());

      if (connectivityResult.contains(ConnectivityResult.none)) {
        result.skipped = true;
        result.reason = 'Sin conexión';
        return result;
      }

      final hasWifiOrEthernet = connectivityResult.any(
        (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
      );

      if (_wifiOnlySync && !hasWifiOrEthernet) {
        result.skipped = true;
        result.reason = 'Solo sincroniza por WiFi';
        return result;
      }

      bool hasInternet = true;
      try {
        hasInternet =
            await (internetCheckOverride ?? ServicioBackend.tieneConexionRemota)();
      } catch (e) {
        if (kDebugMode) {
          RegistroApp.warning('Check internet falló (se asume true): $e',
              tag: 'SYNC_BG');
        }
        hasInternet = true;
      }
      if (!hasInternet) {
        result.skipped = true;
        result.reason = 'Sin internet real';
        return result;
      }

      // 2. PUSH: Subir ventas pendientes
      try {
        await _runWithRetry(
          operation:
              subirVentasPendientesOverride ?? ServicioBackend.subirVentasPendientes,
          operationName: 'subirVentasPendientes',
        );
        result.ventasSubidas = true;
      } catch (e) {
        RegistroApp.error('Error subiendo ventas', tag: 'SYNC_BG', error: e);
        result.errores++;
      }

      // 2.5 PUSH: Reintentar cola de impresión cuando hay conectividad
      try {
        await (procesarColaImpresionOverride ?? ColaImpresion.procesarCola)();
      } catch (e) {
        RegistroApp.error('Error procesando cola de impresión', tag: 'SYNC_BG', error: e);
      }

      // 3. PUSH: Procesar cola de sync (deletes, updates)
      try {
        await _runWithRetry(
          operation:
              procesarSyncQueueV2Override ?? ServicioBackend.procesarSyncQueueV2,
          operationName: 'procesarSyncQueueV2',
        );
        result.syncQueueProcesada = true;
      } catch (e) {
        RegistroApp.error('Error procesando sync_queue V2', tag: 'SYNC_BG', error: e);
        result.errores++;
      }

      // 3.5. Cleanup de cola V2 antigua (cada 24 ciclos aprox 12 min, o cada ciclo por ahora)
      try {
        await (limpiarSyncQueueV2Override ?? ServicioDbLocal.limpiarSyncQueueV2Antigua)();
      } catch (e) {
        RegistroApp.error('Error limpiando sync_queue V2 antigua', tag: 'SYNC_BG', error: e);
      }

      // 4. PULL: Sincronizar productos desde Supabase
      try {
        final ok = await _runWithRetry<bool>(
          operation: sincronizarProductosOverride ??
              ServicioBackend.sincronizarProductos,
          operationName: 'sincronizarProductos',
        );
        result.productosSincronizados = ok;
      } catch (e) {
        RegistroApp.error('Error sincronizando productos', tag: 'SYNC_BG', error: e);
        result.errores++;
      }

      // 5. Log resultado
      if (result.errores == 0) {
        RegistroApp.debug('Sync completado sin errores', tag: 'SYNC_BG');
      } else {
        RegistroApp.warning(
          'Sync completado con ${result.errores} errores',
          tag: 'SYNC_BG',
        );
      }

      return result;
    } catch (e) {
      RegistroApp.error('Error general en ciclo sync', tag: 'SYNC_BG', error: e);
      result.errores++;
      return result;
    } finally {
      _isSyncing = false;
    }
  }

  Future<T> _runWithRetry<T>({
    required Future<T> Function() operation,
    required String operationName,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        return await operation();
      } catch (e) {
        lastError = e;
        if (attempt >= _maxRetries) break;
        final backoff = retryBackoffOverride?.call(attempt) ??
            Duration(milliseconds: 500 * (1 << (attempt - 1)));
        RegistroApp.warning(
          'Retry $attempt/$_maxRetries en $operationName tras error: $e',
          tag: 'SYNC_BG',
        );
        await Future.delayed(backoff);
      }
    }
    throw lastError ?? Exception('Error desconocido en $operationName');
  }

  bool get _wifiOnlySync => _envBool('SYNC_WIFI_ONLY', true);

  bool _envBool(String key, bool fallback) {
    final fromDefine = String.fromEnvironment(key);
    final fromEnv =
        (dotenv.isInitialized ? (dotenv.env[key] ?? '') : '').toString();
    final raw = (fromDefine.isNotEmpty ? fromDefine : fromEnv)
        .toLowerCase()
        .trim();
    if (raw.isEmpty) return fallback;
    return raw == '1' || raw == 'true' || raw == 'yes';
  }

  /// Restablece overrides inyectados para pruebas.
  void resetTestingOverrides() {
    connectivityCheckOverride = null;
    subirVentasPendientesOverride = null;
    procesarSyncQueueV2Override = null;
    sincronizarProductosOverride = null;
    procesarColaImpresionOverride = null;
    limpiarSyncQueueV2Override = null;
    retryBackoffOverride = null;
  }
}

/// Resultado de un ciclo de sincronización.
class ResultadoSincronizacion {
  bool skipped;
  String? reason;
  bool ventasSubidas;
  bool syncQueueProcesada;
  bool productosSincronizados;
  int errores;

  ResultadoSincronizacion({
    this.skipped = false,
    this.reason,
    this.ventasSubidas = false,
    this.syncQueueProcesada = false,
    this.productosSincronizados = false,
    this.errores = 0,
  });

  @override
  String toString() {
    if (skipped) return 'ResultadoSincronizacion(skipped: $reason)';
    return 'ResultadoSincronizacion(ventas: $ventasSubidas, queue: $syncQueueProcesada, '
        'productos: $productosSincronizados, errores: $errores)';
  }
}
