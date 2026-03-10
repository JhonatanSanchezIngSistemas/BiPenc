import 'dart:convert';

/// Modelo para tabla order_lists en Supabase
/// Representa una lista de pedidos de papel capturada como foto
class OrderList {
  final String id;
  final String clienteNombre;
  final double montoAdelantado;
  final DateTime fechaRecojo;
  final String estado; // 'PENDIENTE', 'EN_PROCESO', 'COMPLETADO', 'CANCELADO'
  final List<String> fotosUrls; // URLs de fotos en Storage
  final String? notas;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? vendedorId;
  final OrderListMeta meta;

  OrderList({
    required this.id,
    required this.clienteNombre,
    required this.montoAdelantado,
    required this.fechaRecojo,
    required this.estado,
    required this.fotosUrls,
    this.notas,
    required this.createdAt,
    this.updatedAt,
    this.vendedorId,
    this.meta = const OrderListMeta(),
  });

  /// Copia con campos actualizables
  OrderList copyWith({
    String? id,
    String? clienteNombre,
    double? montoAdelantado,
    DateTime? fechaRecojo,
    String? estado,
    List<String>? fotosUrls,
    String? notas,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? vendedorId,
    OrderListMeta? meta,
  }) {
    return OrderList(
      id: id ?? this.id,
      clienteNombre: clienteNombre ?? this.clienteNombre,
      montoAdelantado: montoAdelantado ?? this.montoAdelantado,
      fechaRecojo: fechaRecojo ?? this.fechaRecojo,
      estado: estado ?? this.estado,
      fotosUrls: fotosUrls ?? this.fotosUrls,
      notas: notas ?? this.notas,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      vendedorId: vendedorId ?? this.vendedorId,
      meta: meta ?? this.meta,
    );
  }

  /// Convierte desde JSON de Supabase
  factory OrderList.fromJson(Map<String, dynamic> json) {
    final rawNotas = json['notas'] as String?;
    final decoded = OrderListMetaCodec.decode(rawNotas);
    return OrderList(
      id: json['id'] as String,
      clienteNombre: json['cliente_nombre'] as String,
      montoAdelantado: (json['monto_adelantado'] as num).toDouble(),
      fechaRecojo: DateTime.parse(json['fecha_recojo'] as String),
      estado: json['estado'] as String,
      fotosUrls: List<String>.from(json['fotos_urls'] as List<dynamic>? ?? []),
      notas: decoded.$2,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      vendedorId: json['vendedor_id'] as String?,
      meta: decoded.$1,
    );
  }

  /// Convierte a JSON para Supabase
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cliente_nombre': clienteNombre,
      'monto_adelantado': montoAdelantado,
      'fecha_recojo': fechaRecojo.toIso8601String(),
      'estado': estado,
      'fotos_urls': fotosUrls,
      'notas': OrderListMetaCodec.encode(
        meta: meta,
        notas: notas,
      ),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'vendedor_id': vendedorId,
    };
  }

  String? get telefonoContacto => meta.telefono;
  String? get responsable => meta.responsable;
  double get totalLista => meta.totalLista ?? montoAdelantado;
  double get saldoPendiente {
    final saldo = totalLista - montoAdelantado;
    return saldo <= 0 ? 0 : saldo;
  }

  bool get estaCancelado => saldoPendiente <= 0;
  int get prioridadAtencion => estaCancelado ? 0 : 1;
  DateTime get llegadaAt => createdAt;

  @override
  String toString() => 'OrderList(id: $id, cliente: $clienteNombre, estado: $estado)';
}

class OrderListMeta {
  final String? telefono;
  final String? responsable;
  final double? totalLista;

  const OrderListMeta({
    this.telefono,
    this.responsable,
    this.totalLista,
  });

  Map<String, dynamic> toJson() {
    return {
      if (telefono != null && telefono!.isNotEmpty) 'telefono': telefono,
      if (responsable != null && responsable!.isNotEmpty) 'responsable': responsable,
      if (totalLista != null) 'total_lista': totalLista,
    };
  }

  factory OrderListMeta.fromJson(Map<String, dynamic> json) {
    return OrderListMeta(
      telefono: json['telefono']?.toString(),
      responsable: json['responsable']?.toString(),
      totalLista: json['total_lista'] == null
          ? null
          : double.tryParse(json['total_lista'].toString()),
    );
  }

  OrderListMeta copyWith({
    String? telefono,
    String? responsable,
    double? totalLista,
  }) {
    return OrderListMeta(
      telefono: telefono ?? this.telefono,
      responsable: responsable ?? this.responsable,
      totalLista: totalLista ?? this.totalLista,
    );
  }
}

class OrderListMetaCodec {
  static const _prefix = '__META__:';

  static String? encode({
    required OrderListMeta meta,
    String? notas,
  }) {
    final metaJson = meta.toJson();
    final plain = (notas ?? '').trim();
    if (metaJson.isEmpty) return plain.isEmpty ? null : plain;
    final encodedMeta = jsonEncode(metaJson);
    if (plain.isEmpty) return '$_prefix$encodedMeta';
    return '$_prefix$encodedMeta\n$plain';
  }

  static (OrderListMeta, String?) decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return (const OrderListMeta(), null);
    }
    final value = raw.trim();
    if (!value.startsWith(_prefix)) {
      return (const OrderListMeta(), value);
    }
    final lines = value.split('\n');
    final first = lines.first;
    final payload = first.substring(_prefix.length).trim();
    try {
      final parsed = jsonDecode(payload);
      if (parsed is Map<String, dynamic>) {
        final notes = lines.length > 1 ? lines.sublist(1).join('\n').trim() : null;
        return (
          OrderListMeta.fromJson(parsed),
          notes == null || notes.isEmpty ? null : notes,
        );
      }
    } catch (_) {}
    return (const OrderListMeta(), value);
  }
}
