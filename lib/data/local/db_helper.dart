import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import '../models/product.dart';
import '../models/venta.dart';
import '../models/cliente.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('bipenc_local.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      password: 'bipenc_secure_key_2026', // Clave maestra de cifrado 256 bits
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Tabla Principal: Productos
    await db.execute('''
      CREATE TABLE productos (
        id TEXT PRIMARY KEY,
        descripcion TEXT NOT NULL,
        marca TEXT,
        codigoBarras TEXT,
        categoria TEXT,
        imagen_url TEXT,
        requiere_autorizacion INTEGER NOT NULL
      )
    ''');

    // Módulo de Caja: Historial de Ventas
    await db.execute('''
      CREATE TABLE ventas (
        id TEXT PRIMARY KEY,
        fecha TEXT NOT NULL,
        total REAL NOT NULL,
        metodoPago TEXT NOT NULL,
        montoRecibido REAL NOT NULL,
        vuelto REAL NOT NULL,
        resumenItems TEXT NOT NULL
      )
    ''');

    // Módulo de CRM Básico: Caché de Clientes
    await db.execute('''
      CREATE TABLE clientes (
        documento TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        direccion TEXT
      )
    ''');

    // Tabla Secundaria (Uno a Muchos): Presentaciones
    // ON DELETE CASCADE asegura que si borramos un producto, sus presentaciones mueren también para no dejar huérfanos.
    await db.execute('''
      CREATE TABLE presentaciones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        producto_id TEXT NOT NULL,
        nombre TEXT NOT NULL,
        cantidad INTEGER NOT NULL,
        precio_unitario REAL NOT NULL,
        precio_mayor REAL NOT NULL,
        FOREIGN KEY (producto_id) REFERENCES productos (id) ON DELETE CASCADE
      )
    ''');
    
    // ESTRATEGIA DE INDEXACIÓN (Rendimiento Instantáneo a >10,000 registros)
    // Cuando el usuario busque en el inventario o escanee un QR, SQlite no tendrá que leer las 10,000 filas (Table Scan),
    // sino que usará un B-Tree estructurado saltando directo al resultado en milisegundos.
    await db.execute('CREATE INDEX idx_producto_codigo ON productos(codigoBarras)');
    await db.execute('CREATE INDEX idx_producto_desc ON productos(descripcion)');
  }

  // --- MÉTODOS CRUD ---

  /// Inserta un producto y todas sus presentaciones en una sola Transacción.
  /// Si falla a la mitad, hace Rollback automático, protegiendo la integridad.
  Future<void> insertProduct(Product producto) async {
    final db = await database;
    await db.transaction((txn) async {
      // 1. Insertamos el producto principal
      await txn.insert(
        'productos',
        {
          'id': producto.id,
          'descripcion': producto.descripcion,
          'marca': producto.marca,
          'codigoBarras': producto.codigoBarras,
          'categoria': producto.categoria ?? '', 
          'imagen_url': producto.imagenUrl ?? '',
          'requiere_autorizacion': producto.requiereAutorizacion ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 2. Insertamos la lista de presentaciones atada a su ID
      for (final pres in producto.presentaciones) {
        await txn.insert(
          'presentaciones',
          {
            'producto_id': producto.id,
            'nombre': pres.nombre,
            'cantidad': pres.cantidadPorEmpaque,
            'precio_unitario': pres.precioUnitario,
            'precio_mayor': pres.precioMayor,
          },
        );
      }
    });
  }

  /// Recupera TODOS los productos ensamblados con su respectiva lista de Presentaciones (JOIN virtual)
  Future<List<Product>> getAllProducts() async {
    final db = await database;
    
    // Obtenemos todos los productos principales
    final List<Map<String, dynamic>> maps = await db.query('productos');
    
    // Por motivos de eficiencia máxima, obtenemos TODAS las presentaciones de golpe
    // en lugar de hacer 10,000 queries dentro de un bucle for.
    final List<Map<String, dynamic>> allPresentaciones = await db.query('presentaciones');
    
    return List.generate(maps.length, (i) {
      final String currentId = maps[i]['id'];
      
      // Filtramos en memoria de Dart las presentaciones que le pertenecen a este producto
      final rawPresentaciones = allPresentaciones.where((p) => p['producto_id'] == currentId);
      
      final persistPresentaciones = rawPresentaciones.map((pMap) => Presentacion(
        nombre: pMap['nombre'],
        cantidadPorEmpaque: pMap['cantidad'],
        precioUnitario: pMap['precio_unitario'],
        precioMayor: pMap['precio_mayor'],
      )).toList();

      return Product(
        id: currentId,
        descripcion: maps[i]['descripcion'],
        marca: maps[i]['marca'],
        codigoBarras: maps[i]['codigoBarras'],
        categoria: maps[i]['categoria'],
        imagenUrl: maps[i]['imagen_url'],
        requiereAutorizacion: maps[i]['requiere_autorizacion'] == 1,
        presentaciones: persistPresentaciones,
      );
    });
  }

  /// Elimina un producto. Por regla ON DELETE CASCADE trazada en la creación, se lleva sus presentaciones.
  Future<int> deleteProduct(String id) async {
    final db = await database;
    return await db.delete(
      'productos',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- Módulo de Caja (Ventas) ---

  Future<void> insertVenta(Venta venta) async {
    final db = await database;
    await db.insert(
      'ventas',
      venta.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Venta>> getUltimasVentas({int limit = 5}) async {
    final db = await database;
    final maps = await db.query(
      'ventas',
      orderBy: 'fecha DESC',
      limit: limit,
    );
    return maps.map((map) => Venta.fromMap(map)).toList();
  }

  // --- Módulo de Clientes (Caché Local) ---

  Future<Cliente?> getCliente(String documento) async {
    final db = await database;
    final maps = await db.query(
      'clientes',
      where: 'documento = ?',
      whereArgs: [documento],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return Cliente.fromMap(maps.first);
    }
    return null;
  }

  Future<void> insertCliente(Cliente cliente) async {
    final db = await database;
    await db.insert(
      'clientes',
      cliente.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
