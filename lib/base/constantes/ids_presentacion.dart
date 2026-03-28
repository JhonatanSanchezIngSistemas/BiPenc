/// IDs canónicos de las presentaciones estándar de un producto.
///
/// Usar siempre estas constantes en lugar de los string literals
/// 'unid', 'mayo', 'espe' dispersos por el código.
///
/// Ejemplo de uso:
/// ```dart
/// if (presentacion.id == IdsPresentacion.unitario) { ... }
/// ```
abstract class IdsPresentacion {
  /// Presentación unitaria — precio base
  static const String unitario = 'unid';

  /// Presentación mayorista — precio por volumen
  static const String mayorista = 'mayo';

  /// Presentación especial / distribuidor
  static const String especial = 'espe';

  /// Prefijo para presentaciones dinámicas adicionales
  static const String prefijoDinamica = 'pres_';

  /// Comprueba si un ID corresponde a una presentación fija (no dinámica)
  static bool esFija(String id) =>
      id == unitario || id == mayorista || id == especial;

  /// IDs fijos para iterar o excluir
  static const List<String> todasFijas = [unitario, mayorista, especial];
}
