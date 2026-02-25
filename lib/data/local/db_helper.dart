import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:bipenc/data/models/product.dart';
import 'package:bipenc/data/models/venta.dart';
import 'package:bipenc/data/models/cliente.dart';

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
      password: 'bipenc_secure_key_2026',
      version: 3, // Bumped: categorías dinámicas
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Tabla Productos (nueva estructura unificada)
    await db.execute('''
      CREATE TABLE productos (
        sku TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        marca TEXT NOT NULL DEFAULT '',
        categoria TEXT NOT NULL DEFAULT '',
        precio_base REAL NOT NULL DEFAULT 0.0,
        precio_mayorista REAL NOT NULL DEFAULT 0.0,
        imagen_url TEXT NOT NULL DEFAULT ''
      )
    ''');

    // Tabla Ventas
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

    // Tabla Clientes (caché local)
    await db.execute('''
      CREATE TABLE clientes (
        documento TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        direccion TEXT
      )
    ''');

    // Tabla Categorías (Fase Librero Pro)
    await db.execute('''
      CREATE TABLE categorias (
        nombre TEXT PRIMARY KEY
      )
    ''');

    // Índices de rendimiento
    await db.execute('CREATE INDEX idx_prod_nombre ON productos(nombre)');
    await db.execute('CREATE INDEX idx_prod_categoria ON productos(categoria)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Migración: eliminar tablas antiguas y recrear
      await db.execute('DROP TABLE IF EXISTS presentaciones');
      await db.execute('DROP TABLE IF EXISTS productos');
      await db.execute('''
        CREATE TABLE productos (
          sku TEXT PRIMARY KEY,
          nombre TEXT NOT NULL,
          marca TEXT NOT NULL DEFAULT '',
          categoria TEXT NOT NULL DEFAULT '',
          precio_base REAL NOT NULL DEFAULT 0.0,
          precio_mayorista REAL NOT NULL DEFAULT 0.0,
          imagen_url TEXT NOT NULL DEFAULT ''
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_prod_nombre ON productos(nombre)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_prod_categoria ON productos(categoria)');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS categorias (
          nombre TEXT PRIMARY KEY
        )
      ''');
      // Sembrar categorías iniciales
      final bases = ['Escritura', 'Arte', 'Cuadernos', 'Papelería'];
      for (final cat in bases) {
        await db.insert('categorias', {'nombre': cat}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  // === CRUD Productos ===

  Future<void> insertProduct(Product p) async {
    final db = await database;
    await db.insert('productos', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateProduct(Product p) async {
    final db = await database;
    await db.update('productos', p.toMap(), where: 'sku = ?', whereArgs: [p.sku]);
  }

  Future<int> deleteProduct(String sku) async {
    final db = await database;
    return await db.delete('productos', where: 'sku = ?', whereArgs: [sku]);
  }

  Future<List<Product>> getAllProducts() async {
    final db = await database;
    final maps = await db.query('productos', orderBy: 'nombre ASC');
    return maps.map(Product.fromMap).toList();
  }

  Future<Product?> getProductBySku(String sku) async {
    final db = await database;
    final maps = await db.query('productos', where: 'sku = ?', whereArgs: [sku], limit: 1);
    return maps.isEmpty ? null : Product.fromMap(maps.first);
  }

  Future<List<Product>> searchProducts(String query) async {
    final db = await database;
    final q = '%${query.toLowerCase()}%';
    final maps = await db.rawQuery(
      'SELECT * FROM productos WHERE LOWER(nombre) LIKE ? OR LOWER(sku) LIKE ? OR LOWER(marca) LIKE ? ORDER BY nombre ASC',
      [q, q, q],
    );
    return maps.map(Product.fromMap).toList();
  }

  /// Siembra el catálogo solo si la tabla está vacía (primera ejecución).
  Future<void> seedIfEmpty() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM productos');
    final int count = (result.first['cnt'] as int? ?? 0);
    if (count > 0) return;
    for (final p in _seedProducts()) {
      await insertProduct(p);
    }
  }

  // === Ventas ===

  Future<void> insertVenta(Venta venta) async {
    final db = await database;
    await db.insert('ventas', venta.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Venta>> getUltimasVentas({int limit = 5}) async {
    final db = await database;
    final maps = await db.query('ventas', orderBy: 'fecha DESC', limit: limit);
    return maps.map(Venta.fromMap).toList();
  }

  // === Clientes ===

  Future<Cliente?> getCliente(String documento) async {
    final db = await database;
    final maps = await db.query('clientes', where: 'documento = ?', whereArgs: [documento], limit: 1);
    return maps.isEmpty ? null : Cliente.fromMap(maps.first);
  }

  Future<void> insertCliente(Cliente cliente) async {
    final db = await database;
    await db.insert('clientes', cliente.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // === Categorías ===

  Future<List<String>> getAllCategories() async {
    final db = await database;
    final maps = await db.query('categorias', orderBy: 'nombre ASC');
    return maps.map((m) => m['nombre'] as String).toList();
  }

  Future<void> insertCategory(String nombre) async {
    final db = await database;
    await db.insert('categorias', {'nombre': nombre}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}

// =============================================================================
// DATA SEED — 55 Productos de Librería Peruana
// =============================================================================
List<Product> _seedProducts() {
  int n = 1;
  String sku() => 'BP${(n++).toString().padLeft(4, '0')}';

  return [
    // ── ESCRITURA ──────────────────────────────────────────────────────────
    Product(sku: sku(), nombre: 'Lapicero Pilot BPS-GP Azul', marca: 'Pilot', categoria: 'Escritura', precioBase: 1.50, precioMayorista: 1.20),
    Product(sku: sku(), nombre: 'Lapicero Pilot BPS-GP Rojo', marca: 'Pilot', categoria: 'Escritura', precioBase: 1.50, precioMayorista: 1.20),
    Product(sku: sku(), nombre: 'Lapicero Pilot BPS-GP Negro', marca: 'Pilot', categoria: 'Escritura', precioBase: 1.50, precioMayorista: 1.20),
    Product(sku: sku(), nombre: 'Lapicero Faber-Castell 1423 Azul', marca: 'Faber-Castell', categoria: 'Escritura', precioBase: 0.70, precioMayorista: 0.55),
    Product(sku: sku(), nombre: 'Lapicero Faber-Castell 1423 Rojo', marca: 'Faber-Castell', categoria: 'Escritura', precioBase: 0.70, precioMayorista: 0.55),
    Product(sku: sku(), nombre: 'Lapicero Faber-Castell 1423 Negro', marca: 'Faber-Castell', categoria: 'Escritura', precioBase: 0.70, precioMayorista: 0.55),
    Product(sku: sku(), nombre: 'Lapicero Stabilo Exam Grade Azul', marca: 'Stabilo', categoria: 'Escritura', precioBase: 2.50, precioMayorista: 2.00),
    Product(sku: sku(), nombre: 'Lápiz Faber-Castell 1221 HB', marca: 'Faber-Castell', categoria: 'Escritura', precioBase: 0.50, precioMayorista: 0.40),
    Product(sku: sku(), nombre: 'Lápiz Faber-Castell 1221 2B', marca: 'Faber-Castell', categoria: 'Escritura', precioBase: 0.50, precioMayorista: 0.40),
    Product(sku: sku(), nombre: 'Lápiz Técnico Staedtler HB', marca: 'Staedtler', categoria: 'Escritura', precioBase: 2.80, precioMayorista: 2.30),
    Product(sku: sku(), nombre: 'Lápiz Mecánico Pentel Graph 0.5mm', marca: 'Pentel', categoria: 'Escritura', precioBase: 18.00, precioMayorista: 15.00),
    Product(sku: sku(), nombre: 'Lapicero Roller Pentel EnerGel Azul', marca: 'Pentel', categoria: 'Escritura', precioBase: 8.50, precioMayorista: 7.00),
    Product(sku: sku(), nombre: 'Borrador Pelikan PZ-30', marca: 'Pelikan', categoria: 'Escritura', precioBase: 1.00, precioMayorista: 0.80),
    Product(sku: sku(), nombre: 'Borrador Faber-Castell 7071', marca: 'Faber-Castell', categoria: 'Escritura', precioBase: 0.80, precioMayorista: 0.65),
    Product(sku: sku(), nombre: 'Tajador Faber-Castell Doble Agujero', marca: 'Faber-Castell', categoria: 'Escritura', precioBase: 1.20, precioMayorista: 0.90),
    Product(sku: sku(), nombre: 'Corrector Líquido BIC Wite-Out 7ml', marca: 'BIC', categoria: 'Escritura', precioBase: 3.50, precioMayorista: 2.80),
    Product(sku: sku(), nombre: 'Corrector Cinta Pelikan Roll Correct 4.2mm', marca: 'Pelikan', categoria: 'Escritura', precioBase: 5.50, precioMayorista: 4.50),
    Product(sku: sku(), nombre: 'Resaltador Stabilo Boss Amarillo', marca: 'Stabilo', categoria: 'Escritura', precioBase: 3.00, precioMayorista: 2.50),
    Product(sku: sku(), nombre: 'Resaltador Stabilo Boss Verde', marca: 'Stabilo', categoria: 'Escritura', precioBase: 3.00, precioMayorista: 2.50),
    Product(sku: sku(), nombre: 'Plumón Faber-Castell Punta Fina Negro', marca: 'Faber-Castell', categoria: 'Escritura', precioBase: 1.50, precioMayorista: 1.20),

    // ── ARTE ───────────────────────────────────────────────────────────────
    Product(sku: sku(), nombre: 'Lápiz de Color Faber-Castell x12', marca: 'Faber-Castell', categoria: 'Arte', precioBase: 8.50, precioMayorista: 7.00),
    Product(sku: sku(), nombre: 'Lápiz de Color Faber-Castell x24 Brilliants', marca: 'Faber-Castell', categoria: 'Arte', precioBase: 14.50, precioMayorista: 12.00),
    Product(sku: sku(), nombre: 'Acuarela Winsor & Newton Cotman x12', marca: 'Winsor & Newton', categoria: 'Arte', precioBase: 32.00, precioMayorista: 28.00),
    Product(sku: sku(), nombre: 'Acuarela Pelikan Opaque x12', marca: 'Pelikan', categoria: 'Arte', precioBase: 12.00, precioMayorista: 10.00),
    Product(sku: sku(), nombre: 'Tempera Faber-Castell x12 colores 20ml', marca: 'Faber-Castell', categoria: 'Arte', precioBase: 15.00, precioMayorista: 12.50),
    Product(sku: sku(), nombre: 'Pincel Redondo Sintético N°12', marca: 'Princeton', categoria: 'Arte', precioBase: 4.50, precioMayorista: 3.80),
    Product(sku: sku(), nombre: 'Pincel Plano Cerda Natural N°8', marca: 'Princeton', categoria: 'Arte', precioBase: 3.80, precioMayorista: 3.20),
    Product(sku: sku(), nombre: 'Plumón de Tela Colorart x6', marca: 'Colorart', categoria: 'Arte', precioBase: 9.00, precioMayorista: 7.50),
    Product(sku: sku(), nombre: 'Papel Canson Aquarelle A4 300g x20', marca: 'Canson', categoria: 'Arte', precioBase: 22.00, precioMayorista: 18.00),
    Product(sku: sku(), nombre: 'Marcador Prismacolor Premier Azul', marca: 'Prismacolor', categoria: 'Arte', precioBase: 12.00, precioMayorista: 10.00),
    Product(sku: sku(), nombre: 'Crayón Jumbo Faber-Castell x10', marca: 'Faber-Castell', categoria: 'Arte', precioBase: 6.50, precioMayorista: 5.50),
    Product(sku: sku(), nombre: 'Plastilina Faber-Castell x10 barras', marca: 'Faber-Castell', categoria: 'Arte', precioBase: 6.00, precioMayorista: 5.00),
    Product(sku: sku(), nombre: 'Tiza Pastel Soft Faber-Castell x24', marca: 'Faber-Castell', categoria: 'Arte', precioBase: 24.00, precioMayorista: 20.00),
    Product(sku: sku(), nombre: 'Lienzo Algodón 30x40cm', marca: 'Talens', categoria: 'Arte', precioBase: 9.50, precioMayorista: 8.00),

    // ── CUADERNOS ─────────────────────────────────────────────────────────
    Product(sku: sku(), nombre: 'Cuaderno Norma 100h Cuadriculado A4', marca: 'Norma', categoria: 'Cuadernos', precioBase: 6.20, precioMayorista: 5.50),
    Product(sku: sku(), nombre: 'Cuaderno Norma 100h Rayado A4', marca: 'Norma', categoria: 'Cuadernos', precioBase: 6.20, precioMayorista: 5.50),
    Product(sku: sku(), nombre: 'Cuaderno Stanford 200h A4 Tapa Dura', marca: 'Stanford', categoria: 'Cuadernos', precioBase: 9.50, precioMayorista: 8.00),
    Product(sku: sku(), nombre: 'Cuaderno Stanford 100h A5 Espiral', marca: 'Stanford', categoria: 'Cuadernos', precioBase: 5.80, precioMayorista: 5.00),
    Product(sku: sku(), nombre: 'Cuaderno Espiralado Artesco 80h Rayado', marca: 'Artesco', categoria: 'Cuadernos', precioBase: 5.00, precioMayorista: 4.20),
    Product(sku: sku(), nombre: 'Cuaderno Escolar Pacsa 72h Cuadriculado', marca: 'Pacsa', categoria: 'Cuadernos', precioBase: 3.50, precioMayorista: 3.00),
    Product(sku: sku(), nombre: 'Block de Notas Post-it 3x3 Amarillo x100', marca: '3M', categoria: 'Cuadernos', precioBase: 8.00, precioMayorista: 6.50),
    Product(sku: sku(), nombre: 'Agenda 2026 Ejecutiva A5 Tapa Blanda', marca: 'Stanford', categoria: 'Cuadernos', precioBase: 18.00, precioMayorista: 15.00),

    // ── PAPELERÍA ─────────────────────────────────────────────────────────
    Product(sku: sku(), nombre: 'Papel Bond A4 80g x500 Hojas', marca: 'Navigator', categoria: 'Papelería', precioBase: 18.90, precioMayorista: 16.50),
    Product(sku: sku(), nombre: 'Tijera Maped Study 21cm', marca: 'Maped', categoria: 'Papelería', precioBase: 4.50, precioMayorista: 3.80),
    Product(sku: sku(), nombre: 'Grapadora Faber-Castell Estándar', marca: 'Faber-Castell', categoria: 'Papelería', precioBase: 12.00, precioMayorista: 10.00),
    Product(sku: sku(), nombre: 'Caja de Grapas 26/6 x1000', marca: 'Artesco', categoria: 'Papelería', precioBase: 2.50, precioMayorista: 2.00),
    Product(sku: sku(), nombre: 'Pegamento en Barra UHU Stick 21g', marca: 'UHU', categoria: 'Papelería', precioBase: 3.50, precioMayorista: 2.80),
    Product(sku: sku(), nombre: 'Silicona Líquida 125ml Artesco', marca: 'Artesco', categoria: 'Papelería', precioBase: 4.20, precioMayorista: 3.50),
    Product(sku: sku(), nombre: 'Regla 30cm Faber-Castell Transparente', marca: 'Faber-Castell', categoria: 'Papelería', precioBase: 2.00, precioMayorista: 1.60),
    Product(sku: sku(), nombre: 'Escuadra 45° Faber-Castell 25cm', marca: 'Faber-Castell', categoria: 'Papelería', precioBase: 3.50, precioMayorista: 2.80),
    Product(sku: sku(), nombre: 'Compás Maped Stop System', marca: 'Maped', categoria: 'Papelería', precioBase: 8.50, precioMayorista: 7.00),
    Product(sku: sku(), nombre: 'Sobre Manila A4 x25 unidades', marca: 'Artesco', categoria: 'Papelería', precioBase: 4.50, precioMayorista: 3.80),
    Product(sku: sku(), nombre: 'Cinta Adhesiva Scotch 18mm x33m', marca: '3M', categoria: 'Papelería', precioBase: 3.00, precioMayorista: 2.50),
    Product(sku: sku(), nombre: 'Perforador 2 Agujeros Artesco 20 hojas', marca: 'Artesco', categoria: 'Papelería', precioBase: 8.50, precioMayorista: 7.00),
    Product(sku: sku(), nombre: 'Folder Manila A4 x25', marca: 'Artesco', categoria: 'Papelería', precioBase: 6.50, precioMayorista: 5.50),
    Product(sku: sku(), nombre: 'Archivador Lomo Ancho A4 Artesco', marca: 'Artesco', categoria: 'Papelería', precioBase: 9.00, precioMayorista: 7.50),
    Product(sku: sku(), nombre: 'Calculadora Científica Casio FX-82LA Plus', marca: 'Casio', categoria: 'Papelería', precioBase: 75.00, precioMayorista: 65.00),
  ];
}
