import 'package:flutter_test/flutter_test.dart';
import 'package:bipenc/data/models/producto.dart';
import 'package:bipenc/data/models/presentation.dart';

void main() {
  group('Producto Model Tests', () {
    test('Should handle price helpers correctly', () {
      final prod = Producto(
        id: '123',
        skuCode: 'SKU123',
        nombre: 'Test',
        presentaciones: [
          Presentacion(
            id: 'unid',
            skuCode: 'SKU123',
            name: 'Unidad',
            conversionFactor: 1,
            prices: [PricePoint(type: 'NORMAL', amount: 10.0)],
          ),
          Presentacion(
            id: 'mayo',
            skuCode: 'SKU123-MAYO',
            name: 'Mayorista',
            conversionFactor: 1,
            prices: [PricePoint(type: 'WHOLESALE', amount: 8.0)],
          ),
          Presentacion(
            id: 'espe',
            skuCode: 'SKU123-ESPE',
            name: 'Especial',
            conversionFactor: 1,
            prices: [PricePoint(type: 'SPECIAL', amount: 7.0)],
          ),
        ],
      );

      expect(prod.precioBase, 10.0);
      expect(prod.precioMayorista, 8.0);
      expect(prod.precioEspecial, 7.0);
    });

    test('Should use fallback for missing prices', () {
      final prod = Producto(
        id: '123',
        skuCode: 'SKU123',
        nombre: 'Test',
        presentaciones: [
          Presentacion(
            id: 'unid',
            skuCode: 'SKU123',
            name: 'Unidad',
            conversionFactor: 1,
            prices: [PricePoint(type: 'NORMAL', amount: 10.0)],
          ),
        ],
      );

      expect(prod.precioMayorista, 10.0);
      expect(prod.precioEspecial, 10.0);
    });
  });
}
