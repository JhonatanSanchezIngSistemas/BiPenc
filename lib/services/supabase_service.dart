import 'dart:io';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/producto.dart';
import '../helpers/alias_helper.dart';
import '../services/local_db_service.dart';
import '../utils/app_logger.dart';
import 'package:path/path.dart' as p;

class SupabaseService {
  static final client = Supabase.instance.client;

  // ──────────────────────────────────────────────
  // Storage — Imágenes
  // ──────────────────────────────────────────────

  /// Sube la imagen al bucket 'productos' y retorna la URL pública.
  static Future<String?> subirImagen(File imageFile) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${p.basename(imageFile.path)}';
      final path = 'public/$fileName';

      await client.storage.from('productos').upload(path, imageFile);

      final String publicUrl = client.storage.from('productos').getPublicUrl(path);
      AppLogger.info('Imagen subida: $publicUrl', tag: 'STORAGE');
      return publicUrl;
    } catch (e) {
      AppLogger.error('Error subiendo imagen', tag: 'STORAGE', error: e);
      return null;
    }
  }

  // ──────────────────────────────────────────────
  // Perfiles
  // ──────────────────────────────────────────────

  static Future<Perfil?> obtenerPerfil() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) {
        AppLogger.warning('currentUser es null', tag: 'PERFIL');
        return null;
      }

      final response = await client
          .from('perfiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (response == null) {
        AppLogger.warning('No se encontró fila en perfiles para userId: ${user.id}', tag: 'PERFIL');
        return null;
      }

      AppLogger.info('Perfil: alias=${response['alias']} rol=${response['rol']}', tag: 'PERFIL');
      return Perfil(
        id: response['id'],
        nombre: response['nombre'],
        apellido: response['apellido'],
        alias: response['alias'],
        rol: response['rol'],
        deviceId: response['device_id'],
      );
    } catch (e) {
      AppLogger.error('Error obteniendo perfil', tag: 'PERFIL', error: e);
      return null;
    }
  }

  /// Crea un perfil mínimo de recuperación cuando el usuario tiene cuenta
  /// Auth pero no tiene fila en la tabla perfiles.
  static Future<Perfil?> crearPerfilDeRecuperacion() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return null;

      final email = user.email ?? 'usuario';
      final base = email.split('@').first;
      final nombre = base.length > 1 ? base[0].toUpperCase() + base.substring(1) : base.toUpperCase();
      const apellido = 'BiPenc';
      final alias = AliasHelper.generarAlias(nombre, apellido);

      // Primer perfil del sistema → SERVER, el resto → VENTAS
      final countRes = await client.from('perfiles').select().count(CountOption.exact);
      final bool isFirst = countRes.count == 0;
      final String rol = isFirst ? 'SERVER' : 'VENTAS';

      AppLogger.info('Creando perfil de recuperación: alias=$alias rol=$rol', tag: 'PERFIL');

      await client.from('perfiles').insert({
        'id': user.id,
        'nombre': nombre,
        'apellido': apellido,
        'alias': alias,
        'rol': rol,
      });

      return Perfil(id: user.id, nombre: nombre, apellido: apellido, alias: alias, rol: rol);
    } catch (e) {
      AppLogger.error('No se pudo crear perfil de recuperación', tag: 'PERFIL', error: e);
      return null;
    }
  }

  // ──────────────────────────────────────────────
  // Autenticación
  // ──────────────────────────────────────────────

  static Future<AuthResponse?> iniciarSesion(String email, String password) async {
    try {
      final response = await client.auth.signInWithPassword(email: email, password: password);
      AppLogger.info('Login OK: ${response.user?.email}', tag: 'AUTH');
      return response;
    } on AuthException catch (e) {
      AppLogger.error('Error AuthException: ${e.message}', tag: 'AUTH');
      rethrow;
    } catch (e) {
      AppLogger.error('Error inesperado en login', tag: 'AUTH', error: e);
      return null;
    }
  }

  static Future<String?> crearCuenta(String email, String password, String nombre, String apellido) async {
    try {
      final res = await client.auth.signUp(email: email, password: password);
      final user = res.user;

      if (user == null) return 'Error al crear la cuenta.';

      if (res.session == null) {
        return 'Cuenta creada. Revisa tu email para confirmar antes de ingresar.';
      }

      final exitoPerfil = await _crearPerfilEnBaseDeDatos(user.id, nombre, apellido);

      if (exitoPerfil) return null;
      return 'Cuenta creada, pero hubo un problema al configurar tu perfil.';
    } on AuthException catch (e) {
      if (e.message.contains('rate limit')) {
        return 'Demasiados intentos. Intenta de nuevo en unos minutos.';
      }
      if (e.message.contains('already registered')) {
        return 'Este correo ya está registrado.';
      }
      return e.message;
    } catch (e) {
      AppLogger.error('Error en registro', tag: 'AUTH', error: e);
      if (e.toString().contains('FormatException')) {
        return 'Error de servidor. Revisa tu conexión.';
      }
      return 'Error: $e';
    }
  }

  static Future<bool> _crearPerfilEnBaseDeDatos(String userId, String nombre, String apellido) async {
    try {
      final alias = AliasHelper.generarAlias(nombre, apellido);

      // Primer perfil del sistema → SERVER, el resto → VENTAS
      final countRes = await client.from('perfiles').select().count(CountOption.exact);
      final bool isFirst = countRes.count == 0;
      final String rol = isFirst ? 'SERVER' : 'VENTAS';

      await client.from('perfiles').insert({
        'id': userId,
        'nombre': nombre,
        'apellido': apellido,
        'alias': alias,
        'rol': rol,
      });
      return true;
    } catch (e) {
      AppLogger.error('Error insertando perfil en DB', tag: 'AUTH', error: e);
      return false;
    }
  }

  // ──────────────────────────────────────────────
  // Sincronización
  // ──────────────────────────────────────────────

  static Future<bool> sincronizarProductos() async {
    try {
      final response = await client.from('productos').select().order('nombre');
      final productos = (response as List)
          .map((row) => _mapToProducto(row as Map<String, dynamic>))
          .toList();
      await LocalDbService.upsertProductos(productos);
      AppLogger.info('${productos.length} productos sincronizados', tag: 'SYNC');
      return true;
    } catch (e) {
      AppLogger.error('Error sincronizando productos', tag: 'SYNC', error: e);
      return false;
    }
  }

  static Future<void> subirVentasPendientes() async {
    try {
      final pendientes = await LocalDbService.obtenerVentasPendientes();
      if (pendientes.isEmpty) return;

      AppLogger.info('Subiendo ${pendientes.length} ventas pendientes...', tag: 'SYNC');
      for (final venta in pendientes) {
        await client.from('ventas').insert({
          'correlativo': venta['correlativo'],
          'items': venta['items_json'],
          'total': venta['total'],
          'alias_vendedor': venta['alias_vendedor'],
        });
        await LocalDbService.marcarVentaSincronizada(venta['id'] as int);
      }
    } catch (e) {
      AppLogger.error('Error subiendo ventas pendientes', tag: 'SYNC', error: e);
    }
  }

  // ──────────────────────────────────────────────
  // Ventas
  // ──────────────────────────────────────────────

  static Future<String> generarSiguienteCorrelativo(String alias) async {
    final prefix = 'V-${alias.toUpperCase()}';
    try {
      final response = await client
          .from('ventas')
          .select('correlativo')
          .ilike('correlativo', '$prefix-%')
          .order('correlativo', ascending: false)
          .limit(1);

      int nextNum = 1;
      if ((response as List).isNotEmpty) {
        final lastCorr = response[0]['correlativo'] as String;
        final parts = lastCorr.split('-');
        if (parts.length >= 3) {
          nextNum = int.parse(parts[2]) + 1;
        }
      }

      return '$prefix-${nextNum.toString().padLeft(5, '0')}';
    } catch (e) {
      AppLogger.error('Error generando correlativo', tag: 'VENTAS', error: e);
      return '$prefix-00001';
    }
  }

  static Future<bool> registrarVenta({
    required List<ItemCarrito> items,
    required double total,
    required String alias,
    required String metodoPago,
    required String tipoDocumento,
    String? dniRuc,
    String? nombreCliente,
  }) async {
    try {
      final correlativo = await generarSiguienteCorrelativo(alias);

      final itemsData = items.map((i) => {
        'sku': i.producto.id,
        'nombre': i.producto.nombre,
        'marca': i.producto.marca,
        'cantidad': i.cantidad,
        'presentacion_id': i.presentacion.id,
        'presentacion_nombre': i.presentacion.nombre,
        'unidades_totales': i.unidadesTotales,
        'precio': i.precioActual,
      }).toList();

      await client.from('ventas').insert({
        'correlativo': correlativo,
        'items': itemsData,
        'total': total,
        'alias_vendedor': alias,
        'metodo_pago': metodoPago,
        'tipo_documento': tipoDocumento,
        'dni_ruc': dniRuc,
        'nombre_cliente': nombreCliente,
      });

      AppLogger.info('Venta registrada: $correlativo total=S/$total', tag: 'VENTAS');
      return true;
    } catch (e) {
      AppLogger.error('Error registrando venta', tag: 'VENTAS', error: e);
      return false;
    }
  }

  // ──────────────────────────────────────────────
  // Productos
  // ──────────────────────────────────────────────

  static Future<bool> upsertProducto(
    Producto p, {
    bool isUpdate = false,
    required String userRol,
    required String userAlias,
  }) async {
    final bool isAdmin = userRol == 'ADMIN' || userRol == 'SERVER';
    try {
      final Map<String, dynamic> data = {
        'sku': p.id,
        'nombre': p.nombre,
        'marca': p.marca,
        'categoria': p.categoria,
        'presentaciones': p.presentaciones.map((pres) => pres.toJson()).toList(),
        'precio_base': p.precioBase,
        'precio_mayorista': p.precioMayorista,
        'precio_caja_12': p.getPrecioPresentacion('c12'),
        'precio_caja_72': p.getPrecioPresentacion('c72'),
        'imagen_url': p.imagenPath,
        'creado_por': userAlias,
        'updated_at': DateTime.now().toIso8601String(),
        'estado': isAdmin ? 'VERIFICADO' : 'PENDIENTE',
      };

      if (isUpdate) {
        await client.from('productos').update(data).eq('sku', p.id);
      } else {
        await client.from('productos').insert(data);
      }

      AppLogger.info('Producto ${isUpdate ? "actualizado" : "creado"}: ${p.id}', tag: 'PRODUCTOS');
      return true;
    } catch (e) {
      AppLogger.error('Error en upsert de producto', tag: 'PRODUCTOS', error: e);
      return false;
    }
  }

  static Future<List<Producto>> buscarProductos(String query) async {
    try {
      final response = await client
          .from('productos')
          .select()
          .or('sku.ilike.%$query%,nombre.ilike.%$query%,marca.ilike.%$query%,categoria.ilike.%$query%')
          .order('nombre');

      return (response as List).map((data) => _mapToProducto(data)).toList();
    } catch (e) {
      AppLogger.error('Error buscando productos', tag: 'PRODUCTOS', error: e);
      return [];
    }
  }

  static Future<List<Producto>> obtenerProductosParaAuditoria() async {
    try {
      final response = await client
          .from('productos')
          .select()
          .eq('estado', 'PENDIENTE')
          .order('updated_at', ascending: false);

      return (response as List).map((data) => _mapToProducto(data)).toList();
    } catch (e) {
      AppLogger.error('Error en auditoría', tag: 'PRODUCTOS', error: e);
      return [];
    }
  }

  static Future<bool> aprobarProducto(String sku, double pBase, double pMayorista) async {
    try {
      await client.from('productos').update({
        'precio_base': pBase,
        'precio_mayorista': pMayorista,
        'precio_propuesto': null,
        'precio_mayorista_propuesto': null,
        'estado': 'VERIFICADO',
      }).eq('sku', sku);
      return true;
    } catch (e) {
      AppLogger.error('Error aprobando producto', tag: 'PRODUCTOS', error: e);
      return false;
    }
  }

  // ──────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────

  static Producto _mapToProducto(Map<String, dynamic> data) {
    List<Presentacion> presentations = [];

    if (data['presentaciones'] != null) {
      if (data['presentaciones'] is String) {
        presentations = (jsonDecode(data['presentaciones']) as List)
            .map((i) => Presentacion.fromJson(i))
            .toList();
      } else if (data['presentaciones'] is List) {
        presentations = (data['presentaciones'] as List)
            .map((i) => Presentacion.fromJson(i))
            .toList();
      }
    } else {
      // Fallback a columnas individuales (retrocompatibilidad)
      presentations = [
        Presentacion(id: 'unid', nombre: 'Unidad', factor: 1, precio: (data['precio_base'] ?? 0).toDouble()),
        if ((data['precio_mayorista'] ?? 0) > 0)
          Presentacion(id: 'mayo', nombre: 'Mayorista', factor: 1, precio: (data['precio_mayorista'] ?? 0).toDouble()),
        if ((data['precio_caja_12'] ?? 0) > 0)
          Presentacion(id: 'c12', nombre: 'Caja x12', factor: 12, precio: (data['precio_caja_12'] ?? 0).toDouble()),
        if ((data['precio_caja_72'] ?? 0) > 0)
          Presentacion(id: 'c72', nombre: 'Caja x72', factor: 72, precio: (data['precio_caja_72'] ?? 0).toDouble()),
      ];
    }

    return Producto(
      id: data['sku'] ?? '',
      nombre: data['nombre'] ?? 'SIN NOMBRE',
      marca: data['marca'] ?? 'GENÉRICO',
      categoria: data['categoria'] ?? 'General',
      presentaciones: presentations,
      imagenPath: data['imagen_url'],
      estado: data['estado'] ?? 'PENDIENTE',
      creadoPor: data['creado_por'],
      updatedAt: data['updated_at'] != null ? DateTime.tryParse(data['updated_at']) : null,
    );
  }
}
