part of 'package:bipenc/servicios/servicio_db_local.dart';

class RepositorioConfigLocal {
  static Future<Map<String, dynamic>?> getEmpresaConfig() async {
    final db = await ServicioDbLocal.database;
    final rows = await db.query('empresa_config', limit: 1);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  static Future<void> upsertEmpresaConfig(Map<String, dynamic> values) async {
    final db = await ServicioDbLocal.database;
    await db.insert('empresa_config', values,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> setCorrelativoManual({
    required String tipoDoc,
    required String serie,
    required int ultimoNumero,
  }) async {
    final db = await ServicioDbLocal.database;
    await db.insert(
      'config_correlativos',
      {
        'tipo_documento': tipoDoc,
        'serie': serie,
        'ultimo_numero': ultimoNumero,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<Map<String, dynamic>?> getCorrelativoConfig(
      {required String tipoDoc}) async {
    final db = await ServicioDbLocal.database;
    final rows = await db.query('config_correlativos',
        where: 'tipo_documento = ?', whereArgs: [tipoDoc], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  static Future<List<Map<String, dynamic>>> getAllCorrelativos() async {
    final db = await ServicioDbLocal.database;
    return db.query('config_correlativos');
  }

  static Future<void> syncCorrelativosDesdeSupabase(
      List<Map<String, dynamic>> rows) async {
    final db = await ServicioDbLocal.database;
    await db.transaction((txn) async {
      await txn.delete('config_correlativos');
      for (final r in rows) {
        await txn.insert('config_correlativos', {
          'tipo_documento': r['tipo_documento'],
          'serie': r['serie'],
          'ultimo_numero': r['ultimo_numero'],
        });
      }
    });
  }
}
