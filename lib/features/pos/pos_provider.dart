import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../main.dart';
import '../../data/models/product.dart';
import '../../data/local/db_helper.dart';
import '../../data/models/venta.dart';
import '../../data/models/cliente.dart';

export '../../data/models/product.dart';

enum MetodoPago { efectivo, yapePlin, tarjeta }

// ── Cart Item ────────────────────────────────────────────────────────────────
class CartItem {
  final Product product;
  int cantidad;
  bool usarPrecioMayorista;
  double? precioManual; // Para rebajas especiales

  CartItem({
    required this.product,
    this.cantidad = 1,
    this.usarPrecioMayorista = false,
    this.precioManual,
  });

  double get precioUnitario {
    if (precioManual != null && precioManual! > 0) return precioManual!;
    // Auto-activar precio por mayor si hay 3+ unidades y el producto lo soporta
    if (cantidad >= 3 && product.tienePrecioMayorista) return product.precioMayorista;
    if (usarPrecioMayorista && product.tienePrecioMayorista) return product.precioMayorista;
    return product.precioBase;
  }

  double get subtotal => precioUnitario * cantidad;

  String get etiquetaPrecio {
    if (precioManual != null) return 'Precio especial';
    if (cantidad >= 3 && product.tienePrecioMayorista) return 'x Mayor (auto)';
    if (usarPrecioMayorista) return 'Precio Mayor';
    return 'Unitario';
  }
}

// ── PosProvider ──────────────────────────────────────────────────────────────
class PosProvider extends ChangeNotifier {

  // ── 5 CARRITOS INDEPENDIENTES (Constitución BiPenc — Artículo 2) ──────────
  static const int maxClientes = 5;
  final List<List<CartItem>> _carritos = List.generate(maxClientes, (_) => []);
  final List<Cliente?> _clientes = List.filled(maxClientes, null, growable: false);
  int _carritoActivoIndex = 0;

  List<CartItem> get items => _carritos[_carritoActivoIndex];
  int get activeCartIndex => _carritoActivoIndex;
  int get maxCarritos => maxClientes;

  bool isCartEmpty(int index) =>
      index >= 0 && index < maxClientes ? _carritos[index].isEmpty : true;

  int cartItemCount(int index) =>
      index >= 0 && index < maxClientes ? _carritos[index].length : 0;

  void cambiarCarrito(int index) {
    if (index >= 0 && index < maxClientes) {
      _carritoActivoIndex = index;
      _resetearMetodoPago();
      notifyListeners();
    }
  }

  Cliente? get clienteActivo => _clientes[_carritoActivoIndex];

  void setCliente(Cliente? cliente) {
    _clientes[_carritoActivoIndex] = cliente;
    notifyListeners();
  }

  // ── CONEXIÓN ──────────────────────────────────────────────────────────────
  bool _isOnline = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySub;

  bool get isOnline => _isOnline;

  PosProvider() {
    _initConnectivity();
  }

  void _initConnectivity() {
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final wasOnline = _isOnline;
      _isOnline = !results.contains(ConnectivityResult.none);
      notifyListeners();
      if (wasOnline != _isOnline && scaffoldMessengerKey.currentState != null) {
        scaffoldMessengerKey.currentState!.showSnackBar(SnackBar(
          content: Row(children: [
            Icon(_isOnline ? Icons.cloud_done : Icons.cloud_off, color: Colors.white),
            const SizedBox(width: 8),
            Text(_isOnline ? 'En línea ✅' : '🔴 Modo Offline — datos en SQLite'),
          ]),
          backgroundColor: _isOnline ? Colors.teal : Colors.red.shade700,
          duration: Duration(seconds: _isOnline ? 2 : 4),
        ));
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
    super.dispose();
  }

  // ── CACHÉ DE BÚSQUEDA ─────────────────────────────────────────────────────
  final Map<String, Product> _cache = {};

  Future<Product?> buscarProducto(String query) async {
    if (_cache.containsKey(query)) return _cache[query];
    final result = await DBHelper().getProductBySku(query);
    if (result != null) {
      _cache[query] = result;
      return result;
    }
    // Búsqueda por nombre si no hay SKU exacto
    final lista = await DBHelper().searchProducts(query);
    return lista.isNotEmpty ? lista.first : null;
  }

  Future<List<Product>> buscarProductos(String query) async {
    if (query.length < 2) return [];
    return DBHelper().searchProducts(query);
  }

  // ── OPERACIONES DE CARRITO ────────────────────────────────────────────────

  void agregarProducto(Product product, {int cantidad = 1}) {
    final idx = items.indexWhere((i) => i.product.sku == product.sku);
    if (idx >= 0) {
      items[idx].cantidad += cantidad;
    } else {
      items.add(CartItem(product: product, cantidad: cantidad));
    }
    notifyListeners();
  }

  /// Producto genérico para ventas rápidas con precio manual
  void agregarProductoGenerico() {
    items.add(CartItem(
      product: Product(
        sku: 'GEN-${DateTime.now().millisecondsSinceEpoch % 10000}',
        nombre: 'Varios / Precio libre',
        marca: '',
        categoria: '',
        precioBase: 1.00,
      ),
      cantidad: 1,
      precioManual: 1.00,
    ));
    notifyListeners();
  }

  void actualizarCantidad(int index, int delta) {
    if (index < 0 || index >= items.length) return;
    final nueva = items[index].cantidad + delta;
    if (nueva > 0) {
      items[index].cantidad = nueva;
    } else {
      items.removeAt(index);
    }
    notifyListeners();
  }

  void setPrecioManual(int index, double precio) {
    if (index >= 0 && index < items.length) {
      items[index].precioManual = precio;
      notifyListeners();
    }
  }

  void toggleMayorista(int index) {
    if (index >= 0 && index < items.length) {
      items[index].usarPrecioMayorista = !items[index].usarPrecioMayorista;
      notifyListeners();
    }
  }

  void eliminarItem(int index) {
    if (index >= 0 && index < items.length) {
      items.removeAt(index);
      notifyListeners();
    }
  }

  void vaciarCarrito() {
    _carritos[_carritoActivoIndex].clear();
    _clientes[_carritoActivoIndex] = null;
    notifyListeners();
  }

  // ── MOTOR FINANCIERO ──────────────────────────────────────────────────────
  double get subtotal => items.fold(0, (s, i) => s + i.subtotal);
  double get totalCobrar => subtotal; // Precios ya incluyen IGV
  int get cantidadArticulos => items.fold(0, (s, i) => s + i.cantidad);

  // ── PAGO ──────────────────────────────────────────────────────────────────
  MetodoPago _metodoPago = MetodoPago.efectivo;
  double _montoRecibido = 0.0;

  MetodoPago get metodoPago => _metodoPago;
  double get montoRecibido => _montoRecibido;
  double get vuelto => (_montoRecibido - totalCobrar).clamp(0, double.infinity);

  bool get canCheckout {
    if (items.isEmpty) return false;
    if (_metodoPago == MetodoPago.efectivo && _montoRecibido < totalCobrar) return false;
    return true;
  }

  void setMetodoPago(MetodoPago metodo) {
    _metodoPago = metodo;
    if (metodo != MetodoPago.efectivo) _montoRecibido = totalCobrar;
    notifyListeners();
  }

  void setMontoRecibido(double monto) {
    _montoRecibido = monto;
    notifyListeners();
  }

  void _resetearMetodoPago() {
    _metodoPago = MetodoPago.efectivo;
    _montoRecibido = 0.0;
  }

  // ── PROCESAR VENTA ────────────────────────────────────────────────────────
  Future<void> procesarVenta() async {
    if (!canCheckout) return;

    final resumen = items
        .map((i) => '${i.cantidad}x ${i.product.nombre} S/.${i.precioUnitario.toStringAsFixed(2)}')
        .join(' | ');

    final venta = Venta(
      id: 'V_${DateTime.now().millisecondsSinceEpoch}',
      fecha: DateTime.now(),
      total: totalCobrar,
      metodoPago: _metodoPago,
      montoRecibido: _montoRecibido,
      vuelto: vuelto,
      resumenItems: resumen,
    );

    await DBHelper().insertVenta(venta);
    vaciarCarrito();
    _resetearMetodoPago();
  }

  Future<List<Venta>> obtenerUltimosTickets() async =>
      DBHelper().getUltimasVentas(limit: 5);
}
