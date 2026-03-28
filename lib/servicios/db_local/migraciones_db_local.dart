part of 'package:bipenc/servicios/servicio_db_local.dart';

class MigracionesDbLocal {
  static Future<Database> inicializar() async {
    final dbPath = p.join(await getDatabasesPath(), 'bipenc_local.db');
    return openDatabase(
      dbPath,
      version: 24,
      onOpen: (db) async {
        await ensureSchemaCompatibility(db);
        await ensureIndexes(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 7) {
          await db.execute('DROP TABLE IF EXISTS presentaciones');
          await db.execute('DROP TABLE IF EXISTS productos_cache');
          await createTables(db);
        }
        if (oldVersion == 7) {
          await db.execute(
              'ALTER TABLE ventas_pendientes ADD COLUMN despachado INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 9) {
          const columns = [
            'subtotal',
            'igv',
            'documento_cliente',
            'nombre_cliente'
          ];
          for (final col in columns) {
            try {
              await db.execute(
                  'ALTER TABLE ventas_pendientes ADD COLUMN $col TEXT');
            } catch (e, st) {
              RegistroApp.debug(
                  'Columna ya existe en ventas_pendientes: $col ($e)',
                  tag: 'LOCAL_DB');
              RegistroApp.warn('Detalle error migración',
                  tag: 'LOCAL_DB', error: e, stackTrace: st);
            }
          }
        }
        if (oldVersion < 10) {
          try {
            await db.execute(
                'ALTER TABLE ventas_pendientes ADD COLUMN estado TEXT DEFAULT "PENDIENTE"');
          } catch (e, st) {
            RegistroApp.debug(
                'Columna estado ya existe en ventas_pendientes ($e)',
                tag: 'LOCAL_DB');
            RegistroApp.warn('Detalle error migración',
                tag: 'LOCAL_DB', error: e, stackTrace: st);
          }
          try {
            await db.execute(
                'ALTER TABLE ventas_pendientes ADD COLUMN error_msg TEXT');
          } catch (e, st) {
            RegistroApp.debug(
                'Columna error_msg ya existe en ventas_pendientes ($e)',
                tag: 'LOCAL_DB');
            RegistroApp.warn('Detalle error migración',
                tag: 'LOCAL_DB', error: e, stackTrace: st);
          }
        }
        if (oldVersion < 11) {
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
          try {
            await db.execute(
                'ALTER TABLE productos_cache ADD COLUMN last_sync_timestamp TEXT');
          } catch (e, st) {
            RegistroApp.debug(
                'Columna last_sync_timestamp ya existe en productos_cache ($e)',
                tag: 'LOCAL_DB');
            RegistroApp.warn('Detalle error migración',
                tag: 'LOCAL_DB', error: e, stackTrace: st);
          }
          try {
            await db.execute(
                'ALTER TABLE productos_cache ADD COLUMN local_version INTEGER DEFAULT 0');
          } catch (e, st) {
            RegistroApp.debug(
                'Columna local_version ya existe en productos_cache ($e)',
                tag: 'LOCAL_DB');
            RegistroApp.warn('Detalle error migración',
                tag: 'LOCAL_DB', error: e, stackTrace: st);
          }
          try {
            await db.execute(
                'ALTER TABLE productos_cache ADD COLUMN sync_hash TEXT');
          } catch (e, st) {
            RegistroApp.debug(
                'Columna sync_hash ya existe en productos_cache ($e)',
                tag: 'LOCAL_DB');
            RegistroApp.warn('Detalle error migración',
                tag: 'LOCAL_DB', error: e, stackTrace: st);
          }
        }
        if (oldVersion < 16) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS document_cache (
              numero TEXT PRIMARY KEY,
              tipo TEXT NOT NULL,
              nombre TEXT NOT NULL,
              direccion TEXT,
              cached_at INTEGER NOT NULL,
              expires_at INTEGER NOT NULL
            )
          ''');
        }
        if (oldVersion < 17) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS audit_logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              accion TEXT NOT NULL,
              usuario TEXT,
              detalle TEXT,
              created_at INTEGER NOT NULL
            )
          ''');
        }
        if (oldVersion < 18) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS clientes_cache (
              numero TEXT PRIMARY KEY,
              nombre TEXT NOT NULL,
              direccion TEXT,
              tipo TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
        }
        if (oldVersion < 19) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS empresa_config (
              id INTEGER PRIMARY KEY DEFAULT 1,
              logo_url TEXT,
              ruc TEXT,
              razon_social TEXT,
              direccion TEXT,
              telefono TEXT,
              ticket_header TEXT,
              ticket_footer TEXT,
              pdf_terminos TEXT
            )
          ''');
        }
        if (oldVersion < 20) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS config_correlativos (
              tipo_documento TEXT NOT NULL, -- 01 factura, 03 boleta
              serie TEXT NOT NULL,
              ultimo_numero INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (tipo_documento, serie)
            )
          ''');
          try {
            await db.execute(
                'ALTER TABLE venta_items ADD COLUMN producto_nombre TEXT');
          } catch (e, st) {
            RegistroApp.debug(
                'Columna producto_nombre ya existe en venta_items ($e)',
                tag: 'LOCAL_DB');
            RegistroApp.warn('Detalle error migración',
                tag: 'LOCAL_DB', error: e, stackTrace: st);
          }
          try {
            await db.execute('ALTER TABLE venta_items ADD COLUMN sku TEXT');
          } catch (e, st) {
            RegistroApp.debug('Columna sku ya existe en venta_items ($e)',
                tag: 'LOCAL_DB');
            RegistroApp.warn('Detalle error migración',
                tag: 'LOCAL_DB', error: e, stackTrace: st);
          }
          try {
            await db.execute(
                'ALTER TABLE venta_items ADD COLUMN presentacion_id TEXT');
          } catch (e, st) {
            RegistroApp.debug(
                'Columna presentacion_id ya existe en venta_items ($e)',
                tag: 'LOCAL_DB');
            RegistroApp.warn('Detalle error migración',
                tag: 'LOCAL_DB', error: e, stackTrace: st);
          }
          try {
            await db.execute(
                'ALTER TABLE venta_items ADD COLUMN presentacion_nombre TEXT');
          } catch (e, st) {
            RegistroApp.debug(
                'Columna presentacion_nombre ya existe en venta_items ($e)',
                tag: 'LOCAL_DB');
            RegistroApp.warn('Detalle error migración',
                tag: 'LOCAL_DB', error: e, stackTrace: st);
          }
          try {
            await db.execute(
                'ALTER TABLE ventas_pendientes ADD COLUMN estado_sunat TEXT DEFAULT "PENDIENTE"');
          } catch (e, st) {
            RegistroApp.debug(
                'Columna estado_sunat ya existe en ventas_pendientes ($e)',
                tag: 'LOCAL_DB');
            RegistroApp.warn('Detalle error migración',
                tag: 'LOCAL_DB', error: e, stackTrace: st);
          }
          try {
            await db.execute(
                'ALTER TABLE ventas_pendientes ADD COLUMN estado TEXT DEFAULT "PENDIENTE"');
          } catch (e, st) {
            RegistroApp.debug(
                'Columna estado ya existe en ventas_pendientes ($e)',
                tag: 'LOCAL_DB');
            RegistroApp.warn('Detalle error migración',
                tag: 'LOCAL_DB', error: e, stackTrace: st);
          }
          try {
            await db.execute(
                'ALTER TABLE ventas_pendientes ADD COLUMN sync_hash TEXT');
          } catch (e, st) {
            RegistroApp.debug(
                'Columna sync_hash ya existe en ventas_pendientes ($e)',
                tag: 'LOCAL_DB');
            RegistroApp.warn('Detalle error migración',
                tag: 'LOCAL_DB', error: e, stackTrace: st);
          }
        }
        if (oldVersion < 22) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS producto_codigos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              codigo_barras TEXT NOT NULL,
              producto_id TEXT NOT NULL,
              descripcion_variante TEXT,
              creado_en TEXT NOT NULL
            )
          ''');
          await db.execute(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_pc_barcode_producto ON producto_codigos(codigo_barras, producto_id)');
        }
        if (oldVersion < 23) {
          await migrateSensitiveCachesV23(db);
        }
        if (oldVersion < 24) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS monitoreo_api (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              metodo TEXT NOT NULL,
              latencia REAL NOT NULL,
              exito INTEGER NOT NULL,
              fecha TEXT NOT NULL
            )
          ''');
        }
        await ensureIndexes(db);
      },
      onCreate: (db, version) async {
        await createTables(db);
        await ensureSchemaCompatibility(db);
        await ensureIndexes(db);
      },
    );
  }

  static Future<void> ensureSchemaCompatibility(Database db) async {
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
          RegistroApp.warning(
            'Esquema auto-corregido: $table.$column agregado',
            tag: 'LOCAL_DB',
          );
        } catch (e, st) {
          RegistroApp.debug(
              'No se pudo agregar columna $table.$column ($e)',
              tag: 'LOCAL_DB');
          RegistroApp.warn('Detalle error migración',
              tag: 'LOCAL_DB', error: e, stackTrace: st);
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
    await ensureColumn(
        'ventas_pendientes', 'anulado', 'INTEGER NOT NULL DEFAULT 0');
    await ensureColumn('ventas_pendientes', 'anulado_motivo', 'TEXT');
    await ensureColumn('ventas_pendientes', 'anulado_at', 'TEXT');
    await ensureColumn('ventas_pendientes', 'anulado_por', 'TEXT');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS document_cache (
        numero TEXT PRIMARY KEY,
        tipo TEXT NOT NULL,
        nombre TEXT NOT NULL,
        direccion TEXT,
        cached_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        accion TEXT NOT NULL,
        usuario TEXT,
        detalle TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS empresa_config (
        id INTEGER PRIMARY KEY DEFAULT 1,
        logo_url TEXT,
        ruc TEXT,
        razon_social TEXT,
        direccion TEXT,
        telefono TEXT,
        ticket_header TEXT,
        ticket_footer TEXT,
        pdf_terminos TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS clientes_cache (
        numero TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        direccion TEXT,
        tipo TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS config_correlativos (
        tipo_documento TEXT NOT NULL,
        serie TEXT NOT NULL,
        ultimo_numero INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (tipo_documento, serie)
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
    await ensureColumn('venta_items', 'producto_nombre', 'TEXT');
    await ensureColumn('venta_items', 'sku', 'TEXT');
    await ensureColumn('venta_items', 'presentacion_id', 'TEXT');
    await ensureColumn('venta_items', 'presentacion_nombre', 'TEXT');
    await ensureColumn('ventas_pendientes', 'order_list_id', 'TEXT');
    await ensureColumn('ventas_pendientes', 'documento_cliente_hash', 'TEXT');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS producto_codigos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo_barras TEXT NOT NULL,
        producto_id TEXT NOT NULL,
        descripcion_variante TEXT,
        creado_en TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_pc_barcode_producto ON producto_codigos(codigo_barras, producto_id)');
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS monitoreo_api (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        metodo TEXT NOT NULL,
        latencia REAL NOT NULL,
        exito INTEGER NOT NULL,
        fecha TEXT NOT NULL
      )
    ''');
  }

  static Future<void> migrateSensitiveCachesV23(Database db) async {
    try {
      await db.execute(
          'ALTER TABLE ventas_pendientes ADD COLUMN documento_cliente_hash TEXT');
    } catch (e, st) {
      RegistroApp.debug(
          'Columna documento_cliente_hash ya existe en ventas_pendientes ($e)',
          tag: 'LOCAL_DB');
      RegistroApp.warn('Detalle error migración',
          tag: 'LOCAL_DB', error: e, stackTrace: st);
    }

    final enc = await ServicioDbLocal._getEnc();

    try {
      final ventas = await db.query(
        'ventas_pendientes',
        columns: ['id', 'documento_cliente', 'nombre_cliente'],
      );
      for (final row in ventas) {
        final id = row['id'];
        final rawDoc = row['documento_cliente']?.toString() ?? '';
        final rawNombre = row['nombre_cliente']?.toString() ?? '';
        final updates = <String, Object?>{};

        if (rawDoc.isNotEmpty) {
          String docPlain = rawDoc;
          if (enc != null) {
            if (rawDoc.startsWith(ServicioDbLocal._encPrefix)) {
              try {
                docPlain = ServicioDbLocal._decryptField(enc, rawDoc);
              } catch (e, st) {
                RegistroApp.debug(
                    'No se pudo descifrar documento (prefijo) ($e)',
                    tag: 'LOCAL_DB');
                RegistroApp.warn('Detalle descifrado',
                    tag: 'LOCAL_DB', error: e, stackTrace: st);
              }
            } else {
              try {
                docPlain = enc.desencriptar(rawDoc);
              } catch (e, st) {
                RegistroApp.debug(
                    'No se pudo descifrar documento (legacy) ($e)',
                    tag: 'LOCAL_DB');
                RegistroApp.warn('Detalle descifrado',
                    tag: 'LOCAL_DB', error: e, stackTrace: st);
              }
            }
          }
          final hash = await ServicioDbLocal._blindIndexForDoc(docPlain);
          if (hash != null) updates['documento_cliente_hash'] = hash;
          if (enc != null && !rawDoc.startsWith(ServicioDbLocal._encPrefix)) {
            updates['documento_cliente'] =
                ServicioDbLocal._encryptField(enc, docPlain);
          }
        }

        if (rawNombre.isNotEmpty && enc != null) {
          if (!rawNombre.startsWith(ServicioDbLocal._encPrefix)) {
            String nombrePlain = rawNombre;
            try {
              nombrePlain = enc.desencriptar(rawNombre);
            } catch (e, st) {
              RegistroApp.debug(
                  'No se pudo descifrar nombre cliente ($e)',
                  tag: 'LOCAL_DB');
              RegistroApp.warn('Detalle descifrado',
                  tag: 'LOCAL_DB', error: e, stackTrace: st);
            }
            updates['nombre_cliente'] =
                ServicioDbLocal._encryptField(enc, nombrePlain);
          }
        }

        if (updates.isNotEmpty) {
          await db.update(
            'ventas_pendientes',
            updates,
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    } catch (e, st) {
      RegistroApp.warn('Error migrando ventas_pendientes v23',
          tag: 'LOCAL_DB', error: e, stackTrace: st);
    }

    try {
      final rows = await db.query('document_cache');
      await db.execute('DROP TABLE IF EXISTS document_cache_v23');
      await db.execute('''
        CREATE TABLE document_cache_v23 (
          numero TEXT PRIMARY KEY,
          tipo TEXT NOT NULL,
          nombre TEXT NOT NULL,
          direccion TEXT,
          cached_at INTEGER NOT NULL,
          expires_at INTEGER NOT NULL
        )
      ''');
      for (final row in rows) {
        final numeroRaw = row['numero']?.toString() ?? '';
        final numeroKey =
            await ServicioDbLocal._blindIndexForDoc(numeroRaw) ?? numeroRaw;
        final nombreRaw = row['nombre']?.toString() ?? '';
        final direccionRaw = row['direccion']?.toString();
        String nombreValue = nombreRaw;
        if (enc != null &&
            nombreRaw.isNotEmpty &&
            !nombreRaw.startsWith(ServicioDbLocal._encPrefix)) {
          try {
            nombreValue =
                ServicioDbLocal._encryptField(enc, enc.desencriptar(nombreRaw));
          } catch (e, st) {
            RegistroApp.debug('No se pudo descifrar nombre cache ($e)',
                tag: 'LOCAL_DB');
            RegistroApp.warn('Detalle descifrado',
                tag: 'LOCAL_DB', error: e, stackTrace: st);
            nombreValue = ServicioDbLocal._encryptField(enc, nombreRaw);
          }
        }
        String? direccionValue = direccionRaw;
        if (enc != null &&
            (direccionRaw?.isNotEmpty ?? false) &&
            !direccionRaw!.startsWith(ServicioDbLocal._encPrefix)) {
          try {
            direccionValue = ServicioDbLocal._encryptField(
                enc, enc.desencriptar(direccionRaw));
          } catch (e, st) {
            RegistroApp.debug('No se pudo descifrar direccion cache ($e)',
                tag: 'LOCAL_DB');
            RegistroApp.warn('Detalle descifrado',
                tag: 'LOCAL_DB', error: e, stackTrace: st);
            direccionValue = ServicioDbLocal._encryptField(enc, direccionRaw);
          }
        }
        await db.insert(
          'document_cache_v23',
          {
            'numero': numeroKey,
            'tipo': row['tipo'],
            'nombre': nombreValue,
            'direccion': direccionValue,
            'cached_at': row['cached_at'],
            'expires_at': row['expires_at'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      try {
        await db.execute(
            'ALTER TABLE document_cache RENAME TO document_cache_legacy_v22');
      } catch (e, st) {
        RegistroApp.debug('No se pudo renombrar document_cache ($e)',
            tag: 'LOCAL_DB');
        RegistroApp.warn('Detalle migración',
            tag: 'LOCAL_DB', error: e, stackTrace: st);
      }
      try {
        await db.execute('ALTER TABLE document_cache_v23 RENAME TO document_cache');
      } catch (e, st) {
        RegistroApp.debug('No se pudo renombrar document_cache_v23 ($e)',
            tag: 'LOCAL_DB');
        RegistroApp.warn('Detalle migración',
            tag: 'LOCAL_DB', error: e, stackTrace: st);
      }
    } catch (e, st) {
      RegistroApp.warn('Error migrando document_cache v23',
          tag: 'LOCAL_DB', error: e, stackTrace: st);
    }

    try {
      final rows = await db.query('clientes_cache');
      await db.execute('DROP TABLE IF EXISTS clientes_cache_v23');
      await db.execute('''
        CREATE TABLE clientes_cache_v23 (
          numero TEXT PRIMARY KEY,
          nombre TEXT NOT NULL,
          direccion TEXT,
          tipo TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      for (final row in rows) {
        final numeroRaw = row['numero']?.toString() ?? '';
        final numeroKey =
            await ServicioDbLocal._blindIndexForDoc(numeroRaw) ?? numeroRaw;
        final nombreRaw = row['nombre']?.toString() ?? '';
        final direccionRaw = row['direccion']?.toString();
        String nombreValue = nombreRaw;
        if (enc != null &&
            nombreRaw.isNotEmpty &&
            !nombreRaw.startsWith(ServicioDbLocal._encPrefix)) {
          try {
            nombreValue =
                ServicioDbLocal._encryptField(enc, enc.desencriptar(nombreRaw));
          } catch (e, st) {
            RegistroApp.debug('No se pudo descifrar nombre cliente ($e)',
                tag: 'LOCAL_DB');
            RegistroApp.warn('Detalle descifrado',
                tag: 'LOCAL_DB', error: e, stackTrace: st);
            nombreValue = ServicioDbLocal._encryptField(enc, nombreRaw);
          }
        }
        String? direccionValue = direccionRaw;
        if (enc != null &&
            (direccionRaw?.isNotEmpty ?? false) &&
            !direccionRaw!.startsWith(ServicioDbLocal._encPrefix)) {
          try {
            direccionValue = ServicioDbLocal._encryptField(
                enc, enc.desencriptar(direccionRaw));
          } catch (e, st) {
            RegistroApp.debug('No se pudo descifrar direccion cliente ($e)',
                tag: 'LOCAL_DB');
            RegistroApp.warn('Detalle descifrado',
                tag: 'LOCAL_DB', error: e, stackTrace: st);
            direccionValue = ServicioDbLocal._encryptField(enc, direccionRaw);
          }
        }
        await db.insert(
          'clientes_cache_v23',
          {
            'numero': numeroKey,
            'nombre': nombreValue,
            'direccion': direccionValue,
            'tipo': row['tipo'],
            'updated_at': row['updated_at'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      try {
        await db.execute(
            'ALTER TABLE clientes_cache RENAME TO clientes_cache_legacy_v22');
      } catch (e, st) {
        RegistroApp.debug('No se pudo renombrar clientes_cache ($e)',
            tag: 'LOCAL_DB');
        RegistroApp.warn('Detalle migración',
            tag: 'LOCAL_DB', error: e, stackTrace: st);
      }
      try {
        await db.execute('ALTER TABLE clientes_cache_v23 RENAME TO clientes_cache');
      } catch (e, st) {
        RegistroApp.debug('No se pudo renombrar clientes_cache_v23 ($e)',
            tag: 'LOCAL_DB');
        RegistroApp.warn('Detalle migración',
            tag: 'LOCAL_DB', error: e, stackTrace: st);
      }
    } catch (e, st) {
      RegistroApp.warn('Error migrando clientes_cache v23',
          tag: 'LOCAL_DB', error: e, stackTrace: st);
    }
  }

  static Future<void> createTables(Database db) async {
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
        documento_cliente_hash TEXT,
        nombre_cliente TEXT,
        estado TEXT DEFAULT 'PENDIENTE',
        estado_sunat TEXT DEFAULT 'PENDIENTE',
        error_msg TEXT,
        anulado INTEGER NOT NULL DEFAULT 0,
        anulado_motivo TEXT,
        anulado_at TEXT,
        anulado_por TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE venta_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        venta_id INTEGER NOT NULL,
        producto_id TEXT NOT NULL,
        producto_nombre TEXT,
        sku TEXT,
        presentacion_id TEXT,
        presentacion_nombre TEXT,
        cantidad INTEGER NOT NULL,
        precio_unitario REAL NOT NULL,
        subtotal REAL NOT NULL,
        creado_at TEXT NOT NULL,
        FOREIGN KEY (venta_id) REFERENCES ventas_pendientes(id) 
          ON DELETE CASCADE
      )
    ''');

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

    await db.execute('''
      CREATE TABLE document_cache (
        numero TEXT PRIMARY KEY,
        tipo TEXT NOT NULL,
        nombre TEXT NOT NULL,
        direccion TEXT,
        cached_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE monitoreo_api (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        metodo TEXT NOT NULL,
        latencia REAL NOT NULL,
        exito INTEGER NOT NULL,
        fecha TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE movimientos_inventario (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        venta_id INTEGER,
        producto_id TEXT NOT NULL,
        cantidad REAL NOT NULL,
        tipo TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE config_correlativos (
        tipo_documento TEXT NOT NULL,
        serie TEXT NOT NULL,
        ultimo_numero INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (tipo_documento, serie)
      )
    ''');
  }

  static Future<void> ensureIndexes(Database db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_productos_cache_sku ON productos_cache(sku)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_productos_cache_nombre ON productos_cache(nombre)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_productos_cache_marca ON productos_cache(marca)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_productos_cache_categoria ON productos_cache(categoria)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_productos_cache_local_version ON productos_cache(local_version)');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_presentaciones_producto_id ON presentaciones(producto_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_presentaciones_codigo_barras ON presentaciones(codigo_barras)');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ventas_correlativo ON ventas_pendientes(correlativo)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ventas_creado_at ON ventas_pendientes(creado_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ventas_estado_sync ON ventas_pendientes(estado, sincronizado)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ventas_anulado ON ventas_pendientes(anulado)');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sync_v2_estado_intentos ON sync_queue_v2(sincronizado, intentos)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sync_v2_created_at ON sync_queue_v2(created_at)');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_caja_turnos_estado ON caja_turnos(estado)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_caja_turnos_abierto_at ON caja_turnos(abierto_at DESC)');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_producto_codigos_barcode ON producto_codigos(codigo_barras)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_document_cache_expires ON document_cache(expires_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON audit_logs(created_at DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_clientes_cache_updated ON clientes_cache(updated_at DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_config_corr_tipo_serie ON config_correlativos(tipo_documento, serie)');
  }

  static Future<void> hardResetDatabase() async {
    final db = await ServicioDbLocal.database;
    await db.transaction((txn) async {
      await txn.delete('productos_cache');
      await txn.delete('presentaciones');
      await txn.delete('ventas_pendientes');
      await txn.delete('venta_items');
      await txn.delete('sync_queue_v2');
      await txn.delete('print_queue');
      await txn.delete('caja_turnos');
      await txn.delete('document_cache');
      await txn.delete('clientes_cache');
    });
    RegistroApp.info('Hard Reset ejecutado: DB local limpia', tag: 'LOCAL_DB');
  }
}
