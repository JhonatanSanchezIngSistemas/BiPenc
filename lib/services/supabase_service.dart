import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bipenc/data/models/producto.dart';
import 'package:bipenc/data/models/presentation.dart';
import 'package:bipenc/helpers/alias_helper.dart';
import 'package:bipenc/services/local_db_service.dart';
import 'package:bipenc/utils/app_logger.dart';
import 'package:path/path.dart' as p;
import 'package:bipenc/data/models/venta.dart';
import 'package:bipenc/services/config_service.dart';
import 'package:bipenc/core/constantes/categorias_producto.dart';

class SupabaseService {
  static final client = Supabase.instance.client;

  static bool _isMissingColumnError(PostgrestException e, String columnName) {
    final msg = e.message.toLowerCase();
    return e.code == 'PGRST204' && msg.contains(columnName.toLowerCase());
  }

  @visibleForTesting
  static Map<String, dynamic>? nextVentaPayloadForCompatibilityForTest(
    Map<String, dynamic> currentPayload,
    PostgrestException e,
  ) =>
      _nextVentaPayloadForCompatibility(currentPayload, e);

  static Map<String, dynamic>? _nextVentaPayloadForCompatibility(
    Map<String, dynamic> currentPayload,
    PostgrestException e,
  ) {
    if (_isMissingColumnError(e, 'despachado') &&
        currentPayload.containsKey('despachado')) {
      final next = Map<String, dynamic>.from(currentPayload)
        ..remove('despachado');
      AppLogger.warning(
        'Compat: columna "despachado" no existe en ventas, reintentando sin ese campo',
        tag: 'WATERFALL',
      );
      return next;
    }

    if (_isMissingColumnError(e, 'dni_cliente') &&
        currentPayload.containsKey('dni_cliente')) {
      final next = Map<String, dynamic>.from(currentPayload);
      final dniValue = next.remove('dni_cliente');
      if (!next.containsKey('dni_ruc') && dniValue != null) {
        next['dni_ruc'] = dniValue;
        AppLogger.warning(
          'Compat: columna "dni_cliente" no existe; reintentando con "dni_ruc"',
          tag: 'WATERFALL',
        );
      } else if (!next.containsKey('documento_cliente') && dniValue != null) {
        next['documento_cliente'] = dniValue;
        AppLogger.warning(
          'Compat: columna "dni_cliente" no existe; reintentando con "documento_cliente"',
          tag: 'WATERFALL',
        );
      } else {
        AppLogger.warning(
          'Compat: columna "dni_cliente" no existe; reintentando sin documento de cliente',
          tag: 'WATERFALL',
        );
      }
      return next;
    }

    if (_isMissingColumnError(e, 'dni_ruc') &&
        currentPayload.containsKey('dni_ruc')) {
      final next = Map<String, dynamic>.from(currentPayload);
      final dniValue = next.remove('dni_ruc');
      if (!next.containsKey('documento_cliente') && dniValue != null) {
        next['documento_cliente'] = dniValue;
      }
      AppLogger.warning(
        'Compat: columna "dni_ruc" no existe; reintentando con "documento_cliente"',
        tag: 'WATERFALL',
      );
      return next;
    }

    if (_isMissingColumnError(e, 'documento_cliente') &&
        currentPayload.containsKey('documento_cliente')) {
      final next = Map<String, dynamic>.from(currentPayload)
        ..remove('documento_cliente');
      AppLogger.warning(
        'Compat: columna "documento_cliente" no existe; reintentando sin documento de cliente',
        tag: 'WATERFALL',
      );
      return next;
    }

    return null;
  }

  static Future<void> _insertVentaWithCompatibility(
    Map<String, dynamic> payload,
  ) async {
    var workingPayload = Map<String, dynamic>.from(payload);
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await client.from('ventas').insert(workingPayload);
        return;
      } on PostgrestException catch (e) {
        final next = _nextVentaPayloadForCompatibility(workingPayload, e);
        if (next == null) rethrow;
        workingPayload = next;
      }
    }
    throw Exception('No se pudo insertar venta por compatibilidad de columnas');
  }

  static Future<Map<String, dynamic>> _insertVentaReturningWithCompatibility(
    Map<String, dynamic> payload,
  ) async {
    var workingPayload = Map<String, dynamic>.from(payload);
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        return await client
            .from('ventas')
            .insert(workingPayload)
            .select()
            .single()
            .timeout(const Duration(seconds: 30));
      } on PostgrestException catch (e) {
        final next = _nextVentaPayloadForCompatibility(workingPayload, e);
        if (next == null) rethrow;
        workingPayload = next;
      }
    }
    throw Exception('No se pudo insertar venta por compatibilidad de columnas');
  }

  static Future<bool> _updateVentaAnulacionWithCompatibility({
    required String correlativo,
    required Map<String, dynamic> payload,
  }) async {
    var current = Map<String, dynamic>.from(payload);
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        await client
            .from('ventas')
            .update(current)
            .eq('correlativo', correlativo);
        return true;
      } on PostgrestException catch (e) {
        if (_isMissingColumnError(e, 'anulado') &&
            current.containsKey('anulado')) {
          current.remove('anulado');
          continue;
        }
        if (_isMissingColumnError(e, 'anulado_motivo') &&
            current.containsKey('anulado_motivo')) {
          current.remove('anulado_motivo');
          continue;
        }
        if (_isMissingColumnError(e, 'anulado_at') &&
            current.containsKey('anulado_at')) {
          current.remove('anulado_at');
          continue;
        }
        if (_isMissingColumnError(e, 'anulado_por') &&
            current.containsKey('anulado_por')) {
          current.remove('anulado_por');
          continue;
        }
        if (_isMissingColumnError(e, 'estado') &&
            current.containsKey('estado')) {
          current.remove('estado');
          continue;
        }
        rethrow;
      }
    }
    return false;
  }

  /// Genera/obtiene el siguiente correlativo desde el RPC nativo.
  /// IMPORTANTE: Ahora usa RPC 'generar_correlativo' en lugar de fallback timestamp.
  /// Si el RPC falla, retorna un identificador temporal seguro pero LOGUEA WARNING.
  static Future<String> generarSiguienteCorrelativo(String alias) async {
    try {
      AppLogger.debug(
        'Llamando RPC generar_correlativo para alias: $alias',
        tag: 'CORRELATIVO',
      );

      // Llamar RPC nativo
      final res = await client.rpc(
        'generar_correlativo',
        params: {'alias': alias},
      ).maybeSingle();

      if (res != null && res['correlativo'] != null) {
        final corrResult = res['correlativo'].toString();
        AppLogger.info(
          'Correlativo generado por RPC: $corrResult',
          tag: 'CORRELATIVO',
        );
        return corrResult;
      }

      // Si RPC retorna null o sin campo correlativo
      throw Exception('RPC retornó respuesta vacía');
    } on PostgrestException catch (e) {
      AppLogger.warning(
        'Error PostgreSQL en RPC: ${e.message}. Usando fallback temporal.',
        tag: 'CORRELATIVO',
      );
      return _generarCorrelativoFallback();
    } on TimeoutException catch (_) {
      AppLogger.warning(
        'Timeout en RPC. Usando fallback temporal.',
        tag: 'CORRELATIVO',
      );
      return _generarCorrelativoFallback();
    } catch (e) {
      AppLogger.error(
        'Error inesperado en RPC: $e. Usando fallback temporal.',
        tag: 'CORRELATIVO',
        error: e,
      );
      return _generarCorrelativoFallback();
    }
  }

  /// Fallback: Genera correlativo temporal si RPC falla
  /// Usa timestamp + random para evitar colisiones
  static String _generarCorrelativoFallback() {
    final now = DateTime.now();
    final timestamp = now.millisecondsSinceEpoch;
    final random = (now.microsecond % 1000).toString().padLeft(3, '0');
    final fallbackCorr = 'T-${timestamp % 1000000}-$random';
    AppLogger.warning(
      'Usando correlativo fallback: $fallbackCorr (NOTA: Esto NO debería suceder en producción)',
      tag: 'CORRELATIVO',
    );
    return fallbackCorr;
  }

  @visibleForTesting
  static String generarCorrelativoFallbackForTest() =>
      _generarCorrelativoFallback();

  // ──────────────────────────────────────────────
  // Configuración Global y Versiones
  // ──────────────────────────────────────────────

  /// Obtiene la versión mínima requerida desde Supabase
  static Future<String?> obtenerVersionMinima() async {
    try {
      final res = await client
          .from('store_config')
          .select('min_version')
          .eq('id', 1)
          .maybeSingle();
      return res?['min_version']?.toString();
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('store_config') && msg.contains('pgrst205')) {
        AppLogger.warning(
            'Tabla store_config no existe; se omite check de versión',
            tag: 'CONFIG');
      } else {
        AppLogger.error('Error obteniendo min_version',
            tag: 'CONFIG', error: e);
      }
      return null;
    }
  }

  // ──────────────────────────────────────────────
  // Storage — Imágenes
  // ──────────────────────────────────────────────

  /// Sube la imagen al bucket 'productos' y retorna la URL pública.
  static Future<String?> subirImagen(File imageFile) async {
    try {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${p.basename(imageFile.path)}';
      final path = 'public/$fileName';

      await client.storage.from('productos').upload(path, imageFile);

      final String publicUrl =
          client.storage.from('productos').getPublicUrl(path);
      AppLogger.info('Imagen subida: $publicUrl', tag: 'STORAGE');
      return publicUrl;
    } catch (e) {
      AppLogger.error('Error subiendo imagen', tag: 'STORAGE', error: e);
      return null;
    }
  }

  /// Sube avatar de perfil al bucket `productos` (ruta `avatars/`) y retorna URL pública.
  static Future<String?> subirAvatarPerfil(File imageFile) async {
    try {
      final fileName =
          'avatar_${DateTime.now().millisecondsSinceEpoch}_${p.basename(imageFile.path)}';
      final path = 'avatars/$fileName';
      await client.storage.from('productos').upload(path, imageFile);
      final String publicUrl =
          client.storage.from('productos').getPublicUrl(path);
      AppLogger.info('Avatar subido: $publicUrl', tag: 'STORAGE');
      return publicUrl;
    } catch (e) {
      AppLogger.error('Error subiendo avatar', tag: 'STORAGE', error: e);
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
        AppLogger.warning(
            'No se encontró fila en perfiles para userId: ${user.id}',
            tag: 'PERFIL');
        return null;
      }

      AppLogger.info(
          'Perfil: alias=${response['alias']} rol=${response['rol']}',
          tag: 'PERFIL');
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

  /// Actualiza datos de perfil del usuario autenticado.
  static Future<bool> actualizarPerfil({
    required String nombre,
    required String apellido,
    required String alias,
    String? avatarUrl,
  }) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return false;

      final payload = <String, dynamic>{
        'nombre': nombre.trim(),
        'apellido': apellido.trim(),
        'alias': alias.trim().toUpperCase(),
      };
      if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
        payload['avatar_url'] = avatarUrl.trim();
      }

      try {
        await client.from('perfiles').update(payload).eq('id', user.id);
      } on PostgrestException catch (e) {
        // Compatibilidad si la columna avatar_url no existe aún.
        if (_isMissingColumnError(e, 'avatar_url') &&
            payload.containsKey('avatar_url')) {
          payload.remove('avatar_url');
          await client.from('perfiles').update(payload).eq('id', user.id);
        } else {
          rethrow;
        }
      }
      return true;
    } catch (e) {
      AppLogger.error('Error actualizando perfil', tag: 'PERFIL', error: e);
      return false;
    }
  }

  /// Cambia la contraseña del usuario autenticado.
  static Future<String?> cambiarPassword({
    required String nuevaPassword,
  }) async {
    try {
      await client.auth.updateUser(
        UserAttributes(password: nuevaPassword),
      );
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      AppLogger.error('Error actualizando contraseña', tag: 'AUTH', error: e);
      return 'No se pudo actualizar la contraseña';
    }
  }

  /// Cambia el correo del usuario actual.
  /// Nota: Supabase puede requerir confirmación por email.
  static Future<String?> cambiarEmail({required String nuevoEmail}) async {
    try {
      await client.auth.updateUser(UserAttributes(email: nuevoEmail.trim()));
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'No se pudo actualizar el correo: $e';
    }
  }

  /// Alias operativo del usuario autenticado.
  static Future<String> obtenerAliasVendedorActual() async {
    final perfil = await obtenerPerfil();
    if (perfil?.alias != null && perfil!.alias.isNotEmpty) return perfil.alias;
    final email = client.auth.currentUser?.email;
    if (email != null && email.contains('@')) {
      return email.split('@').first.toUpperCase();
    }
    return 'VENDEDOR';
  }

  /// Crea un perfil mínimo de recuperación cuando el usuario tiene cuenta
  /// Auth pero no tiene fila en la tabla perfiles.
  static Future<Perfil?> crearPerfilDeRecuperacion() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return null;

      final email = user.email ?? 'usuario';
      final base = email.split('@').first;
      final nombre = base.length > 1
          ? base[0].toUpperCase() + base.substring(1)
          : base.toUpperCase();
      const apellido = 'BiPenc';
      final alias = AliasHelper.generarAlias(nombre, apellido);

      // Primer perfil del sistema → SERVER, el resto → VENTAS
      final countRes =
          await client.from('perfiles').select().count(CountOption.exact);
      final bool isFirst = countRes.count == 0;
      final String rol = isFirst ? 'ADMIN' : 'USER';

      AppLogger.info('Creando perfil de recuperación: alias=$alias rol=$rol',
          tag: 'PERFIL');

      await client.from('perfiles').insert({
        'id': user.id,
        'nombre': nombre,
        'apellido': apellido,
        'alias': alias,
        'rol': rol,
      });

      return Perfil(
          id: user.id,
          nombre: nombre,
          apellido: apellido,
          alias: alias,
          rol: rol);
    } catch (e) {
      AppLogger.error('No se pudo crear perfil de recuperación',
          tag: 'PERFIL', error: e);
      return null;
    }
  }

  // ──────────────────────────────────────────────
  // Autenticación
  // ──────────────────────────────────────────────

  static Future<AuthResponse?> iniciarSesion(
      String email, String password) async {
    try {
      final response = await client.auth
          .signInWithPassword(email: email, password: password);
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

  static Future<String?> crearCuenta(
      String email, String password, String nombre, String apellido) async {
    try {
      final res = await client.auth.signUp(email: email, password: password);
      final user = res.user;

      if (user == null) return 'Error al crear la cuenta.';

      if (res.session == null) {
        return 'Cuenta creada. Revisa tu email para confirmar antes de ingresar.';
      }

      final exitoPerfil =
          await _crearPerfilEnBaseDeDatos(user.id, nombre, apellido);

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

  static Future<bool> _crearPerfilEnBaseDeDatos(
      String userId, String nombre, String apellido) async {
    try {
      final alias = AliasHelper.generarAlias(nombre, apellido);

      // Primer perfil del sistema → SERVER, el resto → VENTAS
      final countRes =
          await client.from('perfiles').select().count(CountOption.exact);
      final bool isFirst = countRes.count == 0;
      final String rol = isFirst ? 'ADMIN' : 'USER';

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
      // T1.2: Resolver conflictos antes de bajar la nueva versión
      await resolverConflictosSync();

      final response = await client.from('productos').select().order('nombre');
      final lista = response as List;

      if (lista.isEmpty) {
        AppLogger.info(
            'sincronizarProductos: tabla "productos" sin filas (catálogo vacío)',
            tag: 'SYNC');
        return true;
      }

      final List<Producto> productos = lista
          .map<Producto>((row) => mapToProducto(row as Map<String, dynamic>))
          .where((p) => p.id.isNotEmpty)
          .toList();

      try {
        await LocalDbService.upsertProductos(productos);
        // ... (bidirectional sync logic) ...
        final cloudIds = productos.map((p) => p.id).toSet();
        final localCount = await LocalDbService.contarProductos();
        if (localCount > 0) {
          final localProducts = await LocalDbService.buscarLocal('');
          final localIds = localProducts.map((p) => p.id).toSet();
          final deletedIds = localIds.difference(cloudIds);
          for (final deletedId in deletedIds) {
            await LocalDbService.eliminarProductoLocal(deletedId);
          }
        }
      } catch (dbError) {
        AppLogger.error('Fallo crítico insertando productos en SQLite local',
            tag: 'SYNC', error: dbError);
        return false;
      }
      return true;
    } catch (e) {
      AppLogger.error('Error sincronizando productos: $e',
          tag: 'SYNC', error: e);
      return false;
    }
  }

  /// T1.2: Resuelve conflictos de sincronización usando Last-Timestamp-Wins.
  /// Compara productos locales modificados con la versión en Supabase.
  static Future<void> resolverConflictosSync() async {
    try {
      // 1. Obtener productos locales que han sido modificados (local_version > 0)
      final localesModificados =
          await LocalDbService.obtenerProductosModificadosLocalmente();
      if (localesModificados.isEmpty) return;

      AppLogger.info(
          'Resolviendo conflictos para ${localesModificados.length} productos...',
          tag: 'SYNC_T1_2');

      for (final local in localesModificados) {
        try {
          // 2. Obtener versión de la nube para este SKU
          final cloudRow = await client
              .from('productos')
              .select('last_sync_timestamp, local_version')
              .eq('id', local.id)
              .maybeSingle();

          if (cloudRow == null) {
            // Producto no existe en nube (o fue borrado), ignorar o subir como nuevo
            continue;
          }

          final cloudTs = DateTime.parse(cloudRow['last_sync_timestamp']);
          final localTs =
              local.lastSyncTimestamp ?? DateTime.fromMillisecondsSinceEpoch(0);

          // 3. Estrategia: Last-Timestamp-Wins
          if (localTs.isAfter(cloudTs)) {
            // Local es más reciente -> PUSH a la nube
            AppLogger.info('Conflicto ${local.skuCode}: Local gana (Pushing)',
                tag: 'SYNC_T1_2');
            await client.from('productos').update({
              'last_sync_timestamp': localTs.toIso8601String(),
              'local_version': local
                  .localVersion, // Podríamos resetear a 0 en nube o mantener rastro
              'presentations':
                  local.presentaciones.map((p) => p.toJson()).toList(),
              // ... otros campos críticos ...
            }).eq('id', local.id);

            // Registrar éxito de resolución
            await client.from('sync_conflicts').insert({
              'tabla': 'productos',
              'registro_id': local.id,
              'version_local': local.localVersion,
              'version_servidor': cloudRow['local_version'],
              'resultado': 'LocalWins',
            });
          } else {
            // Nube es más reciente -> LOCAL cede (el Pull normal lo sobreescribirá)
            AppLogger.info(
                'Conflicto ${local.skuCode}: Nube gana (Skipping local change)',
                tag: 'SYNC_T1_2');

            await client.from('sync_conflicts').insert({
              'tabla': 'productos',
              'registro_id': local.id,
              'version_local': local.localVersion,
              'version_servidor': cloudRow['local_version'],
              'resultado': 'ServerWins',
            });
          }
        } catch (itemError) {
          AppLogger.error(
              'Error resolviendo conflicto para ${local.skuCode}: $itemError',
              tag: 'SYNC_T1_2');
        }
      }
    } catch (e) {
      AppLogger.error('Error general en resolverConflictosSync: $e',
          tag: 'SYNC_T1_2');
    }
  }

  /// Categorías dinámicas (Mission CTO)
  static Future<List<String>> obtenerCategorias() async {
    try {
      final res =
          await client.from('categorias').select('nombre').order('nombre');
      return (res as List).map((row) => row['nombre'].toString()).toList();
    } catch (e) {
      AppLogger.warning(
          'No se pudo obtener categorías de Supabase. Usando locales.',
          tag: 'SYNC');
      return List.from(CategoriasProducto.lista);
    }
  }

  static Future<void> agregarCategoria(String nombre) async {
    try {
      await client
          .from('categorias')
          .upsert({'nombre': nombre}, onConflict: 'nombre');
      AppLogger.info('Categoría agregada/actualizada: $nombre', tag: 'SYNC');
    } catch (e) {
      AppLogger.error('Error agregando categoría a Supabase',
          tag: 'SYNC', error: e);
    }
  }

  static Future<bool> eliminarCategoriaSiNoEstaEnUso(String nombre) async {
    try {
      final inUse = await client
          .from('productos')
          .select('id')
          .eq('categoria', nombre)
          .neq('estado', 'DESCONTINUADO')
          .limit(1);
      if ((inUse as List).isNotEmpty) {
        return false;
      }
      await client.from('categorias').delete().eq('nombre', nombre);
      AppLogger.info('Categoría eliminada: $nombre', tag: 'SYNC');
      return true;
    } catch (e) {
      AppLogger.error('Error eliminando categoría en Supabase',
          tag: 'SYNC', error: e);
      return false;
    }
  }

  static Future<void> subirVentasPendientes() async {
    try {
      final pendientes = await LocalDbService.obtenerVentasPendientes();
      if (pendientes.isEmpty) return;

      AppLogger.info('Subiendo ${pendientes.length} ventas pendientes...',
          tag: 'SYNC');
      for (final venta in pendientes) {
        try {
          final itemsDecoded = jsonDecode(venta['items_json'] ?? '[]');

          final ventaPayload = {
            'correlativo': venta['correlativo'],
            'serie': venta['serie'] ?? 'B001',
            'tipo_comprobante_cod':
                (venta['correlativo']?.toString().contains('F') ?? false)
                    ? '01'
                    : '03',
            'items': itemsDecoded,
            'total': venta['total'],
            'subtotal': venta['subtotal'],
            'operacion_gravada': venta['subtotal'], // Blueprint compliance
            'igv': venta['igv'],
            'dni_cliente': venta['documento_cliente'],
            'nombre_cliente': venta['nombre_cliente'],
            'alias_vendedor': venta['alias_vendedor'],
            'despachado': (venta['despachado'] ?? 0) == 1,
          };

          await _insertVentaWithCompatibility(ventaPayload);
          await LocalDbService.marcarVentaSincronizada(venta['id'] as int);
        } catch (itemError) {
          AppLogger.error('Error subiendo venta local ID ${venta['id']}',
              tag: 'SYNC', error: itemError);
          await LocalDbService.registrarErrorSincronizacion(
              venta['id'] as int, itemError.toString());
        }
      }
    } catch (e) {
      AppLogger.error('Error general de cola de ventas pendientes',
          tag: 'SYNC', error: e);
    }
  }

  /// Procesa la cola de sincronización (Stock y Eliminaciones).
  static Future<void> procesarSyncQueue() async {
    try {
      final queue = await LocalDbService.obtenerSyncQueue();
      if (queue.isEmpty) return;

      AppLogger.info('Procesando sync_queue con ${queue.length} items...',
          tag: 'SYNC');
      for (final item in queue) {
        final id = item['id'] as int;
        final tabla = item['tabla'] as String;
        final identifier = item['identificador'] as String;
        final accion = item['accion'] as String;

        bool success = false;
        try {
          if (tabla == 'productos' && accion == 'DELETE') {
            // Borrar de Supabase usando el ID del producto
            await client.from('productos').delete().eq('sku', identifier);
            AppLogger.info(
                'Producto $identifier eliminado de Supabase vía sync_queue',
                tag: 'SYNC');
            success = true;
          }
          // Agregar más acciones/tablas aquí cuando sea necesario
        } catch (e) {
          AppLogger.error('Error procesando sync_queue item $id: $e',
              tag: 'SYNC', error: e);
        }

        if (success) {
          await LocalDbService.eliminarDeSyncQueue(id);
        }
      }
    } catch (e) {
      AppLogger.error('Error procesando sync_queue', tag: 'SYNC', error: e);
    }
  }

  /// T1.5: Procesa la cola de sincronización V2 (Robusta con reintentos).
  static Future<void> procesarSyncQueueV2() async {
    try {
      final queue = await LocalDbService.obtenerSyncQueueV2Pendiente();
      if (queue.isEmpty) return;

      AppLogger.info('Procesando sync_queue_v2 con ${queue.length} items...',
          tag: 'SYNC_V2');

      for (final item in queue) {
        final id = item['id'] as String;
        final tabla = item['tabla'] as String;
        final operacion = item['operacion'] as String;
        final datosStr = item['datos'] as String;
        final datos = jsonDecode(datosStr) as Map<String, dynamic>;

        try {
          if (tabla == 'productos' && operacion == 'DELETE') {
            final sku = (datos['sku'] ?? '').toString();
            final id = (datos['id'] ?? '').toString();
            if (sku.isNotEmpty) {
              await client.from('productos').delete().eq('sku', sku);
              AppLogger.info('Sync V2: Producto $sku eliminado',
                  tag: 'SYNC_V2');
            } else if (id.isNotEmpty) {
              await client.from('productos').delete().eq('id', id);
              AppLogger.info('Sync V2: Producto id=$id eliminado',
                  tag: 'SYNC_V2');
            } else {
              throw Exception('DELETE producto sin sku/id');
            }
          } else if (tabla == 'productos' && operacion == 'UPSERT') {
            await client.from('productos').upsert(datos, onConflict: 'sku');
            AppLogger.info('Sync V2: Producto ${datos['sku']} upsert',
                tag: 'SYNC_V2');
          } else if (tabla == 'productos' && operacion == 'SALE_EVENT') {
            final sku = datos['sku'] as String;
            AppLogger.info('Sync V2: Venta registrada para $sku',
                tag: 'SYNC_V2');
          } else if (tabla == 'productos' && operacion == 'STOCK_UPDATE') {
            // Stock desactivado por decisión funcional del proyecto.
            AppLogger.info(
                'Sync V2: STOCK_UPDATE ignorado (módulo stock desactivado)',
                tag: 'SYNC_V2');
          } else if (tabla == 'ventas' && operacion == 'INSERT') {
            // Ejemplo de inserción de venta si falló inicialmente
            await _insertVentaWithCompatibility(datos);
            AppLogger.info('Sync V2: Venta $id sincronizada', tag: 'SYNC_V2');
          } else if (tabla == 'ventas' && operacion == 'ANULAR') {
            final correlativo = (datos['correlativo'] ?? '').toString();
            if (correlativo.isEmpty) {
              throw Exception('ANULAR sin correlativo en sync_queue_v2');
            }
            final ok = await _updateVentaAnulacionWithCompatibility(
              correlativo: correlativo,
              payload: {
                'anulado': true,
                'anulado_motivo': datos['anulado_motivo'],
                'anulado_at': datos['anulado_at'],
                'anulado_por': datos['anulado_por'],
                'estado': 'ANULADO',
              },
            );
            if (!ok) {
              throw Exception('No fue posible actualizar anulación en nube');
            }
            AppLogger.info('Sync V2: Venta $correlativo anulada',
                tag: 'SYNC_V2');
          }
          // Marcar como exitoso
          await LocalDbService.marcarSyncQueueV2Sincronizado(id);
        } catch (e) {
          AppLogger.error('Error en Sync V2 item $id: $e', tag: 'SYNC_V2');
          await LocalDbService.registrarIntentoSyncQueueV2(id, e.toString());
        }
      }
    } catch (e) {
      AppLogger.error('Error crítico en procesarSyncQueueV2: $e',
          tag: 'SYNC_V2');
    }
  }

  // ──────────────────────────────────────────────
  // Ventas
  // ──────────────────────────────────────────────

  // ELIMINADO: generarSiguienteCorrelativo local para evitar colisiones.
  // La base de datos ahora asigna el número atómicamente mediante get_next_correlativo.

  static Future<Venta?> registrarVenta({
    required List<ItemCarrito> items,
    required double total,
    required String alias,
    required String metodoPago,
    required String tipoDocumento,
    String? dniRuc,
    String? nombreCliente,
  }) async {
    try {
      final itemsData = items
          .map((i) => {
                'sku': i.producto.skuCode.isNotEmpty
                    ? i.producto.skuCode
                    : i.producto.id,
                'nombre': i.producto.nombre,
                'marca': i.producto.marca,
                'cantidad': i.cantidad,
                'presentacion_id': i.presentacion.id,
                'presentacion_nombre': i.presentacion.name,
                'unidades_totales': i.unidadesTotales,
                'precio': i.precioActual,
              })
          .toList();

      // Calcular impuestos usando tasa de configuración
      final ivaRate = await ConfigService.obtenerIGVActual();
      final base = total / (1 + ivaRate);
      final igvValue = total - base;

      final response = await client
          .from('ventas')
          .insert({
            'correlativo': null, // Asignación automática en Servidor (SUNAT V2)
            'serie': 'B001',
            'tipo_comprobante_cod': tipoDocumento == 'BOLETA' ? '03' : '01',
            'items': itemsData,
            'total': total,
            'subtotal': base,
            'operacion_gravada': base,
            'igv': igvValue,
            'alias_vendedor': alias,
            'metodo_pago': metodoPago,
            'tipo_documento': tipoDocumento,
            'dni_ruc': dniRuc,
            'nombre_cliente': nombreCliente,
          })
          .select()
          .single();

      AppLogger.info(
          'Venta registrada: ${response['correlativo']} total=S/$total',
          tag: 'VENTAS');

      // Devolvemos el modelo hidratado con el correlativo real de la DB
      return Venta.fromMap({
        'id': response['id'].toString(),
        'fecha': response['created_at'] ?? DateTime.now().toIso8601String(),
        'tipoComprobante': tipoDocumento == 'BOLETA' ? 'boleta' : 'factura',
        'documentoCliente': dniRuc ?? '00000000',
        'nombreCliente': nombreCliente,
        'correlativo': response['correlativo'],
        'operacionGravada': (response['operacion_gravada'] ?? 0.0).toDouble(),
        'igv': (response['igv'] ?? 0.0).toDouble(),
        'total': (response['total'] ?? 0.0).toDouble(),
        'serie': response['serie'] ?? 'B001',
        'metodoPago': metodoPago.toLowerCase(), // Normalizar para el enum
        'montoRecibido': total,
        'vuelto': 0.0,
        'items': itemsData,
        'despachado': 0,
      });
    } catch (e) {
      AppLogger.error('Error registrando venta', tag: 'VENTAS', error: e);
      return null;
    }
  }

  static Future<bool> anularVentaEnNube({
    required String correlativo,
    required String motivo,
    required String aliasUsuario,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      final ok = await _updateVentaAnulacionWithCompatibility(
        correlativo: correlativo,
        payload: {
          'anulado': true,
          'anulado_motivo': motivo,
          'anulado_at': now,
          'anulado_por': aliasUsuario,
          'estado': 'ANULADO',
        },
      );
      return ok;
    } catch (e) {
      AppLogger.error('Error anulando venta en nube', tag: 'VENTAS', error: e);
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
    final normalizedSku =
        p.skuCode.trim().isNotEmpty ? p.skuCode.trim().toUpperCase() : p.id;
    try {
      final Map<String, dynamic> data = {
        'id': p.id,
        'sku': normalizedSku,
        'nombre': p.nombre,
        'marca': p.marca,
        'categoria': p.categoria,
        'presentaciones':
            p.presentaciones.map((pres) => pres.toJson()).toList(),
        'precio_base': p.precioBase,
        'precio_mayorista': p.precioMayorista,
        'precio_caja_12': p.getPrecioPresentacion('c12'),
        'precio_caja_72': p.getPrecioPresentacion('c72'),
        'precio_especial': p.getPrecioPresentacion('espe'),
        'imagen_url': p.imagenPath,
        'creado_por': userAlias,
        'descripcion': p.descripcion,
        'updated_at': DateTime.now().toIso8601String(),
        'estado': isAdmin ? 'VERIFICADO' : 'PENDIENTE',
      };

      if (isUpdate) {
        await client.from('productos').update(data).eq('sku', normalizedSku);
      } else {
        await client.from('productos').insert(data);
      }

      AppLogger.info(
          'Producto ${isUpdate ? "actualizado" : "creado"}: $normalizedSku',
          tag: 'PRODUCTOS');
      return true;
    } catch (e) {
      AppLogger.error('Error en upsert de producto',
          tag: 'PRODUCTOS', error: e);
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

      final List<dynamic> responseList = response as List;
      return responseList
          .map<Producto>((data) => mapToProducto(data as Map<String, dynamic>))
          .toList();
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

      final List<dynamic> responseList = response as List;
      return responseList
          .map<Producto>((data) => mapToProducto(data as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('Error en auditoría', tag: 'PRODUCTOS', error: e);
      return [];
    }
  }

  static Future<bool> aprobarProducto(
      String sku, double pBase, double pMayorista) async {
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

  static Producto mapToProducto(Map<String, dynamic> data) {
    // El id debe ser el UUID de Supabase (Art 5.2)
    final id = (data['id'] ?? '').toString();
    final sku = (data['sku'] ?? '').toString();

    List<Presentacion> presentations = [];

    try {
      if (data['presentaciones'] != null) {
        if (data['presentaciones'] is String) {
          presentations = (jsonDecode(data['presentaciones']) as List)
              .map((i) => Presentacion.fromJson(i))
              .toList();
        } else if (data['presentaciones'] is List) {
          presentations = (data['presentaciones'] as List)
              .map((i) => Presentacion.fromJson(Map<String, dynamic>.from(i)))
              .toList();
        }
      }
    } catch (e) {
      AppLogger.warning('Error parseando presentaciones para sku=$sku: $e',
          tag: 'SYNC');
    }

    // Fallback a columnas individuales si presentaciones está vacío
    if (presentations.isEmpty) {
      final precioBase =
          (data['precio_base'] ?? data['precio'] ?? 0).toDouble();
      final precioMayorista = (data['precio_mayorista'] ?? 0).toDouble();
      presentations = [
        Presentacion(
            id: 'unid',
            skuCode: sku,
            name: 'Unidad',
            conversionFactor: 1,
            barcode: sku,
            prices: [PricePoint(type: 'NORMAL', amount: precioBase)]),
        if (precioMayorista > 0)
          Presentacion(
              id: 'mayo',
              skuCode: '$sku-MAYO',
              name: 'Mayorista',
              conversionFactor: 1,
              prices: [PricePoint(type: 'NORMAL', amount: precioMayorista)]),
        if ((data['precio_caja_12'] ?? 0) > 0)
          Presentacion(
              id: 'c12',
              skuCode: '$sku-C12',
              name: 'Caja x12',
              conversionFactor: 12,
              prices: [
                PricePoint(
                    type: 'NORMAL', amount: (data['precio_caja_12']).toDouble())
              ]),
        if ((data['precio_caja_72'] ?? 0) > 0)
          Presentacion(
              id: 'c72',
              skuCode: '$sku-C72',
              name: 'Caja x72',
              conversionFactor: 72,
              prices: [
                PricePoint(
                    type: 'NORMAL', amount: (data['precio_caja_72']).toDouble())
              ]),
        if ((data['precio_especial'] ?? 0) > 0)
          Presentacion(
              id: 'espe',
              skuCode: '$sku-ESPE',
              name: 'Especial',
              conversionFactor: 1,
              prices: [
                PricePoint(
                    type: 'NORMAL',
                    amount: (data['precio_especial']).toDouble())
              ]),
      ];
    }

    return Producto(
      id: id,
      skuCode: sku,
      nombre: (data['nombre'] ?? 'SIN NOMBRE').toString(),
      marca: (data['marca'] ?? 'GENÉRICO').toString(),
      categoria: (data['categoria'] ?? 'General').toString(),
      presentaciones: presentations,
      imagenPath: data['imagen_url']?.toString(),
      estado: (data['estado'] ?? 'PENDIENTE').toString(),
      creadoPor: data['creado_por']?.toString(),
      descripcion: data['descripcion']?.toString(),
      updatedAt: data['updated_at'] != null
          ? DateTime.tryParse(data['updated_at'].toString())
          : null,
      lastSyncTimestamp: data['last_sync_timestamp'] != null
          ? DateTime.tryParse(data['last_sync_timestamp'].toString())
          : null,
      localVersion: data['local_version'] as int? ?? 0,
      syncHash: data['sync_hash']?.toString(),
    );
  }

  // ──────────────────────────────────────────────
  // PATRÓN WATERFALL: Supabase primero, fallback SQLite
  // ──────────────────────────────────────────────

  /// Intenta guardar venta en Supabase primero.
  /// Si éxito: retorna (true, docId)
  /// Si falla: retorna (false, null) para que el cliente caiga a SQLite
  ///
  /// IMPORTANTE: El cliente es responsable de guardar en SQLite si esto falla.
  /// Patrón:
  /// ```dart
  /// final (success, docId) = await SupabaseService.insertarVentaWaterfall(venta);
  /// if (!success) {
  ///   await LocalDbService.guardarVentaPendienteAtomica(...);  // Fallback
  /// }
  /// ```
  static Future<(bool success, String? docId)> insertarVentaWaterfall(
      Venta venta) async {
    try {
      // 1. Validar que hay conexión
      final isOnline = await _checkConectividad();
      if (!isOnline) {
        AppLogger.warning('Sin conexión. Venta será guardada offline.',
            tag: 'WATERFALL');
        return (false, null);
      }

      final itemsData = venta.items
          .map((i) => {
                'sku': i.producto.id,
                'nombre': i.producto.nombre,
                'marca': i.producto.marca,
                'cantidad': i.cantidad,
                'presentacion_id': i.presentacion.id,
                'presentacion_nombre': i.presentacion.name,
                'unidades_totales': i.unidadesTotales,
                'precio': i.precioActual,
              })
          .toList();

      // 2. Preparar datos de venta (modelo unificado con tabla `ventas`)
      final docData = {
        'correlativo': venta.id,
        'serie': venta.serie,
        'tipo_comprobante_cod':
            venta.tipoComprobante == TipoComprobante.factura ? '01' : '03',
        'items': itemsData,
        'nombre_cliente': venta.nombreCliente,
        'dni_cliente': venta.documentoCliente,
        'operacion_gravada': venta.operacionGravada,
        'subtotal': venta.operacionGravada,
        'igv': venta.igv,
        'total': venta.total,
        'metodo_pago': venta.metodoPago.name.toUpperCase(),
        'despachado': false,
      };

      // 3. Intenta insertar venta
      final docRes = await _insertVentaReturningWithCompatibility(docData);

      if (docRes['id'] == null) {
        throw Exception('Response vacío al insertar documento');
      }

      final docId = docRes['id'].toString();

      // 4. Insertar items normalizados (best-effort)
      for (final item in venta.items) {
        final itemData = {
          'venta_id': docId,
          'producto_id': item.producto.id,
          'presentacion_id': item.presentacion.id,
          'cantidad': item.cantidad,
          'precio_unitario': item.precioActual,
          'subtotal': item.subtotal,
          'precio_override': item.manualPriceOverride,
        };

        try {
          await client
              .from('venta_items')
              .insert(itemData)
              .timeout(const Duration(seconds: 15));
        } catch (itemErr) {
          AppLogger.warning(
            'No se pudo insertar item en venta_items (venta principal OK): $itemErr',
            tag: 'WATERFALL',
          );
        }
      }

      // 5. Log de éxito
      AppLogger.info(
        'Venta guardada en Supabase: $docId | Total: S/.${venta.total.toStringAsFixed(2)}',
        tag: 'WATERFALL',
      );

      return (true, docId);
    } on TimeoutException catch (_) {
      AppLogger.warning(
        'Timeout guardando en Supabase. Fallback a SQLite.',
        tag: 'WATERFALL',
      );
      return (false, null);
    } on PostgrestException catch (e) {
      AppLogger.error(
        'Error PostgreSQL al guardar venta: ${e.message}',
        tag: 'WATERFALL',
        error: e,
      );
      return (false, null);
    } catch (e, st) {
      AppLogger.error(
        'Error inesperado en Waterfall sync',
        tag: 'WATERFALL',
        error: e,
      );
      debugPrint('Stack trace: $st');
      return (false, null);
    }
  }

  /// Verifica conectividad rápida
  static Future<bool> _checkConectividad() async {
    try {
      await client
          .from('perfiles')
          .select('id')
          .limit(1)
          .maybeSingle()
          .timeout(const Duration(seconds: 4));
      return true;
    } on PostgrestException {
      // El servidor respondió (aunque haya restricciones RLS).
      return true;
    } on TimeoutException {
      return false;
    } on SocketException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
