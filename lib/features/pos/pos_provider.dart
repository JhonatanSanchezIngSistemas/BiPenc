import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../core/keys.dart';
import '../../services/config_service.dart';
import 'package:bipenc/data/models/producto.dart';
import 'package:bipenc/data/models/presentation.dart';
import 'package:bipenc/services/local_db_service.dart';
import 'package:bipenc/services/supabase_service.dart';
import '../../data/models/venta.dart';
import '../../data/models/cliente.dart';

export 'package:bipenc/data/models/producto.dart';

enum MetodoPago { efectivo, yapePlin, tarjeta }

// ── PosProvider ──────────────────────────────────────────────────────────────
class PosProvider extends ChangeNotifier {
  // ── 5 CARRITOS INDEPENDIENTES (Constitución BiPenc — Artículo 2) ──────────
  static const int maxClientes = 5;
  final List<List<ItemCarrito>> _carritos =
      List.generate(maxClientes, (_) => []);
  final List<Cliente?> _clientes =
      List.filled(maxClientes, null, growable: false);
  int _carritoActivoIndex = 0;

  List<ItemCarrito> get items => _carritos[_carritoActivoIndex];
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
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // tasa de IGV obtenida dinámicamente
  double _ivaRate = 0.18;
  double get ivaRate => _ivaRate;

  bool get isOnline => _isOnline;

  PosProvider({bool testMode = false}) {
    if (!testMode) {
      _initConnectivity();
      _loadConfiguracion();
    }
  }

  Future<void> _loadConfiguracion() async {
    _ivaRate = await ConfigService.obtenerIGVActual();
    notifyListeners();
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
            Icon(_isOnline ? Icons.cloud_done : Icons.cloud_off,
                color: Colors.white),
            const SizedBox(width: 8),
            Text(
                _isOnline ? 'En línea ✅' : '🔴 Modo Offline — datos en SQLite'),
          ]),
          backgroundColor: _isOnline ? Colors.teal : Colors.red.shade700,
          duration: Duration(seconds: _isOnline ? 2 : 4),
        ));
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  // ── CACHÉ DE BÚSQUEDA ─────────────────────────────────────────────────────
  Future<Producto?> buscarProducto(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return null;
    final list = await LocalDbService.buscarLocal(normalized);
    return list.isNotEmpty ? list.first : null;
  }

  Future<List<Producto>> buscarProductos(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return [];
    // Primero buscar en local (rápido, sin conexión)
    final localResults = await LocalDbService.buscarLocal(normalized);
    if (localResults.isNotEmpty) return localResults;
    // Fallback: buscar en Supabase si el cache local está vacío
    try {
      final supabaseResults = await SupabaseService.buscarProductos(normalized)
          .timeout(const Duration(seconds: 10));
      // Guardar en local para futuras búsquedas
      if (supabaseResults.isNotEmpty) {
        await LocalDbService.upsertProductos(supabaseResults);
      }
      return supabaseResults;
    } on TimeoutException catch (e) {
      debugPrint('Timeout al buscar productos en Supabase: $e');
      if (scaffoldMessengerKey.currentState != null) {
        scaffoldMessengerKey.currentState!.showSnackBar(const SnackBar(
            content: Text('Servidor lento. Intente de nuevo.'),
            backgroundColor: Colors.orange));
      }
      return [];
    } on SocketException catch (e) {
      debugPrint('Error de red (SocketException): $e');
      if (scaffoldMessengerKey.currentState != null) {
        scaffoldMessengerKey.currentState!.showSnackBar(const SnackBar(
            content: Text('Sin conexión. Buscando en caché local...'),
            backgroundColor: Colors.orange));
      }
      return [];
    } catch (e, st) {
      debugPrint('Error inesperado buscando productos: $e\n$st');
      if (scaffoldMessengerKey.currentState != null) {
        scaffoldMessengerKey.currentState!.showSnackBar(const SnackBar(
            content: Text('Error al buscar productos. Reintente.'),
            backgroundColor: Colors.red));
      }
      return [];
    }
  }

  // ── OPERACIONES DE CARRITO ────────────────────────────────────────────────

  Future<void> agregarProducto(Producto product,
      {int cantidad = 1, Presentacion? presentacion}) async {
    final selectedPres = presentacion ??
        (product.presentaciones.isNotEmpty
            ? product.presentaciones.first
            : Presentation.unit);

    final idx = items.indexWhere((i) =>
        i.producto.id == product.id && i.presentacion.id == selectedPres.id);
    if (idx >= 0) {
      items[idx].cantidad += cantidad;
      _aplicarReglaVolumen(idx);
    } else {
      items.add(ItemCarrito(
        producto: product,
        cantidad: cantidad,
        presentacion: selectedPres,
      ));
      _aplicarReglaVolumen(items.length - 1);
    }
    notifyListeners();
  }

  /// Producto genérico para ventas rápidas con precio manual
  void agregarProductoGenerico() {
    final genericSku = 'GEN-${DateTime.now().millisecondsSinceEpoch % 10000}';
    final genericProduct = Producto(
      id: genericSku,
      skuCode: genericSku,
      nombre: 'Varios / Precio libre',
      marca: '',
      categoria: 'Otros',
      presentaciones: [
        Presentation(
          id: 'unid',
          skuCode: genericSku,
          name: 'Unitario',
          conversionFactor: 1,
          prices: [PricePoint(type: 'NORMAL', amount: 0.0)],
        ),
      ],
    );

    items.add(ItemCarrito(
      producto: genericProduct,
      presentacion: genericProduct.presentaciones.first,
      cantidad: 1,
      manualPriceOverride: 1.00,
      manualPriceLocked: true,
    ));
    notifyListeners();
  }

  Future<void> actualizarCantidad(int index, int delta) async {
    if (index < 0 || index >= items.length) return;

    final nueva = items[index].cantidad + delta;
    if (nueva > 0) {
      items[index].cantidad = nueva;
      _aplicarReglaVolumen(index);
    } else {
      items.removeAt(index);
    }
    notifyListeners();
  }

  void setPrecioManual(int index, double precio) {
    if (index >= 0 && index < items.length) {
      items[index].setPriceOverride(precio);
      notifyListeners();
    }
  }

  void toggleMayorista(int index) {
    setTipoPrecio(index, 'WHOLESALE');
  }

  void setTipoPrecio(int index, String tipo) {
    if (index < 0 || index >= items.length) return;
    final item = items[index];
    final target = _findPresentationByTipo(item.producto, tipo);
    if (target == null) return;
    items[index] = ItemCarrito(
      producto: item.producto,
      presentacion: target,
      cantidad: item.cantidad,
      manualPriceOverride: item.manualPriceOverride,
      manualPriceLocked: item.manualPriceLocked,
      despachado: item.despachado,
      addedAt: item.addedAt,
      afectacionIgv: item.afectacionIgv,
    );
    notifyListeners();
  }

  Presentation? _findPresentationByTipo(Producto p, String tipo) {
    if (p.presentaciones.isEmpty) return null;
    if (tipo == 'NORMAL') {
      return p.presentaciones.firstWhere(
        (x) => x.id == 'unid',
        orElse: () => p.presentaciones.first,
      );
    }
    if (tipo == 'WHOLESALE') {
      return p.presentaciones.firstWhere(
        (x) => x.id == 'mayo',
        orElse: () => p.presentaciones.first,
      );
    }
    if (tipo == 'SPECIAL') {
      return p.presentaciones.firstWhere(
        (x) => x.id == 'espe',
        orElse: () => p.presentaciones.first,
      );
    }
    return p.presentaciones.first;
  }

  /// Regla de volumen dinámica por presentaciones:
  /// - Si el vendedor fijó precio manual, no se toca.
  /// - Sobre UNIDAD evalúa presentaciones con factor > 1 (pack/caja/docena/etc).
  /// - Si una presentación tiene mejor precio por unidad y aplica por cantidad,
  ///   se autocalcula precio unitario promedio.
  void _aplicarReglaVolumen(int index) {
    if (index < 0 || index >= items.length) return;
    final item = items[index];
    if (item.manualPriceLocked) return;
    if (item.presentacion.id != 'unid') return;

    final basePrice = item.presentacion.getPriceByType('NORMAL');
    var bestTotal = basePrice * item.cantidad;

    for (final p in item.producto.presentaciones) {
      if (p.id == 'unid') continue;
      if (p.conversionFactor <= 1) continue;
      final packPrice = p.getPriceByType('NORMAL');
      if (packPrice <= 0) continue;
      final factor = p.conversionFactor.round();
      if (factor <= 1) continue;
      if (item.cantidad < factor) continue;

      final packs = item.cantidad ~/ factor;
      final remainder = item.cantidad % factor;
      final candidateTotal = (packs * packPrice) + (remainder * basePrice);
      if (candidateTotal < bestTotal) {
        bestTotal = candidateTotal;
      }
    }

    final autoUnitPrice = bestTotal / item.cantidad;
    if ((autoUnitPrice - basePrice).abs() < 0.0001) {
      item.setAutoPriceOverride(null);
    } else {
      item.setAutoPriceOverride(autoUnitPrice);
    }
  }

  void eliminarItem(int index) {
    if (index >= 0 && index < items.length) {
      items.removeAt(index);
      notifyListeners();
    }
  }

  void editarItemGenerico(int index, String nuevoNombre, double nuevoPrecio) {
    if (index >= 0 && index < items.length) {
      final item = items[index];
      items[index] = ItemCarrito(
        producto: item.producto.copyWith(
          nombre: nuevoNombre,
        ),
        presentacion: item.presentacion,
        cantidad: item.cantidad,
        manualPriceOverride: nuevoPrecio,
        manualPriceLocked: true,
      );
      notifyListeners();
    }
  }

  void vaciarCarrito() {
    _carritos[_carritoActivoIndex].clear();
    _clientes[_carritoActivoIndex] = null;
    notifyListeners();
  }

  // ── MOTOR FINANCIERO (SUNAT Art 5) ─────────────────────────────────────────
  double get totalCobrar => items.fold(0, (s, i) => s + i.subtotal);

  // Matemática de Impuestos (IGV configurable)
  // El precio actual YA incluye IGV, por lo que desglosamos:
  // Base = Total / (1 + tasa)
  // IGV = Total - Base
  double get operacionGravada => totalCobrar / (1 + _ivaRate);
  double get igv => totalCobrar - operacionGravada;

  int get cantidadArticulos => items.fold(0, (s, i) => s + i.unidadesTotales);

  // ── PAGO ──────────────────────────────────────────────────────────────────
  MetodoPago _metodoPago = MetodoPago.efectivo;
  double _montoRecibido = 0.0;

  MetodoPago get metodoPago => _metodoPago;
  double get montoRecibido => _montoRecibido;
  double get vuelto => _montoRecibido - totalCobrar;

  bool get canCheckout {
    if (items.isEmpty) return false;
    if (_metodoPago == MetodoPago.efectivo && _montoRecibido < totalCobrar) {
      return false;
    }
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
  Future<Venta?> procesarVenta({
    TipoComprobante tipo = TipoComprobante.boleta,
    String? docCliente,
    String? nombreCliente,
  }) async {
    if (!canCheckout) return null;

    final aliasVendedor = await SupabaseService.obtenerAliasVendedorActual();

    // 1. Generar correlativo usando alias real del vendedor
    final correlativo =
        await SupabaseService.generarSiguienteCorrelativo(aliasVendedor);

    final ventaBase = Venta(
      id: correlativo,
      correlativo: correlativo,
      fecha: DateTime.now(),
      tipoComprobante: tipo,
      documentoCliente: docCliente ?? '00000000',
      nombreCliente: nombreCliente,
      operacionGravada: operacionGravada,
      igv: igv,
      total: totalCobrar,
      metodoPago: _metodoPago,
      montoRecibido: _montoRecibido,
      vuelto: vuelto,
      items: List.from(items), // Copia defensiva
    );

    // 2. PATRÓN WATERFALL: Intenta Supabase primero
    final (syncSuccess, _) =
        await SupabaseService.insertarVentaWaterfall(ventaBase);

    // El ID funcional de ticket siempre es el correlativo visible (B001-000123).
    final finalId = correlativo;

    // 3. Persistir en LocalDbService (atómico)
    final dbId = await LocalDbService.guardarVentaPendienteAtomica(
      items: items,
      total: totalCobrar,
      subtotal: operacionGravada,
      igv: igv,
      aliasVendedor: aliasVendedor,
      documentoCliente: docCliente,
      nombreCliente: nombreCliente,
      correlativo: finalId,
      metodoPago: _metodoPago.name,
      estaSincronizado: syncSuccess,
    );

    // 4. Retornar venta completa con su ID de base de datos local y estado
    return ventaBase.copyWith(
      id: finalId,
      dbId: dbId,
      synced: syncSuccess,
    );
  }

  void finalizarVentaYLimpiar() {
    vaciarCarrito();
    _resetearMetodoPago();
    notifyListeners();
  }

  Future<List<Venta>> obtenerUltimosTickets({int limit = 30}) async {
    try {
      final rows = await LocalDbService.getUltimasVentas(
          limit: limit, includeAnuladas: true);
      final iva = await ConfigService.obtenerIGVActual();
      return mapRowsToVentas(rows, ivaRate: iva);
    } catch (e, st) {
      debugPrint('Error obteniendo tickets recientes: $e\n$st');
      return [];
    }
  }

  /// Helper puro para transformar filas SQLite a modelo Venta.
  /// Se expone para facilitar pruebas unitarias sin dependencia de DB.
  static List<Venta> mapRowsToVentas(
    List<Map<String, dynamic>> rows, {
    double ivaRate = 0.18,
  }) {
    final tickets = <Venta>[];

    for (final row in rows) {
      try {
        final rawItems = (row['items_json'] ?? '[]').toString();
        final decoded = jsonDecode(rawItems);
        final items = <ItemCarrito>[];
        if (decoded is List) {
          for (final raw in decoded) {
            try {
              if (raw is Map<String, dynamic>) {
                items.add(ItemCarrito.fromJson(raw));
              } else if (raw is Map) {
                items.add(ItemCarrito.fromJson(Map<String, dynamic>.from(raw)));
              }
            } catch (_) {}
          }
        }

        final total = ((row['total'] ?? 0) as num).toDouble();
        final subtotal = row['subtotal'] != null
            ? double.tryParse(row['subtotal'].toString()) ??
                (total / (1 + ivaRate))
            : (total / (1 + ivaRate));
        final igvValue = row['igv'] != null
            ? double.tryParse(row['igv'].toString()) ?? (total - subtotal)
            : (total - subtotal);
        final correlativo = row['correlativo']?.toString();
        final fecha = DateTime.tryParse((row['creado_at'] ?? '').toString()) ??
            DateTime.now();

        tickets.add(
          Venta(
            id: correlativo?.isNotEmpty == true
                ? correlativo!
                : row['id'].toString(),
            correlativo: correlativo,
            fecha: fecha,
            tipoComprobante: (correlativo?.contains('F') ?? false)
                ? TipoComprobante.factura
                : TipoComprobante.boleta,
            documentoCliente:
                (row['documento_cliente'] ?? '').toString().isNotEmpty
                    ? row['documento_cliente'].toString()
                    : '00000000',
            nombreCliente: row['nombre_cliente']?.toString(),
            operacionGravada: subtotal,
            igv: igvValue,
            total: total,
            metodoPago: MetodoPago.values.firstWhere(
              (e) =>
                  e.name.toUpperCase() ==
                  (row['metodo_pago']?.toString().toUpperCase() ?? 'EFECTIVO'),
              orElse: () => MetodoPago.efectivo,
            ),
            montoRecibido: total,
            vuelto: 0,
            items: items,
            dbId: row['id'] as int?,
            despachado: (row['despachado'] ?? 0) == 1,
            synced: (row['sincronizado'] ?? 0) == 1,
          ),
        );
      } catch (_) {
        // Ignorar fila malformada para no romper toda la lista de tickets.
      }
    }
    return tickets;
  }
}
