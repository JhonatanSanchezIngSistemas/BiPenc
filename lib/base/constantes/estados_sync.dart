/// Estados de sincronización para ventas, pedidos y registros de la sync queue.
///
/// Reemplaza 'PENDIENTE', 'OK', 'ERROR' dispersos en el código.
///
/// Ejemplo de uso:
/// ```dart
/// 'estado': EstadoSync.pendiente,
/// where: 'estado_sync = ?', whereArgs: [EstadoSync.ok]
/// ```
abstract class EstadoSync {
  /// Registro guardado localmente, pendiente de enviar a Supabase
  static const String pendiente = 'PENDIENTE';

  /// Registro sincronizado correctamente con el servidor
  static const String ok = 'OK';

  /// Intento de sync que falló — se reintentará automáticamente
  static const String error = 'ERROR';

  /// Sync omitida permanentemente por ser dato local sin necesidad de sync
  static const String omitida = 'LOCAL';

  static const List<String> todos = [pendiente, ok, error, omitida];

  static bool esValido(String estado) => todos.contains(estado);

  /// Retorna true si el registro necesita intentar sync
  static bool necesitaSync(String estado) =>
      estado == pendiente || estado == error;
}

/// Estados del turno de caja (apertura / cierre).
abstract class EstadoCaja {
  static const String abierta = 'ABIERTA';
  static const String cerrada = 'CERRADA';
  static const String omitida = 'INVENTARIO'; // Sin apertura formal
}

/// Estados de un pedido de lista/orden.
abstract class EstadoPedido {
  static const String pendiente = 'PENDIENTE';
  static const String procesando = 'PROCESANDO';
  static const String despachado = 'DESPACHADO';
  static const String cancelado = 'CANCELADO';
  static const String completado = 'COMPLETADO';
}
