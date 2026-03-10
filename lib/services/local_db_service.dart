import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../data/models/producto.dart';
import '../utils/app_logger.dart';
import 'encryption_service.dart';
import 'package:bipenc/features/pos/pos_provider.dart';
import 'supabase_service.dart';

/// Servicio singleton de base de datos local SQLite para modo offline.
/// Gestiona caché de productos y cola de ventas pendientes.
class LocalDbService {
  static Database? _db;

  static Future<Database> get database async {
    _db ??= await _inicializar();
    return _db!;
  }

  // ──────────────────────────────────────────────
  // Inicialización
  // ──────────────────────────────────────────────

  static Future<Database> _inicializar() async {
    final dbPath = p.join(await getDatabasesPath(), 'bipenc_local.db');
    return openDatabase(
      dbPath,
      version: 15, // v15: cache DNI + mejoras
      onOpen: (db) async {
        await _ensureSchemaCompatibility(db);
        await _ensureIndexes(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 7) {
          await db.execute('DROP TABLE IF EXISTS presentaciones');
          await db.execute('DROP TABLE IF EXISTS productos_cache');
          await _createTables(db);
        }
        if (oldVersion == 7) {
          await db.execute('ALTER TABLE ventas_pendientes ADD COLUMN despachado INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 9) {
          // Migración segura para v9
          const columns = ['subtotal', 'igv', 'documento_cliente', 'nombre_cliente'];
          for (final col in columns) {
            try { await db.execute('ALTER TABLE ventas_pendientes ADD COLUMN $col TEXT'); } catch (_) {}
          }
        }
        if (oldVersion < 10) {
          try { await db.execute('ALTER TABLE ventas_pendientes ADD COLUMN estado TEXT DEFAULT "PENDIENTE"'); } catch (_) {}
          try { await db.execute('ALTER TABLE ventas_pendientes ADD COLUMN error_msg TEXT'); } catch (_) {}
        }
        if (oldVersion < 11) {
          // T1.5: Cola de sincronización incremental con reintentos
          await db.execute('''
            CREATE TABLE IF NOT EXISTS sync_queue_v2 (
              id TEXT PRIMARY KEY,
              tabla TEXT NOT NULL,
              operacion TEXT NOT NULL,
              datos TEXT NOT NULL,
              created_at TEXT NOT NULL,
              intentos INTEGER DEFAULT 0,
              ultimo_intento TEXT,
              sincronizado INTEGER DEFAULT 0,
              error_mensaje TEXT
            )
          ''');
        }
        if (oldVersion < 12) {
          // Stock tracking simple para validar cantidad disponible
          await db.execute('''
            CREATE TABLE IF NOT EXISTS stock_cache (
              producto_id TEXT PRIMARY KEY,
              cantidad INTEGER NOT NULL DEFAULT 0,
              sincronizado_at TEXT,
              FOREIGN KEY (producto_id) REFERENCES productos_cache(id) ON DELETE CASCADE
            )
          ''');
        }
        if (oldVersion < 13) {
          // T1.2: Conflict Resolution fields
          try { await db.execute('ALTER TABLE productos_cache ADD COLUMN last_sync_timestamp TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE productos_cache ADD COLUMN local_version INTEGER DEFAULT 0'); } catch (_) {}
          try { await db.execute('ALTER TABLE productos_cache ADD COLUMN sync_hash TEXT'); } catch (_) {}
        }
        if (oldVersion < 14) {
          try { await db.execute('ALTER TABLE ventas_pendientes ADD COLUMN anulado INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
          try { await db.execute('ALTER TABLE ventas_pendientes ADD COLUMN anulado_motivo TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE ventas_pendientes ADD COLUMN anulado_at TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE ventas_pendientes ADD COLUMN anulado_por TEXT'); } catch (_) {}
          await db.execute('''
            CREATE TABLE IF NOT EXISTS caja_turnos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              abierto_at TEXT NOT NULL,
              cerrado_at TEXT,
              monto_apertura REAL NOT NULL DEFAULT 0,
              monto_cierre_real REAL,
              monto_teorico REAL,
              diferencia REAL,
              estado TEXT NOT NULL DEFAULT 'ABIERTO',
              abierto_por TEXT,
              cerrado_por TEXT,
              observaciones TEXT
            )
          ''');
        }
        if (oldVersion < 15) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS dni_cache (
              dni TEXT PRIMARY KEY,
              nombre TEXT,
              apellido_p TEXT,
              apellido_m TEXT,
              json TEXT,
              updated_at TEXT NOT NULL
            )
          ''');
        }
        await _ensureIndexes(db);
      },
      onCreate: (db, version) async {
        await _createTables(db);
        await _ensureSchemaCompatibility(db);
        await _ensureIndexes(db);
      },
    );
  }

  static Future<void> _ensureSchemaCompatibility(Database db) async {
    Future<void> ensureColumn(
      String table,
      String column,
      String definition,
    ) async {
      final cols = await db.rawQuery('PRAGMA table_info($table)');
      final exists = cols.any((c) => c['name'] == column);
      if (!exists) {
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
          AppLogger.warning(
            'Esquema auto-corregido: $table.$column agregado',
            tag: 'LOCAL_DB',
          );
        } catch (_) {
          // Ignorar: otro hilo/proceso pudo agregarla en paralelo.
        }
      }
    }

    await ensureColumn('productos_cache', 'last_sync_timestamp', 'TEXT');
    await ensureColumn(
      'productos_cache',
      'local_version',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await ensureColumn('productos_cache', 'sync_hash', 'TEXT');
    await ensureColumn('ventas_pendientes', 'anulado', 'INTEGER NOT NULL DEFAULT 0');
    await ensureColumn('ventas_pendientes', 'anulado_motivo', 'TEXT');
    await ensureColumn('ventas_pendientes', 'anulado_at', 'TEXT');
    await ensureColumn('ventas_pendientes', 'anulado_por', 'TEXT');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS dni_cache (
        dni TEXT PRIMARY KEY,
        nombre TEXT,
        apellido_p TEXT,
        apellido_m TEXT,
        json TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS caja_turnos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        abierto_at TEXT NOT NULL,
        cerrado_at TEXT,
        monto_apertura REAL NOT NULL DEFAULT 0,
        monto_cierre_real REAL,
        monto_teorico REAL,
        diferencia REAL,
        estado TEXT NOT NULL DEFAULT 'ABIERTO',
        abierto_por TEXT,
        cerrado_por TEXT,
        observaciones TEXT
      )
    ''');
  }

  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE productos_cache (
        id TEXT PRIMARY KEY,
        sku TEXT,
        nombre TEXT NOT NULL,
        marca TEXT NOT NULL,
        categoria TEXT NOT NULL,
        imagen_url TEXT,
        estado TEXT NOT NULL DEFAULT 'VERIFICADO',
        precio_propuesto REAL DEFAULT 0.0,
        contador_ventas INTEGER NOT NULL DEFAULT 0,
        ultima_venta_at TEXT,
        creado_at TEXT NOT NULL,
        last_sync_timestamp TEXT,
        local_version INTEGER NOT NULL DEFAULT 0,
        sync_hash TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE presentaciones (
        id TEXT NOT NULL,
        producto_id TEXT NOT NULL,
        nombre TEXT NOT NULL,
        factor INTEGER NOT NULL,
        precio REAL NOT NULL,
        codigo_barras TEXT,
        PRIMARY KEY (id, producto_id),
        FOREIGN KEY (producto_id) REFERENCES productos_cache (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE ventas_pendientes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        items_json TEXT NOT NULL,
        total REAL NOT NULL,
        alias_vendedor TEXT NOT NULL,
        app_version TEXT,
        correlativo TEXT,
        creado_at TEXT NOT NULL,
        metodo_pago TEXT NOT NULL DEFAULT 'EFECTIVO',
        sincronizado INTEGER NOT NULL DEFAULT 0,
        despachado INTEGER NOT NULL DEFAULT 0,
        subtotal REAL,
        igv REAL,
        documento_cliente TEXT,
        nombre_cliente TEXT,
        estado TEXT DEFAULT 'PENDIENTE',
        error_msg TEXT,
        anulado INTEGER NOT NULL DEFAULT 0,
        anulado_motivo TEXT,
        anulado_at TEXT,
        anulado_por TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tabla TEXT NOT NULL,
        identificador TEXT NOT NULL,
        accion TEXT NOT NULL,
        datos_json TEXT,
        creado_at TEXT NOT NULL
      )
    ''');

    // AUDITORÍA: Tabla para items de venta (normalizado, no JSON)
    await db.execute('''
      CREATE TABLE venta_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        venta_id INTEGER NOT NULL,
        producto_id TEXT NOT NULL,
        cantidad INTEGER NOT NULL,
        precio_unitario REAL NOT NULL,
        subtotal REAL NOT NULL,
        creado_at TEXT NOT NULL,
        FOREIGN KEY (venta_id) REFERENCES ventas_pendientes(id) 
          ON DELETE CASCADE
      )
    ''');

    // AUDITORÍA: Cola de impresión con reintentos
    await db.execute('''
      CREATE TABLE print_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bytes_hex TEXT NOT NULL,
        tipo_comprobante TEXT NOT NULL,
        venta_id TEXT NOT NULL,
        intentos INTEGER NOT NULL DEFAULT 0,
        creado_at TEXT NOT NULL,
        impreso INTEGER NOT NULL DEFAULT 0,
        error_msg TEXT
      )
    ''');

    // T1.5: Cola de sincronización incremental con reintentos exponenciales
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue_v2 (
        id TEXT PRIMARY KEY,
        tabla TEXT NOT NULL,
        operacion TEXT NOT NULL,
        datos TEXT NOT NULL,
        created_at TEXT NOT NULL,
        intentos INTEGER DEFAULT 0,
        ultimo_intento TEXT,
        sincronizado INTEGER DEFAULT 0,
        error_mensaje TEXT
      )
    ''');

    // Stock tracking simple
    await db.execute('''
      CREATE TABLE stock_cache (
        producto_id TEXT PRIMARY KEY,
        cantidad INTEGER NOT NULL DEFAULT 0,
        sincronizado_at TEXT,
        FOREIGN KEY (producto_id) REFERENCES productos_cache(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE caja_turnos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        abierto_at TEXT NOT NULL,
        cerrado_at TEXT,
        monto_apertura REAL NOT NULL DEFAULT 0,
        monto_cierre_real REAL,
        monto_teorico REAL,
        diferencia REAL,
        estado TEXT NOT NULL DEFAULT 'ABIERTO',
        abierto_por TEXT,
        cerrado_por TEXT,
        observaciones TEXT
      )
    ''');
  }

  static Future<void> _ensureIndexes(Database db) async {
    // Productos / búsqueda
    await db.execute('CREATE INDEX IF NOT EXISTS idx_productos_cache_sku ON productos_cache(sku)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_productos_cache_nombre ON productos_cache(nombre)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_productos_cache_marca ON productos_cache(marca)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_productos_cache_categoria ON productos_cache(categoria)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_productos_cache_local_version ON productos_cache(local_version)');

    // Presentaciones / códigos de barras
    await db.execute('CREATE INDEX IF NOT EXISTS idx_presentaciones_producto_id ON presentaciones(producto_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_presentaciones_codigo_barras ON presentaciones(codigo_barras)');

    // Boletas/ventas
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ventas_correlativo ON ventas_pendientes(correlativo)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ventas_creado_at ON ventas_pendientes(creado_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ventas_estado_sync ON ventas_pendientes(estado, sincronizado)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ventas_anulado ON ventas_pendientes(anulado)');

    // Sync V2
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_v2_estado_intentos ON sync_queue_v2(sincronizado, intentos)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_v2_created_at ON sync_queue_v2(created_at)');

    // Turnos de caja
    await db.execute('CREATE INDEX IF NOT EXISTS idx_caja_turnos_estado ON caja_turnos(estado)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_caja_turnos_abierto_at ON caja_turnos(abierto_at DESC)');
  }

  static Future<void> upsertProducto(Producto producto) async {
    final db = await database;
    await db.transaction((txn) async {
      String skuPrincipal = producto.skuCode.isNotEmpty 
          ? producto.skuCode 
          : (producto.presentaciones.isNotEmpty && producto.presentaciones.first.barcode != null
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
          'creado_at': producto.updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
          'last_sync_timestamp': producto.lastSyncTimestamp?.toIso8601String(),
          'local_version': producto.localVersion,
          'sync_hash': producto.syncHash,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete('presentaciones', where: 'producto_id = ?', whereArgs: [producto.id]);
      
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
      } else if (producto.precioPropuesto != null && producto.precioPropuesto! > 0) {
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
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final p in productos) {
        batch.insert(
          'productos_cache',
          {
            'id': p.id,
            'sku': p.skuCode.isNotEmpty
                ? p.skuCode
                : (p.presentaciones.isNotEmpty ? (p.presentaciones.first.barcode ?? p.id) : p.id),
            'nombre': p.nombre,
            'marca': p.marca,
            'categoria': p.categoria,
            'imagen_url': p.imagenPath,
            'estado': p.estado,
            'precio_propuesto': p.precioPropuesto,
            'creado_at': p.updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
            'last_sync_timestamp': p.lastSyncTimestamp?.toIso8601String(),
            'local_version': p.localVersion,
            'sync_hash': p.syncHash,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        batch.delete('presentaciones', where: 'producto_id = ?', whereArgs: [p.id]);
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
    final db = await database;
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
        final presRows = await db.query('presentaciones', where: 'producto_id = ?', whereArgs: [id]);
        productos.add(_mapToProducto(row, presRows));
      }
      return productos;
    }
    final q = '%$rawQuery%';
    final rows = await db.query(
      'productos_cache',
      where: 'LOWER(nombre) LIKE ? OR LOWER(marca) LIKE ? OR LOWER(sku) LIKE ? OR LOWER(categoria) LIKE ? OR LOWER(id) LIKE ?',
      whereArgs: [q, q, q, q, q],
      orderBy: 'contador_ventas DESC',
    );
    
    List<Producto> productos = [];
    for (final row in rows) {
      final id = row['id'] as String;
      final presRows = await db.query('presentaciones', where: 'producto_id = ?', whereArgs: [id]);
      productos.add(_mapToProducto(row, presRows));
    }
    return productos;
  }

  /// Top 10 de productos más vendidos para la pantalla de inicio.
  static Future<List<Producto>> obtenerTop10() async {
    final db = await database;
    final rows = await db.query(
      'productos_cache',
      orderBy: 'contador_ventas DESC, ultima_venta_at DESC, creado_at DESC',
      limit: 10,
    );

    List<Producto> productos = [];
    for (final row in rows) {
      final id = row['id'] as String;
      final presRows = await db.query('presentaciones', where: 'producto_id = ?', whereArgs: [id]);
      productos.add(_mapToProducto(row, presRows));
    }
    return productos;
  }

  /// Obtiene un producto por su ID desde la cache local, o null si no existe.
  static Future<Producto?> getProductoById(String id) async {
    final db = await database;
    final rows = await db.query('productos_cache', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final presRows = await db.query('presentaciones', where: 'producto_id = ?', whereArgs: [id]);
    return _mapToProducto(row, presRows);
  }

  static Future<void> registrarVentaLocal(List<ItemCarrito> items) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();
    
    for (final item in items) {
      // totalUnidades used in the future if we need more logic
      
      batch.rawUpdate('''
        UPDATE productos_cache 
        SET contador_ventas = contador_ventas + 1, 
            ultima_venta_at = ?
        WHERE id = ?
      ''', [now, item.producto.id]);

      // T1.5: Migrado a SyncQueueV2
      final syncId = 'sale_ev_${item.producto.id}_${DateTime.now().millisecondsSinceEpoch}';
      batch.insert('sync_queue_v2', {
        'id': syncId,
        'tabla': 'productos',
        'operacion': 'SALE_EVENT',
        'datos': jsonEncode({
          'sku': item.producto.skuCode.isNotEmpty ? item.producto.skuCode : item.producto.id,
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
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as total FROM productos_cache');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<void> seedIfEmpty() async {
    final count = await contarProductos();
    if (count > 0) return;
    
    AppLogger.info('Sembrando catálogo inicial...', tag: 'LOCAL_DB');
    final productos = _seedProducts();
    await upsertProductos(productos);
  }
  /// VERSION NUEVA Y SEGURA: Guarda venta con items normalizados (atómico)
  /// Usa TRANSACTION para garantizar consistency
  static Future<int> guardarVentaPendienteAtomica({
    required List<ItemCarrito> items,
    required double total,
    required double subtotal,
    required double igv,
    required String aliasVendedor,
    String? documentoCliente,
    String? nombreCliente,
    String? appVersion,
    String? correlativo,
    String metodoPago = 'EFECTIVO',
    bool estaSincronizado = false,
  }) async {
    final db = await database;
    
    return await db.transaction((txn) async {
      final itemsData = items.map((i) => {
        'sku': i.producto.skuCode.isNotEmpty ? i.producto.skuCode : i.producto.id,
        'sku_code': i.producto.skuCode,
        'nombre': i.producto.nombre,
        'marca': i.producto.marca,
        'cantidad': i.cantidad,
        'presentacion_id': i.presentacion.id,
        'presentacion_nombre': i.presentacion.name,
        'unidades_totales': i.unidadesTotales,
        'precio': i.precioActual,
        'subtotal': i.subtotal,
      }).toList();

      // T1.4: Encriptar PII del cliente antes de guardar localmente
      final enc = EncryptionService();
      String? encryptedDocumento = documentoCliente;
      String? encryptedNombre = nombreCliente;

      if (enc.isInitialized) {
        if (documentoCliente != null && documentoCliente.isNotEmpty) {
          encryptedDocumento = enc.encriptar(documentoCliente);
        }
        if (nombreCliente != null && nombreCliente.isNotEmpty) {
          encryptedNombre = enc.encriptar(nombreCliente);
        }
      }

      // 1. Insertar venta (con todos los datos necesarios para Supabase)
      final ventaId = await txn.insert('ventas_pendientes', {
        'total': total,
        'subtotal': subtotal,
        'igv': igv,
        'documento_cliente': encryptedDocumento,
        'nombre_cliente': encryptedNombre,
        'alias_vendedor': aliasVendedor,
        'app_version': appVersion,
        'correlativo': correlativo,
        'creado_at': DateTime.now().toIso8601String(),
        'metodo_pago': metodoPago,
        'sincronizado': estaSincronizado ? 1 : 0,
        'despachado': 0,
        'anulado': 0,
        'estado': estaSincronizado ? 'OK' : 'PENDIENTE',
        'items_json': jsonEncode(itemsData), // REPARADO: Datos reales para no enviar ventas vacías
      });

      // 2. Insertar cada item en tabla normalizada
      // Stock desactivado por decisión funcional del proyecto.
      final ahoraTs = DateTime.now().toIso8601String();
      for (final item in items) {
        // v2.1: Insertar en venta_items
        await txn.insert('venta_items', {
          'venta_id': ventaId,
          'producto_id': item.producto.id,
          'cantidad': item.cantidad,
          'precio_unitario': item.precioActual,
          'subtotal': item.subtotal,
          'creado_at': ahoraTs,
        });

        // Bloque de stock eliminado (no se maneja inventario por cantidad).
      }

      AppLogger.info(
        'Venta atómica guardada: ID=$ventaId, items=${items.length}',
        tag: 'LOCAL_DB'
      );
      
      return ventaId;
    });
  }

  /// VERSION ANTIGUA: Mantener para compatibilidad
  /// DEPRECATED: Usar guardarVentaPendienteAtomica() en su lugar
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
    final db = await database;
    return await db.insert('ventas_pendientes', {
      'items_json': itemsJson,
      'total': total,
      'subtotal': subtotal,
      'igv': igv,
      'documento_cliente': documentoCliente,
      'nombre_cliente': nombreCliente,
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

  /// Limpia datos antiguos (>30 días) para mantenimiento (Art 5.2)
  static Future<int> purgarDatosAntiguos() async {
    final db = await database;
    final limitDate = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
    
    // Solo purgamos ventas que ya han sido sincronizadas
    final count = await db.delete(
      'ventas_pendientes',
      where: 'creado_at < ? AND sincronizado = 1',
      whereArgs: [limitDate],
    );
    
    await db.delete('sync_queue', where: 'creado_at < ?', whereArgs: [limitDate]);
    
    AppLogger.info('Mantenimiento: Purga de $count ventas antiguas completada', tag: 'LOCAL_DB');
    return count;
  }

  static Future<List<Map<String, dynamic>>> obtenerVentasPendientes() async {
    final db = await database;
    final rows = await db.transaction((txn) async {
       // Recuperación de crash: liberar ventas que quedaron atascadas en estado SINCRONIZANDO.
       await txn.update(
         'ventas_pendientes',
         {'estado': 'PENDIENTE'},
         where: 'sincronizado = 0 AND estado = "SINCRONIZANDO"',
       );

       await txn.update(
         'ventas_pendientes',
         {'estado': 'SINCRONIZANDO'},
         where: 'sincronizado = 0 AND (estado IS NULL OR estado != "SINCRONIZANDO")',
       );
       return await txn.query(
         'ventas_pendientes',
         where: 'estado = "SINCRONIZANDO" AND (anulado IS NULL OR anulado = 0)',
         orderBy: 'creado_at ASC',
       );
    });

    // T1.4: Descifrar PII antes de retornar a SupabaseService
    return rows.map((r) => _descifrarPillaVenta(r)).toList();
  }

  static Future<void> registrarErrorSincronizacion(int id, String error) async {
    final db = await database;
    await db.update(
      'ventas_pendientes',
      {'estado': 'ERROR', 'error_msg': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Obtiene las últimas ventas para reportes de cierre de caja
  static Future<List<Map<String, dynamic>>> getUltimasVentas({
    int limit = 100,
    bool includeAnuladas = false,
  }) async {
    final db = await database;
    final rows = await db.query(
      'ventas_pendientes',
      where: includeAnuladas ? null : '(anulado IS NULL OR anulado = 0)',
      orderBy: 'creado_at DESC',
      limit: limit,
    );
    return rows.map((r) => _descifrarPillaVenta(r)).toList();
  }

  /// Busca ventas por correlativo o id local.
  /// Funciona offline (fuente local) para reimpresión/reenvío PDF.
  static Future<List<Map<String, dynamic>>> buscarVentasPorCorrelativo(
    String query, {
    int limit = 100,
    bool includeAnuladas = true,
  }) async {
    final db = await database;
    final q = query.trim();
    late final List<Map<String, Object?>> rows;
    final anuladoClause = includeAnuladas ? '' : ' AND (anulado IS NULL OR anulado = 0)';
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

  /// T1.4: Ayudante para descifrar PII de una fila de venta
  static Map<String, dynamic> _descifrarPillaVenta(Map<String, dynamic> row) {
    final mutableRow = Map<String, dynamic>.from(row);
    final enc = EncryptionService();
    
    if (!enc.isInitialized) return mutableRow;

    final doc = mutableRow['documento_cliente'] as String?;
    final nom = mutableRow['nombre_cliente'] as String?;

    if (doc != null && doc.isNotEmpty) {
      try { mutableRow['documento_cliente'] = enc.desencriptar(doc); } catch (_) {}
    }
    if (nom != null && nom.isNotEmpty) {
      try { mutableRow['nombre_cliente'] = enc.desencriptar(nom); } catch (_) {}
    }
    
    return mutableRow;
  }

  static Future<void> marcarVentaSincronizada(int id) async {
    final db = await database;
    await db.update(
      'ventas_pendientes',
      {'sincronizado': 1, 'estado': 'OK', 'error_msg': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> marcarDespachado(int id) async {
    final db = await database;
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
    final db = await database;
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
      final estabaSincronizada = ((row['sincronizado'] ?? 0) as num).toInt() == 1;
      if (correlativo != null && correlativo.isNotEmpty && estabaSincronizada) {
        final syncId = 'anul_venta_${DateTime.now().millisecondsSinceEpoch}_$ventaId';
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
        // Si nunca subió a nube, la anulamos solo local y evitamos subirla luego.
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

  static Future<Map<String, dynamic>?> obtenerTurnoCajaAbierto() async {
    final db = await database;
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
    final db = await database;
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
    final db = await database;
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
      } else if (metodo == 'YAPEPLIN' || metodo == 'YAPE/PLIN' || metodo == 'YAPE_PLIN') {
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
    final db = await database;
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

  static Future<List<Map<String, dynamic>>> obtenerSyncQueue() async {
    final db = await database;
    return db.query('sync_queue', orderBy: 'creado_at ASC');
  }

  static Future<void> eliminarDeSyncQueue(int id) async {
    final db = await database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> eliminarProducto(String id, {String? sku}) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('productos_cache', where: 'id = ?', whereArgs: [id]);
      
      // T1.5: Migrado a SyncQueueV2
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

  /// Elimina un producto solo de la cache local SIN agregar a sync_queue.
  /// Usado por el sync inverso cuando se detecta que el producto
  /// ya fue eliminado de Supabase (evita loop de borrado circular).
  static Future<void> eliminarProductoLocal(String id) async {
    final db = await database;
    await db.delete('productos_cache', where: 'id = ?', whereArgs: [id]);
  }

  static Producto _mapToProducto(Map<String, dynamic> row, List<Map<String, dynamic>> presRows) {
    final presentations = presRows.map((p) => Presentacion.fromJson({
      'id': p['id'],
      'skuCode': p['codigo_barras'] ?? '',
      'name': p['nombre'],
      'conversionFactor': (p['factor'] ?? 1).toDouble(),
      'barcode': p['codigo_barras'],
      'prices': [{'type': 'NORMAL', 'amount': p['precio']}],
    })).toList();

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
      updatedAt: row['creado_at'] != null ? DateTime.tryParse(row['creado_at'] as String) : null,
    );
  }

  static List<Producto> _seedProducts() {
    return []; // Eliminado por orden de CTO (Mission Beta)
  }

  // ──────────────────────────────────────────────
  // Sync Queue V2 — Sincronización Incremental (T1.5)
  // ──────────────────────────────────────────────

  /// Inserta un item en la cola de sync incremental.
  static Future<void> insertarEnSyncQueueV2({
    required String id,
    required String tabla,
    required String operacion,
    required String datosJson,
  }) async {
    final db = await database;
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

  /// Obtiene items pendientes de sincronizar (no sincronizados, <= 5 intentos).
  static Future<List<Map<String, dynamic>>> obtenerSyncQueueV2Pendiente() async {
    final db = await database;
    return db.query(
      'sync_queue_v2',
      where: 'sincronizado = 0 AND intentos <= 5',
      orderBy: 'created_at ASC',
      limit: 20, // Procesar en lotes
    );
  }

  /// Marca un item de sync_queue_v2 como sincronizado.
  static Future<void> marcarSyncQueueV2Sincronizado(String id) async {
    final db = await database;
    await db.update(
      'sync_queue_v2',
      {'sincronizado': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Incrementa el contador de intentos y registra error.
  static Future<void> registrarIntentoSyncQueueV2(String id, String? error) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE sync_queue_v2 
      SET intentos = intentos + 1,
          ultimo_intento = ?,
          error_mensaje = ?
      WHERE id = ?
    ''', [DateTime.now().toIso8601String(), error, id]);
  }

  /// Limpia items sincronizados con más de 7 días.
  static Future<void> limpiarSyncQueueV2Antigua() async {
    final db = await database;
    final limit = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
    await db.delete(
      'sync_queue_v2',
      where: 'sincronizado = 1 AND created_at < ?',
      whereArgs: [limit],
    );
  }

  /// Obtiene el stock actual de un producto desde la cache local.
  static Future<int> obtenerStockLocal(String productId) async {
    return 0;
  }

  /// T1.2: Decremento de stock con versionamiento para resolución de conflictos.
  static Future<void> decrementarStockConVersioning(String productId, int cantidad) async {
    return;
  }

  /// T1.2: Obtiene productos locales con cambios pendientes (local_version > 0).
  static Future<List<Producto>> obtenerProductosModificadosLocalmente() async {
    final db = await database;
    final rows = await db.query('productos_cache', where: 'local_version > 0');
    
    List<Producto> productos = [];
    for (final row in rows) {
      final id = row['id'] as String;
      // Obtener presentaciones de la tabla local
      final presRows = await db.query('presentaciones', where: 'producto_id = ?', whereArgs: [id]);
      
      // Adaptar presentaciones de SQLite al formato que espera mapToProducto / Supabase
      final mappedPres = presRows.map((p) => {
        'id': p['id'],
        'nombre': p['nombre'],
        'factor': p['factor'],
        'precio': p['precio'],
        'codigo_barras': p['codigo_barras'],
      }).toList();

      final fullData = Map<String, dynamic>.from(row);
      fullData['presentaciones'] = mappedPres;
      
      productos.add(SupabaseService.mapToProducto(fullData));
    }
    return productos;
  }

  /// T1.1: Reset TOTAL de la base de datos local.
  /// Borra todos los productos, ventas y colas. 
  /// Útil para pasar de Beta a Producción o limpieza profunda.
  static Future<void> hardResetDatabase() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('productos_cache');
      await txn.delete('presentaciones');
      await txn.delete('ventas_pendientes');
      await txn.delete('venta_items');
      await txn.delete('sync_queue');
      await txn.delete('sync_queue_v2');
      await txn.delete('print_queue');
      await txn.delete('caja_turnos');
    });
    AppLogger.info('Hard Reset ejecutado: DB local limpia', tag: 'LOCAL_DB');
  }
}
