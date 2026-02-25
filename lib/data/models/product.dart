/// Modelo de Producto con nuevo esquema simplificado.
/// sku = clave primaria, precio_base = unitario, precio_mayorista = 3+ unidades.
class Product {
  final String sku;
  final String nombre;
  final String marca;
  final String categoria;
  final double precioBase;
  final double precioMayorista;
  final String imagenUrl;

  const Product({
    required this.sku,
    required this.nombre,
    required this.marca,
    required this.categoria,
    required this.precioBase,
    this.precioMayorista = 0.0,
    this.imagenUrl = '',
  });

  /// Motor de Cálculo: precio por mayor activado a partir de 3 unidades.
  double calcularTotal(int cantidad, {double? precioManual}) {
    if (precioManual != null && precioManual > 0) return precioManual * cantidad;
    if (cantidad >= 3 && tienePrecioMayorista) {
      return precioMayorista * cantidad;
    }
    return precioBase * cantidad;
  }

  bool get tienePrecioMayorista => precioMayorista > 0 && precioMayorista < precioBase;

  Map<String, dynamic> toMap() => {
    'sku': sku,
    'nombre': nombre,
    'marca': marca,
    'categoria': categoria,
    'precio_base': precioBase,
    'precio_mayorista': precioMayorista,
    'imagen_url': imagenUrl,
  };

  /// BLINDAJE (Fase 2 de Auditoría): 
  /// Defensa contra datos corruptos, nulos o tipos incorrectos.
  factory Product.fromMap(Map<String, dynamic> m) {
    try {
      return Product(
        sku: (m['sku'] ?? 'BR-ERR-${DateTime.now().millisecondsSinceEpoch}').toString(),
        nombre: (m['nombre'] ?? 'Producto sin nombre').toString(),
        marca: (m['marca'] ?? '').toString(),
        categoria: (m['categoria'] ?? 'General').toString(),
        precioBase: _parseNum(m['precio_base']),
        precioMayorista: _parseNum(m['precio_mayorista']),
        imagenUrl: (m['imagen_url'] ?? '').toString(),
      );
    } catch (e) {
      // Si todo falla, devolvemos un producto placeholder para no matar la UI
      return Product(
        sku: 'ERR-DATA',
        nombre: 'Error de Datos',
        marca: '',
        categoria: 'ERROR',
        precioBase: 0.0,
      );
    }
  }

  static double _parseNum(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  Product copyWith({
    String? sku,
    String? nombre,
    String? marca,
    String? categoria,
    double? precioBase,
    double? precioMayorista,
    String? imagenUrl,
  }) => Product(
    sku: sku ?? this.sku,
    nombre: nombre ?? this.nombre,
    marca: marca ?? this.marca,
    categoria: categoria ?? this.categoria,
    precioBase: precioBase ?? this.precioBase,
    precioMayorista: precioMayorista ?? this.precioMayorista,
    imagenUrl: imagenUrl ?? this.imagenUrl,
  );
}
