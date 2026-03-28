import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../datos/modelos/producto.dart';
import '../datos/modelos/presentacion.dart';
import '../datos/modelos/venta.dart';
import '../utilidades/registro_app.dart';
import 'servicio_cifrado.dart';
import 'servicio_backend.dart';

part 'db_local/migraciones_db_local.dart';
part 'db_local/repositorio_auditoria_local.dart';
part 'db_local/repositorio_config_local.dart';
part 'db_local/repositorio_documentos_local.dart';
part 'db_local/repositorio_productos_local.dart';
part 'db_local/repositorio_ventas_local.dart';
part 'db_local/repositorio_caja_local.dart';
part 'db_local/repositorio_sync_local.dart';
part 'db_local/repositorio_monitoreo_local.dart';

class ServicioDbLocal {
  static Database? _db;
  static const String _encPrefix = 'enc:';

  static Future<Database> get database async {
    _db ??= await _inicializar();
    return _db!;
  }

  static Future<ServicioCifrado?> _getEnc() async {
    final enc = ServicioCifrado();
    try {
      if (!enc.isInitialized) {
        await enc.init();
      }
      return enc;
    } catch (e, st) {
      RegistroApp.warn('No se pudo inicializar ServicioCifrado',
          tag: 'LOCAL_DB', error: e, stackTrace: st);
      return null;
    }
  }

  static String _encryptField(ServicioCifrado enc, String value) {
    return '$_encPrefix${enc.encriptar(value)}';
  }

  static String _decryptField(ServicioCifrado enc, String value) {
    if (!value.startsWith(_encPrefix)) return value;
    return enc.desencriptar(value.substring(_encPrefix.length));
  }

  static String _normalizeDoc(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }

  static Future<String?> _blindIndexForDoc(String? value) async {
    if (value == null) return null;
    final cleaned = _normalizeDoc(value);
    if (cleaned.isEmpty) return null;
    final enc = await _getEnc();
    if (enc != null) {
      return enc.blindIndex(cleaned);
    }
    return sha256.convert(utf8.encode(cleaned)).toString();
  }

  static Future<Database> _inicializar() async {
    return MigracionesDbLocal.inicializar();
  }

  static Future<void> logAudit({
    required String accion,
    String? usuario,
    String? detalle,
  }) async {
    return RepositorioAuditoriaLocal.logAudit(
        accion: accion, usuario: usuario, detalle: detalle);
  }

  static Future<List<Map<String, dynamic>>> obtenerAuditLogs(
          {int limit = 50}) async =>
      RepositorioAuditoriaLocal.obtenerAuditLogs(limit: limit);

  static Future<void> registrarMetricaAPI({
    required String metodo,
    required double latencia,
    required bool exito,
  }) async {
    return RepositorioMonitoreoLocal.registrarMetricaAPI(
      metodo: metodo,
      latencia: latencia,
      exito: exito,
    );
  }

  static Future<int> countPendingSync() async =>
      RepositorioSyncLocal.countPendingSync();

  static Future<Map<String, dynamic>?> getEmpresaConfig() async =>
      RepositorioConfigLocal.getEmpresaConfig();

  static Future<void> upsertEmpresaConfig(Map<String, dynamic> values) async =>
      RepositorioConfigLocal.upsertEmpresaConfig(values);

  static Future<void> upsertClienteCache({
    required String numero,
    required String nombre,
    String? direccion,
    required String tipo,
  }) async {
    return RepositorioDocumentosLocal.upsertClienteCache(
      numero: numero,
      nombre: nombre,
      direccion: direccion,
      tipo: tipo,
    );
  }

  static Future<List<Map<String, dynamic>>> obtenerItemsDeVenta(
          int ventaId) async =>
      RepositorioVentasLocal.obtenerItemsDeVenta(ventaId);

  static Future<Map<String, dynamic>?> getCachedDocument(String numero) async =>
      RepositorioDocumentosLocal.getCachedDocument(numero);

  static Future<void> saveDocumentCache({
    required String numero,
    required String tipo,
    required String nombre,
    String? direccion,
    required DateTime expiresAt,
  }) async {
    return RepositorioDocumentosLocal.saveDocumentCache(
      numero: numero,
      tipo: tipo,
      nombre: nombre,
      direccion: direccion,
      expiresAt: expiresAt,
    );
  }

  static Future<void> purgeExpiredDocuments() async =>
      RepositorioDocumentosLocal.purgeExpiredDocuments();

  static Future<void> upsertProducto(Producto producto) async =>
      RepositorioProductosLocal.upsertProducto(producto);

  static Future<void> setCorrelativoManual({
    required String tipoDoc,
    required String serie,
    required int ultimoNumero,
  }) async {
    return RepositorioConfigLocal.setCorrelativoManual(
      tipoDoc: tipoDoc,
      serie: serie,
      ultimoNumero: ultimoNumero,
    );
  }

  static Future<Map<String, dynamic>?> getCorrelativoConfig(
          {required String tipoDoc}) async =>
      RepositorioConfigLocal.getCorrelativoConfig(tipoDoc: tipoDoc);

  static Future<List<Map<String, dynamic>>> getAllCorrelativos() async =>
      RepositorioConfigLocal.getAllCorrelativos();

  static Future<void> syncCorrelativosDesdeSupabase(
          List<Map<String, dynamic>> rows) async =>
      RepositorioConfigLocal.syncCorrelativosDesdeSupabase(rows);

  static Future<void> upsertProductos(List<Producto> productos) async =>
      RepositorioProductosLocal.upsertProductos(productos);

  static Future<List<Producto>> buscarLocal(String query) async =>
      RepositorioProductosLocal.buscarLocal(query);

  static Future<List<Producto>> obtenerTop10() async =>
      RepositorioProductosLocal.obtenerTop10();

  static Future<Producto?> getProductoById(String id) async =>
      RepositorioProductosLocal.getProductoById(id);

  static Future<List<Producto>> buscarPorCodigoBarras(String codigo) async =>
      RepositorioProductosLocal.buscarPorCodigoBarras(codigo);

  static Future<void> vincularCodigoLocal(
    String codigo,
    String productoId, {
    String? variante,
  }) async {
    return RepositorioProductosLocal.vincularCodigoLocal(
      codigo,
      productoId,
      variante: variante,
    );
  }

  static Future<void> desvincularCodigoLocal(
    String codigo,
    String productoId,
  ) async {
    return RepositorioProductosLocal.desvincularCodigoLocal(codigo, productoId);
  }

  static Future<List<Map<String, dynamic>>> getVinculosPorCodigo(
          String codigo) async =>
      RepositorioProductosLocal.getVinculosPorCodigo(codigo);

  static Future<void> registrarVentaLocal(List<ItemCarrito> items) async =>
      RepositorioProductosLocal.registrarVentaLocal(items);

  static Future<int> contarProductos() async =>
      RepositorioProductosLocal.contarProductos();

  static Future<void> seedIfEmpty() async =>
      RepositorioProductosLocal.seedIfEmpty();

  static Future<({int ventaId, String correlativo})>
      guardarVentaPendienteAtomica({
    required List<ItemCarrito> items,
    required double total,
    required double subtotal,
    required double igv,
    required String aliasVendedor,
    String? documentoCliente,
    String? nombreCliente,
    String? appVersion,
    TipoComprobante tipoComprobante = TipoComprobante.boleta,
    String? correlativo,
    String metodoPago = 'EFECTIVO',
    bool estaSincronizado = false,
    String? orderListId,
  }) async {
    return RepositorioVentasLocal.guardarVentaPendienteAtomica(
      items: items,
      total: total,
      subtotal: subtotal,
      igv: igv,
      aliasVendedor: aliasVendedor,
      documentoCliente: documentoCliente,
      nombreCliente: nombreCliente,
      appVersion: appVersion,
      tipoComprobante: tipoComprobante,
      correlativo: correlativo,
      metodoPago: metodoPago,
      estaSincronizado: estaSincronizado,
      orderListId: orderListId,
    );
  }

  static Future<int> guardarVentaPendiente({
    required String itemsJson,
    required double total,
    required String aliasVendedor,
    required double subtotal,
    required double igv,
    String? documentoCliente,
    String? nombreCliente,
    String? appVersion,
    String? correlativo,
    String metodoPago = 'EFECTIVO',
  }) async {
    return RepositorioVentasLocal.guardarVentaPendiente(
      itemsJson: itemsJson,
      total: total,
      aliasVendedor: aliasVendedor,
      subtotal: subtotal,
      igv: igv,
      documentoCliente: documentoCliente,
      nombreCliente: nombreCliente,
      appVersion: appVersion,
      correlativo: correlativo,
      metodoPago: metodoPago,
    );
  }

  static Future<int> purgarDatosAntiguos() async =>
      RepositorioVentasLocal.purgarDatosAntiguos();

  static Future<List<Map<String, dynamic>>> obtenerVentasPendientes() async =>
      RepositorioVentasLocal.obtenerVentasPendientes();

  static Future<void> registrarErrorSincronizacion(
          int id, String error) async =>
      RepositorioVentasLocal.registrarErrorSincronizacion(id, error);

  static Future<List<Map<String, dynamic>>> getUltimasVentas({
    int limit = 100,
    bool includeAnuladas = false,
  }) async =>
      RepositorioVentasLocal.getUltimasVentas(
          limit: limit, includeAnuladas: includeAnuladas);

  static Future<List<Map<String, dynamic>>> buscarVentasPorCorrelativo(
    String query, {
    int limit = 100,
    bool includeAnuladas = true,
  }) async =>
      RepositorioVentasLocal.buscarVentasPorCorrelativo(
        query,
        limit: limit,
        includeAnuladas: includeAnuladas,
      );

  static Future<void> marcarVentaSincronizada(int id) async =>
      RepositorioVentasLocal.marcarVentaSincronizada(id);

  static Future<void> marcarDespachado(int id) async =>
      RepositorioVentasLocal.marcarDespachado(id);

  static Future<bool> anularVentaLocal({
    required int ventaId,
    required String motivo,
    required String aliasUsuario,
  }) async {
    return RepositorioVentasLocal.anularVentaLocal(
      ventaId: ventaId,
      motivo: motivo,
      aliasUsuario: aliasUsuario,
    );
  }

  static Future<Map<String, dynamic>?> obtenerTurnoCajaAbierto() async =>
      RepositorioCajaLocal.obtenerTurnoCajaAbierto();

  static Future<int> abrirTurnoCaja({
    required double montoApertura,
    required String aliasUsuario,
  }) async =>
      RepositorioCajaLocal.abrirTurnoCaja(
          montoApertura: montoApertura, aliasUsuario: aliasUsuario);

  static Future<Map<String, dynamic>> obtenerResumenTurnoActual() async =>
      RepositorioCajaLocal.obtenerResumenTurnoActual();

  static Future<bool> cerrarTurnoCaja({
    required int turnoId,
    required double montoCierreReal,
    required String aliasUsuario,
    String? observaciones,
  }) async {
    return RepositorioCajaLocal.cerrarTurnoCaja(
      turnoId: turnoId,
      montoCierreReal: montoCierreReal,
      aliasUsuario: aliasUsuario,
      observaciones: observaciones,
    );
  }

  static Future<List<Map<String, dynamic>>> obtenerSyncQueue() async =>
      RepositorioSyncLocal.obtenerSyncQueue();

  static Future<void> eliminarDeSyncQueue(int id) async =>
      RepositorioSyncLocal.eliminarDeSyncQueue(id);

  static Future<void> eliminarProducto(String id, {String? sku}) async =>
      RepositorioProductosLocal.eliminarProducto(id, sku: sku);

  static Future<void> eliminarProductoLocal(String id) async =>
      RepositorioProductosLocal.eliminarProductoLocal(id);

  static Future<void> insertarEnSyncQueueV2({
    required String id,
    required String tabla,
    required String operacion,
    required String datosJson,
  }) async {
    return RepositorioSyncLocal.insertarEnSyncQueueV2(
      id: id,
      tabla: tabla,
      operacion: operacion,
      datosJson: datosJson,
    );
  }

  static Future<void> enqueueDocumentoCache(Map<String, dynamic> payload) async =>
      RepositorioSyncLocal.enqueueDocumentoCache(payload);

  static Future<List<Map<String, dynamic>>>
          obtenerSyncQueueV2Pendiente() async =>
      RepositorioSyncLocal.obtenerSyncQueueV2Pendiente();

  static Future<void> marcarSyncQueueV2Sincronizado(String id) async =>
      RepositorioSyncLocal.marcarSyncQueueV2Sincronizado(id);

  static Future<void> registrarIntentoSyncQueueV2(
          String id, String? error) async =>
      RepositorioSyncLocal.registrarIntentoSyncQueueV2(id, error);

  static Future<bool> existeSyncQueueV2EnAlerta(
          {Duration threshold = const Duration(hours: 12)}) async =>
      RepositorioSyncLocal.existeSyncQueueV2EnAlerta(threshold: threshold);

  static Future<void> limpiarSyncQueueV2Antigua() async =>
      RepositorioSyncLocal.limpiarSyncQueueV2Antigua();

  static Future<int> obtenerStockLocal(String productId) async =>
      RepositorioProductosLocal.obtenerStockLocal(productId);

  static Future<void> decrementarStockConVersioning(
          String productId, int cantidad) async =>
      RepositorioProductosLocal.decrementarStockConVersioning(
          productId, cantidad);

  static Future<List<Producto>> obtenerProductosModificadosLocalmente() async =>
      RepositorioProductosLocal.obtenerProductosModificadosLocalmente();

  static Future<void> hardResetDatabase() async =>
      MigracionesDbLocal.hardResetDatabase();
}
