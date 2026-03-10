import '../../features/pos/pos_provider.dart';

enum TipoComprobante { boleta, factura, notaVenta }

class Venta {
  final String id;
  final DateTime fecha;
  final TipoComprobante tipoComprobante;
  final String documentoCliente;
  final String? nombreCliente;
  final String? correlativo;
  final int? dbId;
  
  // Matemática SUNAT
  final double operacionGravada; // Subtotal sin IGV
  final double igv;              // 18%
  final double total;
  
  final List<ItemCarrito> items;
  
  // Seguimiento de despacho (Art 6.2)
  final bool despachado;
  final String serie;
  final MetodoPago metodoPago;
  final double montoRecibido;
  final bool synced;
  final double vuelto;

  Venta({
    required this.id,
    required this.fecha,
    required this.tipoComprobante,
    required this.documentoCliente,
    this.nombreCliente,
    this.correlativo,
    required this.operacionGravada,
    required this.igv,
    required this.total,
    this.serie = 'B001',
    required this.metodoPago,
    required this.montoRecibido,
    required this.vuelto,
    required this.items,
    this.dbId,
    this.despachado = false,
    this.synced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fecha': fecha.toIso8601String(),
      'tipoComprobante': tipoComprobante.name,
      'documentoCliente': documentoCliente,
      'nombreCliente': nombreCliente,
      'correlativo': correlativo,
      'operacionGravada': operacionGravada,
      'igv': igv,
      'total': total,
      'serie': serie,
      'metodoPago': metodoPago.name,
      'montoRecibido': montoRecibido,
      'vuelto': vuelto,
      'items': items.map((x) => x.toJson()).toList(),
      'despachado': despachado ? 1 : 0,
      'synced': synced ? 1 : 0,
    };
  }

  factory Venta.fromMap(Map<String, dynamic> map) {
    return Venta(
      id: map['id'],
      fecha: DateTime.parse(map['fecha']),
      tipoComprobante: TipoComprobante.values.firstWhere((e) => e.name == map['tipoComprobante']),
      documentoCliente: map['documentoCliente'],
      nombreCliente: map['nombreCliente'],
      correlativo: map['correlativo'],
      operacionGravada: (map['operacionGravada'] ?? 0.0).toDouble(),
      igv: (map['igv'] ?? 0.0).toDouble(),
      total: (map['total'] ?? 0.0).toDouble(),
      serie: map['serie'] ?? 'B001',
      metodoPago: MetodoPago.values.firstWhere((e) => e.name == map['metodoPago']),
      montoRecibido: (map['montoRecibido'] ?? 0.0).toDouble(),
      vuelto: (map['vuelto'] ?? 0.0).toDouble(),
      items: [], // Items se cargarán por separado
      dbId: map['dbId'] ?? map['id_local'], 
      despachado: (map['despachado'] ?? 0) == 1,
      synced: (map['synced'] ?? 0) == 1,
    );
  }

  Venta copyWith({
    String? id,
    DateTime? fecha,
    TipoComprobante? tipoComprobante,
    String? documentoCliente,
    String? nombreCliente,
    String? correlativo,
    double? operacionGravada,
    double? igv,
    double? total,
    List<ItemCarrito>? items,
    int? dbId,
    bool? despachado,
    String? serie,
    MetodoPago? metodoPago,
    double? montoRecibido,
    double? vuelto,
    bool? synced,
  }) {
    return Venta(
      id: id ?? this.id,
      fecha: fecha ?? this.fecha,
      tipoComprobante: tipoComprobante ?? this.tipoComprobante,
      documentoCliente: documentoCliente ?? this.documentoCliente,
      nombreCliente: nombreCliente ?? this.nombreCliente,
      correlativo: correlativo ?? this.correlativo,
      operacionGravada: operacionGravada ?? this.operacionGravada,
      igv: igv ?? this.igv,
      total: total ?? this.total,
      items: items ?? this.items,
      dbId: dbId ?? this.dbId,
      despachado: despachado ?? this.despachado,
      serie: serie ?? this.serie,
      metodoPago: metodoPago ?? this.metodoPago,
      montoRecibido: montoRecibido ?? this.montoRecibido,
      vuelto: vuelto ?? this.vuelto,
      synced: synced ?? this.synced,
    );
  }
}
