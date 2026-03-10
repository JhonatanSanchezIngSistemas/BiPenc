import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bipenc/services/supabase_service.dart';

void main() {
  group('SupabaseService Compatibility', () {
    test('remueve campo despachado cuando columna no existe', () {
      final payload = {
        'total': 10,
        'despachado': false,
      };
      const e = PostgrestException(
        message: 'Could not find the despachado column',
        code: 'PGRST204',
      );

      final next = SupabaseService.nextVentaPayloadForCompatibilityForTest(payload, e);
      expect(next, isNotNull);
      expect(next!.containsKey('despachado'), isFalse);
    });

    test('migra dni_cliente a dni_ruc cuando corresponde', () {
      final payload = {
        'dni_cliente': '12345678',
      };
      const e = PostgrestException(
        message: 'Could not find the dni_cliente column',
        code: 'PGRST204',
      );

      final next = SupabaseService.nextVentaPayloadForCompatibilityForTest(payload, e);
      expect(next, isNotNull);
      expect(next!.containsKey('dni_cliente'), isFalse);
      expect(next['dni_ruc'], '12345678');
    });

    test('fallback correlativo genera prefijo temporal', () {
      final corr = SupabaseService.generarCorrelativoFallbackForTest();
      expect(corr.startsWith('T-'), isTrue);
      expect(corr.length, greaterThan(6));
    });
  });

  group('SupabaseService mapToProducto', () {
    test('usa fallback de presentaciones cuando viene sin presentaciones', () {
      final p = SupabaseService.mapToProducto({
        'id': 'abc',
        'sku': 'SKU-01',
        'nombre': 'Producto',
        'marca': 'Marca',
        'categoria': 'Cat',
        'precio_base': 5.5,
        'precio_mayorista': 4.5,
      });

      expect(p.id, 'abc');
      expect(p.skuCode, 'SKU-01');
      expect(p.presentaciones, isNotEmpty);
      expect(p.precioBase, 5.5);
      final mayorista = p.presentaciones.firstWhere((x) => x.id == 'mayo');
      expect(mayorista.getPriceByType('NORMAL'), 4.5);
    });
  });
}
