import 'package:flutter_test/flutter_test.dart';
import 'package:bipenc/base/constantes/ids_presentacion.dart';
import 'package:bipenc/base/constantes/tipos_precio.dart';
import 'package:bipenc/base/constantes/estados_producto.dart';
import 'package:bipenc/base/constantes/estados_sync.dart';
import 'package:bipenc/datos/modelos/producto.dart';
import 'package:bipenc/datos/modelos/presentacion.dart';

void main() {
  // ── 1. IDs de Presentación ──────────────────────────────────────────────
  group('IdsPresentacion', () {
    test('constantes tienen los valores correctos', () {
      expect(IdsPresentacion.unitario, 'unid');
      expect(IdsPresentacion.mayorista, 'mayo');
      expect(IdsPresentacion.especial, 'espe');
    });

    test('esFija() devuelve true para IDs fijos', () {
      expect(IdsPresentacion.esFija('unid'), isTrue);
      expect(IdsPresentacion.esFija('mayo'), isTrue);
      expect(IdsPresentacion.esFija('espe'), isTrue);
    });

    test('esFija() devuelve false para IDs dinámicos', () {
      expect(IdsPresentacion.esFija('pres_1'), isFalse);
      expect(IdsPresentacion.esFija('pres_2'), isFalse);
      expect(IdsPresentacion.esFija('custom'), isFalse);
      expect(IdsPresentacion.esFija(''), isFalse);
    });

    test('todasFijas contiene exactamente los 3 IDs estándar', () {
      expect(IdsPresentacion.todasFijas.length, 3);
      expect(IdsPresentacion.todasFijas,
          containsAll(['unid', 'mayo', 'espe']));
    });
  });

  // ── 2. Tipos de Precio ──────────────────────────────────────────────────
  group('TipoPrecio', () {
    test('constantes tienen valores correctos', () {
      expect(TipoPrecio.normal, 'NORMAL');
      expect(TipoPrecio.mayorista, 'WHOLESALE');
      expect(TipoPrecio.especial, 'SPECIAL');
    });

    test('esValido() acepta tipos correctos', () {
      expect(TipoPrecio.esValido('NORMAL'), isTrue);
      expect(TipoPrecio.esValido('WHOLESALE'), isTrue);
      expect(TipoPrecio.esValido('SPECIAL'), isTrue);
    });

    test('esValido() rechaza tipos desconocidos', () {
      expect(TipoPrecio.esValido('normal'), isFalse); // lowercase
      expect(TipoPrecio.esValido('MAYORISTA'), isFalse);
      expect(TipoPrecio.esValido(''), isFalse);
      expect(TipoPrecio.esValido('COSTO'), isFalse);
    });
  });

  // ── 3. Estados de Producto ──────────────────────────────────────────────
  group('EstadoProducto', () {
    test('constantes tienen valores correctos', () {
      expect(EstadoProducto.activo, 'ACTIVO');
      expect(EstadoProducto.verificado, 'VERIFICADO');
      expect(EstadoProducto.descontinuado, 'DESCONTINUADO');
      expect(EstadoProducto.borrador, 'BORRADOR');
    });

    test('esVendible() acepta activo y verificado', () {
      expect(EstadoProducto.esVendible('ACTIVO'), isTrue);
      expect(EstadoProducto.esVendible('VERIFICADO'), isTrue);
    });

    test('esVendible() rechaza descontinuado y borrador', () {
      expect(EstadoProducto.esVendible('DESCONTINUADO'), isFalse);
      expect(EstadoProducto.esVendible('BORRADOR'), isFalse);
      expect(EstadoProducto.esVendible(''), isFalse);
    });

    test('esValido() incluye todos los estados', () {
      for (final e in EstadoProducto.todos) {
        expect(EstadoProducto.esValido(e), isTrue,
            reason: 'Estado "$e" debería ser válido');
      }
    });
  });

  // ── 4. Estados de Sync ──────────────────────────────────────────────────
  group('EstadoSync', () {
    test('constantes tienen valores correctos', () {
      expect(EstadoSync.pendiente, 'PENDIENTE');
      expect(EstadoSync.ok, 'OK');
      expect(EstadoSync.error, 'ERROR');
    });

    test('necesitaSync() para PENDIENTE y ERROR', () {
      expect(EstadoSync.necesitaSync('PENDIENTE'), isTrue);
      expect(EstadoSync.necesitaSync('ERROR'), isTrue);
    });

    test('necesitaSync() para OK y LOCAL retorna false', () {
      expect(EstadoSync.necesitaSync('OK'), isFalse);
      expect(EstadoSync.necesitaSync('LOCAL'), isFalse);
    });
  });

  // ── 5. Integración: Producto con constantes ─────────────────────────────
  group('Producto — uso de constantes', () {
    late Producto producto;

    setUp(() {
      producto = Producto(
        id: 'TEST001',
        skuCode: 'TEST001',
        nombre: 'Cuaderno A4',
        presentaciones: [
          Presentacion(
            id: IdsPresentacion.unitario,
            skuCode: 'TEST001',
            name: 'Unidad',
            conversionFactor: 1,
            prices: [PuntoPrecio(type: TipoPrecio.normal, amount: 3.50)],
          ),
          Presentacion(
            id: IdsPresentacion.mayorista,
            skuCode: 'TEST001-MAYO',
            name: 'Mayorista',
            conversionFactor: 1,
            prices: [PuntoPrecio(type: TipoPrecio.normal, amount: 3.00)],
          ),
        ],
        estado: EstadoProducto.verificado,
      );
    });

    test('buscar presentación unitaria por ID constante', () {
      final pres = producto.presentaciones
          .firstWhere((p) => p.id == IdsPresentacion.unitario);
      expect(pres.name, 'Unidad');
    });

    test('obtener precio normal por constante', () {
      final pres = producto.presentaciones
          .firstWhere((p) => p.id == IdsPresentacion.unitario);
      final precio = pres.getPriceByType(TipoPrecio.normal);
      expect(precio, closeTo(3.50, 0.001));
    });

    test('estado verificado → esVendible es true', () {
      expect(EstadoProducto.esVendible(producto.estado), isTrue);
    });

    test('filtrar presentaciones dinámicas excluye las fijas', () {
      final dinamicas = producto.presentaciones
          .where((p) => !IdsPresentacion.esFija(p.id))
          .toList();
      expect(dinamicas, isEmpty); // Este producto no tiene dinámicas
    });

    test('precio base del producto desde presentacion unitaria', () {
      expect(producto.precioBase, closeTo(3.50, 0.001));
    });

    test('precio mayorista del producto desde presentacion mayo', () {
      expect(producto.precioMayorista, closeTo(3.00, 0.001));
    });
  });
}
