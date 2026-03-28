import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../base/llaves.dart';
import '../../servicios/servicio_configuracion.dart';
import 'package:bipenc/datos/modelos/producto.dart';
import 'package:bipenc/datos/modelos/presentacion.dart';
import 'package:bipenc/servicios/servicio_db_local.dart';
import 'package:bipenc/servicios/servicio_backend.dart';
import 'package:bipenc/utilidades/fiscal.dart';
import '../../servicios/servicio_sesion.dart';
import '../../datos/modelos/venta.dart';
import '../../utilidades/registro_app.dart';
import '../../datos/modelos/cliente.dart';
import '../../datos/modelos/metodo_pago.dart';
import '../../servicios/servicio_busqueda_documento.dart';

export 'package:bipenc/datos/modelos/producto.dart';
export 'package:bipenc/datos/modelos/metodo_pago.dart';

// ── ProveedorCaja ──────────────────────────────────────────────────────────────
class ProveedorCaja extends ChangeNotifier {
  final ServicioBusquedaDocumento _documentLookupService = ServicioBusquedaDocumento();
  // ── 5 CARRITOS INDEPENDIENTES (Constitución BiPenc — Artículo 2) ──────────
  static const int maxClientes = 5;
  final List<List<ItemCarrito>> _carritos =
      List.generate(maxClientes, (_) => []);
  final List<Cliente?> _clientes =
      List.filled(maxClientes, null, growable: false);
  int _carritoActivoIndex = 0;
  String? _orderListId;
  String? _orderFotoUrl;

  bool _isLoadingDocument = false;
  bool get isLoadingDocument => _isLoadingDocument;

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
      _scheduleLiveCartSync();
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

  // La caja es global y administrada. Por ahora se considera siempre habilitada.
  double? get montoAperturaCanguro => 0.0;
  bool get tieneApertura => true;
  bool get cajaOmitida => false;
  bool get cobroHabilitado => true;

  // tasa de IGV obtenida dinámicamente
  double _ivaRate = 0.18;
  double get ivaRate => _ivaRate;

  bool get isOnline => _isOnline;

  // Alertas de sincronización (SUNAT / Supabase)
  bool _syncAlert = false;
  bool get syncAlert => _syncAlert;
  Timer? _syncAlertTimer;
  Timer? _liveCartDebounce;
  bool _liveCartInFlight = false;
  String _lastCartSignature = '';
  final bool _enableLiveCartSync;
  bool _liveCartsEnabled = false;
  DateTime _lastLiveCartsCheck = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _liveCartMinInterval = Duration(seconds: 5);
  static const Duration _liveCartsCheckInterval = Duration(minutes: 5);
  String? get orderListId => _orderListId;
  String? get orderFotoUrl => _orderFotoUrl;
  bool get hasPedidoActivo => _orderListId != null;

  ProveedorCaja({bool testMode = false}) : _enableLiveCartSync = !testMode {
    if (!testMode) {
      _initConnectivity();
      _loadConfiguracion();
      _refreshLiveCartsSetting();
      // _loadApertura(); // Removed as per instruction
      _startSyncAlertMonitor();
    }
  }


  Future<void> _loadConfiguracion() async {
    _ivaRate = await ServicioConfiguracion.obtenerIGVActual();
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
    _syncAlertTimer?.cancel();
    _liveCartDebounce?.cancel();
    super.dispose();
  }

  void _scheduleLiveCartSync() {
    if (!_enableLiveCartSync || !_isOnline) return;
    _refreshLiveCartsSetting();
    if (!_liveCartsEnabled) return;
    final perfil = ServicioSesion().perfil;
    if (perfil == null) return;

    final signature = _buildCartSignature();
    if (signature == _lastCartSignature) return;
    _lastCartSignature = signature;

    _liveCartDebounce?.cancel();
    _liveCartDebounce = Timer(_liveCartMinInterval, () async {
      if (_liveCartInFlight) return;
      _liveCartInFlight = true;
      try {
        await ServicioBackend.upsertCarritoEnVivo(_buildCartPayload(perfil));
      } catch (_) {
        // Ignorar errores de red para no afectar POS
      } finally {
        _liveCartInFlight = false;
      }
    });
  }

  Future<void> _refreshLiveCartsSetting({bool force = false}) async {
    final now = DateTime.now();
    if (!force && now.difference(_lastLiveCartsCheck) < _liveCartsCheckInterval) {
      return;
    }
    _lastLiveCartsCheck = now;
    try {
      _liveCartsEnabled = await ServicioConfiguracion.getLiveCartsEnabled();
    } catch (_) {}
  }

  String _buildCartSignature() {
    final items = _carritos[_carritoActivoIndex];
    final total = _cartTotal(items).toStringAsFixed(2);
    final count = items.length;
    final sigItems = items
        .map((i) => '${i.producto.id}:${i.cantidad}:${i.precioActual}')
        .join('|');
    return '$_carritoActivoIndex|$count|$total|$sigItems';
  }

  Map<String, dynamic> _buildCartPayload(Perfil perfil) {
    final activeItems = _carritos[_carritoActivoIndex];
    final itemsPreview = activeItems
        .take(5)
        .map((i) => {
              'nombre': i.producto.nombre,
              'cantidad': i.cantidad,
              'precio': i.precioActual,
              'subtotal': i.subtotal,
            })
        .toList();

    final cartsSummary = List.generate(maxClientes, (i) {
      final items = _carritos[i];
      return {
        'index': i,
        'items_count': items.length,
        'total': _cartTotal(items),
      };
    });

    return {
      'alias': perfil.alias,
      'rol': perfil.rol,
      'device_id': perfil.deviceId,
      'active_cart_index': _carritoActivoIndex,
      'active_cart_total': _cartTotal(activeItems),
      'active_cart_items_count': activeItems.length,
      'carts': cartsSummary,
      'items_preview': itemsPreview,
    };
  }

  double _cartTotal(List<ItemCarrito> items) {
    double total = 0;
    for (final i in items) {
      total += i.subtotal;
    }
    return total;
  }

  void _startSyncAlertMonitor() {
    _checkSyncAlert();
    _syncAlertTimer?.cancel();
    _syncAlertTimer =
        Timer.periodic(const Duration(minutes: 2), (_) => _checkSyncAlert());
  }

  Future<void> _checkSyncAlert() async {
    final hasAlert = await ServicioDbLocal.existeSyncQueueV2EnAlerta();
    if (hasAlert != _syncAlert) {
      _syncAlert = hasAlert;
      notifyListeners();
    }
  }

  // ── BÚSQUEDA POR CÓDIGO (tabla puente v22) ──────────────────────────────
  /// Busca todos los productos vinculados a un código de barras.
  /// - 1 producto → flujo normal
  /// - >1 productos → mostrar selector de ambigüedad
  /// - 0 productos → mostrar asistente de vinculación
  Future<List<Producto>> buscarPorCodigoAmbiguo(String codigo) async {
    final normalized = codigo.trim();
    if (normalized.isEmpty) return [];
    // Capa 1: tabla puente local (más rápida, funciona offline)
    final localResults = await ServicioDbLocal.buscarPorCodigoBarras(normalized);
    if (localResults.isNotEmpty) {
      debugPrint('[POS] Código $normalized → ${localResults.length} producto(s) (local)');
      return localResults;
    }
    // Capa 2: Supabase (si hay internet)
    if (_isOnline) {
      try {
        final remoteResults = await ServicioBackend.buscarPorCodigoRemoto(normalized)
            .timeout(const Duration(seconds: 8));
        if (remoteResults.isNotEmpty) {
          // Guardar en cache local para futuras búsquedas offline
          await ServicioDbLocal.upsertProductos(remoteResults);
          debugPrint('[POS] Código $normalized → ${remoteResults.length} producto(s) (remoto)');
          return remoteResults;
        }
      } catch (e) {
        debugPrint('[POS] Error fetch remoto por código: $e');
      }
    }
    debugPrint('[POS] Producto no encontrado: $normalized');
    return [];
  }

  // ── CACHÉ DE BÚSQUEDA ─────────────────────────────────────────────────────
  /// Busca un único producto (retrocompatible). Delega a buscarPorCodigoAmbiguo.
  Future<Producto?> buscarProducto(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return null;
    final list = await buscarPorCodigoAmbiguo(normalized);
    return list.isNotEmpty ? list.first : null;
  }

  /// Vincula un código de barras a un producto en la tabla puente.
  /// Funciona offline: encola la operación para sincronizar más tarde.
  Future<void> vincularCodigo(
    String codigo,
    Producto producto, {
    String? variante,
  }) async {
    await ServicioDbLocal.vincularCodigoLocal(
      codigo,
      producto.id,
      variante: variante,
    );
    RegistroApp.info('[BarcodeLink] VINCULAR: $codigo → ${producto.nombre}', tag: 'POS');
  }

  /// Desvincula un código de barras de un producto y lo asocia al correcto.
  /// Útil para corregir asociaciones erróneas desde el carrito.
  Future<void> corregirVinculo(
    String codigo,
    Producto productoAntiguo,
    Producto productoNuevo, {
    String? variante,
  }) async {
    await ServicioDbLocal.desvincularCodigoLocal(codigo, productoAntiguo.id);
    await ServicioDbLocal.vincularCodigoLocal(codigo, productoNuevo.id,
        variante: variante);
    RegistroApp.info('[BarcodeLink] CORREGIR: $codigo: ${productoAntiguo.nombre} → ${productoNuevo.nombre}', tag: 'POS');
  }

  // ── BÚSQUEDA DNI/RUC CON 3 CAPAS ─────────────────────────────────────────
  Future<void> buscarDocumentoCliente(String numero) async {
    final normalized = numero.trim();
    if (normalized.length != 8 && normalized.length != 11) return;

    _isLoadingDocument = true;
    notifyListeners();
    try {
      final result = await _documentLookupService.lookup(normalized);
      setCliente(Cliente(
        documento: normalized,
        nombre: result.nombre,
        direccion: result.direccion,
      ));
    } catch (e) {
      debugPrint('Error buscando documento: $e');
    } finally {
      _isLoadingDocument = false;
      notifyListeners();
    }
  }

  Future<List<Producto>> buscarProductos(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return [];
    // Primero buscar en local (rápido, sin conexión)
    final localResults = await ServicioDbLocal.buscarLocal(normalized);
    if (localResults.isNotEmpty) return localResults;
    // Fallback: buscar en Supabase si el cache local está vacío
    try {
      final supabaseResults = await ServicioBackend.buscarProductos(normalized)
          .timeout(const Duration(seconds: 10));
      // Guardar en local para futuras búsquedas
      if (supabaseResults.isNotEmpty) {
        await ServicioDbLocal.upsertProductos(supabaseResults);
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
            : Presentacion.unit);

    final idx = items.indexWhere((i) =>
        i.producto.id == product.id && i.presentacion.id == selectedPres.id);
    if (idx >= 0) {
      items[idx].cantidad += cantidad;
      final item = items.removeAt(idx);
      items.insert(0, item);
      _aplicarReglaVolumen(0);
    } else {
      items.insert(
          0,
          ItemCarrito(
            producto: product,
            cantidad: cantidad,
            presentacion: selectedPres,
          ));
      _aplicarReglaVolumen(0);
    }
    notifyListeners();
    _scheduleLiveCartSync();
  }

  /// Producto genérico para ventas rápidas con precio manual
  void agregarProductoGenerico({String? nombre, double? precio}) {
    final genericSku = 'GEN-${DateTime.now().millisecondsSinceEpoch % 10000}';
    final genericProduct = Producto(
      id: genericSku,
      skuCode: genericSku,
      nombre: nombre?.trim().isNotEmpty == true
          ? nombre!.trim()
          : 'Varios / Precio libre',
      marca: '',
      categoria: 'Otros',
      presentaciones: [
        Presentacion(
          id: 'unid',
          skuCode: genericSku,
          name: 'Unitario',
          conversionFactor: 1,
          prices: [PuntoPrecio(type: 'NORMAL', amount: 0.0)],
        ),
      ],
    );

    items.insert(
        0,
        ItemCarrito(
          producto: genericProduct,
          presentacion: genericProduct.presentaciones.first,
          cantidad: 1,
          manualPriceOverride: precio ?? 1.00,
          manualPriceLocked: true,
        ));
    notifyListeners();
    _scheduleLiveCartSync();
  }

  Future<void> actualizarCantidad(int index, int delta) async {
    if (index < 0 || index >= items.length) return;

    final nueva = items[index].cantidad + delta;
    if (nueva > 0) {
      items[index].cantidad = nueva;
      _aplicarReglaVolumen(index);
    } else {
      final removed = items.removeAt(index);
      unawaited(_logAudit('ELIMINAR_ITEM',
          detalle: '${removed.producto.nombre} x${removed.cantidad}'));
    }
    notifyListeners();
    _scheduleLiveCartSync();
  }

  void setPrecioManual(int index, double precio) {
    if (index >= 0 && index < items.length) {
      final previo = items[index].precioActual;
      items[index].setPriceOverride(precio);
      notifyListeners();
      _scheduleLiveCartSync();
      if (precio < previo) {
        unawaited(_logAudit('DESCUENTO_MANUAL',
            detalle: '${items[index].producto.nombre}: $previo -> $precio'));
      }
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
    _scheduleLiveCartSync();
  }

  Presentacion? _findPresentationByTipo(Producto p, String tipo) {
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

  Future<void> _logAudit(String accion, {String? detalle}) async {
    final usuario = ServicioSesion().perfil?.alias ?? 'N/A';
    await ServicioDbLocal.logAudit(
      accion: accion,
      usuario: usuario,
      detalle: detalle,
    );
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

  Future<void> eliminarItem(int index) async {
    if (index >= 0 && index < items.length) {
      final removed = items.removeAt(index);
      notifyListeners();
      _scheduleLiveCartSync();
      unawaited(_logAudit('ELIMINAR_ITEM',
          detalle: '${removed.producto.nombre} x${removed.cantidad}'));
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
      _scheduleLiveCartSync();
    }
  }

  void vaciarCarrito() {
    _carritos[_carritoActivoIndex].clear();
    _clientes[_carritoActivoIndex] = null;
    notifyListeners();
    _scheduleLiveCartSync();
  }

  // ── MOTOR FINANCIERO (SUNAT Art 5) ─────────────────────────────────────────
  double get totalCobrar => items.fold(0, (s, i) => s + i.subtotal);

  // Matemática de Impuestos (IGV configurable) con redondeo bancario
  ParFiscal get _desglose => UtilFiscal.calcularDesglose(totalCobrar, tasa: _ivaRate);
  double get operacionGravada => _desglose.$1;
  double get igv => _desglose.$2;

  int get cantidadArticulos => items.fold(0, (s, i) => s + i.unidadesTotales);

  // ── PAGO ──────────────────────────────────────────────────────────────────
  MetodoPago _metodoPago = MetodoPago.efectivo;
  double _montoRecibido = 0.0;

  MetodoPago get metodoPago => _metodoPago;
  double get montoRecibido => _montoRecibido;
  double get vuelto => _montoRecibido - totalCobrar;
  double? get vueltoCalculado => _metodoPago == MetodoPago.efectivo
      ? (_montoRecibido >= totalCobrar ? _montoRecibido - totalCobrar : null)
      : null;

  bool get canCheckout {
    if (items.isEmpty) return false;
    if (!cobroHabilitado) return false;
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

  void attachOrderLink({String? orderId, String? fotoUrl}) {
    _orderListId = orderId;
    _orderFotoUrl = fotoUrl;
    notifyListeners();
  }

  void clearOrderLink() {
    _orderListId = null;
    _orderFotoUrl = null;
    notifyListeners();
  }

  // ── PROCESAR VENTA ────────────────────────────────────────────────────────
  Future<Venta?> procesarVenta({
    TipoComprobante tipo = TipoComprobante.boleta,
    String? docCliente,
    String? nombreCliente,
  }) async {
    if (!canCheckout) return null;

    final aliasVendedor = await ServicioBackend.obtenerAliasVendedorActual();

    // 1. Guardar venta local con correlativo atómico (rollback si falla)
    // 1. Guardar venta local con correlativo atómico (rollback si falla)
    final ({int ventaId, String correlativo}) localResult =
        await ServicioDbLocal.guardarVentaPendienteAtomica(
      items: items,
      total: totalCobrar,
      subtotal: operacionGravada,
      igv: igv,
      aliasVendedor: aliasVendedor,
      documentoCliente: docCliente,
      nombreCliente: nombreCliente,
      tipoComprobante: tipo,
      metodoPago: _metodoPago.name,
      estaSincronizado: false,
      orderListId: _orderListId,
    );

    final correlativo = localResult.correlativo;

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
      orderListId: _orderListId,
    );

    // 2. PATRÓN WATERFALL: Intenta Supabase; si falla queda pendiente
    bool syncSuccess = false;
    final (success, _) = await ServicioBackend.insertarVentaWaterfall(ventaBase);
    syncSuccess = success;
    if (syncSuccess) {
      await ServicioDbLocal.marcarVentaSincronizada(localResult.ventaId);
    }

    // 3. Retornar venta completa con su ID de base de datos local y estado
    return ventaBase.copyWith(
      id: correlativo,
      dbId: localResult.ventaId,
      synced: syncSuccess,
      orderListId: _orderListId,
    );
  }

  void finalizarVentaYLimpiar() {
    vaciarCarrito();
    _resetearMetodoPago();
    clearOrderLink();
    notifyListeners();
  }

  Future<List<Venta>> obtenerUltimosTickets({int limit = 30}) async {
    try {
      final rows = await ServicioDbLocal.getUltimasVentas(
          limit: limit, includeAnuladas: true);
      final iva = await ServicioConfiguracion.obtenerIGVActual();
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
        final desglose = UtilFiscal.calcularDesglose(total, tasa: ivaRate);
        final subtotal = row['subtotal'] != null
            ? double.tryParse(row['subtotal'].toString()) ?? desglose.$1
            : desglose.$1;
        final igvValue = row['igv'] != null
            ? double.tryParse(row['igv'].toString()) ?? desglose.$2
            : desglose.$2;
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
