import 'package:bipenc/servicios/cola_impresion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (txn, _) async {
        await txn.execute('''
          CREATE TABLE print_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bytes_hex TEXT NOT NULL,
            tipo_comprobante TEXT NOT NULL,
            venta_id TEXT,
            creado_at TEXT NOT NULL,
            intentos INTEGER NOT NULL DEFAULT 0,
            impreso INTEGER NOT NULL DEFAULT 0,
            error_msg TEXT
          )
        ''');
      },
    );

    ColaImpresion.databaseOverride = () async => db;
    ColaImpresion.perItemDelayOverride = () => Duration.zero;
  });

  tearDown(() async {
    ColaImpresion.resetTestingOverrides();
    await db.close();
  });

  test('encolarImpresion guarda pendiente cuando no hay conexión', () async {
    ColaImpresion.connectionStatusOverride = () async => false;
    var writes = 0;
    ColaImpresion.writeBytesOverride = (_) async {
      writes++;
      return true;
    };

    await ColaImpresion.encolarImpresion(
      bytes: [0x1B, 0x40],
      tipoComprobante: 'BOLETA',
      ventaId: 'V-001',
    );

    final rows = await db.query('print_queue');
    expect(rows, hasLength(1));
    expect(rows.first['impreso'], 0);
    expect(rows.first['intentos'], 0);
    expect(writes, 0);
  });

  test('procesarCola marca como impreso cuando writeBytes retorna true',
      () async {
    await db.insert('print_queue', {
      'bytes_hex': '1b40',
      'tipo_comprobante': 'BOLETA',
      'venta_id': 'V-OK',
      'creado_at': DateTime.now().toIso8601String(),
      'intentos': 0,
      'impreso': 0,
    });

    ColaImpresion.connectionStatusOverride = () async => true;
    ColaImpresion.writeBytesOverride = (_) async => true;

    await ColaImpresion.procesarCola();

    final rows = await db
        .query('print_queue', where: 'venta_id = ?', whereArgs: ['V-OK']);
    expect(rows, hasLength(1));
    expect(rows.first['impreso'], 1);
    expect(rows.first['intentos'], 0);
  });

  test('procesarCola incrementa intentos cuando writeBytes falla', () async {
    await db.insert('print_queue', {
      'bytes_hex': '1b40',
      'tipo_comprobante': 'BOLETA',
      'venta_id': 'V-FAIL',
      'creado_at': DateTime.now().toIso8601String(),
      'intentos': 1,
      'impreso': 0,
    });

    ColaImpresion.connectionStatusOverride = () async => true;
    ColaImpresion.writeBytesOverride = (_) async => false;

    await ColaImpresion.procesarCola();

    final rows = await db
        .query('print_queue', where: 'venta_id = ?', whereArgs: ['V-FAIL']);
    expect(rows, hasLength(1));
    expect(rows.first['impreso'], 0);
    expect(rows.first['intentos'], 2);
  });

  test('procesarCola registra error_msg truncado cuando hay excepción',
      () async {
    await db.insert('print_queue', {
      'bytes_hex': '1b40',
      'tipo_comprobante': 'BOLETA',
      'venta_id': 'V-EX',
      'creado_at': DateTime.now().toIso8601String(),
      'intentos': 0,
      'impreso': 0,
    });

    ColaImpresion.connectionStatusOverride = () async => true;
    ColaImpresion.writeBytesOverride = (_) async => throw Exception('x' * 160);

    await ColaImpresion.procesarCola();

    final rows = await db
        .query('print_queue', where: 'venta_id = ?', whereArgs: ['V-EX']);
    expect(rows, hasLength(1));
    expect(rows.first['impreso'], 0);
    expect(rows.first['intentos'], 1);
    final msg = (rows.first['error_msg'] ?? '').toString();
    expect(msg, isNotEmpty);
    expect(msg.length, lessThanOrEqualTo(100));
  });

  test('procesarCola concurrente no duplica impresion del mismo item',
      () async {
    await db.insert('print_queue', {
      'bytes_hex': '1b40',
      'tipo_comprobante': 'BOLETA',
      'venta_id': 'V-CONCURRENT',
      'creado_at': DateTime.now().toIso8601String(),
      'intentos': 0,
      'impreso': 0,
    });

    ColaImpresion.connectionStatusOverride = () async => true;
    var writes = 0;
    ColaImpresion.writeBytesOverride = (_) async {
      writes++;
      await Future.delayed(const Duration(milliseconds: 30));
      return true;
    };

    await Future.wait([
      ColaImpresion.procesarCola(),
      ColaImpresion.procesarCola(),
    ]);

    final rows = await db.query('print_queue',
        where: 'venta_id = ?', whereArgs: ['V-CONCURRENT']);
    expect(rows, hasLength(1));
    expect(rows.first['impreso'], 1);
    expect(writes, 1);
  });
}
