import 'package:flutter/foundation.dart';
import '../models/producto.dart';
import '../utils/precio_engine.dart';

/// Singleton ChangeNotifier que gestiona el estado del carrito globalmente.
/// Cualquier widget puede escucharlo vía ListenableBuilder.
class CarritoService extends ChangeNotifier {
  // ── Singleton ──
  static final CarritoService _instance = CarritoService._();
  factory CarritoService() => _instance;
  CarritoService._();

  final List<ItemCarrito> _items = [];

  /// Lista inmutable de items del carrito.
  List<ItemCarrito> get items => List.unmodifiable(_items);

  /// Número total de unidades en el carrito.
  int get totalItems => _items.fold<int>(0, (s, i) => s + i.cantidad);

  /// Subtotal sin redondeo.
  double get subtotal => _items.fold(0.0, (s, i) => s + i.subtotal);

  /// Total redondeado por la fórmula ceiling BiPenc.
  double get totalRedondeado => PrecioEngine.ceilingTotal(subtotal);

  /// Diferencia de redondeo.
  double get redondeo => totalRedondeado - subtotal;

  /// Ahorro total por precios especiales.
  double get ahorroTotal => _items.fold(0.0, (s, i) => s + i.ahorroTotal);

  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  // ──────────────────────────────────────────────
  // Mutaciones
  // ──────────────────────────────────────────────

  /// Agrega un producto al carrito. Si ya existe con la misma presentación,
  /// incrementa la cantidad.
  void agregar(Producto producto, int cantidad, Presentacion presentacion) {
    final idx = _items.indexWhere(
      (i) => i.producto.id == producto.id && i.presentacion.id == presentacion.id,
    );
    if (idx >= 0) {
      _items[idx].cantidad += cantidad;
    } else {
      _items.add(ItemCarrito(
        producto: producto,
        cantidad: cantidad,
        presentacion: presentacion,
      ));
    }
    notifyListeners();
  }

  /// Incrementa la cantidad de un item.
  void incrementar(int index) {
    if (index < 0 || index >= _items.length) return;
    _items[index].cantidad++;
    notifyListeners();
  }

  /// Decrementa la cantidad de un item. Si llega a 0, lo elimina.
  void decrementar(int index) {
    if (index < 0 || index >= _items.length) return;
    if (_items[index].cantidad > 1) {
      _items[index].cantidad--;
    } else {
      _items.removeAt(index);
    }
    notifyListeners();
  }

  /// Elimina un item por índice.
  void eliminar(int index) {
    if (index < 0 || index >= _items.length) return;
    _items.removeAt(index);
    notifyListeners();
  }

  /// Aplica un precio personalizado ("precio amigo") a un item.
  void aplicarPrecioPersonalizado(int index, double precio) {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    // Si el precio es mayor o igual al base, restauramos
    if (precio >= item.producto.precioBase * item.presentacion.factor) {
      item.precioEditado = null;
    } else {
      item.precioEditado = precio;
    }
    notifyListeners();
  }

  /// Restaura el precio original de un item.
  void restaurarPrecio(int index) {
    if (index < 0 || index >= _items.length) return;
    _items[index].precioEditado = null;
    notifyListeners();
  }

  /// Vacía completamente el carrito.
  void limpiar() {
    _items.clear();
    notifyListeners();
  }

  /// Devuelve una copia snapshot de los items (para pasar a PDF, registro, etc.)
  List<ItemCarrito> snapshot() => List.from(_items);
}
