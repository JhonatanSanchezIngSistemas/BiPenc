import 'package:flutter_test/flutter_test.dart';
import 'package:bipenc/data/models/producto.dart';
import 'package:bipenc/data/models/presentation.dart';
import 'package:bipenc/data/logic/cart_logic.dart';

void main() {
  group('Pure Cart Logic Tests (No Hardware)', () {
    late Producto prodTest;

    setUp(() {
      prodTest = Producto(
        id: 'TEST001',
        skuCode: 'TEST001',
        nombre: 'Producto de Prueba',
        marca: 'BiPenc',
        categoria: 'Test',
        presentaciones: [
          Presentacion(
            id: 'unid',
            skuCode: 'TEST001-UNID',
            name: 'Unidad',
            conversionFactor: 1,
            prices: [PricePoint(type: 'NORMAL', amount: 10.0)],
          ),
          Presentacion(
            id: 'mayo',
            skuCode: 'TEST001-MAYO',
            name: 'Mayorista',
            conversionFactor: 1,
            prices: [PricePoint(type: 'WHOLESALE', amount: 8.0)],
          ),
        ],
        precioPropuesto: 8.0,
      );
    });

    test('calcularSubtotal - lista vacía devuelve 0', () {
      expect(calcularSubtotal([]), 0.0);
    });

    test('calcularSubtotal - calcula correctamente', () {
      final items = [
        {'precio': 10.0, 'cantidad': 1},
        {'precio': 8.0, 'cantidad': 3},
      ];
      expect(calcularSubtotal(items), 34.0);
    });

    test('calcularVuelto - positivo', () {
      expect(calcularVuelto(34.0, 50.0), 16.0);
    });

    test('calcularVuelto - negativo devuelve 0', () {
      expect(calcularVuelto(100.0, 34.0), 0.0);
    });

    test('Producto tiene presentaciones correctas', () {
      expect(prodTest.precioBase, 10.0);
      expect(prodTest.precioMayorista, 8.0);
    });
  });
}
