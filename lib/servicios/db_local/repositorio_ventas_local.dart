part of 'package:bipenc/servicios/servicio_db_local.dart';

class RepositorioVentasLocal {
  static Future<List<Map<String, dynamic>>> obtenerItemsDeVenta(
      int ventaId) async {
    final db = await ServicioDbLocal.database;
    return db.query('venta_items',
        where: 'venta_id = ?', whereArgs: [ventaId], orderBy: 'id ASC');
  }

  static Future<({int ventaId, String correlativo})>
      guardarVentaPendienteAtomica({
    required List<ItemCarrito> items,
    required double total,
    required double subtotal,
    required double igv,
    required String aliasVendedor,
    String? documentoCliente,
    String? nombreCliente,
    String? appVersion,
    TipoComprobante tipoComprobante = TipoComprobante.boleta,
    String? correlativo,
    String metodoPago = 'EFECTIVO',
    bool estaSincronizado = false,
    String? orderListId,
  }) async {
    final db = await ServicioDbLocal.database;

    return await db.transaction((txn) async {
      final itemsData = items
          .map((i) => {
                'sku': i.producto.skuCode.isNotEmpty
                    ? i.producto.skuCode
                    : i.producto.id,
                'sku_code': i.producto.skuCode,
                'nombre': i.producto.nombre,
                'marca': i.producto.marca,
                'cantidad': i.cantidad,
                'presentacion_id': i.presentacion.id,
                'presentacion_nombre': i.presentacion.name,
                'unidades_totales': i.unidadesTotales,
                'precio': i.precioActual,
                'subtotal': i.subtotal,
              })
          .toList();

      final enc = await ServicioDbLocal._getEnc();
      String? encryptedDocumento = documentoCliente;
      String? encryptedNombre = nombreCliente;
      String? documentoHash;

      if (enc != null) {
        if (documentoCliente != null && documentoCliente.isNotEmpty) {
          encryptedDocumento = ServicioDbLocal._encryptField(enc, documentoCliente);
          documentoHash = await ServicioDbLocal._blindIndexForDoc(documentoCliente);
        }
        if (nombreCliente != null && nombreCliente.isNotEmpty) {
          encryptedNombre = ServicioDbLocal._encryptField(enc, nombreCliente);
        }
      } else {
        if (documentoCliente != null || nombreCliente != null) {
          RegistroApp.warn(
            'ServicioCifrado no disponible; PII se guardará sin cifrar',
            tag: 'LOCAL_DB',
          );
        }
        documentoHash = await ServicioDbLocal._blindIndexForDoc(documentoCliente);
      }

      final corrFinal = correlativo ??
          await _siguienteCorrelativoTxn(
            txn,
            tipoComprobante == TipoComprobante.factura ? '01' : '03',
          );

      final ventaId = await txn.insert('ventas_pendientes', {
        'total': total,
        'subtotal': subtotal,
        'igv': igv,
        'documento_cliente': encryptedDocumento,
        'documento_cliente_hash': documentoHash,
        'nombre_cliente': encryptedNombre,
        'alias_vendedor': aliasVendedor,
        'app_version': appVersion,
        'correlativo': corrFinal,
        'creado_at': DateTime.now().toIso8601String(),
        'metodo_pago': metodoPago,
        'sincronizado': estaSincronizado ? 1 : 0,
        'despachado': 0,
        'anulado': 0,
        'estado': estaSincronizado ? 'OK' : 'PENDIENTE',
        'estado_sunat': estaSincronizado ? 'EMITIDO' : 'PENDIENTE',
        'items_json': jsonEncode(itemsData),
        'order_list_id': orderListId,
      });

      final ahoraTs = DateTime.now().toIso8601String();
      for (final item in items) {
        await txn.insert('venta_items', {
          'venta_id': ventaId,
          'producto_id': item.producto.id,
          'producto_nombre': item.producto.nombre,
          'sku': item.producto.skuCode.isNotEmpty
              ? item.producto.skuCode
              : item.producto.id,
          'presentacion_id': item.presentacion.id,
          'presentacion_nombre': item.presentacion.name,
          'cantidad': item.cantidad,
          'precio_unitario': item.precioActual,
          'subtotal': item.subtotal,
          'creado_at': ahoraTs,
        });
      }

      RegistroApp.info(
          'Venta atómica guardada: ID=$ventaId, corr=$corrFinal, items=${items.length}',
          tag: 'LOCAL_DB');

      return (ventaId: ventaId, correlativo: corrFinal);
    });
  }

  static Future<int> guardarVentaPendiente({
    required String itemsJson,
    required double total,
    required String aliasVendedor,
    required double subtotal,
    required double igv,
    String? documentoCliente,
    String? nombreCliente,
    String? appVersion,
    String? correlativo,
    String metodoPago = 'EFECTIVO',
  }) async {
    final db = await ServicioDbLocal.database;
    final enc = await ServicioDbLocal._getEnc();
    final encryptedDocumento =
        (enc != null && (documentoCliente?.isNotEmpty ?? false))
            ? ServicioDbLocal._encryptField(enc, documentoCliente!)
            : documentoCliente;
    final encryptedNombre =
        (enc != null && (nombreCliente?.isNotEmpty ?? false))
            ? ServicioDbLocal._encryptField(enc, nombreCliente!)
            : nombreCliente;
    if (enc == null && (documentoCliente != null || nombreCliente != null)) {
      RegistroApp.warn(
        'ServicioCifrado no disponible; PII se guardará sin cifrar',
        tag: 'LOCAL_DB',
      );
    }
    final documentoHash = await ServicioDbLocal._blindIndexForDoc(documentoCliente);
    return await db.insert('ventas_pendientes', {
      'items_json': itemsJson,
      'total': total,
      'subtotal': subtotal,
      'igv': igv,
      'documento_cliente': encryptedDocumento,
      'documento_cliente_hash': documentoHash,
      'nombre_cliente': encryptedNombre,
      'alias_vendedor': aliasVendedor,
      'app_version': appVersion,
      'correlativo': correlativo,
      'creado_at': DateTime.now().toIso8601String(),
      'metodo_pago': metodoPago,
      'sincronizado': 0,
      'despachado': 0,
      'anulado': 0,
    });
  }

  static Future<int> purgarDatosAntiguos() async {
    final db = await ServicioDbLocal.database;
    final limitDate =
        DateTime.now().subtract(const Duration(days: 30)).toIso8601String();

    final count = await db.delete(
      'ventas_pendientes',
      where: 'creado_at < ? AND sincronizado = 1',
      whereArgs: [limitDate],
    );

    await db
        .delete('sync_queue', where: 'creado_at < ?', whereArgs: [limitDate]);

    RegistroApp.info('Mantenimiento: Purga de $count ventas antiguas completada',
        tag: 'LOCAL_DB');
    return count;
  }

  static Future<List<Map<String, dynamic>>> obtenerVentasPendientes() async {
    final db = await ServicioDbLocal.database;
    final rows = await db.transaction((txn) async {
      await txn.update(
        'ventas_pendientes',
        {'estado': 'PENDIENTE'},
        where: 'sincronizado = 0 AND estado = ?',
        whereArgs: ['SINCRONIZANDO'],
      );

      await txn.update(
        'ventas_pendientes',
        {'estado': 'SINCRONIZANDO'},
        where:
            'sincronizado = 0 AND (estado IS NULL OR estado != ?)',
        whereArgs: ['SINCRONIZANDO'],
      );
      return await txn.query(
        'ventas_pendientes',
        where: 'estado = ? AND (anulado IS NULL OR anulado = 0)',
        whereArgs: ['SINCRONIZANDO'],
        orderBy: 'creado_at ASC',
      );
    });

    return rows.map((r) => _descifrarPillaVenta(r)).toList();
  }

  static Future<void> registrarErrorSincronizacion(int id, String error) async {
    final db = await ServicioDbLocal.database;
    await db.update(
      'ventas_pendientes',
      {'estado': 'ERROR', 'error_msg': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<List<Map<String, dynamic>>> getUltimasVentas({
    int limit = 100,
    bool includeAnuladas = false,
  }) async {
    final db = await ServicioDbLocal.database;
    final rows = await db.query(
      'ventas_pendientes',
      where: includeAnuladas ? null : '(anulado IS NULL OR anulado = 0)',
      orderBy: 'creado_at DESC',
      limit: limit,
    );
    return rows.map((r) => _descifrarPillaVenta(r)).toList();
  }

  static Future<List<Map<String, dynamic>>> buscarVentasPorCorrelativo(
    String query, {
    int limit = 100,
    bool includeAnuladas = true,
  }) async {
    final db = await ServicioDbLocal.database;
    final q = query.trim();
    late final List<Map<String, Object?>> rows;
    final anuladoClause =
        includeAnuladas ? '' : ' AND (anulado IS NULL OR anulado = 0)';
    if (q.isEmpty) {
      rows = await db.query(
        'ventas_pendientes',
        where: includeAnuladas ? null : '(anulado IS NULL OR anulado = 0)',
        orderBy: 'creado_at DESC',
        limit: limit,
      );
    } else {
      rows = await db.query(
        'ventas_pendientes',
        where: '(correlativo LIKE ? OR CAST(id AS TEXT) LIKE ?)$anuladoClause',
        whereArgs: ['%$q%', '%$q%'],
        orderBy: 'creado_at DESC',
        limit: limit,
      );
    }
    return rows
        .map((r) => _descifrarPillaVenta(Map<String, dynamic>.from(r)))
        .toList();
  }

  static Map<String, dynamic> _descifrarPillaVenta(Map<String, dynamic> row) {
    final mutableRow = Map<String, dynamic>.from(row);
    final enc = ServicioCifrado();

    if (!enc.isInitialized) return mutableRow;

    final doc = mutableRow['documento_cliente'] as String?;
    final nom = mutableRow['nombre_cliente'] as String?;

    if (doc != null && doc.isNotEmpty) {
      try {
        if (doc.startsWith(ServicioDbLocal._encPrefix)) {
          mutableRow['documento_cliente'] = ServicioDbLocal._decryptField(enc, doc);
        } else {
          mutableRow['documento_cliente'] = enc.desencriptar(doc);
        }
      } catch (e, st) {
        RegistroApp.debug('No se pudo descifrar documento cliente ($e)',
            tag: 'LOCAL_DB');
        RegistroApp.warn('Detalle descifrado',
            tag: 'LOCAL_DB', error: e, stackTrace: st);
      }
    }
    if (nom != null && nom.isNotEmpty) {
      try {
        if (nom.startsWith(ServicioDbLocal._encPrefix)) {
          mutableRow['nombre_cliente'] = ServicioDbLocal._decryptField(enc, nom);
        } else {
          mutableRow['nombre_cliente'] = enc.desencriptar(nom);
        }
      } catch (e, st) {
        RegistroApp.debug('No se pudo descifrar nombre cliente ($e)',
            tag: 'LOCAL_DB');
        RegistroApp.warn('Detalle descifrado',
            tag: 'LOCAL_DB', error: e, stackTrace: st);
      }
    }

    return mutableRow;
  }

  static Future<void> marcarVentaSincronizada(int id) async {
    final db = await ServicioDbLocal.database;
    await db.update(
      'ventas_pendientes',
      {'sincronizado': 1, 'estado': 'OK', 'error_msg': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> marcarDespachado(int id) async {
    final db = await ServicioDbLocal.database;
    await db.update(
      'ventas_pendientes',
      {'despachado': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<bool> anularVentaLocal({
    required int ventaId,
    required String motivo,
    required String aliasUsuario,
  }) async {
    final db = await ServicioDbLocal.database;
    return db.transaction((txn) async {
      final venta = await txn.query(
        'ventas_pendientes',
        where: 'id = ?',
        whereArgs: [ventaId],
        limit: 1,
      );
      if (venta.isEmpty) return false;
      final row = venta.first;
      if ((row['anulado'] ?? 0) == 1) return true;

      final ts = DateTime.now().toIso8601String();
      await txn.update(
        'ventas_pendientes',
        {
          'anulado': 1,
          'anulado_motivo': motivo,
          'anulado_at': ts,
          'anulado_por': aliasUsuario,
          'estado': 'ANULADO',
        },
        where: 'id = ?',
        whereArgs: [ventaId],
      );

      final correlativo = row['correlativo']?.toString();
      final estabaSincronizada =
          ((row['sincronizado'] ?? 0) as num).toInt() == 1;
      final items = await txn.query('venta_items',
          columns: ['producto_id', 'cantidad'],
          where: 'venta_id = ?',
          whereArgs: [ventaId]);
      final tsMov = DateTime.now().toIso8601String();
      for (final it in items) {
        await txn.insert('movimientos_inventario', {
          'venta_id': ventaId,
          'producto_id': it['producto_id'],
          'cantidad': (it['cantidad'] as num?)?.toDouble() ?? 0,
          'tipo': 'ANULACION',
          'created_at': tsMov,
        });
      }
      if (correlativo != null && correlativo.isNotEmpty && estabaSincronizada) {
        final syncId =
            'anul_venta_${DateTime.now().millisecondsSinceEpoch}_$ventaId';
        await txn.insert('sync_queue_v2', {
          'id': syncId,
          'tabla': 'ventas',
          'operacion': 'ANULAR',
          'datos': jsonEncode({
            'correlativo': correlativo,
            'anulado': true,
            'anulado_motivo': motivo,
            'anulado_at': ts,
            'anulado_por': aliasUsuario,
            'id_local': ventaId,
          }),
          'created_at': ts,
          'intentos': 0,
          'sincronizado': 0,
        });
      } else if (!estabaSincronizada) {
        await txn.update(
          'ventas_pendientes',
          {'sincronizado': 1, 'error_msg': null},
          where: 'id = ?',
          whereArgs: [ventaId],
        );
      }

      return true;
    });
  }

  static Future<String> _siguienteCorrelativoTxn(
    DatabaseExecutor txn,
    String tipoDoc,
  ) async {
    final defaultSerie = tipoDoc == '01' ? 'F001' : 'B001';
    final rows = await txn.query(
      'config_correlativos',
      where: 'tipo_documento = ?',
      whereArgs: [tipoDoc],
      limit: 1,
    );
    String serie;
    int ultimo;
    if (rows.isEmpty) {
      serie = defaultSerie;
      ultimo = 0;
      await txn.insert('config_correlativos', {
        'tipo_documento': tipoDoc,
        'serie': serie,
        'ultimo_numero': ultimo,
      });
    } else {
      serie = rows.first['serie'] as String? ?? defaultSerie;
      ultimo = (rows.first['ultimo_numero'] as int?) ?? 0;
    }
    final nuevo = ultimo + 1;
    await txn.update(
      'config_correlativos',
      {'ultimo_numero': nuevo},
      where: 'tipo_documento = ? AND serie = ?',
      whereArgs: [tipoDoc, serie],
    );
    return '$serie-${nuevo.toString().padLeft(5, '0')}';
  }
}
