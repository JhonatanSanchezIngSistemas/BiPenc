class Product {
  final String id;
  final String descripcion;
  final String marca;
  final String codigoBarras;
  final String? categoria;
  final String? imagenUrl;
  
  /// Lista de presentaciones asociadas a este producto.
  /// Ejemplo: Unidad (1), Docena (12), Caja (100).
  final List<Presentacion> presentaciones;
  
  /// Flag de seguridad: Si es true, requerirá de un PIN o autorización para aplicar precios manuales.
  final bool requiereAutorizacion;

  Product({
    required this.id,
    required this.descripcion,
    required this.marca,
    required this.codigoBarras,
    this.categoria,
    this.imagenUrl,
    required this.presentaciones,
    required this.requiereAutorizacion,
  });
}

class Presentacion {
  final String nombre; // e.g. "Unidad", "Blister x 5", "Caja x 100"
  
  /// Cuántas unidades mínimas contiene esta presentación. Resuelve el problema de cantidades escalables.
  final int cantidadPorEmpaque; 
  
  final double precioUnitario;
  
  // Opcional o fijo, aplicable cuando se compran a partir de ciertas unidades (ej. 3+)
  final double precioMayor; 

  Presentacion({
    required this.nombre,
    required this.cantidadPorEmpaque,
    required this.precioUnitario,
    required this.precioMayor,
  });

  /// Validación de Entidad: Garantiza que el precio al por mayor no supere el precio unitario general.
  bool get esPrecioMayorValido => precioMayor <= precioUnitario;

  /// Motor de Cálculo de BiPenc: Determina el precio según la cantidad o autorización manual.
  double calcularPrecioTotal(int cantidad, {bool isManualPriceAuthorized = false, double? manualPrice}) {
    // Si el precio manual fue autorizado (vía SecurityService), el motor confía en él y anula las demás reglas.
    if (isManualPriceAuthorized && manualPrice != null) {
      return manualPrice * cantidad;
    }

    // Regla de Negocio: A partir de 3 unidades se aplica el precio por mayor
    // (siempre y cuando sea válido y haya sido configurado).
    if (cantidad >= 3 && precioMayor > 0.0 && esPrecioMayorValido) {
      return precioMayor * cantidad;
    }
    
    // Regla base: Precio unitario multiplicando por la cantidad vendida
    return precioUnitario * cantidad;
  }
}
