import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bipenc/datos/modelos/producto.dart';
import 'package:bipenc/datos/modelos/presentacion.dart';
import 'package:bipenc/utilidades/alias.dart';
import 'package:bipenc/servicios/servicio_base_datos_local.dart';
import 'package:bipenc/utilidades/registro_app.dart';
import 'package:bipenc/utilidades/fiscal.dart';
import 'package:path/path.dart' as p;
import 'package:bipenc/datos/modelos/venta.dart';
import 'package:bipenc/servicios/servicio_configuracion.dart';
import 'package:bipenc/arquitectura/constantes/categorias_producto.dart';
import 'package:bipenc/arquitectura/constantes/estados_producto.dart';
import 'package:bipenc/servicios/supabase/servicio_monitoreo.dart';
import 'package:bipenc/datos/modelos/perfil.dart';
import 'package:sqflite/sqflite.dart';

part 'supabase/supabase_sincronizacion.dart';
part 'supabase/supabase_ventas.dart';
part 'supabase/supabase_productos.dart';

class ServicioSupabase {
  @visibleForTesting
  static SupabaseClient? clientOverride;

  static const String _productosLastFullSyncKey = 'productos_last_full_sync_ms';
  static const String _productosLastDeltaSyncKey =
      'productos_last_delta_sync_ms';
  static const Duration _productosFullSyncInterval = Duration(hours: 24);
  static const int _productosPageSize = 500;

  static SupabaseClient get client =>
      clientOverride ?? Supabase.instance.client;

  static SupabaseClient? get _maybeClient {
    try {
      return clientOverride ?? Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  // ──────────────────────────────────────────────
  // Cache compartido de documentos (DNI/RUC)
  // ──────────────────────────────────────────────

  static Future<Map<String, dynamic>?> fetchDocumentoCache(
      String numero) async {
    try {
      final res = await client
          .from('document_cache')
          .select()
          .eq('numero', numero)
          .maybeSingle();
      return res;
    } on PostgrestException catch (e) {
      // Si la tabla no existe en Supabase, devolvemos null silencioso
      if (e.code == '42P01') {
        RegistroApp.warning('Tabla document_cache no existe; se omite fetch',
            tag: 'DOC_CACHE');
        return null;
      }
      RegistroApp.error('Error fetchDocumentoCache',
          tag: 'DOC_CACHE', error: e);
      return null;
    } catch (e) {
      RegistroApp.error('Error fetchDocumentoCache',
          tag: 'DOC_CACHE', error: e);
      return null;
    }
  }

  static Future<bool> upsertDocumentoCache({
    required String numero,
    required String tipo,
    required String nombre,
    String? direccion,
    required int expiresAtMs,
  }) async {
    try {
      await client.from('document_cache').upsert({
        'numero': numero,
        'tipo': tipo,
        'nombre': nombre,
        'direccion': direccion,
        'cached_at': DateTime.now().millisecondsSinceEpoch,
        'expires_at': expiresAtMs,
      });
      return true;
    } catch (e) {
      RegistroApp.warn('Upsert document_cache falló (best-effort)',
          tag: 'DOC_CACHE', error: e);
      return false;
    }
  }

  // ──────────────────────────────────────────────
  // Configuración de empresa
  // ──────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getConfiguracionEmpresa() async {
    try {
      final res = await client
          .from('empresa_config')
          .select()
          .eq('id', 1)
          .maybeSingle();
      return res;
    } catch (e) {
      RegistroApp.error('Error obteniendo empresa_config',
          tag: 'EMPRESA', error: e);
      return null;
    }
  }

  static Future<void> upsertConfiguracionEmpresa(
      Map<String, dynamic> values) async {
    try {
      await client.from('empresa_config').upsert(values..['id'] = 1);
    } catch (e) {
      RegistroApp.error('Error guardando empresa_config',
          tag: 'EMPRESA', error: e);
    }
  }

  /// Obtiene items de venta desde Supabase (tabla venta_items) usando venta_id
  /// o correlativo. Devuelve una lista de mapas simples.
  static Future<List<Map<String, dynamic>>> fetchVentaItemsSimple(
      {String? ventaId, String? correlativo}) async {
    try {
      if (ventaId == null && correlativo == null) return [];
      String? resolvedVentaId = ventaId;
      if (resolvedVentaId == null && correlativo != null) {
        try {
          final venta = await client
              .from('ventas')
              .select('id')
              .eq('correlativo', correlativo)
              .maybeSingle();
          resolvedVentaId = venta?['id']?.toString();
        } catch (e) {
          RegistroApp.warn('No se pudo resolver venta_id por correlativo',
              tag: 'VENTA_ITEMS', error: e);
          return [];
        }
      }
      if (resolvedVentaId == null) return [];
      final data = await client
          .from('venta_items')
          .select()
          .eq('venta_id', resolvedVentaId)
          .timeout(const Duration(seconds: 15));
      return (data as List).map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      RegistroApp.error('Error fetchVentaItemsSimple',
          tag: 'VENTA_ITEMS', error: e);
    }
    return [];
  }

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
      RegistroApp.warning(
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
        RegistroApp.warning(
          'Compat: columna "dni_cliente" no existe; reintentando con "dni_ruc"',
          tag: 'WATERFALL',
        );
      } else if (!next.containsKey('documento_cliente') && dniValue != null) {
        next['documento_cliente'] = dniValue;
        RegistroApp.warning(
          'Compat: columna "dni_cliente" no existe; reintentando con "documento_cliente"',
          tag: 'WATERFALL',
        );
      } else {
        RegistroApp.warning(
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
      RegistroApp.warning(
        'Compat: columna "dni_ruc" no existe; reintentando con "documento_cliente"',
        tag: 'WATERFALL',
      );
      return next;
    }

    if (_isMissingColumnError(e, 'documento_cliente') &&
        currentPayload.containsKey('documento_cliente')) {
      final next = Map<String, dynamic>.from(currentPayload)
        ..remove('documento_cliente');
      RegistroApp.warning(
        'Compat: columna "documento_cliente" no existe; reintentando sin documento de cliente',
        tag: 'WATERFALL',
      );
      return next;
    }

    if (_isMissingColumnError(e, 'order_list_id') &&
        currentPayload.containsKey('order_list_id')) {
      final next = Map<String, dynamic>.from(currentPayload)
        ..remove('order_list_id');
      RegistroApp.warning(
        'Compat: columna "order_list_id" no existe; reintentando sin link a pedido',
        tag: 'WATERFALL',
      );
      return next;
    }

    return null;
  }

  // ignore: unused_element
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
      RegistroApp.debug(
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
        RegistroApp.info(
          'Correlativo generado por RPC: $corrResult',
          tag: 'CORRELATIVO',
        );
        return corrResult;
      }

      // Si RPC retorna null o sin campo correlativo
      throw Exception('RPC retornó respuesta vacía');
    } on PostgrestException catch (e) {
      RegistroApp.warning(
        'Error PostgreSQL en RPC de correlativo: ${e.message}',
        tag: 'CORRELATIVO',
      );
      return _generarCorrelativoFallback(alias: alias, motivo: e.message);
    } on TimeoutException catch (_) {
      RegistroApp.warning(
        'Timeout en RPC correlativo.',
        tag: 'CORRELATIVO',
      );
      return _generarCorrelativoFallback(alias: alias, motivo: 'timeout');
    } catch (e) {
      RegistroApp.error(
        'Error inesperado en RPC correlativo: $e',
        tag: 'CORRELATIVO',
        error: e,
      );
      return _generarCorrelativoFallback(alias: alias, motivo: e.toString());
    }
  }

  /// Fallback: Genera correlativo temporal si RPC falla
  /// Usa timestamp + random para evitar colisiones
  static String _generarCorrelativoFallback({String? alias, String? motivo}) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(9000) + 1000;
    final device = _maybeClient?.auth.currentUser?.id ?? 'device';
    // REFACTOR: prefijo local + device id garantizan continuidad offline sin colisiones.
    final corr = 'T-${alias ?? 'POS'}-$device-$ts-$rand';
    RegistroApp.warning(
      'Fallback de correlativo usado: $corr (motivo: ${motivo ?? 'desconocido'})',
      tag: 'CORRELATIVO',
    );
    return corr;
  }

  // ──────────────────────────────────────────────
  // Config correlativos (supabase)
  // ──────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> obtenerConfigCorrelativos() async {
    try {
      final res = await client.from('config_correlativos').select();
      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      RegistroApp.error('Error obteniendo config_correlativos',
          tag: 'CORR', error: e);
      return [];
    }
  }

  static Future<void> upsertConfigCorrelativo({
    required String tipoDocumento,
    required String serie,
    required int ultimoNumero,
  }) async {
    try {
      final payload = {
        'tipo_documento': tipoDocumento,
        'serie': serie,
        'ultimo_numero': ultimoNumero,
      };
      try {
        await client
            .from('config_correlativos')
            .upsert(payload, onConflict: 'tipo_documento,serie');
      } on PostgrestException catch (e) {
        // Compatibilidad: si no existe constraint compuesto, reintenta con clave simple.
        RegistroApp.warn(
            'Upsert correlativo con conflict compuesto falló, reintentando simple',
            tag: 'CORR',
            error: e);
        await client
            .from('config_correlativos')
            .upsert(payload, onConflict: 'tipo_documento');
      }
    } catch (e) {
      RegistroApp.error('Error upsert correlativo', tag: 'CORR', error: e);
    }
  }

  static Future<bool> resetVentasProduccion() async {
    try {
      await client.rpc('reset_ventas');
      return true;
    } catch (e) {
      RegistroApp.error('Error ejecutando reset_ventas',
          tag: 'RESET', error: e);
      return false;
    }
  }

  @visibleForTesting
  static String generarCorrelativoFallbackForTest() =>
      _generarCorrelativoFallback(alias: 'TEST', motivo: 'unit');

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
        RegistroApp.warning(
            'Tabla store_config no existe; se omite check de versión',
            tag: 'CONFIG');
      } else {
        RegistroApp.error('Error obteniendo min_version',
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
      final uploadFile = await _prepareUploadFile(imageFile);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${p.basename(uploadFile.path)}';
      final path = fileName;

      await client.storage.from('productos').upload(path, uploadFile);

      final String publicUrl =
          client.storage.from('productos').getPublicUrl(path);
      RegistroApp.info('Imagen subida: $publicUrl', tag: 'STORAGE');
      return publicUrl;
    } catch (e) {
      RegistroApp.error('Error subiendo imagen', tag: 'STORAGE', error: e);
      return null;
    }
  }

  /// Sube avatar de perfil al bucket `productos` (ruta `avatars/`) y retorna URL pública.
  static Future<String?> subirAvatarPerfil(File imageFile) async {
    try {
      final uploadFile = await _prepareUploadFile(imageFile);
      final fileName =
          'avatar_${DateTime.now().millisecondsSinceEpoch}_${p.basename(uploadFile.path)}';
      try {
        // Bucket dedicado (preferido)
        await client.storage.from('avatars').upload(fileName, uploadFile);
        final String publicUrl =
            client.storage.from('avatars').getPublicUrl(fileName);
        RegistroApp.info('Avatar subido (avatars): $publicUrl', tag: 'STORAGE');
        return publicUrl;
      } on StorageException catch (e) {
        // Fallback compatible con instalaciones antiguas
        RegistroApp.warn(
            'Bucket avatars no disponible, usando productos/avatars',
            tag: 'STORAGE',
            error: e);
        final legacyPath = 'avatars/$fileName';
        await client.storage.from('productos').upload(legacyPath, uploadFile);
        final String publicUrl =
            client.storage.from('productos').getPublicUrl(legacyPath);
        RegistroApp.info('Avatar subido (fallback): $publicUrl',
            tag: 'STORAGE');
        return publicUrl;
      }
    } catch (e) {
      RegistroApp.error('Error subiendo avatar', tag: 'STORAGE', error: e);
      return null;
    }
  }

  // Comprime antes de subir (70% calidad, max 800px)
  static Future<File> _prepareUploadFile(File file) async {
    try {
      final out = await FlutterImageCompress.compressAndGetFile(
        file.path,
        '${file.path}.tmp.webp',
        quality: 70,
        minWidth: 800,
        minHeight: 800,
        format: CompressFormat.webp,
      );
      if (out != null) return File(out.path);
    } catch (_) {}
    return file;
  }

  // ──────────────────────────────────────────────
  // Perfiles
  // ──────────────────────────────────────────────

  static Future<Perfil?> obtenerPerfil() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) {
        RegistroApp.warning('currentUser es null', tag: 'PERFIL');
        return null;
      }

      final response = await client
          .from('perfiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (response == null) {
        RegistroApp.warning(
            'No se encontró fila en perfiles para userId: ${user.id}',
            tag: 'PERFIL');
        return null;
      }

      RegistroApp.debug(
          'Perfil cargado: alias=${response['alias']} rol=${response['rol']}',
          tag: 'PERFIL');

      return Perfil.fromMap(response);
    } catch (e) {
      RegistroApp.error('Error obteniendo perfil', tag: 'PERFIL', error: e);
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

      // Hardening: foto_url es el nombre oficial en la DB Diamond
      if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
        payload['foto_url'] = avatarUrl.trim();
      }

      try {
        await client.from('perfiles').update(payload).eq('id', user.id);
      } on PostgrestException catch (e) {
        // Compatibilidad: si foto_url no existe, intenta avatar_url
        if (_isMissingColumnError(e, 'foto_url') &&
            payload.containsKey('foto_url')) {
          payload['avatar_url'] = payload.remove('foto_url');
          await client.from('perfiles').update(payload).eq('id', user.id);
        } else {
          rethrow;
        }
      }
      return true;
    } catch (e) {
      RegistroApp.error('Error actualizando perfil', tag: 'PERFIL', error: e);
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
      RegistroApp.error('Error actualizando contraseña', tag: 'AUTH', error: e);
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

  /// Garantiza que exista una fila en `perfiles` para el usuario actual y
  /// retorna el alias resultante (o null si no se pudo).
  static Future<String?> ensurePerfilConAlias() async {
    final existing = await obtenerPerfil();
    if (existing != null && existing.alias.isNotEmpty) return existing.alias;

    final recovered = await crearPerfilDeRecuperacion();
    if (recovered != null && recovered.alias.isNotEmpty) return recovered.alias;

    return null;
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
      final alias = Alias.generarAlias(nombre, apellido);

      // Hardening: rol por defecto siempre USER. Elevación solo por RPC controlada.
      const String rol = 'USER';

      RegistroApp.info('Creando perfil de recuperación: alias=$alias rol=$rol',
          tag: 'PERFIL');

      // Intentar alias único (por constraint perfiles_alias_key)
      for (var attempt = 0; attempt < 5; attempt++) {
        final suffix = attempt == 0 ? '' : '${attempt + 1}';
        final candidate = '$alias$suffix'; // JB, JB2, JB3...
        try {
          await client.from('perfiles').insert({
            'id': user.id,
            'nombre': nombre,
            'apellido': apellido,
            'alias': candidate,
            'rol': rol,
            'estado': 'ACTIVO',
          });
          return Perfil(
              id: user.id,
              nombre: nombre,
              apellido: apellido,
              alias: candidate,
              rol: rol,
              estado: 'ACTIVO');
        } on PostgrestException catch (e) {
          if (e.code == '23505') {
            RegistroApp.warning(
                'Alias duplicado ($candidate), reintentando con sufijo...',
                tag: 'PERFIL');
            continue;
          }
          rethrow;
        }
      }
      throw Exception('No se pudo generar alias único');
    } catch (e) {
      RegistroApp.error('No se pudo crear perfil de recuperación',
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
      RegistroApp.info('Login OK: ${response.user?.email}', tag: 'AUTH');
      return response;
    } on AuthException catch (e) {
      RegistroApp.error('Error AuthException: ${e.message}', tag: 'AUTH');
      rethrow;
    } catch (e) {
      RegistroApp.error('Error inesperado en login', tag: 'AUTH', error: e);
      return null;
    }
  }

  // ──────────────────────────────────────────────
  // Sincronización (delegada)
  // ──────────────────────────────────────────────
  static Future<bool> sincronizarProductos() => _sincronizarProductos();
  static Future<void> resolverConflictosSync() => _resolverConflictosSync();
  static Future<List<String>> obtenerCategorias() => _obtenerCategorias();
  static Future<void> agregarCategoria(String nombre) =>
      _agregarCategoria(nombre);
  static Future<bool> eliminarCategoriaSiNoEstaEnUso(String nombre) =>
      _eliminarCategoriaSiNoEstaEnUso(nombre);

  @Deprecated('Usa ServicioMonitoreoSupabase.upsertCarritoEnVivo')
  static Future<void> upsertCarritoEnVivo(Map<String, dynamic> payload) =>
      _upsertCarritoEnVivo(payload);

  static Future<int> subirCatalogoLocal() => _subirCatalogoLocal();
  static Future<void> subirVentasPendientes() => _subirVentasPendientes();
  static Future<void> procesarSyncQueue() => _procesarSyncQueue();
  static Future<void> procesarSyncQueueV2() => _procesarSyncQueueV2();

  // ──────────────────────────────────────────────
  // Ventas
  // ──────────────────────────────────────────────
  // ──────────────────────────────────────────────
  // Sincronización (Multi-Depósito V1)
  // ──────────────────────────────────────────────
  static Future<(bool ok, String error)> syncAll(
          {bool soloProductos = false, bool soloVentas = false}) =>
      _syncAll(soloProductos: soloProductos, soloVentas: soloVentas);

  static Future<void> sincronizarDepositos() => _sincronizarDepositos();

  static Future<void> sincronizarStockMultiDeposito() =>
      _sincronizarStockMultiDeposito();

  static Future<Venta?> registrarVenta({
    required List<ItemCarrito> items,
    required double total,
    required String alias,
    required String metodoPago,
    required String tipoDocumento,
    String? dniRuc,
    String? nombreCliente,
  }) =>
      _registrarVenta(
        items: items,
        total: total,
        alias: alias,
        metodoPago: metodoPago,
        tipoDocumento: tipoDocumento,
        dniRuc: dniRuc,
        nombreCliente: nombreCliente,
      );

  static Future<bool> anularVentaEnNube({
    required String correlativo,
    required String motivo,
    required String aliasUsuario,
  }) =>
      _anularVentaEnNube(
        correlativo: correlativo,
        motivo: motivo,
        aliasUsuario: aliasUsuario,
      );

  // ──────────────────────────────────────────────
  // Productos
  // ──────────────────────────────────────────────
  static Future<bool> upsertProducto(
    Producto p, {
    bool isUpdate = false,
    required String userRol,
    required String userAlias,
  }) =>
      _upsertProducto(
        p,
        isUpdate: isUpdate,
        userRol: userRol,
        userAlias: userAlias,
      );

  static Future<List<Producto>> buscarProductos(String query) =>
      _buscarProductos(query);

  static Future<List<Producto>> buscarPorCodigoRemoto(String codigo) =>
      _buscarPorCodigoRemoto(codigo);

  static Future<DateTime?> obtenerUltimaActualizacionProductos() =>
      _obtenerMaxUpdatedProductos();

  static Future<bool> vincularCodigoRemoto(
    String codigo,
    String presentacionId, {
    String? descripcion,
  }) =>
      _vincularCodigoRemoto(codigo, presentacionId, descripcion);

  static Future<bool> desvincularCodigoRemoto(
    String codigo,
    String presentacionId,
  ) =>
      _desvincularCodigoRemoto(codigo, presentacionId);

  static Future<List<Producto>> obtenerProductosParaAuditoria() =>
      _obtenerProductosParaAuditoria();

  static Future<bool> aprobarProducto(String id) => _aprobarProducto(id);

  // ──────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────
  static Producto mapToProducto(Map<String, dynamic> data) =>
      _mapToProducto(data);

  // ──────────────────────────────────────────────
  // Waterfall / Conectividad
  // ──────────────────────────────────────────────
  static Future<(bool success, String? docId)> insertarVentaWaterfall(
          Venta venta) =>
      _insertarVentaWaterfall(venta);

  static Future<bool> tieneConexionRemota() => _tieneConexionRemota();
}
