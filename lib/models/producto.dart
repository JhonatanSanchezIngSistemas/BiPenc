class Presentacion {
  final String id;
  final String nombre;
  final int factor;
  final double precio;
  final String? codigoBarras;

  const Presentacion({
    required this.id,
    required this.nombre,
    required this.factor,
    required this.precio,
    this.codigoBarras,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombre': nombre,
    'factor': factor,
    'precio': precio,
    'codigo_barras': codigoBarras,
  };

  factory Presentacion.fromJson(Map<String, dynamic> json) => Presentacion(
    id: json['id'] ?? 'unid',
    nombre: json['nombre'] ?? 'Unidad',
    factor: json['factor'] ?? 1,
    precio: (json['precio'] ?? 0).toDouble(),
    codigoBarras: json['codigo_barras'],
  );

  Presentacion copyWith({
    String? id,
    String? nombre,
    int? factor,
    double? precio,
    String? codigoBarras,
  }) =>
      Presentacion(
        id: id ?? this.id,
        nombre: nombre ?? this.nombre,
        factor: factor ?? this.factor,
        precio: precio ?? this.precio,
        codigoBarras: codigoBarras ?? this.codigoBarras,
      );

  // Presentaciones estándar reutilizables
  static const unidad = Presentacion(id: 'unid', nombre: 'Unidad', factor: 1, precio: 0);
  static const mayorista = Presentacion(id: 'mayo', nombre: 'Mayorista', factor: 1, precio: 0);
  static const caja12 = Presentacion(id: 'c12', nombre: 'Caja x12', factor: 12, precio: 0);
  static const caja72 = Presentacion(id: 'c72', nombre: 'Caja x72', factor: 72, precio: 0);
}

class Producto {
  final String id;
  final String nombre;
  final String marca;
  final String categoria;
  final List<Presentacion> presentaciones;
  final String? imagenPath;
  final String estado;
  final String? creadoPor;
  final DateTime? updatedAt;

  const Producto({
    required this.id,
    required this.nombre,
    required this.marca,
    required this.categoria,
    this.presentaciones = const [],
    this.imagenPath,
    this.estado = 'PENDIENTE',
    this.creadoPor,
    this.updatedAt,
  });

  Producto copyWith({
    String? id,
    String? nombre,
    String? marca,
    String? categoria,
    List<Presentacion>? presentaciones,
    String? imagenPath,
    String? estado,
    String? creadoPor,
    DateTime? updatedAt,
  }) =>
      Producto(
        id: id ?? this.id,
        nombre: nombre ?? this.nombre,
        marca: marca ?? this.marca,
        categoria: categoria ?? this.categoria,
        presentaciones: presentaciones ?? this.presentaciones,
        imagenPath: imagenPath ?? this.imagenPath,
        estado: estado ?? this.estado,
        creadoPor: creadoPor ?? this.creadoPor,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  // ── Getters de compatibilidad retroactiva ──

  double get precioBase {
    try {
      return presentaciones.firstWhere((p) => p.id == 'unid').precio;
    } catch (_) {
      return 0.0;
    }
  }

  double get precioMayorista {
    try {
      return presentaciones.firstWhere((p) => p.id == 'mayo').precio;
    } catch (_) {
      return precioBase;
    }
  }

  double getPrecioPresentacion(String idPres) {
    try {
      return presentaciones.firstWhere((p) => p.id == idPres).precio;
    } catch (_) {
      return 0.0;
    }
  }

  String? get codigoBarrasBase {
    try {
      return presentaciones.firstWhere((p) => p.id == 'unid').codigoBarras;
    } catch (_) {
      return null;
    }
  }
}

// ──────────────────────────────────────────────
// Categorías predefinidas del catálogo
// ──────────────────────────────────────────────

class CategoriasProducto {
  CategoriasProducto._();

  static const List<String> lista = [
    'Cuadernos',
    'Lapiceros',
    'Arte',
    'Útiles',
    'Papelería',
    'Mochilas',
    'Tecnología',
    'Otros',
  ];
}

// ──────────────────────────────────────────────
// Perfil de usuario con roles expandidos
// ──────────────────────────────────────────────

class Perfil {
  final String id;
  final String nombre;
  final String apellido;
  final String alias;

  /// Roles disponibles: 'SERVER', 'ADMIN', 'VENTAS'
  final String rol;
  final String? deviceId;

  const Perfil({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.alias,
    required this.rol,
    this.deviceId,
  });

  String get nombreCompleto => '$nombre $apellido';

  bool get esServer => rol == 'SERVER';
  bool get esAdmin => rol == 'ADMIN';
  bool get esVentas => rol == 'VENTAS';

  /// Puede crear y editar productos
  bool get puedeGestionarProductos => esServer || esAdmin;

  /// Puede acceder a módulo de auditoría
  bool get puedeAuditar => esServer || esAdmin;
}

// ──────────────────────────────────────────────
// Ítem del carrito
// ──────────────────────────────────────────────

class ItemCarrito {
  final Producto producto;
  int cantidad;
  double? precioEditado;
  Presentacion presentacion;

  ItemCarrito({
    required this.producto,
    this.cantidad = 1,
    this.precioEditado,
    Presentacion? presentacion,
  }) : presentacion = presentacion ?? Presentacion.unidad;

  /// Precio efectivo según presentación y cualquier edición manual.
  double get precioActual {
    if (precioEditado != null) return precioEditado!;

    final pArray = producto.presentaciones.where((p) => p.id == presentacion.id);
    if (pArray.isNotEmpty && pArray.first.precio > 0) {
      return pArray.first.precio;
    }

    // Fallback al precio base si la presentación no tiene precio definido
    return producto.precioBase;
  }

  /// Unidades individuales totales de este ítem.
  int get unidadesTotales => cantidad * presentacion.factor;

  /// Precio original sin edición (precio unitario de la unidad base).
  double get precioOriginal => producto.precioBase * presentacion.factor;

  /// Subtotal de este ítem.
  double get subtotal => precioActual * cantidad;

  /// Ahorro vs precio original.
  double get ahorroPorUnidad {
    final original = producto.precioBase * presentacion.factor;
    return (original - precioActual).clamp(0.0, double.infinity);
  }

  double get ahorroTotal => ahorroPorUnidad * cantidad;

  bool get tieneDescuento => precioActual < (producto.precioBase * presentacion.factor);
}
