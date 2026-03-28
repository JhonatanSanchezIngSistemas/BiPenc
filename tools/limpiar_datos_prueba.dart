/// Dart Script: Limpieza de datos de prueba en Local SQLite DB
/// Archivo: tools/limpiar_datos_prueba.dart
/// Purpose: Limpiar datos ficticios antes de Go-Live
/// Run: dart run tools/limpiar_datos_prueba.dart

import 'package:bipenc/servicios/servicio_db_local.dart';
import 'package:bipenc/utilidades/registro_app.dart';
import 'package:sqflite/sqflite.dart';

void main() async {
  print('🧹 INICIANDO LIMPIEZA DE DATOS DE PRUEBA EN LOCAL DB');
  print('=' * 60);

  try {
    // 1️⃣ Obtener referencia a la BD local
    final dbService = ServicioDbLocal();
    final db = dbService.database; // Requiere que esté inicializada

    print('\n1️⃣ CONECTANDO A LOCAL DB...');
    if (db == null) {
      await dbService.initDb();
      print('✅ BD Inicializada');
    } else {
      print('✅ BD ya estaba abierta');
    }

    // 2️⃣ Contar datos ANTES de limpiar
    print('\n2️⃣ CONTANDO DATOS ANTES DE LIMPIEZA...');
    final countProductosBefore = Sqflite.firstIntValue(
      await db!.rawQuery('SELECT COUNT(*) FROM productos_cache'),
    ) ?? 0;
    final countVentasBefore = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM ventas_cache'),
    ) ?? 0;
    final countListasBefore = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM listas_cache'),
    ) ?? 0;

    print('   📦 Productos: $countProductosBefore');
    print('   🛒 Ventas: $countVentasBefore');
    print('   📋 Listas: $countListasBefore');

    // 3️⃣ LIMPIAR DATOS DE PRUEBA
    print('\n3️⃣ LIMPIANDO DATOS...');

    // ⚠️ IMPORTANTE: El orden importa (FK constraints)
    // Primero limpiar tablas dependientes, luego las maestras

    // 3.1: Limpiar detalles de venta
    await db.delete('detalles_venta_cache');
    print('   ✅ Limpiado: detalles_venta_cache');

    // 3.2: Limpiar ventas
    await db.delete('ventas_cache');
    print('   ✅ Limpiado: ventas_cache');

    // 3.3: Limpiar items de listas
    await db.delete('orden_items_cache');
    print('   ✅ Limpiado: orden_items_cache');

    // 3.4: Limpiar listas
    await db.delete('listas_cache');
    print('   ✅ Limpiado: listas_cache');

    // 3.5: Limpiar movimientos de caja
    await db.delete('movimientos_caja_cache');
    print('   ✅ Limpiado: movimientos_caja_cache');

    // 3.6: Limpiar stock_cache
    await db.delete('stock_cache');
    print('   ✅ Limpiado: stock_cache');

    // 3.7: Limpiar productos (ÚLTIMA)
    await db.delete('productos_cache');
    print('   ✅ Limpiado: productos_cache');

    // 3.8: Limpiar categorías y maestros (si existen)
    await db.delete('categorias_cache');
    print('   ✅ Limpiado: categorias_cache');

    // Resetear correlativo local
    await _resetCorrelativoLocal(db);
    print('   ✅ Resetado: correlativo local');

    // 4️⃣ VERIFICAR DESPUÉS DE LIMPIAR
    print('\n4️⃣ VERIFICANDO DESPUÉS DE LIMPIEZA...');
    final countProductosAfter = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM productos_cache'),
    ) ?? 0;
    final countVentasAfter = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM ventas_cache'),
    ) ?? 0;
    final countListasAfter = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM listas_cache'),
    ) ?? 0;

    print('   📦 Productos: $countProductosAfter (Borrados: ${countProductosBefore - countProductosAfter})');
    print('   🛒 Ventas: $countVentasAfter (Borrados: ${countVentasBefore - countVentasAfter})');
    print('   📋 Listas: $countListasAfter (Borrados: ${countListasBefore - countListasAfter})');

    // 5️⃣ RESUMEN FINAL
    print('\n' + '=' * 60);
    print('✅ LIMPIEZA COMPLETADA CORRECTAMENTE');
    print('=' * 60);
    print('\n📝 SIGUIENTES PASOS:');
    print('   1. Sincronizar BD Local con Supabase');
    print('   2. Ir a Inventario → Sincronizar');
    print('   3. Esperar a que carguen los datos maestro');
    print('   4. Verificar en POS que aparecen los productos');
    print('   5. Hacer venta de prueba');
    print('   6. Cierre de caja test');

    exit(0);
  } catch (e, stackTrace) {
    print('\n❌ ERROR DURANTE LIMPIEZA:');
    print('   $e');
    print('   $stackTrace');
    exit(1);
  }
}

/// Resetea el correlativo local (equivalente a UPDATE .. SET = 0)
Future<void> _resetCorrelativoLocal(Database db) async {
  try {
    // Opcional: Si existe tabla local de correlativo, resetearla
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%correlativo%'",
    );

    if (tables.isNotEmpty) {
      await db.update(
        'correlativo_local',
        {'numero': 0},
        where: '1=1', // Resetea todos
      );
      print('   ℹ️ Correlativo local resetado a 0');
    }
  } catch (e) {
    print('   ⚠️ Correlativo local: no es tabla crítica, continuando...');
  }
}
