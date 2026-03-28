part of 'package:bipenc/servicios/servicio_db_local.dart';

class RepositorioDocumentosLocal {
  static Future<void> upsertClienteCache({
    required String numero,
    required String nombre,
    String? direccion,
    required String tipo,
  }) async {
    final db = await ServicioDbLocal.database;
    final enc = await ServicioDbLocal._getEnc();
    final numeroKey = await ServicioDbLocal._blindIndexForDoc(numero) ?? numero;
    final nombreValue = enc != null && nombre.isNotEmpty
        ? ServicioDbLocal._encryptField(enc, nombre)
        : nombre;
    final direccionValue = enc != null && (direccion?.isNotEmpty ?? false)
        ? ServicioDbLocal._encryptField(enc, direccion!)
        : direccion;
    await db.insert(
      'clientes_cache',
      {
        'numero': numeroKey,
        'nombre': nombreValue,
        'direccion': direccionValue,
        'tipo': tipo,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<Map<String, dynamic>?> getCachedDocument(String numero) async {
    final db = await ServicioDbLocal.database;
    final enc = await ServicioDbLocal._getEnc();
    final numeroKey = await ServicioDbLocal._blindIndexForDoc(numero) ?? numero;
    var rows = await db.query('document_cache',
        where: 'numero = ?', whereArgs: [numeroKey], limit: 1);
    if (rows.isEmpty && numeroKey != numero) {
      rows = await db.query('document_cache',
          where: 'numero = ?', whereArgs: [numero], limit: 1);
    }
    if (rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first);
    if (enc == null) return row;
    final nombre = row['nombre'] as String?;
    final direccion = row['direccion'] as String?;
    if (nombre != null && nombre.startsWith(ServicioDbLocal._encPrefix)) {
      try {
        row['nombre'] = ServicioDbLocal._decryptField(enc, nombre);
      } catch (e, st) {
        RegistroApp.debug('No se pudo descifrar nombre cache ($e)',
            tag: 'LOCAL_DB');
        RegistroApp.warn('Detalle descifrado',
            tag: 'LOCAL_DB', error: e, stackTrace: st);
      }
    } else if (nombre != null && nombre.contains('.')) {
      try {
        row['nombre'] = enc.desencriptar(nombre);
      } catch (e, st) {
        RegistroApp.debug('No se pudo descifrar nombre cache legacy ($e)',
            tag: 'LOCAL_DB');
        RegistroApp.warn('Detalle descifrado',
            tag: 'LOCAL_DB', error: e, stackTrace: st);
      }
    }
    if (direccion != null && direccion.startsWith(ServicioDbLocal._encPrefix)) {
      try {
        row['direccion'] = ServicioDbLocal._decryptField(enc, direccion);
      } catch (e, st) {
        RegistroApp.debug('No se pudo descifrar direccion cache ($e)',
            tag: 'LOCAL_DB');
        RegistroApp.warn('Detalle descifrado',
            tag: 'LOCAL_DB', error: e, stackTrace: st);
      }
    } else if (direccion != null && direccion.contains('.')) {
      try {
        row['direccion'] = enc.desencriptar(direccion);
      } catch (e, st) {
        RegistroApp.debug('No se pudo descifrar direccion cache legacy ($e)',
            tag: 'LOCAL_DB');
        RegistroApp.warn('Detalle descifrado',
            tag: 'LOCAL_DB', error: e, stackTrace: st);
      }
    }
    return row;
  }

  static Future<void> saveDocumentCache({
    required String numero,
    required String tipo,
    required String nombre,
    String? direccion,
    required DateTime expiresAt,
  }) async {
    final db = await ServicioDbLocal.database;
    final enc = await ServicioDbLocal._getEnc();
    final numeroKey = await ServicioDbLocal._blindIndexForDoc(numero) ?? numero;
    final nombreValue = enc != null && nombre.isNotEmpty
        ? ServicioDbLocal._encryptField(enc, nombre)
        : nombre;
    final direccionValue = enc != null && (direccion?.isNotEmpty ?? false)
        ? ServicioDbLocal._encryptField(enc, direccion!)
        : direccion;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'document_cache',
      {
        'numero': numeroKey,
        'tipo': tipo,
        'nombre': nombreValue,
        'direccion': direccionValue,
        'cached_at': nowMs,
        'expires_at': expiresAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> purgeExpiredDocuments() async {
    final db = await ServicioDbLocal.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db
        .delete('document_cache', where: 'expires_at < ?', whereArgs: [now]);
  }
}
