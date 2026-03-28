part of 'package:bipenc/servicios/servicio_db_local.dart';

class RepositorioAuditoriaLocal {
  static Future<void> logAudit({
    required String accion,
    String? usuario,
    String? detalle,
  }) async {
    final db = await ServicioDbLocal.database;
    await db.insert('audit_logs', {
      'accion': accion,
      'usuario': usuario,
      'detalle': detalle,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<List<Map<String, dynamic>>> obtenerAuditLogs(
      {int limit = 50}) async {
    final db = await ServicioDbLocal.database;
    return db.query('audit_logs', orderBy: 'created_at DESC', limit: limit);
  }
}
