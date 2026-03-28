import 'package:bipenc/datos/modelos/presentacion.dart';
import 'package:bipenc/modulos/caja/proveedor_caja.dart';
import 'package:bipenc/modulos/reportes/pantalla_boletas.dart';
import 'package:bipenc/servicios/servicio_db_local.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await ServicioDbLocal.hardResetDatabase();
    final producto = Producto(
      id: 'SKU-W-1',
      skuCode: 'SKU-W-1',
      nombre: 'Prueba Widget',
      presentaciones: [
        Presentacion(
          id: 'unid',
          skuCode: 'SKU-W-1',
          name: 'Unidad',
          conversionFactor: 1,
          prices: [PuntoPrecio(type: 'NORMAL', amount: 3.5)],
        ),
      ],
    );
    final item = ItemCarrito(
      producto: producto,
      presentacion: producto.presentaciones.first,
      cantidad: 2,
    );
    await ServicioDbLocal.guardarVentaPendienteAtomica(
      items: [item],
      total: 7.0,
      subtotal: 5.93,
      igv: 1.07,
      aliasVendedor: 'TEST',
      correlativo: 'B001-WIDGET-001',
      metodoPago: 'EFECTIVO',
      estaSincronizado: false,
    );
  });

  testWidgets('PantallaBoletas carga listado y muestra buscador', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PantallaBoletas(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Boletas'), findsOneWidget);
    expect(find.textContaining('Buscar por N° boleta'), findsOneWidget);
  });
}
