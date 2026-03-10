/// Representa un atributo de una presentación (ej: color, tamaño)
class PresentationAttribute {
  final String key;
  final String value;

  PresentationAttribute({required this.key, required this.value});

  factory PresentationAttribute.fromJson(Map<String, dynamic> json) {
    return PresentationAttribute(
      key: json['key'] ?? '',
      value: json['value'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'key': key, 'value': value};
}

/// Precio en un contexto específico (normal, mayorista, especial)
class PricePoint {
  final String type; // 'NORMAL', 'WHOLESALE', 'SPECIAL'
  final double amount;
  final String? description;

  PricePoint({
    required this.type,
    required this.amount,
    this.description,
  });

  factory PricePoint.fromJson(Map<String, dynamic> json) {
    return PricePoint(
      type: json['type'] ?? 'NORMAL',
      amount: (json['amount'] ?? 0).toDouble(),
      description: json['description'],
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'amount': amount,
    'description': description,
  };

  @override
  String toString() => '$type: \$$amount';
}

/// Presentación/Variante de un producto
/// Representa diferentes unidades de venta con sus precios
/// Ej: UNIDAD, CAJA, PACK, DOCENA
class Presentation {
  final String id;
  final String skuCode;
  final String name;
  final double conversionFactor; // Cuántas unidades base hay en esta presentación
  final String? parentId; // ID de la presentación padre para conversiones
  final List<PricePoint> prices; // [normal, wholesale, special]
  final List<PresentationAttribute> attributes; // [color, tamaño, etc]
  final String? barcode;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Presentation({
    required this.id,
    required this.skuCode,
    required this.name,
    required this.conversionFactor,
    this.parentId,
    this.prices = const [],
    this.attributes = const [],
    this.barcode,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  /// Factory constructor from JSON/Map (Supabase compatible)
  factory Presentation.fromJson(Map<String, dynamic> json) {
    return Presentation(
      id: json['id'] ?? '',
      skuCode: json['sku_code'] ?? json['skuCode'] ?? '',
      name: json['name'] ?? json['nombre'] ?? '',
      conversionFactor: (json['conversion_factor'] ?? json['factor'] ?? 1).toDouble(),
      parentId: json['parent_id'],
      prices: json['prices'] != null
          ? (json['prices'] as List).map((p) => PricePoint.fromJson(p)).toList()
          : [],
      attributes: json['attributes'] != null
          ? (json['attributes'] as List)
              .map((a) => PresentationAttribute.fromJson(a))
              .toList()
          : [],
      barcode: json['barcode'] ?? json['codigo_barras']?.toString(),
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
    );
  }

  /// Convert to Map for Supabase storage
  Map<String, dynamic> toJson() => {
    'id': id,
    'sku_code': skuCode,
    'name': name,
    'conversion_factor': conversionFactor,
    'parent_id': parentId,
    'prices': prices.map((p) => p.toJson()).toList(),
    'attributes': attributes.map((a) => a.toJson()).toList(),
    'barcode': barcode,
    'is_active': isActive,
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };

  /// Get price by type (with fallback to normal)
  double getPriceByType(String type) {
    try {
      return prices.firstWhere((p) => p.type == type).amount;
    } catch (e) {
      // Fallback to NORMAL if type not found
      return prices.isNotEmpty
          ? prices.firstWhere((p) => p.type == 'NORMAL', orElse: () => prices.first).amount
          : 0.0;
    }
  }

  /// Get all price points as convenient map
  Map<String, double> getAllPrices() {
    return {
      for (var p in prices) p.type: p.amount,
    };
  }

  /// Get attribute value
  String? getAttributeValue(String key) {
    try {
      return attributes.firstWhere((a) => a.key == key).value;
    } catch (e) {
      return null;
    }
  }

  /// Create a copy with modified fields
  Presentation copyWith({
    String? id,
    String? skuCode,
    String? name,
    double? conversionFactor,
    String? parentId,
    List<PricePoint>? prices,
    List<PresentationAttribute>? attributes,
    String? barcode,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Presentation(
      id: id ?? this.id,
      skuCode: skuCode ?? this.skuCode,
      name: name ?? this.name,
      conversionFactor: conversionFactor ?? this.conversionFactor,
      parentId: parentId ?? this.parentId,
      prices: prices ?? this.prices,
      attributes: attributes ?? this.attributes,
      barcode: barcode ?? this.barcode,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Standard unit presentation (1:1 ratio, no attributes)
  static Presentation get unit => Presentation(
    id: 'unit',
    skuCode: 'UNIT-001',
    name: 'UNIDAD',
    conversionFactor: 1.0,
    prices: [PricePoint(type: 'NORMAL', amount: 0.0)],
  );

  @override
  String toString() => 'Presentation($skuCode: $name @ $conversionFactor x ${getPriceByType("NORMAL")})';
}
