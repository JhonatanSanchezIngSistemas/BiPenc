import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bipenc/modulos/caja/proveedor_caja.dart';
import 'package:bipenc/datos/modelos/presentacion.dart';
import 'package:bipenc/servicios/servicio_db_local.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('LocalDb Integration - Ventas', () {
    late Producto prod;
    late ItemCarrito item;

    setUp(() async {
      await ServicioDbLocal.hardResetDatabase();
      prod = Producto(
        id: 'SKU-INT-001',
        skuCode: 'SKU-INT-001',
        nombre: 'Cuaderno Integracion',
        marca: 'BiPenc',
        categoria: 'Cuadernos',
        presentaciones: [
          Presentacion(
            id: 'unid',
            skuCode: 'SKU-INT-001',
            name: 'Unidad',
            conversionFactor: 1,
            prices: [PuntoPrecio(type: 'NORMAL', amount: 12.5)],
          ),
        ],
      );
      item = ItemCarrito(
        producto: prod,
        presentacion: prod.presentaciones.first,
        cantidad: 2,
      );
    });

    test('guardarVentaPendienteAtomica y buscar por correlativo', () async {
      final res = await ServicioDbLocal.guardarVentaPendienteAtomica(
        items: [item],
        total: 25.0,
        subtotal: 21.19,
        igv: 3.81,
        aliasVendedor: 'TESTER',
        correlativo: 'B001-INT-001',
        metodoPago: 'EFECTIVO',
        estaSincronizado: false,
      );

      expect(res.ventaId, greaterThan(0));

      final found = await ServicioDbLocal.buscarVentasPorCorrelativo('INT-001');
      expect(found.length, 1);
      expect(found.first['correlativo'], 'B001-INT-001');
      expect((found.first['total'] as num).toDouble(), 25.0);
    });

    test('anularVentaLocal marca estado y registra motivo', () async {
      final res = await ServicioDbLocal.guardarVentaPendienteAtomica(
        items: [item],
        total: 25.0,
        subtotal: 21.19,
        igv: 3.81,
        aliasVendedor: 'TESTER',
        correlativo: 'B001-INT-ANUL',
        metodoPago: 'EFECTIVO',
        estaSincronizado: true,
      );

      final ok = await ServicioDbLocal.anularVentaLocal(
        ventaId: res.ventaId,
        motivo: 'Error de digitación',
        aliasUsuario: 'ADMIN',
      );
      expect(ok, isTrue);

      final rows = await ServicioDbLocal.buscarVentasPorCorrelativo('INT-ANUL');
      expect(rows.length, 1);
      expect(rows.first['anulado'], 1);
      expect(rows.first['estado'], 'ANULADO');
      expect(rows.first['anulado_motivo'], 'Error de digitación');
    });

    test('marcarVentaSincronizada actualiza flags de sync', () async {
      final res = await ServicioDbLocal.guardarVentaPendienteAtomica(
        items: [item],
        total: 25.0,
        subtotal: 21.19,
        igv: 3.81,
        aliasVendedor: 'TESTER',
        correlativo: 'B001-INT-SYNC',
        metodoPago: 'EFECTIVO',
        estaSincronizado: false,
      );

      await ServicioDbLocal.marcarVentaSincronizada(res.ventaId);
      final rows = await ServicioDbLocal.buscarVentasPorCorrelativo('INT-SYNC');
      expect(rows.length, 1);
      expect(rows.first['sincronizado'], 1);
      expect(rows.first['estado'], 'OK');
    });
  });

  group('LocalDb Integration - Inventario', () {
    late Producto producto;

    setUp(() async {
      await ServicioDbLocal.hardResetDatabase();
      producto = Producto(
        id: 'SKU-INV-001',
        skuCode: 'SKU-INV-001',
        nombre: 'Lapicero Azul',
        marca: 'BiPenc',
        categoria: 'Escritura',
        presentaciones: [
          Presentacion(
            id: 'unid',
            skuCode: 'SKU-INV-001',
            name: 'Unidad',
            conversionFactor: 1,
            barcode: '775000000001',
            prices: [PuntoPrecio(type: 'NORMAL', amount: 2.5)],
          ),
        ],
        descripcion: 'Prueba integración inventario',
        estado: 'VERIFICADO',
      );
    });

    test('upsertProducto + buscarLocal por nombre y SKU', () async {
      await ServicioDbLocal.upsertProducto(producto);

      final byName = await ServicioDbLocal.buscarLocal('lapicero');
      final bySku = await ServicioDbLocal.buscarLocal('SKU-INV-001');

      expect(byName, isNotEmpty);
      expect(byName.first.nombre, 'Lapicero Azul');
      expect(bySku, isNotEmpty);
      expect(bySku.first.skuCode, 'SKU-INV-001');
      expect(bySku.first.presentaciones, isNotEmpty);
      expect(bySku.first.presentaciones.first.barcode, '775000000001');
    });

    test('eliminarProducto encola DELETE con sku correcto en sync_queue_v2', () async {
      await ServicioDbLocal.upsertProducto(producto);
      await ServicioDbLocal.eliminarProducto(producto.id, sku: producto.skuCode);

      final pendientes = await ServicioDbLocal.obtenerSyncQueueV2Pendiente();
      final deletes = pendientes
          .where((e) => e['tabla'] == 'productos' && e['operacion'] == 'DELETE')
          .toList();

      expect(deletes, isNotEmpty);
      final payload = jsonDecode((deletes.first['datos'] ?? '{}').toString()) as Map<String, dynamic>;
      expect(payload['sku'], 'SKU-INV-001');
      expect(payload['id'], 'SKU-INV-001');
    });

    test('buscarLocal vacío retorna catálogo y no falla', () async {
      await ServicioDbLocal.upsertProducto(producto);
      final all = await ServicioDbLocal.buscarLocal('');
      expect(all, isNotEmpty);
    });
  });
}
