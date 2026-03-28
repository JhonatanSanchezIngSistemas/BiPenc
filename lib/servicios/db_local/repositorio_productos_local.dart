part of 'package:bipenc/servicios/servicio_db_local.dart';

class RepositorioProductosLocal {
  static Future<void> upsertProducto(Producto producto) async {
    final db = await ServicioDbLocal.database;
    await db.transaction((txn) async {
      String skuPrincipal = producto.skuCode.isNotEmpty
          ? producto.skuCode
          : (producto.presentaciones.isNotEmpty &&
                  producto.presentaciones.first.barcode != null
              ? producto.presentaciones.first.barcode!
              : producto.id);

      await txn.insert(
        'productos_cache',
        {
          'id': producto.id,
          'sku': skuPrincipal,
          'nombre': producto.nombre,
          'marca': producto.marca,
          'categoria': producto.categoria,
          'imagen_url': producto.imagenPath,
          'estado': producto.estado,
          'precio_propuesto': producto.precioPropuesto ?? 0.0,
          'creado_at': producto.updatedAt?.toIso8601String() ??
              DateTime.now().toIso8601String(),
          'last_sync_timestamp': producto.lastSyncTimestamp?.toIso8601String(),
          'local_version': producto.localVersion,
          'sync_hash': producto.syncHash,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete('presentaciones',
          where: 'producto_id = ?', whereArgs: [producto.id]);

      if (producto.presentaciones.isNotEmpty) {
        for (final pres in producto.presentaciones) {
          await txn.insert('presentaciones', {
            'id': pres.id,
            'producto_id': producto.id,
            'nombre': pres.name,
            'factor': pres.conversionFactor.toInt(),
            'precio': pres.getPriceByType('NORMAL'),
            'codigo_barras': pres.barcode,
          });
        }
      } else if (producto.precioPropuesto != null &&
          producto.precioPropuesto! > 0) {
        await txn.insert('presentaciones', {
          'id': 'pres-${producto.id}-default',
          'producto_id': producto.id,
          'nombre': 'Unidad',
          'factor': 1,
          'precio': producto.precioPropuesto!,
          'codigo_barras': skuPrincipal,
        });
      }
    });
  }

  static Future<void> upsertProductos(List<Producto> productos) async {
    final db = await ServicioDbLocal.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final p in productos) {
        batch.insert(
          'productos_cache',
          {
            'id': p.id,
            'sku': p.skuCode.isNotEmpty
                ? p.skuCode
                : (p.presentaciones.isNotEmpty
                    ? (p.presentaciones.first.barcode ?? p.id)
                    : p.id),
            'nombre': p.nombre,
            'marca': p.marca,
            'categoria': p.categoria,
            'imagen_url': p.imagenPath,
            'estado': p.estado,
            'precio_propuesto': p.precioPropuesto,
            'creado_at': p.updatedAt?.toIso8601String() ??
                DateTime.now().toIso8601String(),
            'last_sync_timestamp': p.lastSyncTimestamp?.toIso8601String(),
            'local_version': p.localVersion,
            'sync_hash': p.syncHash,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        batch.delete('presentaciones',
            where: 'producto_id = ?', whereArgs: [p.id]);
        for (final pres in p.presentaciones) {
          batch.insert('presentaciones', {
            'id': pres.id,
            'producto_id': p.id,
            'nombre': pres.name,
            'factor': pres.conversionFactor,
            'precio': pres.getPriceByType('NORMAL'),
            'codigo_barras': pres.barcode,
          });
        }
      }
      await batch.commit(noResult: true);
    });
  }

  static Future<List<Producto>> buscarLocal(String query) async {
    final db = await ServicioDbLocal.database;
    final rawQuery = query.trim().toLowerCase();
    if (rawQuery.isEmpty) {
      final rows = await db.query(
        'productos_cache',
        orderBy: 'contador_ventas DESC, nombre ASC',
        limit: 200,
      );
      final productos = <Producto>[];
      for (final row in rows) {
        final id = row['id'] as String;
        final presRows = await db
            .query('presentaciones', where: 'producto_id = ?', whereArgs: [id]);
        productos.add(_mapToProducto(row, presRows));
      }
      return productos;
    }
    final q = '%$rawQuery%';
    final rows = await db.query(
      'productos_cache',
      where:
          'LOWER(nombre) LIKE ? OR LOWER(marca) LIKE ? OR LOWER(sku) LIKE ? OR LOWER(categoria) LIKE ? OR LOWER(id) LIKE ?',
      whereArgs: [q, q, q, q, q],
      orderBy: 'contador_ventas DESC',
    );

    List<Producto> productos = [];
    for (final row in rows) {
      final id = row['id'] as String;
      final presRows = await db
          .query('presentaciones', where: 'producto_id = ?', whereArgs: [id]);
      productos.add(_mapToProducto(row, presRows));
    }
    return productos;
  }

  static Future<List<Producto>> obtenerTop10() async {
    final db = await ServicioDbLocal.database;
    final rows = await db.query(
      'productos_cache',
      orderBy: 'contador_ventas DESC, ultima_venta_at DESC, creado_at DESC',
      limit: 10,
    );

    List<Producto> productos = [];
    for (final row in rows) {
      final id = row['id'] as String;
      final presRows = await db
          .query('presentaciones', where: 'producto_id = ?', whereArgs: [id]);
      productos.add(_mapToProducto(row, presRows));
    }
    return productos;
  }

  static Future<Producto?> getProductoById(String id) async {
    final db = await ServicioDbLocal.database;
    final rows = await db.query('productos_cache',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final presRows = await db
        .query('presentaciones', where: 'producto_id = ?', whereArgs: [id]);
    return _mapToProducto(row, presRows);
  }

  static Future<List<Producto>> buscarPorCodigoBarras(String codigo) async {
    final db = await ServicioDbLocal.database;
    final normalized = codigo.trim();
    if (normalized.isEmpty) return [];

    final bridgeRows = await db.query(
      'producto_codigos',
      where: 'codigo_barras = ?',
      whereArgs: [normalized],
    );

    final productIds = <String>{};
    for (final r in bridgeRows) {
      final id = r['producto_id'] as String?;
      if (id != null && id.isNotEmpty) productIds.add(id);
    }

    if (productIds.isEmpty) {
      final presRows = await db.query(
        'presentaciones',
        where: 'codigo_barras = ?',
        whereArgs: [normalized],
      );
      for (final r in presRows) {
        final id = r['producto_id'] as String?;
        if (id != null && id.isNotEmpty) productIds.add(id);
      }
    }

    final productos = <Producto>[];
    for (final id in productIds) {
      final prodRows = await db.query(
        'productos_cache',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (prodRows.isNotEmpty) {
        final presRows = await db.query(
          'presentaciones',
          where: 'producto_id = ?',
          whereArgs: [id],
        );
        productos.add(_mapToProducto(prodRows.first, presRows));
      }
    }
    return productos;
  }

  static Future<void> vincularCodigoLocal(
    String codigo,
    String productoId, {
    String? variante,
  }) async {
    final db = await ServicioDbLocal.database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'producto_codigos',
      {
        'codigo_barras': codigo.trim(),
        'producto_id': productoId,
        'descripcion_variante': variante,
        'creado_en': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final syncId =
        'vincular_${codigo}_${productoId}_${DateTime.now().millisecondsSinceEpoch}';
    await db.insert(
        'sync_queue_v2',
        {
          'id': syncId,
          'tabla': 'producto_codigos',
          'operacion': 'VINCULAR_CODIGO',
          'datos': jsonEncode({
            'codigo_barras': codigo.trim(),
            'producto_id': productoId,
            'descripcion_variante': variante,
          }),
          'created_at': now,
          'intentos': 0,
          'sincronizado': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    RegistroApp.info('[BarcodeLink] Vinculado: $codigo → $productoId',
        tag: 'POS');
  }

  static Future<void> desvincularCodigoLocal(
    String codigo,
    String productoId,
  ) async {
    final db = await ServicioDbLocal.database;
    final now = DateTime.now().toIso8601String();
    await db.delete(
      'producto_codigos',
      where: 'codigo_barras = ? AND producto_id = ?',
      whereArgs: [codigo.trim(), productoId],
    );
    final syncId =
        'desvincular_${codigo}_${productoId}_${DateTime.now().millisecondsSinceEpoch}';
    await db.insert(
        'sync_queue_v2',
        {
          'id': syncId,
          'tabla': 'producto_codigos',
          'operacion': 'DESVINCULAR_CODIGO',
          'datos': jsonEncode({
            'codigo_barras': codigo.trim(),
            'producto_id': productoId,
          }),
          'created_at': now,
          'intentos': 0,
          'sincronizado': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    RegistroApp.info('[BarcodeLink] Desvinculado: $codigo ↛ $productoId',
        tag: 'POS');
  }

  static Future<List<Map<String, dynamic>>> getVinculosPorCodigo(
      String codigo) async {
    final db = await ServicioDbLocal.database;
    return db.query('producto_codigos',
        where: 'codigo_barras = ?', whereArgs: [codigo.trim()]);
  }

  static Future<void> registrarVentaLocal(List<ItemCarrito> items) async {
    final db = await ServicioDbLocal.database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();

    for (final item in items) {
      batch.rawUpdate('''
        UPDATE productos_cache 
        SET contador_ventas = contador_ventas + 1, 
            ultima_venta_at = ?
        WHERE id = ?
      ''', [now, item.producto.id]);

      final syncId =
          'sale_ev_${item.producto.id}_${DateTime.now().millisecondsSinceEpoch}';
      batch.insert('sync_queue_v2', {
        'id': syncId,
        'tabla': 'productos',
        'operacion': 'SALE_EVENT',
        'datos': jsonEncode({
          'sku': item.producto.skuCode.isNotEmpty
              ? item.producto.skuCode
              : item.producto.id,
          'mensaje': 'Venta registrada localmente'
        }),
        'created_at': now,
        'intentos': 0,
        'sincronizado': 0,
      });
    }
    await batch.commit(noResult: true);
  }

  static Future<int> contarProductos() async {
    final db = await ServicioDbLocal.database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as total FROM productos_cache');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<void> seedIfEmpty() async {
    final count = await contarProductos();
    if (count > 0) return;

    RegistroApp.info('Sembrando catálogo inicial...', tag: 'LOCAL_DB');
    final productos = _seedProducts();
    await upsertProductos(productos);
  }

  static Future<void> eliminarProducto(String id, {String? sku}) async {
    final db = await ServicioDbLocal.database;
    await db.transaction((txn) async {
      await txn.delete('productos_cache', where: 'id = ?', whereArgs: [id]);

      final syncId = 'del_prod_${DateTime.now().millisecondsSinceEpoch}';
      await txn.insert('sync_queue_v2', {
        'id': syncId,
        'tabla': 'productos',
        'operacion': 'DELETE',
        'datos': jsonEncode({
          'id': id,
          'sku': (sku != null && sku.trim().isNotEmpty) ? sku : id,
        }),
        'created_at': DateTime.now().toIso8601String(),
        'intentos': 0,
        'sincronizado': 0,
      });
    });
  }

  static Future<void> eliminarProductoLocal(String id) async {
    final db = await ServicioDbLocal.database;
    await db.delete('productos_cache', where: 'id = ?', whereArgs: [id]);
  }

  static List<Producto> _seedProducts() {
    return [];
  }

  static Producto _mapToProducto(
      Map<String, dynamic> row, List<Map<String, dynamic>> presRows) {
    final presentations = presRows
        .map((p) => Presentacion.fromJson({
              'id': p['id'],
              'skuCode': p['codigo_barras'] ?? '',
              'name': p['nombre'],
              'conversionFactor': (p['factor'] ?? 1).toDouble(),
              'barcode': p['codigo_barras'],
              'prices': [
                {'type': 'NORMAL', 'amount': p['precio']}
              ],
            }))
        .toList();

    return Producto(
      id: row['id'] as String,
      skuCode: row['sku'] as String? ?? row['id'] as String,
      nombre: row['nombre'] as String,
      marca: row['marca'] as String,
      categoria: row['categoria'] as String,
      presentaciones: presentations,
      imagenPath: row['imagen_url'] as String?,
      estado: row['estado'] as String? ?? 'VERIFICADO',
      precioPropuesto: (row['precio_propuesto'] ?? 0.0).toDouble(),
      updatedAt: row['creado_at'] != null
          ? DateTime.tryParse(row['creado_at'] as String)
          : null,
    );
  }

  static Future<int> obtenerStockLocal(String productId) async {
    return 0;
  }

  static Future<void> decrementarStockConVersioning(
      String productId, int cantidad) async {
    return;
  }

  static Future<List<Producto>> obtenerProductosModificadosLocalmente() async {
    final db = await ServicioDbLocal.database;
    final rows = await db.query('productos_cache', where: 'local_version > 0');

    List<Producto> productos = [];
    for (final row in rows) {
      final id = row['id'] as String;
      final presRows = await db
          .query('presentaciones', where: 'producto_id = ?', whereArgs: [id]);

      final mappedPres = presRows
          .map((p) => {
                'id': p['id'],
                'nombre': p['nombre'],
                'factor': p['factor'],
                'precio': p['precio'],
                'codigo_barras': p['codigo_barras'],
              })
          .toList();

      final fullData = Map<String, dynamic>.from(row);
      fullData['presentaciones'] = mappedPres;

      productos.add(ServicioBackend.mapToProducto(fullData));
    }
    return productos;
  }
  static Future<List<Producto>> obtenerTodosLosProductos() async {
    final db = await ServicioDbLocal.database;
    final rows = await db.query('productos_cache');

    List<Producto> productos = [];
    for (final row in rows) {
      final id = row['id'] as String;
      final presRows = await db
          .query('presentaciones', where: 'producto_id = ?', whereArgs: [id]);
      productos.add(_mapToProducto(row, presRows));
    }
    return productos;
  }
}
