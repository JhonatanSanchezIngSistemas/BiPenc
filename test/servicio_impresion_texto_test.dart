import 'package:flutter_test/flutter_test.dart';
import 'package:bipenc/servicios/servicio_impresion.dart';

void main() {
  group('ServicioImpresion.normalizeForEscPos', () {
    test('normaliza comillas y guiones especiales', () {
      const input = '“oferta” — edición';
      final out = ServicioImpresion.normalizeForEscPos(input);
      expect(out.contains('"oferta" - edicion'), isTrue);
    });

    test('normaliza iconos de pago', () {
      const input = 'Pago 💳 o 📱, efectivo 💵';
      final out = ServicioImpresion.normalizeForEscPos(input);
      expect(out.contains('TARJETA'), isTrue);
      expect(out.contains('YAPE/PLIN'), isTrue);
      expect(out.contains('EFECTIVO'), isTrue);
    });

    test('normaliza tildes y ñ para evitar caracteres raros', () {
      const input = 'Librería Española: útil, rápido, niño';
      final out = ServicioImpresion.normalizeForEscPos(input);
      expect(out, 'Libreria Espanola: util, rapido, nino');
    });

    test('preserva espacios internos para alineacion de columnas', () {
      const input = 'IZQUIERDA            DERECHA';
      final out = ServicioImpresion.normalizeForEscPos(input);
      expect(out.contains('            '), isTrue);
    });
  });
}
