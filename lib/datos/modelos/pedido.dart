import 'dart:convert';

/// Modelo para tabla order_lists en Supabase
/// Representa una lista de pedidos de papel capturada como foto
class Pedido {
  final String id;
  final String? aliasVendedor;
  final String clienteNombre;
  final String? clienteTelefono;
  final double montoAdelantado;
  final double? totalEstimado;
  final DateTime fechaRecojo;
  final String estado; // 'PENDIENTE', 'LISTO', 'ENTREGADO', 'CANCELADO'
  final List<String> fotosUrls; // URLs de fotos en Storage
  final List<Map<String, dynamic>> items;
  final String? notas;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? correlativoComprobante;
  final PedidoMeta meta;

  Pedido({
    required this.id,
    this.aliasVendedor,
    required this.clienteNombre,
    this.clienteTelefono,
    required this.montoAdelantado,
    this.totalEstimado,
    required this.fechaRecojo,
    required this.estado,
    required this.fotosUrls,
    this.items = const [],
    this.notas,
    required this.createdAt,
    this.updatedAt,
    this.correlativoComprobante,
    this.meta = const PedidoMeta(),
  });

  /// Copia con campos actualizables
  Pedido copyWith({
    String? id,
    String? aliasVendedor,
    String? clienteNombre,
    String? clienteTelefono,
    double? montoAdelantado,
    double? totalEstimado,
    DateTime? fechaRecojo,
    String? estado,
    List<String>? fotosUrls,
    List<Map<String, dynamic>>? items,
    String? notas,
    DateTime? createdAt,
    DateTime? updatedAt,
    PedidoMeta? meta,
  }) {
    return Pedido(
      id: id ?? this.id,
      aliasVendedor: aliasVendedor ?? this.aliasVendedor,
      clienteNombre: clienteNombre ?? this.clienteNombre,
      clienteTelefono: clienteTelefono ?? this.clienteTelefono,
      montoAdelantado: montoAdelantado ?? this.montoAdelantado,
      totalEstimado: totalEstimado ?? this.totalEstimado,
      fechaRecojo: fechaRecojo ?? this.fechaRecojo,
      estado: estado ?? this.estado,
      fotosUrls: fotosUrls ?? this.fotosUrls,
      items: items ?? this.items,
      notas: notas ?? this.notas,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      meta: meta ?? this.meta,
    );
  }

  /// Convierte desde JSON de Supabase
  factory Pedido.fromJson(Map<String, dynamic> json) {
    final rawNotas = json['notas'] as String?;
    final decoded = PedidoMetaCodec.decode(rawNotas);
    final totalEstimado = (json['total_estimado'] as num?)?.toDouble();
    final meta = (decoded.$1.totalLista == null && totalEstimado != null)
        ? decoded.$1.copyWith(totalLista: totalEstimado)
        : decoded.$1;
    final fecha = json['fecha_recojo'];
    return Pedido(
      id: json['id'].toString(),
      aliasVendedor: json['alias_vendedor']?.toString(),
      clienteNombre: json['cliente_nombre'] as String,
      clienteTelefono: json['cliente_telefono']?.toString(),
      montoAdelantado: (json['monto_adelantado'] as num).toDouble(),
      totalEstimado: totalEstimado,
      fechaRecojo: fecha is String
          ? DateTime.parse(fecha)
          : DateTime.fromMillisecondsSinceEpoch(fecha as int),
      estado: json['estado'] as String,
      fotosUrls: List<String>.from(json['fotos_urls'] as List<dynamic>? ?? []),
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      notas: decoded.$2,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      correlativoComprobante: json['correlativo_comprobante']?.toString(),
      meta: meta,
    );
  }

  /// Convierte a JSON para Supabase
  Map<String, dynamic> toJson() {
    return {
      // id es opcional porque Supabase tiene DEFAULT uuid
      if (id.isNotEmpty) 'id': id,
      'alias_vendedor': aliasVendedor,
      'cliente_nombre': clienteNombre,
      'cliente_telefono': clienteTelefono,
      'monto_adelantado': montoAdelantado,
      'total_estimado': totalEstimado ?? meta.totalLista ?? montoAdelantado,
      'fecha_recojo': fechaRecojo.toIso8601String(),
      'estado': estado,
      'fotos_urls': fotosUrls,
      'items': items,
      'notas': PedidoMetaCodec.encode(
        meta: meta,
        notas: notas,
      ),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'correlativo_comprobante': correlativoComprobante,
    };
  }

  String? get telefonoContacto => meta.telefono ?? clienteTelefono;
  String? get responsable => meta.responsable ?? aliasVendedor;
  double get totalLista => meta.totalLista ?? totalEstimado ?? montoAdelantado;
  double get saldoPendiente {
    final saldo = totalLista - montoAdelantado;
    return saldo <= 0 ? 0 : saldo;
  }
  int get bultos => meta.bultos ?? 0;

  bool get estaCancelado => saldoPendiente <= 0;
  int get prioridadAtencion => estaCancelado ? 0 : 1;
  DateTime get llegadaAt => createdAt;

  @override
  String toString() => 'Pedido(id: $id, cliente: $clienteNombre, estado: $estado)';
}

class PedidoMeta {
  final String? telefono;
  final String? responsable;
  final double? totalLista;
  final int? bultos;
  final String? destinatario; // 'NIÑO', 'NIÑA', u otro

  const PedidoMeta({
    this.telefono,
    this.responsable,
    this.totalLista,
    this.bultos,
    this.destinatario,
  });

  Map<String, dynamic> toJson() {
    return {
      if (telefono != null && telefono!.isNotEmpty) 'telefono': telefono,
      if (responsable != null && responsable!.isNotEmpty) 'responsable': responsable,
      if (totalLista != null) 'total_lista': totalLista,
      if (bultos != null) 'bultos': bultos,
      if (destinatario != null && destinatario!.isNotEmpty) 'destinatario': destinatario,
    };
  }

  factory PedidoMeta.fromJson(Map<String, dynamic> json) {
    return PedidoMeta(
      telefono: json['telefono']?.toString(),
      responsable: json['responsable']?.toString(),
      totalLista: json['total_lista'] == null
          ? null
          : double.tryParse(json['total_lista'].toString()),
      bultos: json['bultos'] == null
          ? null
          : int.tryParse(json['bultos'].toString()),
      destinatario: json['destinatario']?.toString(),
    );
  }

  PedidoMeta copyWith({
    String? telefono,
    String? responsable,
    double? totalLista,
    int? bultos,
    String? destinatario,
  }) {
    return PedidoMeta(
      telefono: telefono ?? this.telefono,
      responsable: responsable ?? this.responsable,
      totalLista: totalLista ?? this.totalLista,
      bultos: bultos ?? this.bultos,
      destinatario: destinatario ?? this.destinatario,
    );
  }
}

class PedidoMetaCodec {
  static const _prefix = '__META__:';

  static String? encode({
    required PedidoMeta meta,
    String? notas,
  }) {
    final metaJson = meta.toJson();
    final plain = (notas ?? '').trim();
    if (metaJson.isEmpty) return plain.isEmpty ? null : plain;
    final encodedMeta = jsonEncode(metaJson);
    if (plain.isEmpty) return '$_prefix$encodedMeta';
    return '$_prefix$encodedMeta\n$plain';
  }

  static (PedidoMeta, String?) decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return (const PedidoMeta(), null);
    }
    final value = raw.trim();
    if (!value.startsWith(_prefix)) {
      return (const PedidoMeta(), value);
    }
    final lines = value.split('\n');
    final first = lines.first;
    final payload = first.substring(_prefix.length).trim();
    try {
      final parsed = jsonDecode(payload);
      if (parsed is Map<String, dynamic>) {
        final notes = lines.length > 1 ? lines.sublist(1).join('\n').trim() : null;
        return (
          PedidoMeta.fromJson(parsed),
          notes == null || notes.isEmpty ? null : notes,
        );
      }
    } catch (_) {}
    return (const PedidoMeta(), value);
  }
}
