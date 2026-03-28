/// Estados del ciclo de vida de un [Producto].
///
/// Reemplaza los string literals 'ACTIVO', 'VERIFICADO', 'DESCONTINUADO'
/// dispersos en el código y en las consultas SQL.
///
/// Ejemplo de uso:
/// ```dart
/// estado: EstadoProducto.verificado,
/// where: 'estado = ?', whereArgs: [EstadoProducto.activo]
/// ```
abstract class EstadoProducto {
  /// Producto activo, visible y en venta
  static const String activo = 'ACTIVO';

  /// Producto verificado con datos completos (precio, SKU, imagen)
  static const String verificado = 'VERIFICADO';

  /// Producto dado de baja / retirado del catálogo
  static const String descontinuado = 'DESCONTINUADO';

  /// Producto creado localmente, pendiente de revisión
  static const String borrador = 'BORRADOR';

  static const List<String> todos = [
    activo,
    verificado,
    descontinuado,
    borrador,
  ];

  static bool esValido(String estado) => todos.contains(estado);

  /// Retorna true si el producto debe mostrarse en el catálogo de venta
  static bool esVendible(String estado) =>
      estado == activo || estado == verificado;
}
