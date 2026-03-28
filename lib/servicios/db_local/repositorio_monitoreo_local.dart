part of 'package:bipenc/servicios/servicio_db_local.dart';

class RepositorioMonitoreoLocal {
  static Future<void> registrarMetricaAPI({
    required String metodo,
    required double latencia,
    required bool exito,
  }) async {
    try {
      final db = await ServicioDbLocal.database;
      await db.insert('monitoreo_api', {
        'metodo': metodo,
        'latencia': latencia,
        'exito': exito ? 1 : 0,
        'fecha': DateTime.now().toIso8601String(),
      });
    } catch (e, st) {
      RegistroApp.warn('No se pudo guardar la métrica de monitoreo',
          tag: 'MONITOREO_API', error: e, stackTrace: st);
    }
  }

  static Future<List<Map<String, dynamic>>> obtenerMetricas({
    int limit = 100,
  }) async {
    final db = await ServicioDbLocal.database;
    return await db.query(
      'monitoreo_api',
      orderBy: 'id DESC',
      limit: limit,
    );
  }
}
