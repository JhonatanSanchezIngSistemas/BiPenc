part of 'package:bipenc/servicios/servicio_db_local.dart';

class RepositorioCajaLocal {
  static Future<Map<String, dynamic>?> obtenerTurnoCajaAbierto() async {
    final db = await ServicioDbLocal.database;
    final rows = await db.query(
      'caja_turnos',
      where: 'estado = ?',
      whereArgs: ['ABIERTO'],
      orderBy: 'abierto_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  static Future<int> abrirTurnoCaja({
    required double montoApertura,
    required String aliasUsuario,
  }) async {
    final db = await ServicioDbLocal.database;
    final abierto = await obtenerTurnoCajaAbierto();
    if (abierto != null) {
      return (abierto['id'] as num).toInt();
    }
    return db.insert('caja_turnos', {
      'abierto_at': DateTime.now().toIso8601String(),
      'monto_apertura': montoApertura,
      'estado': 'ABIERTO',
      'abierto_por': aliasUsuario,
    });
  }

  static Future<Map<String, dynamic>> obtenerResumenTurnoActual() async {
    final db = await ServicioDbLocal.database;
    final turno = await obtenerTurnoCajaAbierto();
    if (turno == null) {
      return {
        'hay_turno_abierto': false,
        'turno': null,
        'conteo_ventas': 0,
        'total_efectivo': 0.0,
        'total_yapeplin': 0.0,
        'total_tarjeta': 0.0,
        'total_general': 0.0,
      };
    }

    final abiertoAt = (turno['abierto_at'] ?? '').toString();
    final rows = await db.query(
      'ventas_pendientes',
      where: 'creado_at >= ? AND (anulado IS NULL OR anulado = 0)',
      whereArgs: [abiertoAt],
    );

    double efe = 0, yap = 0, tar = 0;
    for (final r in rows) {
      final total = ((r['total'] ?? 0) as num).toDouble();
      final metodo = (r['metodo_pago'] ?? 'EFECTIVO').toString().toUpperCase();
      if (metodo == 'EFECTIVO') {
        efe += total;
      } else if (metodo == 'YAPEPLIN' ||
          metodo == 'YAPE/PLIN' ||
          metodo == 'YAPE_PLIN') {
        yap += total;
      } else if (metodo == 'TARJETA') {
        tar += total;
      } else {
        efe += total;
      }
    }

    return {
      'hay_turno_abierto': true,
      'turno': turno,
      'conteo_ventas': rows.length,
      'total_efectivo': efe,
      'total_yapeplin': yap,
      'total_tarjeta': tar,
      'total_general': efe + yap + tar,
    };
  }

  static Future<bool> cerrarTurnoCaja({
    required int turnoId,
    required double montoCierreReal,
    required String aliasUsuario,
    String? observaciones,
  }) async {
    final db = await ServicioDbLocal.database;
    final rows = await db.query(
      'caja_turnos',
      where: 'id = ? AND estado = ?',
      whereArgs: [turnoId, 'ABIERTO'],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final turno = rows.first;
    final abiertoAt = (turno['abierto_at'] ?? '').toString();
    final montoApertura = ((turno['monto_apertura'] ?? 0) as num).toDouble();

    final ventas = await db.query(
      'ventas_pendientes',
      columns: ['total', 'metodo_pago'],
      where: 'creado_at >= ? AND (anulado IS NULL OR anulado = 0)',
      whereArgs: [abiertoAt],
    );

    double efectivoTurno = 0;
    for (final v in ventas) {
      final metodo = (v['metodo_pago'] ?? 'EFECTIVO').toString().toUpperCase();
      if (metodo == 'EFECTIVO') {
        efectivoTurno += ((v['total'] ?? 0) as num).toDouble();
      }
    }
    final montoTeorico = montoApertura + efectivoTurno;
    final diferencia = montoCierreReal - montoTeorico;

    await db.update(
      'caja_turnos',
      {
        'cerrado_at': DateTime.now().toIso8601String(),
        'monto_cierre_real': montoCierreReal,
        'monto_teorico': montoTeorico,
        'diferencia': diferencia,
        'estado': 'CERRADO',
        'cerrado_por': aliasUsuario,
        'observaciones': observaciones,
      },
      where: 'id = ?',
      whereArgs: [turnoId],
    );
    return true;
  }
}
