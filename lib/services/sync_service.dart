import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:bipenc/services/print_queue.dart';
import 'package:bipenc/services/supabase_service.dart';
import 'package:bipenc/services/local_db_service.dart';
import 'package:bipenc/utils/app_logger.dart';

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
class SyncService {
  static final SyncService _instance = SyncService._();
  factory SyncService() => _instance;
  SyncService._();

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
  Future<void> Function()? procesarPrintQueueOverride;
  Future<void> Function()? limpiarSyncQueueV2Override;
  Duration Function(int attempt)? retryBackoffOverride;

  bool get isRunning => _isRunning;
  bool get isSyncing => _isSyncing;

  /// Inicia el servicio de sincronización background.
  /// Llamar desde `main.dart` después de inicializar Supabase.
  void start() {
    if (_isRunning) return;
    _isRunning = true;

    AppLogger.info(
      'SyncService iniciado (cada ${_intervalSeconds}s)',
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
    AppLogger.info('SyncService detenido', tag: 'SYNC_BG');
  }

  /// Fuerza una sincronización inmediata (pull-to-refresh, etc.)
  Future<SyncResult> syncNow() async {
    return await _syncCycle();
  }

  /// Ciclo de sincronización principal.
  Future<SyncResult> _syncCycle() async {
    if (_isSyncing) {
      return SyncResult(skipped: true, reason: 'Ya hay un sync en curso');
    }

    _isSyncing = true;
    final result = SyncResult();

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

      // Solo sincronizar por WiFi (ahorro de datos móviles)
      final isWifi = connectivityResult.contains(ConnectivityResult.wifi);
      if (!isWifi) {
        result.skipped = true;
        result.reason = 'Solo sincroniza por WiFi';
        return result;
      }

      // 2. PUSH: Subir ventas pendientes
      try {
        await _runWithRetry(
          operation: subirVentasPendientesOverride ?? SupabaseService.subirVentasPendientes,
          operationName: 'subirVentasPendientes',
        );
        result.ventasSubidas = true;
      } catch (e) {
        AppLogger.error('Error subiendo ventas', tag: 'SYNC_BG', error: e);
        result.errores++;
      }

      // 2.5 PUSH: Reintentar cola de impresión cuando hay conectividad
      try {
        await (procesarPrintQueueOverride ?? PrintQueue.procesarCola)();
      } catch (e) {
        AppLogger.error('Error procesando cola de impresión', tag: 'SYNC_BG', error: e);
      }

      // 3. PUSH: Procesar cola de sync (deletes, updates)
      try {
        await _runWithRetry(
          operation: procesarSyncQueueV2Override ?? SupabaseService.procesarSyncQueueV2,
          operationName: 'procesarSyncQueueV2',
        );
        result.syncQueueProcesada = true;
      } catch (e) {
        AppLogger.error('Error procesando sync_queue V2', tag: 'SYNC_BG', error: e);
        result.errores++;
      }

      // 3.5. Cleanup de cola V2 antigua (cada 24 ciclos aprox 12 min, o cada ciclo por ahora)
      try {
        await (limpiarSyncQueueV2Override ?? LocalDbService.limpiarSyncQueueV2Antigua)();
      } catch (e) {
        AppLogger.error('Error limpiando sync_queue V2 antigua', tag: 'SYNC_BG', error: e);
      }

      // 4. PULL: Sincronizar productos desde Supabase
      try {
        final ok = await _runWithRetry<bool>(
          operation: sincronizarProductosOverride ?? SupabaseService.sincronizarProductos,
          operationName: 'sincronizarProductos',
        );
        result.productosSincronizados = ok;
      } catch (e) {
        AppLogger.error('Error sincronizando productos', tag: 'SYNC_BG', error: e);
        result.errores++;
      }

      // 5. Log resultado
      if (result.errores == 0) {
        AppLogger.debug('Sync completado sin errores', tag: 'SYNC_BG');
      } else {
        AppLogger.warning(
          'Sync completado con ${result.errores} errores',
          tag: 'SYNC_BG',
        );
      }

      return result;
    } catch (e) {
      AppLogger.error('Error general en ciclo sync', tag: 'SYNC_BG', error: e);
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
            Duration(milliseconds: 300 * attempt);
        AppLogger.warning(
          'Retry $attempt/$_maxRetries en $operationName tras error: $e',
          tag: 'SYNC_BG',
        );
        await Future.delayed(backoff);
      }
    }
    throw lastError ?? Exception('Error desconocido en $operationName');
  }

  /// Restablece overrides inyectados para pruebas.
  void resetTestingOverrides() {
    connectivityCheckOverride = null;
    subirVentasPendientesOverride = null;
    procesarSyncQueueV2Override = null;
    sincronizarProductosOverride = null;
    procesarPrintQueueOverride = null;
    limpiarSyncQueueV2Override = null;
    retryBackoffOverride = null;
  }
}

/// Resultado de un ciclo de sincronización.
class SyncResult {
  bool skipped;
  String? reason;
  bool ventasSubidas;
  bool syncQueueProcesada;
  bool productosSincronizados;
  int errores;

  SyncResult({
    this.skipped = false,
    this.reason,
    this.ventasSubidas = false,
    this.syncQueueProcesada = false,
    this.productosSincronizados = false,
    this.errores = 0,
  });

  @override
  String toString() {
    if (skipped) return 'SyncResult(skipped: $reason)';
    return 'SyncResult(ventas: $ventasSubidas, queue: $syncQueueProcesada, '
        'productos: $productosSincronizados, errores: $errores)';
  }
}
