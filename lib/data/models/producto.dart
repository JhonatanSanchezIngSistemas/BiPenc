import 'presentation.dart';

/// Alias retrocompatible para Presentation
typedef Presentacion = Presentation;

/// Producto o artículo en el inventario
/// Estructura senior que soporta múltiples presentaciones y variantes
class Producto {
  final String id;
  final String skuCode;
  final String nombre;
  final String marca;
  final String categoria;
  final String? descripcion;
  final List<Presentation> presentaciones;
  final String? imagenPath;
  final String estado; // 'ACTIVO', 'DESCONTINUADO'
  final String? creadoPor;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final double? precioPropuesto;
  final bool isActive;
  final DateTime? lastSyncTimestamp;
  final int localVersion;
  final String? syncHash;

  Producto({
    required this.id,
    required this.skuCode,
    required this.nombre,
    this.marca = '',
    this.categoria = '',
    this.descripcion,
    this.presentaciones = const [],
    this.imagenPath,
    this.estado = 'ACTIVO',
    this.creadoPor,
    this.createdAt,
    this.updatedAt,
    this.precioPropuesto,
    this.isActive = true,
    this.lastSyncTimestamp,
    this.localVersion = 0,
    this.syncHash,
  });

  /// Factory from JSON/Supabase
  factory Producto.fromJson(Map<String, dynamic> json) {
    return Producto(
      id: json['id'] ?? '',
      skuCode: json['sku_code'] ?? json['skuCode'] ?? '',
      nombre: json['name'] ?? json['nombre'] ?? '',
      marca: json['brand'] ?? json['marca'] ?? '',
      categoria: json['category'] ?? json['categoria'] ?? '',
      descripcion: json['description'] ?? json['descripcion'],
      presentaciones: json['presentations'] != null
          ? (json['presentations'] as List)
              .map((p) => Presentation.fromJson(p))
              .toList()
          : [],
      imagenPath: json['image_url'],
      estado: json['state'] ?? 'ACTIVO',
      creadoPor: json['created_by'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      precioPropuesto: json['proposed_price']?.toDouble(),
      isActive: json['is_active'] ?? true,
      lastSyncTimestamp: json['last_sync_timestamp'] != null
          ? DateTime.parse(json['last_sync_timestamp'])
          : null,
      localVersion: json['local_version'] ?? 0,
      syncHash: json['sync_hash'],
    );
  }

  /// Convert to Map for Supabase
  Map<String, dynamic> toJson() => {
        'id': id,
        'sku_code': skuCode,
        'name': nombre,
        'brand': marca,
        'category': categoria,
        'description': descripcion,
        'presentations': presentaciones.map((p) => p.toJson()).toList(),
        'image_url': imagenPath,
        'state': estado,
        'created_by': creadoPor,
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
        'proposed_price': precioPropuesto,
        'is_active': isActive,
        'last_sync_timestamp': lastSyncTimestamp?.toIso8601String(),
        'local_version': localVersion,
        'sync_hash': syncHash,
      };

  Producto copyWith({
    String? id,
    String? skuCode,
    String? nombre,
    String? marca,
    String? categoria,
    String? descripcion,
    List<Presentation>? presentaciones,
    String? imagenPath,
    String? estado,
    String? creadoPor,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? precioPropuesto,
    bool? isActive,
    DateTime? lastSyncTimestamp,
    int? localVersion,
    String? syncHash,
  }) {
    return Producto(
      id: id ?? this.id,
      skuCode: skuCode ?? this.skuCode,
      nombre: nombre ?? this.nombre,
      marca: marca ?? this.marca,
      categoria: categoria ?? this.categoria,
      descripcion: descripcion ?? this.descripcion,
      presentaciones: presentaciones ?? this.presentaciones,
      imagenPath: imagenPath ?? this.imagenPath,
      estado: estado ?? this.estado,
      creadoPor: creadoPor ?? this.creadoPor,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      precioPropuesto: precioPropuesto ?? this.precioPropuesto,
      isActive: isActive ?? this.isActive,
      lastSyncTimestamp: lastSyncTimestamp ?? this.lastSyncTimestamp,
      localVersion: localVersion ?? this.localVersion,
      syncHash: syncHash ?? this.syncHash,
    );
  }

  // Helpers para lógica de precio
  double _precioPorTipo(String type) {
    if (presentaciones.isEmpty) return 0.0;
    for (final p in presentaciones) {
      for (final price in p.prices) {
        if (price.type == type) return price.amount;
      }
    }
    return presentaciones.first.getPriceByType('NORMAL');
  }

  double get precioBase => _precioPorTipo('NORMAL');
  double get precioMayorista => _precioPorTipo('WHOLESALE');
  double get precioEspecial => _precioPorTipo('SPECIAL');

  double getPrecioPresentacion(String presentationId,
      [String priceType = 'NORMAL']) {
    if (presentaciones.isEmpty) return 0.0;
    final p = presentaciones.firstWhere(
      (e) => e.id == presentationId,
      orElse: () => presentaciones.first,
    );
    return p.getPriceByType(priceType);
  }

  /// Soft delete - marca como inactivo
  Producto softDelete() {
    return copyWith(isActive: false, estado: 'DESCONTINUADO');
  }

  @override
  String toString() => 'Producto($skuCode: $nombre)';
}

/// Item en el carrito de compras - incluye override de precio
class ItemCarrito {
  final Producto producto;
  final Presentation presentacion;
  int cantidad;
  double?
      manualPriceOverride; // Permite override del precio por decisión del vendedor
  bool manualPriceLocked; // true si el usuario editó manualmente el precio
  bool despachado;
  final DateTime? addedAt;
  final String
      afectacionIgv; // SUNAT Catálogo 07: 10=Gravado, 20=Exonerado, 30=Inafecto

  ItemCarrito({
    required this.producto,
    required this.presentacion,
    this.cantidad = 1,
    this.manualPriceOverride,
    this.manualPriceLocked = false,
    this.despachado = false,
    this.addedAt,
    this.afectacionIgv = '10',
  });

  /// Precio actual (override si existe, sino del precio normal)
  double get precioActual =>
      manualPriceOverride ?? presentacion.getPriceByType('NORMAL');

  /// Subtotal del item
  double get subtotal => precioActual * cantidad;

  /// Unidades totales convertidas a base
  int get unidadesTotales => (cantidad * presentacion.conversionFactor).toInt();

  /// Label del tipo de precio actual
  String get etiquetaPrecio {
    if (manualPriceOverride != null) return 'OVERRIDE';
    String priceType = presentacion.prices.isNotEmpty
        ? presentacion.prices.first.type
        : 'NORMAL';
    return priceType;
  }

  /// Toggle entre precios disponibles (normal <-> mayorista)
  void togglePriceType([String? targetType]) {
    if (presentacion.prices.isEmpty) return;

    if (targetType != null) {
      manualPriceOverride = null; // Clear override when switching types
      // Validation: targetType must exist in prices
      if (presentacion.prices.any((p) => p.type == targetType)) {
        presentacion.getPriceByType(targetType);
      }
    } else {
      manualPriceOverride = null; // Clear on toggle
    }
  }

  /// Set manual price override
  void setPriceOverride(double newPrice) {
    manualPriceOverride = newPrice;
    manualPriceLocked = true;
  }

  /// Set de precio automático (no bloquea futuras reglas de volumen)
  void setAutoPriceOverride(double? newPrice) {
    manualPriceOverride = newPrice;
    manualPriceLocked = false;
  }

  /// Clear manual override
  void clearPriceOverride() {
    manualPriceOverride = null;
    manualPriceLocked = false;
  }

  /// Serializable para persistencia/transmisión
  Map<String, dynamic> toJson() => {
        'producto_id': producto.id,
        'producto_nombre': producto.nombre,
        'presentacion_id': presentacion.id,
        'presentacion_nombre': presentacion.name,
        'cantidad': cantidad,
        'precio_normal': presentacion.getPriceByType('NORMAL'),
        'precio_override': manualPriceOverride,
        'precio_lock_manual': manualPriceLocked,
        'subtotal': subtotal,
        'despachado': despachado,
        'added_at': addedAt?.toIso8601String(),
        'afectacion_igv': afectacionIgv,
      };

  /// Factory from stored JSON (requires separate Producto instance)
  factory ItemCarrito.fromJson(Map<String, dynamic> json) {
    final productoNombre = (json['producto_nombre'] ??
            json['nombre'] ??
            json['productoName'] ??
            json['name'] ??
            '')
        .toString()
        .trim();
    final productoId = (json['producto_id'] ?? json['id'] ?? '').toString();
    final presentacionNombre = (json['presentacion_nombre'] ??
            json['presentacion'] ??
            json['presentation_name'] ??
            'Unitario')
        .toString()
        .trim();
    final normalPrice =
        (json['precio_normal'] ?? json['precio'] ?? json['price'] ?? 0.0);

    // This constructor is called when we don't have the full Producto object
    // Create a minimal stub producto for compatibility
    final stubProducto = Producto(
      id: productoId,
      skuCode: productoId,
      nombre: productoNombre.isEmpty ? 'PRODUCTO SIN NOMBRE' : productoNombre,
      presentaciones: [],
    );

    final stubPresentacion = Presentation(
      id: json['presentacion_id'] ?? 'unid',
      skuCode: productoId,
      name: presentacionNombre.isEmpty ? 'Unitario' : presentacionNombre,
      conversionFactor: 1.0,
      prices: [
        PricePoint(type: 'NORMAL', amount: (normalPrice as num).toDouble())
      ],
    );

    return ItemCarrito(
      producto: stubProducto,
      presentacion: stubPresentacion,
      cantidad: json['cantidad'] ?? 1,
      manualPriceOverride: json['precio_override']?.toDouble(),
      manualPriceLocked: json['precio_lock_manual'] == true,
      despachado: json['despachado'] ?? false,
      addedAt:
          json['added_at'] != null ? DateTime.parse(json['added_at']) : null,
    );
  }

  /// Factory from stored JSON (requires Producto instance)
  factory ItemCarrito.fromJsonWithProducto(
      Map<String, dynamic> json, Producto producto) {
    return ItemCarrito(
      producto: producto,
      presentacion: producto.presentaciones.isNotEmpty
          ? producto.presentaciones.first
          : Presentation.unit,
      cantidad: json['cantidad'] ?? 1,
      manualPriceOverride: json['precio_override']?.toDouble(),
      manualPriceLocked: json['precio_lock_manual'] == true,
      despachado: json['despachado'] ?? false,
      addedAt:
          json['added_at'] != null ? DateTime.parse(json['added_at']) : null,
    );
  }

  @override
  String toString() =>
      'ItemCarrito(${producto.nombre} x$cantidad @ \$$precioActual = \$$subtotal)';
}

class Perfil {
  final String id;
  final String nombre;
  final String apellido;
  final String alias;
  final String rol;
  final String? deviceId;

  Perfil({
    required this.id,
    required this.nombre,
    this.apellido = '',
    this.alias = '',
    this.rol = 'VENTAS',
    this.deviceId,
  });

  String get nombreCompleto =>
      '$nombre${apellido.isNotEmpty ? ' $apellido' : ''}';
}
