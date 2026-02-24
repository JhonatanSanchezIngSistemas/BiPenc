import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/producto.dart';
import '../utils/app_logger.dart';

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
      version: 3, // Incrementado por cambio a arquitectura relacional
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE presentaciones (
              id TEXT NOT NULL,
              sku TEXT NOT NULL,
              nombre TEXT NOT NULL,
              factor INTEGER NOT NULL,
              precio REAL NOT NULL,
              codigo_barras TEXT,
              PRIMARY KEY (id, sku),
              FOREIGN KEY (sku) REFERENCES productos_cache (sku) ON DELETE CASCADE
            )
          ''');
          AppLogger.info('Migración V3 completada: Tabla presentaciones creada', tag: 'LOCAL_DB');
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE productos_cache (
            sku TEXT PRIMARY KEY,
            nombre TEXT NOT NULL,
            marca TEXT NOT NULL,
            categoria TEXT NOT NULL,
            imagen_url TEXT,
            estado TEXT NOT NULL DEFAULT 'VERIFICADO',
            contador_ventas INTEGER NOT NULL DEFAULT 0,
            ultima_venta_at TEXT,
            creado_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE presentaciones (
            id TEXT NOT NULL,
            sku TEXT NOT NULL,
            nombre TEXT NOT NULL,
            factor INTEGER NOT NULL,
            precio REAL NOT NULL,
            codigo_barras TEXT,
            PRIMARY KEY (id, sku),
            FOREIGN KEY (sku) REFERENCES productos_cache (sku) ON DELETE CASCADE
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
            sincronizado INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
  }

  static Future<void> upsertProducto(Producto producto) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'productos_cache',
        {
          'sku': producto.id,
          'nombre': producto.nombre,
          'marca': producto.marca,
          'categoria': producto.categoria,
          'imagen_url': producto.imagenPath,
          'estado': producto.estado,
          'creado_at': producto.updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Limpiar y re-insertar presentaciones
      await txn.delete('presentaciones', where: 'sku = ?', whereArgs: [producto.id]);
      for (final pres in producto.presentaciones) {
        await txn.insert('presentaciones', {
          'id': pres.id,
          'sku': producto.id,
          'nombre': pres.nombre,
          'factor': pres.factor,
          'precio': pres.precio,
          'codigo_barras': pres.codigoBarras,
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
            'sku': p.id,
            'nombre': p.nombre,
            'marca': p.marca,
            'categoria': p.categoria,
            'imagen_url': p.imagenPath,
            'estado': p.estado,
            'creado_at': p.updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        batch.delete('presentaciones', where: 'sku = ?', whereArgs: [p.id]);
        for (final pres in p.presentaciones) {
          batch.insert('presentaciones', {
            'id': pres.id,
            'sku': p.id,
            'nombre': pres.nombre,
            'factor': pres.factor,
            'precio': pres.precio,
            'codigo_barras': pres.codigoBarras,
          });
        }
      }
      await batch.commit(noResult: true);
    });
  }


  /// Obtiene el Top 10 de productos con presentaciones.
  static Future<List<Producto>> obtenerTop10() async {
    final db = await database;
    final rows = await db.query(
      'productos_cache',
      orderBy: 'contador_ventas DESC, ultima_venta_at DESC, creado_at DESC',
      limit: 10,
    );
    
    List<Producto> productos = [];
    for (final row in rows) {
      final sku = row['sku'] as String;
      final presRows = await db.query('presentaciones', where: 'sku = ?', whereArgs: [sku]);
      productos.add(_mapToProducto(row, presRows));
    }
    return productos;
  }

  /// Busca productos en la caché local con sus presentaciones.
  static Future<List<Producto>> buscarLocal(String query) async {
    final db = await database;
    final q = '%${query.toLowerCase()}%';
    final rows = await db.query(
      'productos_cache',
      where: 'LOWER(nombre) LIKE ? OR LOWER(marca) LIKE ? OR LOWER(sku) LIKE ? OR LOWER(categoria) LIKE ?',
      whereArgs: [q, q, q, q],
      orderBy: 'contador_ventas DESC',
    );
    
    List<Producto> productos = [];
    for (final row in rows) {
      final sku = row['sku'] as String;
      final presRows = await db.query('presentaciones', where: 'sku = ?', whereArgs: [sku]);
      productos.add(_mapToProducto(row, presRows));
    }
    return productos;
  }

  /// Incremente el contador de ventas.
  static Future<void> incrementarContadorVenta(String sku) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE productos_cache
      SET contador_ventas = contador_ventas + 1,
          ultima_venta_at = ?
      WHERE sku = ?
    ''', [DateTime.now().toIso8601String(), sku]);
  }

  static Future<void> registrarVentaLocal(List<ItemCarrito> items) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();
    for (final item in items) {
      for (int i = 0; i < item.cantidad; i++) {
        batch.rawUpdate(
          'UPDATE productos_cache SET contador_ventas = contador_ventas + 1, ultima_venta_at = ? WHERE sku = ?',
          [now, item.producto.id],
        );
      }
    }
    await batch.commit(noResult: true);
  }

  static Future<int> contarProductos() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as total FROM productos_cache');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ──────────────────────────────────────────────
  // Operaciones de Ventas Pendientes (Offline)
  // ──────────────────────────────────────────────

  static Future<void> guardarVentaPendiente({
    required String itemsJson,
    required double total,
    required String aliasVendedor,
    String? appVersion,
    String? correlativo,
  }) async {
    final db = await database;
    await db.insert('ventas_pendientes', {
      'items_json': itemsJson,
      'total': total,
      'alias_vendedor': aliasVendedor,
      'app_version': appVersion,
      'correlativo': correlativo,
      'creado_at': DateTime.now().toIso8601String(),
      'sincronizado': 0,
    });
  }

  static Future<List<Map<String, dynamic>>> obtenerVentasPendientes() async {
    final db = await database;
    return db.query(
      'ventas_pendientes',
      where: 'sincronizado = 0',
      orderBy: 'creado_at ASC',
    );
  }

  static Future<void> marcarVentaSincronizada(int id) async {
    final db = await database;
    await db.update(
      'ventas_pendientes',
      {'sincronizado': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ──────────────────────────────────────────────
  // Helpers privados
  // ──────────────────────────────────────────────

  static Producto _mapToProducto(Map<String, dynamic> row, List<Map<String, dynamic>> presRows) {
    final presentations = presRows.map((p) => Presentacion.fromJson({
      'id': p['id'],
      'nombre': p['nombre'],
      'factor': p['factor'],
      'precio': p['precio'],
      'codigo_barras': p['codigo_barras'],
    })).toList();

    return Producto(
      id: row['sku'] as String,
      nombre: row['nombre'] as String,
      marca: row['marca'] as String,
      categoria: row['categoria'] as String,
      presentaciones: presentations,
      imagenPath: row['imagen_url'] as String?,
      estado: row['estado'] as String? ?? 'VERIFICADO',
      updatedAt: row['creado_at'] != null
          ? DateTime.tryParse(row['creado_at'] as String)
          : null,
    );
  }
}
