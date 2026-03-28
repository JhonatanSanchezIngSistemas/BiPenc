import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'servicio_db_local.dart';
import '../utilidades/registro_app.dart';

/// Gestor de cola de impresión con persistencia
/// Garantiza que ningún ticket se pierda si hay desconexión Bluetooth
class ColaImpresion {
  ColaImpresion._();
  static const int _maxIntentos = 5;
  static Future<void>? _processingTask;

  @visibleForTesting
  static Future<Database> Function()? databaseOverride;
  @visibleForTesting
  static Future<bool> Function()? connectionStatusOverride;
  @visibleForTesting
  static Future<bool> Function(List<int> bytes)? writeBytesOverride;
  @visibleForTesting
  static Duration Function()? perItemDelayOverride;

  static Future<Database> _database() async =>
      databaseOverride != null ? databaseOverride!() : ServicioDbLocal.database;
  static Future<bool> _connectionStatus() async =>
      connectionStatusOverride != null
          ? connectionStatusOverride!()
          : (_isPrintSupported()
              ? PrintBluetoothThermal.connectionStatus
              : false);
  static Future<bool> _writeBytes(List<int> bytes) async =>
      writeBytesOverride != null
          ? writeBytesOverride!(bytes)
          : (_isPrintSupported()
              ? PrintBluetoothThermal.writeBytes(bytes)
              : false);
  static Duration _perItemDelay() => perItemDelayOverride != null
      ? perItemDelayOverride!()
      : const Duration(milliseconds: 500);

  /// Encola un comprobante para impresión con reintentos automáticos
  static Future<void> encolarImpresion({
    required List<int> bytes,
    required String tipoComprobante,
    required String ventaId,
  }) async {
    try {
      final db = await _database();

      // Convertir bytes a string hex para persistencia
      final bytesHex =
          bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      await db.insert('print_queue', {
        'bytes_hex': bytesHex,
        'tipo_comprobante': tipoComprobante,
        'venta_id': ventaId,
        'creado_at': DateTime.now().toIso8601String(),
        'intentos': 0,
        'impreso': 0,
      });

      RegistroApp.info('Comprobante encolado: $ventaId (tipo: $tipoComprobante)',
          tag: 'PRINT_QUEUE');

      // Intenta imprimir AHORA, si falla queda en cola para después
      await procesarCola();
    } catch (e) {
      RegistroApp.error('Error encolando impresión',
          tag: 'PRINT_QUEUE', error: e);
    }
  }

  /// Procesa la cola de impresiones pendientes
  /// Llamar: Al startup, cuando Bluetooth se conecta, etc.
  static Future<void> procesarCola() async {
    if (_processingTask != null) {
      await _processingTask;
      return;
    }
    final task = _procesarColaInternal();
    _processingTask = task;
    try {
      await task;
    } finally {
      _processingTask = null;
    }
  }

  static Future<void> _procesarColaInternal() async {
    try {
      final db = await _database();

      if (!_isPrintSupported()) {
        RegistroApp.debug('Impresión BT no soportada en esta plataforma',
            tag: 'PRINT_QUEUE');
        return;
      }

      final conectado = await _connectionStatus();
      if (!conectado) {
        RegistroApp.warn(
            'Bluetooth no conectado. Cola de impresión queda pendiente.',
            tag: 'PRINT_QUEUE');
        return;
      }

      // Obtener pendientes: no impresos con intentos < max
      final pendientes = await db.query(
        'print_queue',
        where: 'impreso = 0 AND intentos < ?',
        whereArgs: [_maxIntentos],
        orderBy: 'creado_at ASC',
      );

      if (pendientes.isEmpty) return;

      RegistroApp.info('Procesando ${pendientes.length} items de print_queue',
          tag: 'PRINT_QUEUE');

      for (final item in pendientes) {
        final id = item['id'] as int;
        final bytesHex = item['bytes_hex'] as String;
        final intentos = item['intentos'] as int;
        final ventaId = item['venta_id'] as String;

        try {
          // Convertir hex back a bytes
          final bytes = [
            for (int i = 0; i < bytesHex.length; i += 2)
              int.parse(bytesHex.substring(i, i + 2), radix: 16)
          ];

          // Intentar imprimir
          final resultado = await _writeBytes(bytes);

          if (resultado) {
            // Success: marcar como impreso
            await db.update(
              'print_queue',
              {'impreso': 1},
              where: 'id = ?',
              whereArgs: [id],
            );

            RegistroApp.info(
                'Impresión cola exitosa: $ventaId (intento ${intentos + 1})',
                tag: 'PRINT_QUEUE');
          } else {
            // Falló: incrementar contador de intentos
            await db.update(
              'print_queue',
              {'intentos': intentos + 1},
              where: 'id = ?',
              whereArgs: [id],
            );

            RegistroApp.warn(
                'Impresión cola falló: $ventaId (intento ${intentos + 1}/$_maxIntentos)',
                tag: 'PRINT_QUEUE');
          }
        } catch (e) {
          // Error: registrar e incrementar intentos
          await db.update(
            'print_queue',
            {
              'intentos': intentos + 1,
              'error_msg': e.toString().substring(0, 100), // Limitar longitud
            },
            where: 'id = ?',
            whereArgs: [id],
          );

          RegistroApp.error('Excepción imprimiendo cola $ventaId: $e',
              tag: 'PRINT_QUEUE', error: e);
        }

        // Pequeña pausa entre intentos para no saturar
        await Future.delayed(_perItemDelay());
      }
    } catch (e) {
      RegistroApp.error('Error procesando print_queue',
          tag: 'PRINT_QUEUE', error: e);
    }
  }

  /// Elimina toda la cola (impresos y pendientes). Útil en soporte.
  static Future<void> vaciar() async {
    try {
      final db = await _database();
      final deleted = await db.delete('print_queue');
      RegistroApp.warn('Cola de impresión vaciada ($deleted registros)',
          tag: 'PRINT_QUEUE');
    } catch (e) {
      RegistroApp.error('Error vaciando print_queue',
          tag: 'PRINT_QUEUE', error: e);
    }
  }

  /// Limpia queue antigua (mantener BD limpia)
  /// Llamar regularmente, ej: en app startup
  static Future<void> limpiarColaAntigua() async {
    try {
      final db = await _database();
      final now = DateTime.now();

      // Borrar: impresos hace más de 24 horas
      final hace24h = now.subtract(const Duration(days: 1)).toIso8601String();

      final borrados1 = await db.delete(
        'print_queue',
        where: 'impreso = 1 AND creado_at < ?',
        whereArgs: [hace24h],
      );

      // Borrar: intentos agotados hace más de 6 horas
      final hace6h = now.subtract(const Duration(hours: 6)).toIso8601String();

      final borrados2 = await db.delete(
        'print_queue',
        where: 'impreso = 0 AND intentos >= ? AND creado_at < ?',
        whereArgs: [_maxIntentos, hace6h],
      );

      if (borrados1 > 0 || borrados2 > 0) {
        RegistroApp.info(
            'Print queue limpieza: $borrados1 impresos + $borrados2 fallidos',
            tag: 'PRINT_QUEUE');
      }
    } catch (e) {
      RegistroApp.error('Error limpiando print_queue',
          tag: 'PRINT_QUEUE', error: e);
    }
  }

  /// Obtiene estadísticas de la cola
  static Future<Map<String, dynamic>> obtenerEstadisticas() async {
    try {
      final db = await _database();

      final pendientes = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM print_queue WHERE impreso = 0')) ??
          0;

      final impresos = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM print_queue WHERE impreso = 1')) ??
          0;

      final fallidos = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM print_queue WHERE impreso = 0 AND intentos >= $_maxIntentos')) ??
          0;

      return {
        'pendientes': pendientes,
        'impresos': impresos,
        'fallidos': fallidos,
        'total': pendientes + impresos,
      };
    } catch (e) {
      RegistroApp.error('Error obteniendo estadísticas',
          tag: 'PRINT_QUEUE', error: e);
      return {
        'pendientes': 0,
        'impresos': 0,
        'fallidos': 0,
        'total': 0,
      };
    }
  }

  @visibleForTesting
  static void resetTestingOverrides() {
    databaseOverride = null;
    connectionStatusOverride = null;
    writeBytesOverride = null;
    perItemDelayOverride = null;
  }

  static bool _isPrintSupported() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
