/// Lógica de negocio del carrito para pruebas unitarias.
library;

/// Calcula el subtotal de una lista de ítems del carrito.
/// Cada ítem es un Map con 'precio' (double) y 'cantidad' (int).
double calcularSubtotal(List<Map<String, dynamic>> items) {
  return items.fold(0.0, (sum, item) {
    final precio = (item['precio'] as num?)?.toDouble() ?? 0.0;
    final cantidad = (item['cantidad'] as num?)?.toInt() ?? 0;
    return sum + precio * cantidad;
  });
}

/// Calcula el vuelto dado el total a cobrar y el monto recibido.
double calcularVuelto(double total, double montoRecibido) {
  final vuelto = montoRecibido - total;
  return vuelto < 0 ? 0.0 : vuelto;
}
