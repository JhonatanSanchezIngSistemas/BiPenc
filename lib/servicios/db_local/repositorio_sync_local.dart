part of 'package:bipenc/servicios/servicio_db_local.dart';

class RepositorioSyncLocal {
  static Future<int> countPendingSync() async {
    final db = await ServicioDbLocal.database;
    final res = await db.rawQuery(
        'SELECT COUNT(*) as c FROM sync_queue_v2 WHERE sincronizado = 0');
    return (res.first['c'] as int?) ?? 0;
  }

  static Future<List<Map<String, dynamic>>> obtenerSyncQueue() async {
    final db = await ServicioDbLocal.database;
    return db.query('sync_queue', orderBy: 'creado_at ASC');
  }

  static Future<void> eliminarDeSyncQueue(int id) async {
    final db = await ServicioDbLocal.database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> insertarEnSyncQueueV2({
    required String id,
    required String tabla,
    required String operacion,
    required String datosJson,
  }) async {
    final db = await ServicioDbLocal.database;
    await db.insert(
      'sync_queue_v2',
      {
        'id': id,
        'tabla': tabla,
        'operacion': operacion,
        'datos': datosJson,
        'created_at': DateTime.now().toIso8601String(),
        'intentos': 0,
        'sincronizado': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> enqueueDocumentoCache(Map<String, dynamic> payload) async {
    final id =
        'doc_${payload['numero']}_${DateTime.now().millisecondsSinceEpoch}';
    await insertarEnSyncQueueV2(
      id: id,
      tabla: 'document_cache',
      operacion: 'UPSERT',
      datosJson: jsonEncode(payload),
    );
  }

  static Future<List<Map<String, dynamic>>>
      obtenerSyncQueueV2Pendiente() async {
    final db = await ServicioDbLocal.database;
    return db.query(
      'sync_queue_v2',
      where: 'sincronizado = 0 AND intentos <= 5',
      orderBy: 'created_at ASC',
      limit: 20,
    );
  }

  static Future<void> marcarSyncQueueV2Sincronizado(String id) async {
    final db = await ServicioDbLocal.database;
    await db.update(
      'sync_queue_v2',
      {'sincronizado': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> registrarIntentoSyncQueueV2(
      String id, String? error) async {
    final db = await ServicioDbLocal.database;
    await db.rawUpdate('''
      UPDATE sync_queue_v2 
      SET intentos = intentos + 1,
          ultimo_intento = ?,
          error_mensaje = ?
      WHERE id = ?
    ''', [DateTime.now().toIso8601String(), error, id]);
  }

  static Future<bool> existeSyncQueueV2EnAlerta(
      {Duration threshold = const Duration(hours: 12)}) async {
    final db = await ServicioDbLocal.database;
    final cutoff = DateTime.now().subtract(threshold).toIso8601String();
    final rows = await db.rawQuery('''
      SELECT 1
      FROM sync_queue_v2
      WHERE sincronizado = 0
        AND (
          (error_mensaje IS NOT NULL AND error_mensaje != '')
          OR COALESCE(ultimo_intento, created_at) < ?
        )
      LIMIT 1
    ''', [cutoff]);
    return rows.isNotEmpty;
  }

  static Future<void> limpiarSyncQueueV2Antigua() async {
    final db = await ServicioDbLocal.database;
    final limit =
        DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
    await db.delete(
      'sync_queue_v2',
      where: 'sincronizado = 1 AND created_at < ?',
      whereArgs: [limit],
    );
  }
}
