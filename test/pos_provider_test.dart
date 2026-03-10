import 'package:flutter_test/flutter_test.dart';
import 'package:bipenc/features/pos/pos_provider.dart';
import 'package:bipenc/data/models/presentation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PosProvider Logic Tests', () {
    late PosProvider pos;
    late Producto prodTest;

    setUp(() {
      pos = PosProvider(testMode: true);
      prodTest = Producto(
        id: 'TEST001',
        skuCode: 'SKU-TEST-001',
        nombre: 'Producto de Prueba',
        marca: 'BiPenc',
        categoria: 'Test',
        presentaciones: [
          Presentacion(
            id: 'unid',
            skuCode: 'SKU-TEST-001',
            name: 'Unidad',
            conversionFactor: 1,
            prices: [PricePoint(type: 'NORMAL', amount: 10.0)],
          ),
          Presentacion(
            id: 'mayo',
            skuCode: 'SKU-TEST-001-MAYO',
            name: 'Mayorista',
            conversionFactor: 1,
            prices: [PricePoint(type: 'WHOLESALE', amount: 8.0)],
          ),
        ],
        precioPropuesto: 8.0,
      );
    });

    test('Cálculo inicial - Carrito vacío', () {
      expect(pos.items.length, 0);
    });

    test('Agregar producto y calcular cantidad', () async {
      await pos.agregarProducto(prodTest, cantidad: 2);
      expect(pos.items.length, 1);
      expect(pos.items[0].cantidad, 2);
    });

    test('Multi-Carrito - Aislamiento de colas', () async {
      await pos.agregarProducto(prodTest, cantidad: 1);
      expect(pos.items.length, 1);

      pos.cambiarCarrito(1);
      expect(pos.items.length, 0);

      await pos.agregarProducto(prodTest, cantidad: 5);
      expect(pos.items.length, 1);
      expect(pos.items[0].cantidad, 5);

      pos.cambiarCarrito(0);
      expect(pos.items.length, 1);
      expect(pos.items[0].cantidad, 1);
    });

    test('Producto Genérico - Creación dinámica', () {
      pos.agregarProductoGenerico();
      expect(pos.items.length, 1);
      expect(pos.items[0].producto.nombre, 'Varios / Precio libre');
    });

    test('mapRowsToVentas transforma filas SQLite a modelo de tickets', () {
      final rows = [
        {
          'id': 99,
          'correlativo': 'B001-000001',
          'creado_at': DateTime(2026, 3, 9, 10, 30).toIso8601String(),
          'metodo_pago': 'EFECTIVO',
          'total': 20.0,
          'subtotal': 16.95,
          'igv': 3.05,
          'documento_cliente': '12345678',
          'nombre_cliente': 'Cliente Test',
          'despachado': 1,
          'sincronizado': 1,
          'items_json': '[{"producto_id":"TEST001","producto_nombre":"Producto de Prueba","presentacion_id":"unid","presentacion_nombre":"Unidad","cantidad":2,"precio_normal":10.0}]',
        },
      ];

      final tickets = PosProvider.mapRowsToVentas(rows, ivaRate: 0.18);
      expect(tickets, isNotEmpty);
      expect(tickets.first.id, 'B001-000001');
      expect(tickets.first.items.length, 1);
      expect(tickets.first.items.first.producto.nombre, 'Producto de Prueba');
      expect(tickets.first.total, 20.0);
      expect(tickets.first.synced, isTrue);
    });
  });
}
