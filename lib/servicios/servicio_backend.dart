import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bipenc/datos/modelos/producto.dart';
import 'package:bipenc/datos/modelos/venta.dart';
import 'package:bipenc/servicios/servicio_supabase.dart';
import 'package:bipenc/servicios/supabase/servicio_monitoreo.dart';

class SesionBackend {
  final String id;
  final String? email;

  const SesionBackend({required this.id, this.email});
}

abstract class ProveedorBackend {
  Future<SesionBackend?> obtenerSesionActual();
  Future<void> cerrarSesion();
  Future<Map<String, dynamic>?> getEmpresaConfig();
  Future<void> upsertEmpresaConfig(Map<String, dynamic> values);
  Future<List<Map<String, dynamic>>> obtenerConfigCorrelativos();
  Future<void> upsertConfigCorrelativo({
    required String tipoDocumento,
    required String serie,
    required int ultimoNumero,
  });
  Future<String?> obtenerVersionMinima();
  Future<String?> subirImagen(File imageFile);
  Future<String?> subirAvatarPerfil(File imageFile);
  Future<Perfil?> obtenerPerfil();
  Future<bool> actualizarPerfil({
    required String nombre,
    required String apellido,
    required String alias,
    String? avatarUrl,
  });
  Future<String?> cambiarPassword({required String nuevaPassword});
  Future<String?> cambiarEmail({required String nuevoEmail});
  Future<String> obtenerAliasVendedorActual();
  Future<String?> ensurePerfilConAlias();
  Future<Perfil?> crearPerfilDeRecuperacion();
  Future<AuthResponse?> iniciarSesion(String email, String password);
  Future<String?> crearCuenta(
      String email, String password, String nombre, String apellido);
  Future<double?> obtenerIgvRate();
  Future<void> upsertModoPrueba(bool enabled);
  Future<List<Producto>> buscarProductos(String query);
  Future<List<Producto>> buscarPorCodigoRemoto(String codigo);
  Future<(bool success, String? docId)> insertarVentaWaterfall(Venta venta);
  Future<bool> sincronizarProductos();
  Producto mapToProducto(Map<String, dynamic> data);
  Future<List<String>> obtenerCategorias();
  Future<void> agregarCategoria(String nombre);
  Future<bool> eliminarCategoriaSiNoEstaEnUso(String nombre);
  Future<bool> anularVentaEnNube({
    required String correlativo,
    required String motivo,
    required String aliasUsuario,
  });
  Future<void> subirVentasPendientes();
  Future<void> procesarSyncQueue();
  Future<void> procesarSyncQueueV2();
  Future<List<Map<String, dynamic>>> fetchVentaItemsSimple({
    String? ventaId,
    String? correlativo,
  });
  Future<Map<String, dynamic>?> fetchDocumentoCache(String numero);
  Future<bool> upsertDocumentoCache({
    required String numero,
    required String tipo,
    required String nombre,
    String? direccion,
    required int expiresAtMs,
  });
  Future<bool?> obtenerLiveCartsEnabled();
  Future<void> upsertLiveCartsEnabled(bool enabled);
  Future<void> upsertCarritoEnVivo(Map<String, dynamic> payload);
  Stream<List<Map<String, dynamic>>> streamProductos();
  Future<bool> tieneConexionRemota();
}

class ProveedorSupabase implements ProveedorBackend {
  @override
  Future<SesionBackend?> obtenerSesionActual() async {
    final session = ServicioSupabase.client.auth.currentSession;
    if (session == null) return null;
    return SesionBackend(id: session.user.id, email: session.user.email);
  }

  @override
  Future<void> cerrarSesion() async {
    try {
      await ServicioSupabase.client.auth.signOut();
    } catch (_) {
      // Fallback local (sin red) para limpiar tokens.
      await ServicioSupabase.client.auth.signOut(scope: SignOutScope.local);
    }
  }

  @override
  Future<Map<String, dynamic>?> getEmpresaConfig() =>
      ServicioSupabase.getEmpresaConfig();

  @override
  Future<void> upsertEmpresaConfig(Map<String, dynamic> values) =>
      ServicioSupabase.upsertEmpresaConfig(values);

  @override
  Future<List<Map<String, dynamic>>> obtenerConfigCorrelativos() =>
      ServicioSupabase.obtenerConfigCorrelativos();

  @override
  Future<void> upsertConfigCorrelativo({
    required String tipoDocumento,
    required String serie,
    required int ultimoNumero,
  }) =>
      ServicioSupabase.upsertConfigCorrelativo(
        tipoDocumento: tipoDocumento,
        serie: serie,
        ultimoNumero: ultimoNumero,
      );

  @override
  Future<String?> obtenerVersionMinima() => ServicioSupabase.obtenerVersionMinima();

  @override
  Future<String?> subirImagen(File imageFile) =>
      ServicioSupabase.subirImagen(imageFile);

  @override
  Future<String?> subirAvatarPerfil(File imageFile) =>
      ServicioSupabase.subirAvatarPerfil(imageFile);

  @override
  Future<Perfil?> obtenerPerfil() => ServicioSupabase.obtenerPerfil();

  @override
  Future<bool> actualizarPerfil({
    required String nombre,
    required String apellido,
    required String alias,
    String? avatarUrl,
  }) =>
      ServicioSupabase.actualizarPerfil(
        nombre: nombre,
        apellido: apellido,
        alias: alias,
        avatarUrl: avatarUrl,
      );

  @override
  Future<String?> cambiarPassword({required String nuevaPassword}) =>
      ServicioSupabase.cambiarPassword(nuevaPassword: nuevaPassword);

  @override
  Future<String?> cambiarEmail({required String nuevoEmail}) =>
      ServicioSupabase.cambiarEmail(nuevoEmail: nuevoEmail);

  @override
  Future<String> obtenerAliasVendedorActual() =>
      ServicioSupabase.obtenerAliasVendedorActual();

  @override
  Future<String?> ensurePerfilConAlias() => ServicioSupabase.ensurePerfilConAlias();

  @override
  Future<Perfil?> crearPerfilDeRecuperacion() =>
      ServicioSupabase.crearPerfilDeRecuperacion();

  @override
  Future<AuthResponse?> iniciarSesion(String email, String password) =>
      ServicioSupabase.iniciarSesion(email, password);

  @override
  Future<String?> crearCuenta(
          String email, String password, String nombre, String apellido) =>
      ServicioSupabase.crearCuenta(email, password, nombre, apellido);

  @override
  Future<double?> obtenerIgvRate() async {
    final res = await ServicioSupabase.client
        .from('store_config')
        .select('igv_rate')
        .eq('id', 1)
        .maybeSingle();
    if (res == null || res['igv_rate'] == null) return null;
    return (res['igv_rate'] as num).toDouble();
  }

  @override
  Future<void> upsertModoPrueba(bool enabled) async {
    await ServicioSupabase.client.from('store_config').upsert({
      'id': 1,
      'modo_prueba': enabled,
    });
  }

  @override
  Future<bool?> obtenerLiveCartsEnabled() async {
    final res = await ServicioSupabase.client
        .from('store_config')
        .select('live_carts_enabled')
        .eq('id', 1)
        .maybeSingle();
    if (res == null || res['live_carts_enabled'] == null) return null;
    return res['live_carts_enabled'] == true;
  }

  @override
  Future<void> upsertLiveCartsEnabled(bool enabled) async {
    await ServicioSupabase.client.from('store_config').upsert({
      'id': 1,
      'live_carts_enabled': enabled,
    });
  }

  @override
  Future<List<Producto>> buscarProductos(String query) =>
      ServicioSupabase.buscarProductos(query);

  @override
  Future<List<Producto>> buscarPorCodigoRemoto(String codigo) =>
      ServicioSupabase.buscarPorCodigoRemoto(codigo);

  @override
  Future<(bool success, String? docId)> insertarVentaWaterfall(Venta venta) =>
      ServicioSupabase.insertarVentaWaterfall(venta);

  @override
  Future<bool> sincronizarProductos() => ServicioSupabase.sincronizarProductos();

  @override
  Producto mapToProducto(Map<String, dynamic> data) =>
      ServicioSupabase.mapToProducto(data);

  @override
  Future<List<String>> obtenerCategorias() =>
      ServicioSupabase.obtenerCategorias();

  @override
  Future<void> agregarCategoria(String nombre) =>
      ServicioSupabase.agregarCategoria(nombre);

  @override
  Future<bool> eliminarCategoriaSiNoEstaEnUso(String nombre) =>
      ServicioSupabase.eliminarCategoriaSiNoEstaEnUso(nombre);

  @override
  Future<bool> anularVentaEnNube({
    required String correlativo,
    required String motivo,
    required String aliasUsuario,
  }) =>
      ServicioSupabase.anularVentaEnNube(
        correlativo: correlativo,
        motivo: motivo,
        aliasUsuario: aliasUsuario,
      );

  @override
  Future<void> subirVentasPendientes() => ServicioSupabase.subirVentasPendientes();

  @override
  Future<void> procesarSyncQueue() => ServicioSupabase.procesarSyncQueue();

  @override
  Future<void> procesarSyncQueueV2() => ServicioSupabase.procesarSyncQueueV2();

  @override
  Future<List<Map<String, dynamic>>> fetchVentaItemsSimple({
    String? ventaId,
    String? correlativo,
  }) =>
      ServicioSupabase.fetchVentaItemsSimple(
          ventaId: ventaId, correlativo: correlativo);

  @override
  Future<Map<String, dynamic>?> fetchDocumentoCache(String numero) =>
      ServicioSupabase.fetchDocumentoCache(numero);

  @override
  Future<bool> upsertDocumentoCache({
    required String numero,
    required String tipo,
    required String nombre,
    String? direccion,
    required int expiresAtMs,
  }) =>
      ServicioSupabase.upsertDocumentoCache(
        numero: numero,
        tipo: tipo,
        nombre: nombre,
        direccion: direccion,
        expiresAtMs: expiresAtMs,
      );

  @override
  Future<void> upsertCarritoEnVivo(Map<String, dynamic> payload) =>
      ServicioMonitoreoSupabase.upsertCarritoEnVivo(payload);

  @override
  Stream<List<Map<String, dynamic>>> streamProductos() =>
      ServicioSupabase.client
          .from('productos')
          .stream(primaryKey: ['id']).order('nombre');

  @override
  Future<bool> tieneConexionRemota() => ServicioSupabase.tieneConexionRemota();
}

class ProveedorOracle implements ProveedorBackend {
  Future<T> _noImplementado<T>() async {
    throw UnimplementedError('ProveedorOracle no implementado');
  }

  T _noImplementadoSync<T>() {
    throw UnimplementedError('ProveedorOracle no implementado');
  }

  @override
  Future<SesionBackend?> obtenerSesionActual() => _noImplementado();

  @override
  Future<void> cerrarSesion() => _noImplementado();

  @override
  Future<Map<String, dynamic>?> getEmpresaConfig() => _noImplementado();

  @override
  Future<void> upsertEmpresaConfig(Map<String, dynamic> values) =>
      _noImplementado();

  @override
  Future<List<Map<String, dynamic>>> obtenerConfigCorrelativos() =>
      _noImplementado();

  @override
  Future<void> upsertConfigCorrelativo({
    required String tipoDocumento,
    required String serie,
    required int ultimoNumero,
  }) =>
      _noImplementado();

  @override
  Future<String?> obtenerVersionMinima() => _noImplementado();

  @override
  Future<String?> subirImagen(File imageFile) => _noImplementado();

  @override
  Future<String?> subirAvatarPerfil(File imageFile) => _noImplementado();

  @override
  Future<Perfil?> obtenerPerfil() => _noImplementado();

  @override
  Future<bool> actualizarPerfil({
    required String nombre,
    required String apellido,
    required String alias,
    String? avatarUrl,
  }) =>
      _noImplementado();

  @override
  Future<String?> cambiarPassword({required String nuevaPassword}) =>
      _noImplementado();

  @override
  Future<String?> cambiarEmail({required String nuevoEmail}) => _noImplementado();

  @override
  Future<String> obtenerAliasVendedorActual() => _noImplementado();

  @override
  Future<String?> ensurePerfilConAlias() => _noImplementado();

  @override
  Future<Perfil?> crearPerfilDeRecuperacion() => _noImplementado();

  @override
  Future<AuthResponse?> iniciarSesion(String email, String password) =>
      _noImplementado();

  @override
  Future<String?> crearCuenta(
          String email, String password, String nombre, String apellido) =>
      _noImplementado();

  @override
  Future<double?> obtenerIgvRate() => _noImplementado();

  @override
  Future<void> upsertModoPrueba(bool enabled) => _noImplementado();

  @override
  Future<List<Producto>> buscarProductos(String query) => _noImplementado();

  @override
  Future<List<Producto>> buscarPorCodigoRemoto(String codigo) =>
      _noImplementado();

  @override
  Future<(bool success, String? docId)> insertarVentaWaterfall(Venta venta) =>
      _noImplementado();

  @override
  Future<bool> sincronizarProductos() => _noImplementado();

  @override
  Producto mapToProducto(Map<String, dynamic> data) => _noImplementadoSync();

  @override
  Future<List<String>> obtenerCategorias() => _noImplementado();

  @override
  Future<void> agregarCategoria(String nombre) => _noImplementado();

  @override
  Future<bool> eliminarCategoriaSiNoEstaEnUso(String nombre) => _noImplementado();

  @override
  Future<bool> anularVentaEnNube({
    required String correlativo,
    required String motivo,
    required String aliasUsuario,
  }) =>
      _noImplementado();

  @override
  Future<void> subirVentasPendientes() => _noImplementado();

  @override
  Future<void> procesarSyncQueue() => _noImplementado();

  @override
  Future<void> procesarSyncQueueV2() => _noImplementado();

  @override
  Future<List<Map<String, dynamic>>> fetchVentaItemsSimple({
    String? ventaId,
    String? correlativo,
  }) =>
      _noImplementado();

  @override
  Future<Map<String, dynamic>?> fetchDocumentoCache(String numero) =>
      _noImplementado();

  @override
  Future<bool> upsertDocumentoCache({
    required String numero,
    required String tipo,
    required String nombre,
    String? direccion,
    required int expiresAtMs,
  }) =>
      _noImplementado();

  @override
  Future<bool?> obtenerLiveCartsEnabled() => _noImplementado();

  @override
  Future<void> upsertLiveCartsEnabled(bool enabled) => _noImplementado();

  @override
  Future<void> upsertCarritoEnVivo(Map<String, dynamic> payload) =>
      _noImplementado();

  @override
  Stream<List<Map<String, dynamic>>> streamProductos() => _noImplementadoSync();

  @override
  Future<bool> tieneConexionRemota() => _noImplementado();
}

class ServicioBackend {
  static ProveedorBackend _proveedor = ProveedorSupabase();

  static void usarProveedor(ProveedorBackend proveedor) {
    _proveedor = proveedor;
  }

  static Future<SesionBackend?> obtenerSesionActual() =>
      _proveedor.obtenerSesionActual();

  static Future<void> cerrarSesion() => _proveedor.cerrarSesion();

  static Future<Map<String, dynamic>?> getEmpresaConfig() =>
      _proveedor.getEmpresaConfig();

  static Future<void> upsertEmpresaConfig(Map<String, dynamic> values) =>
      _proveedor.upsertEmpresaConfig(values);

  static Future<List<Map<String, dynamic>>> obtenerConfigCorrelativos() =>
      _proveedor.obtenerConfigCorrelativos();

  static Future<void> upsertConfigCorrelativo({
    required String tipoDocumento,
    required String serie,
    required int ultimoNumero,
  }) =>
      _proveedor.upsertConfigCorrelativo(
        tipoDocumento: tipoDocumento,
        serie: serie,
        ultimoNumero: ultimoNumero,
      );

  static Future<String?> obtenerVersionMinima() =>
      _proveedor.obtenerVersionMinima();

  static Future<String?> subirImagen(File imageFile) =>
      _proveedor.subirImagen(imageFile);

  static Future<String?> subirAvatarPerfil(File imageFile) =>
      _proveedor.subirAvatarPerfil(imageFile);

  static Future<Perfil?> obtenerPerfil() => _proveedor.obtenerPerfil();

  static Future<bool> actualizarPerfil({
    required String nombre,
    required String apellido,
    required String alias,
    String? avatarUrl,
  }) =>
      _proveedor.actualizarPerfil(
        nombre: nombre,
        apellido: apellido,
        alias: alias,
        avatarUrl: avatarUrl,
      );

  static Future<String?> cambiarPassword({required String nuevaPassword}) =>
      _proveedor.cambiarPassword(nuevaPassword: nuevaPassword);

  static Future<String?> cambiarEmail({required String nuevoEmail}) =>
      _proveedor.cambiarEmail(nuevoEmail: nuevoEmail);

  static Future<String> obtenerAliasVendedorActual() =>
      _proveedor.obtenerAliasVendedorActual();

  static Future<String?> ensurePerfilConAlias() =>
      _proveedor.ensurePerfilConAlias();

  static Future<Perfil?> crearPerfilDeRecuperacion() =>
      _proveedor.crearPerfilDeRecuperacion();

  static Future<AuthResponse?> iniciarSesion(String email, String password) =>
      _proveedor.iniciarSesion(email, password);

  static Future<String?> crearCuenta(
          String email, String password, String nombre, String apellido) =>
      _proveedor.crearCuenta(email, password, nombre, apellido);

  static Future<double?> obtenerIgvRate() => _proveedor.obtenerIgvRate();

  static Future<void> upsertModoPrueba(bool enabled) =>
      _proveedor.upsertModoPrueba(enabled);

  static Future<List<Producto>> buscarProductos(String query) =>
      _proveedor.buscarProductos(query);

  static Future<List<Producto>> buscarPorCodigoRemoto(String codigo) =>
      _proveedor.buscarPorCodigoRemoto(codigo);

  static Future<(bool success, String? docId)> insertarVentaWaterfall(
          Venta venta) =>
      _proveedor.insertarVentaWaterfall(venta);

  static Future<bool> sincronizarProductos() => _proveedor.sincronizarProductos();

  static Producto mapToProducto(Map<String, dynamic> data) =>
      _proveedor.mapToProducto(data);

  static Future<List<String>> obtenerCategorias() =>
      _proveedor.obtenerCategorias();

  static Future<void> agregarCategoria(String nombre) =>
      _proveedor.agregarCategoria(nombre);

  static Future<bool> eliminarCategoriaSiNoEstaEnUso(String nombre) =>
      _proveedor.eliminarCategoriaSiNoEstaEnUso(nombre);

  static Future<bool> anularVentaEnNube({
    required String correlativo,
    required String motivo,
    required String aliasUsuario,
  }) =>
      _proveedor.anularVentaEnNube(
        correlativo: correlativo,
        motivo: motivo,
        aliasUsuario: aliasUsuario,
      );

  static Future<void> subirVentasPendientes() =>
      _proveedor.subirVentasPendientes();

  static Future<void> procesarSyncQueue() => _proveedor.procesarSyncQueue();

  static Future<void> procesarSyncQueueV2() => _proveedor.procesarSyncQueueV2();

  static Future<List<Map<String, dynamic>>> fetchVentaItemsSimple({
    String? ventaId,
    String? correlativo,
  }) =>
      _proveedor.fetchVentaItemsSimple(
        ventaId: ventaId,
        correlativo: correlativo,
      );

  static Future<Map<String, dynamic>?> fetchDocumentoCache(String numero) =>
      _proveedor.fetchDocumentoCache(numero);

  static Future<bool> upsertDocumentoCache({
    required String numero,
    required String tipo,
    required String nombre,
    String? direccion,
    required int expiresAtMs,
  }) =>
      _proveedor.upsertDocumentoCache(
        numero: numero,
        tipo: tipo,
        nombre: nombre,
        direccion: direccion,
        expiresAtMs: expiresAtMs,
      );

  static Stream<List<Map<String, dynamic>>> streamProductos() =>
      _proveedor.streamProductos();

  static Future<bool?> obtenerLiveCartsEnabled() =>
      _proveedor.obtenerLiveCartsEnabled();

  static Future<void> upsertLiveCartsEnabled(bool enabled) =>
      _proveedor.upsertLiveCartsEnabled(enabled);

  static Future<void> upsertCarritoEnVivo(Map<String, dynamic> payload) =>
      _proveedor.upsertCarritoEnVivo(payload);

  static Future<bool> tieneConexionRemota() => _proveedor.tieneConexionRemota();
}
