import 'package:bipenc/data/models/presentation.dart';
import 'package:bipenc/features/pos/pos_provider.dart';
import 'package:bipenc/services/print_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PrintService formato ticket', () {
    test('formatea fecha como dd/MM/yyyy HH:mm', () {
      final formatted = PrintService.formatFechaTicket(
        DateTime(2026, 3, 9, 14, 5),
      );
      expect(formatted, '09/03/2026 14:05');
    });

    test('preview incluye correlativo, cliente, totales y QR', () {
      final producto = Producto(
        id: 'SKU-1',
        skuCode: 'SKU-1',
        nombre: 'Lapicero',
        presentaciones: [
          Presentacion(
            id: 'unid',
            skuCode: 'SKU-1',
            name: 'Unidad',
            conversionFactor: 1,
            prices: [PricePoint(type: 'NORMAL', amount: 5.00)],
          ),
        ],
      );
      final item = ItemCarrito(
        producto: producto,
        presentacion: producto.presentaciones.first,
        cantidad: 2,
      );

      final preview = PrintService.buildTicketPreview(
        items: [item],
        total: 10.00,
        subtotalSinIgv: 8.47,
        igvValue: 1.53,
        serie: 'B001',
        correlativo: 'B001-000123',
        cliente: 'Ana Perez',
        dniRuc: '12345678',
        tipo: 'BOLETA ELECTRÓNICA',
        vendedor: 'ANA',
        metodoPago: 'efectivo',
        montoRecibido: 20.00,
        vuelto: 10.00,
        fechaVenta: DateTime(2026, 3, 9, 18, 45),
      );

      expect(preview, contains('09/03/2026 18:45'));
      expect(preview, contains('BOLETA ELECTRÓNICA'));
      expect(preview, contains('B001-000123'));
      expect(preview, contains('Cliente: ANA PEREZ'));
      expect(preview, contains('DNI: 12345678'));
      expect(preview, contains('Atendido: ANA'));
      expect(preview, contains('Pago: EFECTIVO'));
      expect(preview, contains('Subtotal: 8.47'));
      expect(preview, contains('IGV: 1.53'));
      expect(preview, contains('Recibido: 20.00'));
      expect(preview, contains('Vuelto: 10.00'));
      expect(preview, contains('TOTAL: 10.00'));
      expect(preview, contains('QR: SI'));
    });

    test('preview no imprime vuelto para métodos no efectivos', () {
      final preview = PrintService.buildTicketPreview(
        items: const [],
        total: 25.00,
        serie: 'B001',
        correlativo: 'B001-000456',
        metodoPago: 'tarjeta',
      );

      expect(preview, contains('Pago: TARJETA'));
      expect(preview, isNot(contains('Recibido:')));
      expect(preview, isNot(contains('Vuelto:')));
    });

    test('layout de item no desborda en 80mm', () {
      final lines = PrintService.buildItemPreviewLines(
        nombre:
            'Cuaderno Profesional Cuadriculado A4 Tapa Dura Super Resistente 200 Hojas',
        cantidad: 12,
        precioUnitario: 7.50,
        subtotal: 90.00,
        lineWidth: 48,
        is80mm: true,
      );

      expect(lines, isNotEmpty);
      for (final line in lines) {
        expect(line.length <= 48, isTrue, reason: 'Linea desbordada: "$line"');
      }
    });

    test('layout de item no desborda en 58mm', () {
      final lines = PrintService.buildItemPreviewLines(
        nombre: 'Lapicero tinta gel punta fina color azul marino premium',
        cantidad: 3,
        precioUnitario: 2.90,
        subtotal: 8.70,
        lineWidth: 32,
        is80mm: false,
      );

      expect(lines, isNotEmpty);
      for (final line in lines) {
        expect(line.length <= 32, isTrue, reason: 'Linea desbordada: "$line"');
      }
    });

    test('wrap para ticket respeta ancho máximo', () {
      final wrapped = PrintService.wrapForTicket(
        'Direccion muy larga con referencia costado del mercado central puerta numero 4',
        32,
      );
      expect(wrapped, isNotEmpty);
      for (final line in wrapped) {
        expect(line.length <= 32, isTrue,
            reason: 'Wrap fuera de rango: "$line"');
      }
    });
  });
}
