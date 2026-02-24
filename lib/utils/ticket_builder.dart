import '../models/producto.dart';
import 'precio_engine.dart';

class TicketBuilder {
  // Configuración de cabecera
  static const String tienda = 'BIPENC LIBRERÍA';
  static const String ruc = '10XXXXXXXXX';
  static const String slogan = 'Calidad y Servicio al Mejor Precio';
  static const String firma = 'BIPENC - Ing. Jhonatan Gamarra';

  // Comandos ESC/POS Raw para Hardware
  static const String escReset = '\x1B\x40';
  static const String escDoubleOn = '\x1B\x21\x30'; // Double Height + Double Width
  static const String escDoubleOff = '\x1B\x21\x00';
  static const String escBoldOn = '\x1B\x45\x01';
  static const String escBoldOff = '\x1B\x45\x00';

  /// Genera ticket de venta optimizado.
  static String buildVenta({
    required int ancho,
    required List<ItemCarrito> items,
    required double total,
    required String vendedor,
    required String correlativo,
    String? cliente,
    String? dniRuc,
    String tipo = 'TICKET',
  }) {
    final sb = StringBuffer();
    final now = DateTime.now();

    // Comandos ESC/POS iniciales (Reset + Titular Grande)
    sb.write(escReset);
    sb.writeln(escDoubleOn + _centrar(tienda, ancho) + escDoubleOff);
    sb.writeln(_centrar(slogan, ancho));
    sb.writeln(_centrar('RUC: $ruc', ancho));
    sb.writeln(_separador('=', ancho));
    
    sb.write(escBoldOn);
    sb.writeln(_centrar('$tipo DE VENTA', ancho));
    sb.writeln(_centrar(correlativo, ancho));
    sb.write(escBoldOff);
    sb.writeln(_separador('-', ancho));

    sb.writeln('FECHA: ${_formato(now)}');
    sb.writeln('VEND : $vendedor');
    if (cliente != null) sb.writeln('CLI  : ${cliente.toUpperCase()}');
    if (dniRuc != null)  sb.writeln('DNI  : $dniRuc');
    sb.writeln(_separador('-', ancho));

    // Cabecera de columnas
    sb.writeln(_columnas('DESCRIPCION', 'TOTAL', ancho));
    sb.writeln(_separador('-', ancho));

    for (final item in items) {
      final desc = '${item.cantidad} ${item.presentacion.nombre} ${item.producto.nombre}';
      final sub = 'S/${(item.precioActual * item.cantidad).toStringAsFixed(2)}';
      
      // Multi-línea para descripción si es larga
      if (desc.length > ancho - 10) {
        sb.writeln(desc);
        sb.writeln(' ' * (ancho - sub.length) + sub);
      } else {
        sb.writeln(_columnas(desc, sub, ancho));
      }
    }

    sb.writeln(_separador('=', ancho));
    
    final desglose = PrecioEngine.calcularDesgloseFiscal(total);
    sb.writeln(_columnas('SUBTOTAL (OPE.G):', 'S/${desglose.subtotal.toStringAsFixed(2)}', ancho));
    sb.writeln(_columnas('IGV (18%):', 'S/${desglose.igv.toStringAsFixed(2)}', ancho));
    
    // Total Resaltado
    sb.write(escBoldOn + escDoubleOn);
    sb.writeln(_columnas('TOTAL A PAGAR:', 'S/${total.toStringAsFixed(2)}', ancho));
    sb.write(escDoubleOff + escBoldOff);
    sb.writeln(_separador('=', ancho));

    sb.writeln('');
    sb.writeln(_centrar('¡GRACIAS POR SU PREFERENCIA!', ancho));
    sb.writeln(_centrar(firma, ancho));
    sb.writeln('\n\n\n'); // Espacio físico
    
    return sb.toString();
  }

  /// Genera ticket de cierre de caja (X/Z).
  static String buildCierre({
    required int ancho,
    required String tipo,
    required Map<String, double> ventas,
    required double total,
    required double ahorro,
    required DateTime fecha,
  }) {
    final sb = StringBuffer();
    sb.writeln(_centrar(tienda, ancho));
    sb.writeln(_centrar('REPORTE DE CIERRE $tipo', ancho));
    sb.writeln(_separador('=', ancho));
    sb.writeln('FECHA: ${_formato(fecha)}');
    sb.writeln(_separador('-', ancho));

    sb.writeln('VENTAS POR USUARIO:');
    ventas.forEach((user, monto) {
      sb.writeln(_columnas(user, 'S/${monto.toStringAsFixed(2)}', ancho));
    });

    sb.writeln(_separador('-', ancho));
    sb.writeln(_columnas('AHORRO REDONDEO:', 'S/${ahorro.toStringAsFixed(2)}', ancho));
    sb.writeln(_columnas('TOTAL CAJA:', 'S/${total.toStringAsFixed(2)}', ancho));
    sb.writeln(_separador('=', ancho));
    sb.writeln('\n\n\n');
    return sb.toString();
  }

  static String _centrar(String t, int a) {
    if (t.length >= a) return t.substring(0, a);
    final pad = (a - t.length) ~/ 2;
    return ' ' * pad + t;
  }

  static String _separador(String c, int a) => c * a;

  static String _columnas(String izq, String der, int a) {
    final gap = a - izq.length - der.length;
    if (gap <= 0) return '$izq $der';
    return izq + (' ' * gap) + der;
  }

  static String _formato(DateTime d) => 
      '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
}

