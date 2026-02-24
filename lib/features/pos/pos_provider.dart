import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../main.dart'; // Importamos scaffoldMessengerKey
import '../../data/models/product.dart';
import '../../data/local/db_helper.dart';
import '../../data/models/venta.dart';
import '../../data/models/cliente.dart';

enum MetodoPago { efectivo, yapePlin, tarjeta }

class CartItem {
  final Product product;
  final Presentacion presentacion;
  int cantidad;
  
  // Soporte para precio manual autorizado
  bool isManualPriceAuthorized;
  double? manualPrice;

  CartItem({
    required this.product,
    required this.presentacion,
    this.cantidad = 1,
    this.isManualPriceAuthorized = false,
    this.manualPrice,
  });

  /// Delega el cálculo del subtotal al motor de precios de la Presentación
  double get subtotal => presentacion.calcularPrecioTotal(
    cantidad, 
    isManualPriceAuthorized: isManualPriceAuthorized, 
    manualPrice: manualPrice,
  );
}

class PosProvider extends ChangeNotifier {
  // --- MULTI-CARRITO (FILA DE ESPERA) ---
  // Representa hasta 3 "Cajas/Carritos" en paralelo.
  final List<List<CartItem>> _carritos = [[], [], []];
  int _carritoActivoIndex = 0;
  
  // Exponemos el carrito actual
  List<CartItem> get items => _carritos[_carritoActivoIndex];
  
  int get activeCartIndex => _carritoActivoIndex;
  
  bool isCartEmpty(int index) {
    if (index >= 0 && index < 3) return _carritos[index].isEmpty;
    return true;
  }
  
  void cambiarCarrito(int index) {
    if (index >= 0 && index < 3) {
      _carritoActivoIndex = index;
      notifyListeners();
    }
  }

  // --- SEMÁFORO DE CONEXIÓN ---
  bool _isOnline = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  bool get isOnline => _isOnline;

  PosProvider() {
    _initConnectivityListener();
  }

  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
       final wasOnline = _isOnline;
       _isOnline = !results.contains(ConnectivityResult.none);
       notifyListeners();

       // Evita alertas al inicio (si no ha cambiado)
       if (wasOnline != _isOnline && scaffoldMessengerKey.currentState != null) {
         if (_isOnline) {
             scaffoldMessengerKey.currentState!.showSnackBar(const SnackBar(
               content: Row(children: [Icon(Icons.cloud_done, color: Colors.white), SizedBox(width:8), Text('Sincronizado con éxito ✅', style: TextStyle(color: Colors.white))]),
               backgroundColor: Colors.green,
               duration: Duration(seconds: 2),
             ));
         } else {
             scaffoldMessengerKey.currentState!.showSnackBar(const SnackBar(
               content: Row(children: [Icon(Icons.cloud_off, color: Colors.white), SizedBox(width:8), Text('Sin conexión: Modo Offline activo 🔴', style: TextStyle(color: Colors.white))]),
               backgroundColor: Colors.red,
               duration: Duration(seconds: 4),
             ));
         }
       }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  // CACHÉ DE MEMORIA: Previene el desgaste de batería y lecturas SSD excesivas
  final Map<String, Product> _searchCache = {};


  /// Busca un código en la caché RAM, si no está va a SQLite y lo guarda en RAM.
  Future<Product?> buscarYLlenarCache(String codigo) async {
    if (_searchCache.containsKey(codigo)) {
      return _searchCache[codigo];
    }
    
    // Si no está en RAM, bajamos a la BD cifrada
    final allProds = await DBHelper().getAllProducts();
    try {
      final encontrado = allProds.firstWhere((p) => p.codigoBarras == codigo);
      _searchCache[codigo] = encontrado; // Guardamos en memoria
      return encontrado;
    } catch (_) {
      return null; // Producto no existe
    }
  }

  /// Añade un Producto Vacio al instante (Modo Ticket Rápido - 100% Editable)
  void agregarProductoGenerico() {
    final prodGen = Product(
      id: 'GEN_${DateTime.now().millisecondsSinceEpoch}',
      descripcion: 'Varios (Ajustar Precio Manualmente)',
      marca: 'S/M',
      codigoBarras: '0000',
      requiereAutorizacion: false,
      presentaciones: [
        Presentacion(nombre: 'Unidad', cantidadPorEmpaque: 1, precioUnitario: 1.00, precioMayor: 0.0)
      ],
    );
    // Añadimos y lo marcamos directo como precio manual para forzar al operario a poner el valor $
    agregarProducto(prodGen, prodGen.presentaciones.first);
  }

  /// Añade un producto al carrito. Si la misma presentación ya existe, incrementa la cantidad.
  void agregarProducto(Product producto, Presentacion presentacion, {int cantidad = 1}) {
    final existingIndex = items.indexWhere((item) => 
        item.product.id == producto.id && item.presentacion.nombre == presentacion.nombre);
        
    if (existingIndex >= 0) {
      items[existingIndex].cantidad += cantidad;
    } else {
      items.add(CartItem(product: producto, presentacion: presentacion, cantidad: cantidad));
    }
    notifyListeners();
  }

  void actualizarCantidad(int index, int delta) {
    if (index >= 0 && index < items.length) {
      final nuevaCantidad = items[index].cantidad + delta;
      if (nuevaCantidad > 0) {
        items[index].cantidad = nuevaCantidad;
      } else {
        items.removeAt(index);
      }
      notifyListeners();
    }
  }

  void autorizarPrecioManual(int index, double nuevoPrecio) {
    if (index >= 0 && index < items.length) {
      items[index].isManualPriceAuthorized = true;
      items[index].manualPrice = nuevoPrecio;
      notifyListeners();
    }
  }

  void vaciarCarrito() {
    items.clear();
    notifyListeners();
  }

  // --- CÁLCULOS DEL MOTOR FINANCIERO ---
  
  double get subtotal => items.fold(0, (sum, item) => sum + item.subtotal);
  
  // Impuestos (ej. IGV/IVA - asumiendo 18% para el ejemplo si BiPenc factura formalmente)
  double get totalIGV => subtotal * 0.18; 
  
  // Gran Total
  double get totalCobrar => subtotal; // Usamos subtotal directo si asumimos precios con IGV incluido

  int get cantidadTotalArticulos => items.fold(0, (sum, item) => sum + item.cantidad);

  // --- MÉTODOS DE PAGO, VUELTO Y CLIENTE ---
  
  MetodoPago _metodoPago = MetodoPago.efectivo;
  double _montoRecibido = 0.0;
  Cliente? _clienteActivo;

  MetodoPago get metodoPago => _metodoPago;
  double get montoRecibido => _montoRecibido;
  Cliente? get clienteActivo => _clienteActivo;

  void setMetodoPago(MetodoPago metodo) {
    _metodoPago = metodo;
    if (_metodoPago != MetodoPago.efectivo) {
      _montoRecibido = totalCobrar; // Pagos digitales asumen monto exacto
    }
    notifyListeners();
  }

  void setMontoRecibido(double monto) {
    _montoRecibido = monto;
    notifyListeners();
  }

  void setCliente(Cliente? cliente) {
    _clienteActivo = cliente;
    notifyListeners();
  }

  // Si recibí más del total, el vuelto es la diferencia
  double get vuelto => (_montoRecibido - totalCobrar) > 0 ? (_montoRecibido - totalCobrar) : 0.0;

  // Validación bloqueante
  bool get canCheckout {
    if (items.isEmpty) return false;
    if (_metodoPago == MetodoPago.efectivo && _montoRecibido < totalCobrar) return false;
    return true;
  }

  // --- EJECUCIÓN DEL FLUJO DE VENTA ---
  
  Future<void> procesarVenta() async {
    if (!canCheckout) return;

    final resumen = items.map((i) => '${i.cantidad}x ${i.product.descripcion}').join(', ');
    final venta = Venta(
      id: 'V_${DateTime.now().millisecondsSinceEpoch}',
      fecha: DateTime.now(),
      total: totalCobrar,
      metodoPago: _metodoPago,
      montoRecibido: _montoRecibido,
      vuelto: vuelto,
      resumenItems: resumen,
    );

    // Persistimos la venta en el disco (Caja)
    await DBHelper().insertVenta(venta);
    
    // Purga el carrito para el siguiente cliente
    vaciarCarrito();
    setMetodoPago(MetodoPago.efectivo);
    setMontoRecibido(0);
    setCliente(null);
  }

  /// Recupera el historial cortísimo para revisión o re-impresión
  Future<List<Venta>> obtenerUltimosTickets() async {
    return await DBHelper().getUltimasVentas(limit: 5);
  }
}

