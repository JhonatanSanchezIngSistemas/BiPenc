import 'package:flutter_test/flutter_test.dart';
import 'package:bipenc/services/print_service.dart';

void main() {
  group('PrintService.normalizeForEscPos', () {
    test('normaliza comillas y guiones especiales', () {
      const input = '“oferta” — edición';
      final out = PrintService.normalizeForEscPos(input);
      expect(out.contains('"oferta" - edicion'), isTrue);
    });

    test('normaliza iconos de pago', () {
      const input = 'Pago 💳 o 📱, efectivo 💵';
      final out = PrintService.normalizeForEscPos(input);
      expect(out.contains('TARJETA'), isTrue);
      expect(out.contains('YAPE/PLIN'), isTrue);
      expect(out.contains('EFECTIVO'), isTrue);
    });

    test('normaliza tildes y ñ para evitar caracteres raros', () {
      const input = 'Librería Española: útil, rápido, niño';
      final out = PrintService.normalizeForEscPos(input);
      expect(out, 'Libreria Espanola: util, rapido, nino');
    });

    test('preserva espacios internos para alineacion de columnas', () {
      const input = 'IZQUIERDA            DERECHA';
      final out = PrintService.normalizeForEscPos(input);
      expect(out.contains('            '), isTrue);
    });
  });
}
