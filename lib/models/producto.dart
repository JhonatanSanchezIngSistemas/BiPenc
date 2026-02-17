/// Modelo de producto para la librería BiPenc.
class Producto {
  final String id;
  final String nombre;
  final String marca;
  final String categoria;
  final double precioBase;
  final double precioMayorista;

  final String? imagenPath;

  const Producto({
    required this.id,
    required this.nombre,
    required this.marca,
    required this.categoria,
    required this.precioBase,
    required this.precioMayorista,
    this.imagenPath,
  });
}

/// Ítem del carrito con soporte para edición de precio y modo mayorista.
class ItemCarrito {
  final Producto producto;
  int cantidad;
  double? precioEditado;
  bool esMayorista;

  ItemCarrito({
    required this.producto,
    this.cantidad = 1,
    this.precioEditado,
    this.esMayorista = false,
  });

  /// Precio efectivo según el modo activo.
  double get precioActual {
    if (precioEditado != null) return precioEditado!;
    if (esMayorista) return producto.precioMayorista;
    return producto.precioBase;
  }

  /// Precio original sin descuentos.
  double get precioOriginal => producto.precioBase;

  /// Subtotal de este ítem.
  double get subtotal => precioActual * cantidad;

  /// Ahorro por unidad respecto al precio base.
  double get ahorroPorUnidad => producto.precioBase - precioActual;

  /// Ahorro total de este ítem.
  double get ahorroTotal => ahorroPorUnidad * cantidad;

  /// Si el precio fue modificado respecto al base.
  bool get tieneDescuento => precioActual < producto.precioBase;
}

// ──────────────────────────────────────────────
// Datos mock — catálogo de librería
// ──────────────────────────────────────────────

final List<Producto> catalogoMock = [
  // Cuadernos
  const Producto(
    id: 'CUA-001', nombre: 'Cuaderno A4 Cuadriculado', marca: 'Scribe',
    categoria: 'Cuadernos', precioBase: 5.50, precioMayorista: 4.20,
  ),
  const Producto(
    id: 'CUA-002', nombre: 'Cuaderno A4 Rayado', marca: 'Scribe',
    categoria: 'Cuadernos', precioBase: 5.50, precioMayorista: 4.20,
  ),
  const Producto(
    id: 'CUA-003', nombre: 'Cuaderno A4 Cuadriculado', marca: 'Stanford',
    categoria: 'Cuadernos', precioBase: 6.00, precioMayorista: 4.80,
  ),
  const Producto(
    id: 'CUA-004', nombre: 'Cuaderno A4 Rayado', marca: 'Stanford',
    categoria: 'Cuadernos', precioBase: 6.00, precioMayorista: 4.80,
  ),
  const Producto(
    id: 'CUA-005', nombre: 'Cuaderno A5 Empastado', marca: 'Justus',
    categoria: 'Cuadernos', precioBase: 8.00, precioMayorista: 6.50,
  ),
  // Lapiceros
  const Producto(
    id: 'LAP-001', nombre: 'Lapicero Azul 035F', marca: 'Faber-Castell',
    categoria: 'Lapiceros', precioBase: 1.00, precioMayorista: 0.70,
  ),
  const Producto(
    id: 'LAP-002', nombre: 'Lapicero Negro 035F', marca: 'Faber-Castell',
    categoria: 'Lapiceros', precioBase: 1.00, precioMayorista: 0.70,
  ),
  const Producto(
    id: 'LAP-003', nombre: 'Lapicero Azul Trimax', marca: 'Pilot',
    categoria: 'Lapiceros', precioBase: 2.50, precioMayorista: 1.80,
  ),
  const Producto(
    id: 'LAP-004', nombre: 'Lapicero Rojo Trimax', marca: 'Pilot',
    categoria: 'Lapiceros', precioBase: 2.50, precioMayorista: 1.80,
  ),
  // Colores y arte
  const Producto(
    id: 'COL-001', nombre: 'Colores x12', marca: 'Faber-Castell',
    categoria: 'Arte', precioBase: 8.00, precioMayorista: 6.00,
  ),
  const Producto(
    id: 'COL-002', nombre: 'Colores x24', marca: 'Faber-Castell',
    categoria: 'Arte', precioBase: 15.00, precioMayorista: 11.50,
  ),
  const Producto(
    id: 'COL-003', nombre: 'Plumones x12', marca: 'Artesco',
    categoria: 'Arte', precioBase: 6.00, precioMayorista: 4.50,
  ),
  // Útiles varios
  const Producto(
    id: 'UTI-001', nombre: 'Borrador Blanco Grande', marca: 'Faber-Castell',
    categoria: 'Útiles', precioBase: 0.50, precioMayorista: 0.30,
  ),
  const Producto(
    id: 'UTI-002', nombre: 'Tajador Metálico', marca: 'Faber-Castell',
    categoria: 'Útiles', precioBase: 1.00, precioMayorista: 0.60,
  ),
  const Producto(
    id: 'UTI-003', nombre: 'Pegamento en Barra 40g', marca: 'UHU',
    categoria: 'Útiles', precioBase: 3.50, precioMayorista: 2.50,
  ),
  const Producto(
    id: 'UTI-004', nombre: 'Tijera Escolar 5"', marca: 'Artesco',
    categoria: 'Útiles', precioBase: 3.00, precioMayorista: 2.20,
  ),
];
