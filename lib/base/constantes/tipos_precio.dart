/// Tipos de precio canónicos de una presentación.
///
/// Reemplaza los string literals 'NORMAL', 'WHOLESALE' dispersos en el código.
///
/// Ejemplo de uso:
/// ```dart
/// pres.getPriceByType(TipoPrecio.normal)
/// PuntoPrecio(type: TipoPrecio.normal, amount: precioBase)
/// ```
abstract class TipoPrecio {
  /// Precio de venta estándar (precio al público)
  static const String normal = 'NORMAL';

  /// Precio mayorista / por volumen
  static const String mayorista = 'WHOLESALE';

  /// Precio especial / distribuidor / costo
  static const String especial = 'SPECIAL';

  /// Todos los tipos disponibles para validación
  static const List<String> todos = [normal, mayorista, especial];

  /// Verifica si el tipo es válido
  static bool esValido(String tipo) => todos.contains(tipo);
}
