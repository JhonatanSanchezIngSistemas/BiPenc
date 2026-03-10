import 'package:bipenc/data/models/presentation.dart';
import 'package:bipenc/features/pos/pos_provider.dart';
import 'package:bipenc/features/reports/boletas_screen.dart';
import 'package:bipenc/services/local_db_service.dart';
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
    await LocalDbService.hardResetDatabase();
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
          prices: [PricePoint(type: 'NORMAL', amount: 3.5)],
        ),
      ],
    );
    final item = ItemCarrito(
      producto: producto,
      presentacion: producto.presentaciones.first,
      cantidad: 2,
    );
    await LocalDbService.guardarVentaPendienteAtomica(
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

  testWidgets('BoletasScreen carga listado y muestra buscador', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BoletasScreen(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Boletas'), findsOneWidget);
    expect(find.textContaining('Buscar por N° boleta'), findsOneWidget);
  });
}
