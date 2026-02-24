import 'dart:io';
import '../models/producto.dart';
import '../utils/app_logger.dart';
import 'local_db_service.dart';
import 'supabase_service.dart';

/// Repositorio de productos — Proxy entre caché local y Supabase.
/// La UI siempre interactúa con este repositorio, nunca directamente
/// con los servicios de datos.
class ProductoRepository {
  // ── Singleton ──
  static final ProductoRepository _instance = ProductoRepository._();
  factory ProductoRepository() => _instance;
  ProductoRepository._();

  // ──────────────────────────────────────────────
  // Consultas
  // ──────────────────────────────────────────────

  /// Busca productos: primero en caché local (instantáneo),
  /// luego en Supabase si hay red.
  Future<List<Producto>> buscar(String query) async {
    if (query.isEmpty) return [];

    // 1. Consulta local rápida
    try {
      final locales = await LocalDbService.buscarLocal(query);
      if (locales.isNotEmpty) {
        AppLogger.debug('Búsqueda local: ${locales.length} resultados para "$query"', tag: 'REPO');
        // Lanza búsqueda remota en background para actualizar caché
        _actualizarDesdeRemoto(query);
        return locales;
      }
    } catch (e) {
      AppLogger.error('Error búsqueda local', tag: 'REPO', error: e);
    }

    // 2. Si no hay local, va directo a Supabase
    return _buscarEnRemoto(query);
  }

  Future<void> _actualizarDesdeRemoto(String query) async {
    try {
      final remotos = await SupabaseService.buscarProductos(query);
      if (remotos.isNotEmpty) {
        await LocalDbService.upsertProductos(remotos);
        AppLogger.debug('Caché actualizada: ${remotos.length} productos', tag: 'REPO');
      }
    } catch (e) {
      AppLogger.warning('Sin conexión para actualizar caché', tag: 'REPO');
    }
  }

  Future<List<Producto>> _buscarEnRemoto(String query) async {
    try {
      final remotos = await SupabaseService.buscarProductos(query);
      if (remotos.isNotEmpty) {
        await LocalDbService.upsertProductos(remotos);
      }
      return remotos;
    } catch (e) {
      AppLogger.error('Error búsqueda remota', tag: 'REPO', error: e);
      return [];
    }
  }

  /// Obtiene el Top 10 de productos más vendidos desde caché local.
  Future<List<Producto>> obtenerTop10() async {
    try {
      return await LocalDbService.obtenerTop10();
    } catch (e) {
      AppLogger.error('Error obteniendo top 10', tag: 'REPO', error: e);
      return [];
    }
  }

  // ──────────────────────────────────────────────
  // Mutaciones
  // ──────────────────────────────────────────────

  /// Guarda un producto nuevo. Sube imagen si se proporciona.
  /// Retorna null en éxito, o un mensaje de error.
  Future<String?> guardar({
    required Producto producto,
    required String userAlias,
    required String userRol,
    File? imagen,
  }) async {
    return _upsert(
      producto: producto,
      isUpdate: false,
      userAlias: userAlias,
      userRol: userRol,
      imagen: imagen,
    );
  }

  /// Actualiza un producto existente. Sube imagen si se proporciona.
  Future<String?> actualizar({
    required Producto producto,
    required String userAlias,
    required String userRol,
    File? imagen,
  }) async {
    return _upsert(
      producto: producto,
      isUpdate: true,
      userAlias: userAlias,
      userRol: userRol,
      imagen: imagen,
    );
  }

  Future<String?> _upsert({
    required Producto producto,
    required bool isUpdate,
    required String userAlias,
    required String userRol,
    File? imagen,
  }) async {
    try {
      // 1. Subir imagen si hay una nueva
      String? imagenUrl = producto.imagenPath;
      if (imagen != null) {
        AppLogger.info('Subiendo imagen...', tag: 'REPO');
        final url = await SupabaseService.subirImagen(imagen);
        if (url == null) {
          return 'No se pudo subir la imagen. Intenta de nuevo.';
        }
        imagenUrl = url;
        AppLogger.info('Imagen subida: $url', tag: 'REPO');
      }

      // 2. Crear producto con URL de imagen actualizada
      final productoFinal = _productoConImagen(producto, imagenUrl);

      // 3. Guardar en Supabase
      final ok = await SupabaseService.upsertProducto(
        productoFinal,
        isUpdate: isUpdate,
        userAlias: userAlias,
        userRol: userRol,
      );

      if (!ok) return 'Error al guardar en la base de datos.';

      // 4. Actualizar caché local
      await LocalDbService.upsertProducto(productoFinal);
      AppLogger.info('Producto guardado: ${productoFinal.id}', tag: 'REPO');
      return null; // null = sin error
    } catch (e) {
      AppLogger.error('Error guardando producto', tag: 'REPO', error: e);
      return 'Error inesperado: $e';
    }
  }

  Producto _productoConImagen(Producto p, String? imagenUrl) {
    return Producto(
      id: p.id,
      nombre: p.nombre,
      marca: p.marca,
      categoria: p.categoria,
      presentaciones: p.presentaciones,
      imagenPath: imagenUrl,
      estado: p.estado,
      creadoPor: p.creadoPor,
      updatedAt: p.updatedAt,
    );
  }

  /// Sincroniza todos los productos desde Supabase a la caché local.
  Future<bool> sincronizar() async {
    final ok = await SupabaseService.sincronizarProductos();
    AppLogger.info('Sincronización: ${ok ? "OK" : "FALLÓ"}', tag: 'REPO');
    return ok;
  }

  /// Registra una venta en los contadores locales y en Supabase.
  Future<void> registrarVentaLocal(List items) async {
    await LocalDbService.registrarVentaLocal(items.cast());
  }

  Future<int> contarProductos() async {
    return LocalDbService.contarProductos();
  }
}
