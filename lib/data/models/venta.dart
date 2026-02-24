import '../../features/pos/pos_provider.dart';

class Venta {
  final String id;
  final DateTime fecha;
  final double total;
  final MetodoPago metodoPago;
  final double montoRecibido;
  final double vuelto;
  
  // Resumen en texto para fácil impresión posterior
  final String resumenItems;

  Venta({
    required this.id,
    required this.fecha,
    required this.total,
    required this.metodoPago,
    required this.montoRecibido,
    required this.vuelto,
    required this.resumenItems,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fecha': fecha.toIso8601String(),
      'total': total,
      'metodoPago': metodoPago.name,
      'montoRecibido': montoRecibido,
      'vuelto': vuelto,
      'resumenItems': resumenItems,
    };
  }

  factory Venta.fromMap(Map<String, dynamic> map) {
    return Venta(
      id: map['id'],
      fecha: DateTime.parse(map['fecha']),
      total: map['total'],
      metodoPago: MetodoPago.values.firstWhere((e) => e.name == map['metodoPago']),
      montoRecibido: map['montoRecibido'],
      vuelto: map['vuelto'],
      resumenItems: map['resumenItems'],
    );
  }
}
