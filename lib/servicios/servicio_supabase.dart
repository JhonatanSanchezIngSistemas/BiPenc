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
import 'package:bipenc/servicios/servicio_db_local.dart';
import 'package:bipenc/utilidades/registro_app.dart';
import 'package:bipenc/utilidades/fiscal.dart';
import 'package:path/path.dart' as p;
import 'package:bipenc/datos/modelos/venta.dart';
import 'package:bipenc/servicios/servicio_configuracion.dart';
import 'package:bipenc/base/constantes/categorias_producto.dart';
import 'package:bipenc/base/constantes/estados_producto.dart';
import 'package:bipenc/servicios/supabase/servicio_monitoreo.dart';

class ServicioSupabase {
  @visibleForTesting
  static SupabaseClient? clientOverride;

  static const String _productosLastFullSyncKey =
      'productos_last_full_sync_ms';
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
        RegistroApp.warning(
            'Tabla document_cache no existe; se omite fetch',
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
  static Future<Map<String, dynamic>?> getEmpresaConfig() async {
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

  static Future<void> upsertEmpresaConfig(Map<String, dynamic> values) async {
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
      RegistroApp.error('Error obteniendo config_correlativos', tag: 'CORR', error: e);
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
      RegistroApp.error('Error ejecutando reset_ventas', tag: 'RESET', error: e);
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
      final path = 'public/$fileName';

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
        RegistroApp.info('Avatar subido (fallback): $publicUrl', tag: 'STORAGE');
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

      RegistroApp.info(
          'Perfil: alias=${response['alias']} rol=${response['rol']}',
          tag: 'PERFIL');
      return Perfil(
        id: response['id'],
        nombre: response['nombre'],
        apellido: response['apellido'],
        alias: response['alias'],
        rol: response['rol'],
        estado: (response['estado'] ?? 'ACTIVO').toString(),
        deviceId: response['device_id'],
      );
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

      // Fallback: intentar crear perfil mínimo si hubo conflicto de alias u otro fallo de DB.
      final recovered = await crearPerfilDeRecuperacion();
      if (recovered != null) return null;

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
      RegistroApp.error('Error en registro', tag: 'AUTH', error: e);
      if (e.toString().contains('FormatException')) {
        return 'Error de servidor. Revisa tu conexión.';
      }
      return 'Error: $e';
    }
  }

  static Future<bool> _crearPerfilEnBaseDeDatos(
      String userId, String nombre, String apellido) async {
    try {
      final alias = Alias.generarAlias(nombre, apellido);

      // Hardening: rol por defecto siempre VENTAS. Elevación solo por RPC controlada.
      const String rol = 'VENTAS';

      for (var attempt = 0; attempt < 5; attempt++) {
        final suffix = attempt == 0 ? '' : '${attempt + 1}';
        final candidate = '$alias$suffix';
        try {
          await client.from('perfiles').insert({
            'id': userId,
            'nombre': nombre,
            'apellido': apellido,
            'alias': candidate,
            'rol': rol,
            'estado': 'ACTIVO',
          });
          return true;
        } on PostgrestException catch (e) {
          if (e.code == '23505') {
            RegistroApp.warning(
                'Alias duplicado ($candidate), reintentando con sufijo...',
                tag: 'AUTH');
            continue;
          }
          RegistroApp.error('Error insertando perfil en DB',
              tag: 'AUTH', error: e);
          return false;
        }
      }
      RegistroApp.error('No se pudo generar alias único para perfil',
          tag: 'AUTH');
      return false;
    } catch (e) {
      RegistroApp.error('Error insertando perfil en DB', tag: 'AUTH', error: e);
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

      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toUtc();
      final lastFullMs = prefs.getInt(_productosLastFullSyncKey);
      final lastDeltaMs = prefs.getInt(_productosLastDeltaSyncKey);
      final lastFull = lastFullMs != null
          ? DateTime.fromMillisecondsSinceEpoch(lastFullMs, isUtc: true)
          : null;
      final doFull = lastFull == null ||
          now.difference(lastFull) >= _productosFullSyncInterval;

      if (doFull) {
        final ok = await _fullSyncProductos();
        if (ok) {
          await prefs.setInt(_productosLastFullSyncKey, now.millisecondsSinceEpoch);
          await prefs.setInt(_productosLastDeltaSyncKey, now.millisecondsSinceEpoch);
        }
        return ok;
      }

      final since = lastDeltaMs != null
          ? DateTime.fromMillisecondsSinceEpoch(lastDeltaMs, isUtc: true)
          : lastFull;

      try {
        final result = await _deltaSyncProductos(since);
        if (result.ok) {
          final marker = (result.maxUpdated ?? now).toUtc();
          await prefs.setInt(
              _productosLastDeltaSyncKey, marker.millisecondsSinceEpoch);
        }
        return result.ok;
      } on PostgrestException catch (e) {
        // Fallback si no existe updated_at o falla el filtro incremental.
        if (_isMissingColumnError(e, 'updated_at')) {
          RegistroApp.warning(
            'sincronizarProductos: updated_at no disponible, fallback full sync',
            tag: 'SYNC',
          );
          final ok = await _fullSyncProductos();
          if (ok) {
            await prefs.setInt(_productosLastFullSyncKey, now.millisecondsSinceEpoch);
            await prefs.setInt(_productosLastDeltaSyncKey, now.millisecondsSinceEpoch);
          }
          return ok;
        }
        rethrow;
      }
    } catch (e) {
      RegistroApp.error('Error sincronizando productos: $e',
          tag: 'SYNC', error: e);
      return false;
    }
  }

  static Future<bool> _fullSyncProductos() async {
    final response = await client.from('productos').select().order('nombre');
    final lista = response as List;

    if (lista.isEmpty) {
      RegistroApp.info(
          'sincronizarProductos: tabla "productos" sin filas (catálogo vacío)',
          tag: 'SYNC');
      return true;
    }

    final List<Producto> productos = lista
        .map<Producto>((row) => mapToProducto(row as Map<String, dynamic>))
        .where((p) => p.id.isNotEmpty)
        .toList();

    try {
      await ServicioDbLocal.upsertProductos(productos);
      // ... (bidirectional sync logic) ...
      final cloudIds = productos.map((p) => p.id).toSet();
      final localCount = await ServicioDbLocal.contarProductos();
      if (localCount > 0) {
        final localProducts = await ServicioDbLocal.buscarLocal('');
        final localIds = localProducts.map((p) => p.id).toSet();
        final deletedIds = localIds.difference(cloudIds);
        for (final deletedId in deletedIds) {
          await ServicioDbLocal.eliminarProductoLocal(deletedId);
        }
      }
    } catch (dbError) {
      RegistroApp.error('Fallo crítico insertando productos en SQLite local',
          tag: 'SYNC', error: dbError);
      return false;
    }
    return true;
  }

  static Future<({bool ok, DateTime? maxUpdated, int fetched})>
      _deltaSyncProductos(DateTime since) async {
    DateTime? maxUpdated;
    var totalFetched = 0;
    var offset = 0;
    final sinceIso = since.toUtc().toIso8601String();

    while (true) {
      final data = await client
          .from('productos')
          .select()
          .gt('updated_at', sinceIso)
          .order('updated_at', ascending: true)
          .range(offset, offset + _productosPageSize - 1)
          .timeout(const Duration(seconds: 30));

      final lista = data as List;
      if (lista.isEmpty) break;
      totalFetched += lista.length;

      final productos = lista
          .map<Producto>((row) => mapToProducto(row as Map<String, dynamic>))
          .where((p) => p.id.isNotEmpty)
          .toList();

      await ServicioDbLocal.upsertProductos(productos);

      for (final row in lista) {
        final raw = (row as Map<String, dynamic>)['updated_at'];
        final parsed = raw != null ? DateTime.tryParse(raw.toString()) : null;
        final currentMax = maxUpdated;
        if (parsed != null &&
            (currentMax == null || parsed.isAfter(currentMax))) {
          maxUpdated = parsed;
        }
      }

      if (lista.length < _productosPageSize) break;
      offset += _productosPageSize;
    }

    return (ok: true, maxUpdated: maxUpdated, fetched: totalFetched);
  }

  /// T1.2: Resuelve conflictos de sincronización usando Last-Timestamp-Wins.
  /// Compara productos locales modificados con la versión en Supabase.
  static Future<void> resolverConflictosSync() async {
    try {
      // 1. Obtener productos locales que han sido modificados (local_version > 0)
      final localesModificados =
          await ServicioDbLocal.obtenerProductosModificadosLocalmente();
      if (localesModificados.isEmpty) return;

      RegistroApp.info(
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
            RegistroApp.info('Conflicto ${local.skuCode}: Local gana (Pushing)',
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
            RegistroApp.info(
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
          RegistroApp.error(
              'Error resolviendo conflicto para ${local.skuCode}: $itemError',
              tag: 'SYNC_T1_2');
        }
      }
    } catch (e) {
      RegistroApp.error('Error general en resolverConflictosSync: $e',
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
      RegistroApp.warning(
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
      RegistroApp.info('Categoría agregada/actualizada: $nombre', tag: 'SYNC');
    } catch (e) {
      RegistroApp.error('Error agregando categoría a Supabase',
          tag: 'SYNC', error: e);
    }
  }

  static Future<bool> eliminarCategoriaSiNoEstaEnUso(String nombre) async {
    try {
      // Si hay productos usándola, los movemos a categoría DEFAULT
      const categoriaFallback = 'SIN CATEGORIA';

      final inUse = await client
          .from('productos')
          .select('id')
          .eq('categoria', nombre)
          .eq('estado', EstadoProducto.activo);

      if ((inUse as List).isNotEmpty) {
        await client.from('categorias').upsert({'nombre': categoriaFallback});
        await client
            .from('productos')
            .update({'categoria': categoriaFallback})
            .eq('categoria', nombre);
        RegistroApp.warning(
            'Productos reasignados a "$categoriaFallback" porque la categoría "$nombre" estaba en uso',
            tag: 'SYNC');
      }

      await client.from('categorias').delete().eq('nombre', nombre);
      RegistroApp.info('Categoría eliminada: $nombre', tag: 'SYNC');
      return true;
    } catch (e) {
      RegistroApp.error('Error eliminando categoría en Supabase',
          tag: 'SYNC', error: e);
      return false;
    }
  }

  @Deprecated('Usa ServicioMonitoreoSupabase.upsertCarritoEnVivo')
  static Future<void> upsertCarritoEnVivo(Map<String, dynamic> payload) async {
    await ServicioMonitoreoSupabase.upsertCarritoEnVivo(payload);
  }

  /// Sincroniza TODO el catálogo local hacia la nube.
  /// Útil cuando la nube está vacía pero el dispositivo tiene datos.
  static Future<int> subirCatalogoLocal() async {
    try {
      final productos = await RepositorioProductosLocal.obtenerTodosLosProductos();
      if (productos.isEmpty) return 0;

      RegistroApp.info('Subiendo catálogo local: ${productos.length} productos',
          tag: 'SYNC');

      int subidos = 0;
      for (final p in productos) {
        try {
          // 1. Upsert del producto
          final productData = {
            'sku': p.skuCode,
            'nombre': p.nombre,
            'marca': p.marca,
            'categoria': p.categoria,
            'precio_propuesto': p.precioPropuesto,
            'estado': p.estado,
            'imagen_url': p.imagenPath,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          };

          await client.from('productos').upsert(productData, onConflict: 'sku');

          // 2. Upsert de presentaciones (mapeo a tabla product_presentations)
          if (p.presentaciones.isNotEmpty) {
            final List<Map<String, dynamic>> presentationsBatch = [];
            for (final pres in p.presentaciones) {
              presentationsBatch.add({
                'sku_code': pres.barcode ?? pres.id,
                'product_id': null, // Se vincula por SKU o trigger en BD si es posible, o buscamos por SKU
                'price': pres.getPriceByType('NORMAL'),
                'conversion_factor': pres.conversionFactor,
                'is_active': true,
              });
            }
            // Nota: En un sistema real, product_id es FK. 
            // Aquí intentaremos el upsert confiando en que sku_code sea único 
            // o que el backend lo resuelva. 
            if (presentationsBatch.isNotEmpty) {
               await client.from('product_presentations').upsert(presentationsBatch, onConflict: 'sku_code');
            }
          }
          
          subidos++;
        } catch (e) {
          RegistroApp.error('Error subiendo producto ${p.skuCode}: $e', tag: 'SYNC');
        }
      }
      
      return subidos;
    } catch (e) {
      RegistroApp.error('Error general en subirCatalogoLocal', tag: 'SYNC', error: e);
      return 0;
    }
  }

  static Future<void> subirVentasPendientes() async {
    try {
      final pendientes = await ServicioDbLocal.obtenerVentasPendientes();
      if (pendientes.isEmpty) return;

      RegistroApp.info('Subiendo ${pendientes.length} ventas pendientes...',
          tag: 'SYNC');
      for (final venta in pendientes) {
        try {
          final itemsDecoded =
              (jsonDecode(venta['items_json'] ?? '[]') as List?) ?? [];

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
            'metodo_pago': venta['metodo_pago'],
            'despachado': (venta['despachado'] ?? 0) == 1,
            if (venta['order_list_id'] != null)
              'order_list_id': venta['order_list_id'],
          };

          final itemsNormalized = _itemsForVentaItemsFromJson(itemsDecoded);
          await _insertVentaWithItemsBestEffort(
            ventaPayload: ventaPayload,
            itemsNormalized: itemsNormalized,
          );
          await ServicioDbLocal.marcarVentaSincronizada(venta['id'] as int);
        } catch (itemError) {
          RegistroApp.error('Error subiendo venta local ID ${venta['id']}',
              tag: 'SYNC', error: itemError);
          await ServicioDbLocal.registrarErrorSincronizacion(
              venta['id'] as int, itemError.toString());
        }
      }
    } catch (e) {
      RegistroApp.error('Error general de cola de ventas pendientes',
          tag: 'SYNC', error: e);
    }
  }

  /// Procesa la cola de sincronización (Stock y Eliminaciones).
  static Future<void> procesarSyncQueue() async {
    try {
      final queue = await ServicioDbLocal.obtenerSyncQueue();
      if (queue.isEmpty) return;

      RegistroApp.info('Procesando sync_queue con ${queue.length} items...',
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
            RegistroApp.info(
                'Producto $identifier eliminado de Supabase vía sync_queue',
                tag: 'SYNC');
            success = true;
          }
          // Agregar más acciones/tablas aquí cuando sea necesario
        } catch (e) {
          RegistroApp.error('Error procesando sync_queue item $id: $e',
              tag: 'SYNC', error: e);
        }

        if (success) {
          await ServicioDbLocal.eliminarDeSyncQueue(id);
        }
      }
    } catch (e) {
      RegistroApp.error('Error procesando sync_queue', tag: 'SYNC', error: e);
    }
  }

  /// T1.5: Procesa la cola de sincronización V2 (Robusta con reintentos).
  static Future<void> procesarSyncQueueV2() async {
    try {
      final queue = await ServicioDbLocal.obtenerSyncQueueV2Pendiente();
      if (queue.isEmpty) return;

      RegistroApp.info('Procesando sync_queue_v2 con ${queue.length} items...',
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
              RegistroApp.info('Sync V2: Producto $sku eliminado',
                  tag: 'SYNC_V2');
            } else if (id.isNotEmpty) {
              await client.from('productos').delete().eq('id', id);
              RegistroApp.info('Sync V2: Producto id=$id eliminado',
                  tag: 'SYNC_V2');
            } else {
              throw Exception('DELETE producto sin sku/id');
            }
          } else if (tabla == 'productos' && operacion == 'UPSERT') {
            await client.from('productos').upsert(datos, onConflict: 'sku');
            RegistroApp.info('Sync V2: Producto ${datos['sku']} upsert',
                tag: 'SYNC_V2');
          } else if (tabla == 'productos' && operacion == 'SALE_EVENT') {
            final sku = datos['sku'] as String;
            RegistroApp.info('Sync V2: Venta registrada para $sku',
                tag: 'SYNC_V2');
          } else if (tabla == 'productos' && operacion == 'STOCK_UPDATE') {
            // Stock desactivado por decisión funcional del proyecto.
            RegistroApp.info(
                'Sync V2: STOCK_UPDATE ignorado (módulo stock desactivado)',
                tag: 'SYNC_V2');
          } else if (tabla == 'ventas' && operacion == 'INSERT') {
            // Ejemplo de inserción de venta si falló inicialmente
            await _insertVentaWithCompatibility(datos);
            RegistroApp.info('Sync V2: Venta $id sincronizada', tag: 'SYNC_V2');
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
            RegistroApp.info('Sync V2: Venta $correlativo anulada',
                tag: 'SYNC_V2');
          } else if (tabla == 'document_cache' && operacion == 'UPSERT') {
            await client.from('document_cache').upsert(datos);
            RegistroApp.info(
                'Sync V2: Documento ${datos['numero']} actualizado en cache',
                tag: 'SYNC_V2');
          } else if (tabla == 'producto_codigos' && operacion == 'VINCULAR_CODIGO') {
            final codigo = (datos['codigo_barras'] ?? '').toString();
            final productoId = (datos['producto_id'] ?? '').toString();
            final variante = datos['descripcion_variante']?.toString();
            // Buscar el SKU del producto para la tabla puente (que usa sku como FK)
            if (codigo.isNotEmpty && productoId.isNotEmpty) {
              final prodRow = await ServicioDbLocal.getProductoById(productoId);
              final sku = prodRow?.skuCode ?? productoId;
              await vincularCodigoRemoto(codigo, sku, variante: variante);
              RegistroApp.info('Sync V2: Código $codigo vinculado a $sku', tag: 'SYNC_V2');
            }
          } else if (tabla == 'producto_codigos' && operacion == 'DESVINCULAR_CODIGO') {
            final codigo = (datos['codigo_barras'] ?? '').toString();
            final productoId = (datos['producto_id'] ?? '').toString();
            if (codigo.isNotEmpty && productoId.isNotEmpty) {
              final prodRow = await ServicioDbLocal.getProductoById(productoId);
              final sku = prodRow?.skuCode ?? productoId;
              await desvincularCodigoRemoto(codigo, sku);
              RegistroApp.info('Sync V2: Código $codigo desvinculado de $sku', tag: 'SYNC_V2');
            }
          }
          // Marcar como exitoso
          await ServicioDbLocal.marcarSyncQueueV2Sincronizado(id);
        } catch (e) {
          RegistroApp.error('Error en Sync V2 item $id: $e', tag: 'SYNC_V2');
          await ServicioDbLocal.registrarIntentoSyncQueueV2(id, e.toString());
        }
      }
    } catch (e) {
      RegistroApp.error('Error crítico en procesarSyncQueueV2: $e',
          tag: 'SYNC_V2');
    }
  }

  // ──────────────────────────────────────────────
  // Ventas
  // ──────────────────────────────────────────────

  // ELIMINADO: generarSiguienteCorrelativo local para evitar colisiones.
  // La base de datos ahora asigna el número atómicamente mediante get_next_correlativo.

  static num _asNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  static List<Map<String, dynamic>> _itemsForVentaItemsFromVenta(Venta venta) {
    return venta.items
        .map((i) => {
              'producto_id': i.producto.id,
              'presentacion_id': i.presentacion.id,
              'cantidad': i.cantidad,
              'precio_unitario': i.precioActual,
              'subtotal': i.subtotal,
              'precio_override': i.manualPriceOverride,
            })
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _itemsForVentaItemsFromJson(
      List<dynamic> items) {
    final out = <Map<String, dynamic>>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final productoId = (map['producto_id'] ??
              map['sku'] ??
              map['sku_code'] ??
              map['id'])
          ?.toString();
      final presentacionId = map['presentacion_id']?.toString();
      final cantidad = _asNum(map['cantidad']);
      final precioUnit = _asNum(map['precio_unitario'] ?? map['precio']);
      final subtotal = _asNum(map['subtotal']);
      final precioOverride = map.containsKey('precio_override')
          ? _asNum(map['precio_override'])
          : null;

      if (productoId == null || productoId.isEmpty) {
        RegistroApp.warning('Item sin producto_id/sku en items_json, omitido',
            tag: 'SYNC');
        continue;
      }

      out.add({
        'producto_id': productoId,
        'presentacion_id': presentacionId ?? '',
        'cantidad': cantidad,
        'precio_unitario': precioUnit,
        'subtotal': subtotal,
        'precio_override': precioOverride,
      });
    }
    return out;
  }

  static Future<String?> _tryInsertVentaWithItemsRpc({
    required Map<String, dynamic> ventaPayload,
    required List<Map<String, dynamic>> itemsNormalized,
  }) async {
    try {
      final params = {
        'p_correlativo': ventaPayload['correlativo'],
        'p_serie': ventaPayload['serie'],
        'p_tipo_comprobante_cod': ventaPayload['tipo_comprobante_cod'],
        'p_items': ventaPayload['items'],
        'p_items_norm': itemsNormalized,
        'p_total': ventaPayload['total'],
        'p_subtotal': ventaPayload['subtotal'],
        'p_operacion_gravada': ventaPayload['operacion_gravada'],
        'p_igv': ventaPayload['igv'],
        'p_nombre_cliente': ventaPayload['nombre_cliente'],
        'p_dni_cliente': ventaPayload['dni_cliente'] ??
            ventaPayload['dni_ruc'] ??
            ventaPayload['documento_cliente'],
        'p_alias_vendedor': ventaPayload['alias_vendedor'],
        'p_metodo_pago': ventaPayload['metodo_pago'],
        'p_despachado': ventaPayload['despachado'] ?? false,
        'p_order_list_id': ventaPayload['order_list_id'],
      };

      final res = await client
          .rpc('insert_venta_with_items', params: params)
          .timeout(const Duration(seconds: 30));
      if (res == null) return null;
      if (res is String) return res;
      if (res is Map && res['id'] != null) return res['id'].toString();
      return res.toString();
    } on PostgrestException catch (e) {
      RegistroApp.warning(
        'RPC insert_venta_with_items no disponible: ${e.message}',
        tag: 'WATERFALL',
      );
      return null;
    } catch (e) {
      RegistroApp.warning(
        'RPC insert_venta_with_items falló: $e',
        tag: 'WATERFALL',
      );
      return null;
    }
  }

  static Future<void> _insertVentaItemsBestEffort(
    String ventaId,
    List<Map<String, dynamic>> itemsNormalized,
  ) async {
    for (final itemData in itemsNormalized) {
      try {
        await client
            .from('venta_items')
            .insert({
              'venta_id': ventaId,
              'producto_id': itemData['producto_id'],
              'presentacion_id': itemData['presentacion_id'],
              'cantidad': itemData['cantidad'],
              'precio_unitario': itemData['precio_unitario'],
              'subtotal': itemData['subtotal'],
              'precio_override': itemData['precio_override'],
            })
            .timeout(const Duration(seconds: 15));
      } catch (itemErr) {
        RegistroApp.warning(
          'No se pudo insertar item en venta_items (venta principal OK): $itemErr',
          tag: 'WATERFALL',
        );
      }
    }
  }

  static Future<String> _insertVentaWithItemsBestEffort({
    required Map<String, dynamic> ventaPayload,
    required List<Map<String, dynamic>> itemsNormalized,
  }) async {
    final rpcId = await _tryInsertVentaWithItemsRpc(
      ventaPayload: ventaPayload,
      itemsNormalized: itemsNormalized,
    );
    if (rpcId != null) return rpcId;

    final docRes =
        await _insertVentaReturningWithCompatibility(ventaPayload);
    final docId = docRes['id']?.toString();
    if (docId == null) {
      throw Exception('Response vacío al insertar documento');
    }
    await _insertVentaItemsBestEffort(docId, itemsNormalized);
    return docId;
  }

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

      // Calcular impuestos usando tasa de configuración (redondeo 2d)
      final ivaRate = await ServicioConfiguracion.obtenerIGVActual();
      final desglose = UtilFiscal.calcularDesglose(total, tasa: ivaRate);
      final base = desglose.$1;
      final igvValue = desglose.$2;

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
            'estado_sunat': 'EMITIDO',
          })
          .select()
          .single();

      RegistroApp.info(
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
      RegistroApp.error('Error registrando venta', tag: 'VENTAS', error: e);
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
          'estado_sunat': 'ANULADO',
        },
      );
      return ok;
    } catch (e) {
      RegistroApp.error('Error anulando venta en nube', tag: 'VENTAS', error: e);
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

      RegistroApp.info(
          'Producto ${isUpdate ? "actualizado" : "creado"}: $normalizedSku',
          tag: 'PRODUCTOS');
      return true;
    } catch (e) {
      RegistroApp.error('Error en upsert de producto',
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
      RegistroApp.error('Error buscando productos', tag: 'PRODUCTOS', error: e);
      return [];
    }
  }

  // ── TABLA PUENTE: producto_codigos (v22) ────────────────────────────────

  /// Busca todos los productos asociados a un código de barras via tabla puente en Supabase.
  static Future<List<Producto>> buscarPorCodigoRemoto(String codigo) async {
    try {
      final rows = await client
          .from('producto_codigos')
          .select('producto_sku')
          .eq('codigo_barras', codigo.trim());
      final skus = (rows as List)
          .map((r) => r['producto_sku']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      if (skus.isEmpty) return [];
      final productoRows = await client
          .from('productos')
          .select()
          .inFilter('sku', skus);
      return (productoRows as List)
          .map<Producto>((d) => mapToProducto(d as Map<String, dynamic>))
          .toList();
    } catch (e) {
      RegistroApp.error('Error buscando por código remoto', tag: 'BARCODE', error: e);
      return [];
    }
  }

  /// Vincula un código de barras a un producto en Supabase (tabla puente).
  static Future<bool> vincularCodigoRemoto(
      String codigo, String productoSku, {String? variante}) async {
    try {
      await client.from('producto_codigos').upsert({
        'codigo_barras': codigo.trim(),
        'producto_sku': productoSku,
        'descripcion_variante': variante,
      }, onConflict: 'codigo_barras,producto_sku');
      RegistroApp.info('[Remoto] Vinculado: $codigo → $productoSku', tag: 'BARCODE');
      return true;
    } catch (e) {
      RegistroApp.error('Error vinculando código remoto', tag: 'BARCODE', error: e);
      return false;
    }
  }

  /// Desvincula un código de barras de un producto en Supabase.
  static Future<bool> desvincularCodigoRemoto(
      String codigo, String productoSku) async {
    try {
      await client
          .from('producto_codigos')
          .delete()
          .eq('codigo_barras', codigo.trim())
          .eq('producto_sku', productoSku);
      RegistroApp.info('[Remoto] Desvinculado: $codigo ↛ $productoSku', tag: 'BARCODE');
      return true;
    } catch (e) {
      RegistroApp.error('Error desvinculando código remoto', tag: 'BARCODE', error: e);
      return false;
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
      RegistroApp.error('Error en auditoría', tag: 'PRODUCTOS', error: e);
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
      RegistroApp.error('Error aprobando producto', tag: 'PRODUCTOS', error: e);
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
      RegistroApp.warning('Error parseando presentaciones para sku=$sku: $e',
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
            prices: [PuntoPrecio(type: 'NORMAL', amount: precioBase)]),
        if (precioMayorista > 0)
          Presentacion(
              id: 'mayo',
              skuCode: '$sku-MAYO',
              name: 'Mayorista',
              conversionFactor: 1,
              prices: [PuntoPrecio(type: 'NORMAL', amount: precioMayorista)]),
        if ((data['precio_caja_12'] ?? 0) > 0)
          Presentacion(
              id: 'c12',
              skuCode: '$sku-C12',
              name: 'Caja x12',
              conversionFactor: 12,
              prices: [
                PuntoPrecio(
                    type: 'NORMAL', amount: (data['precio_caja_12']).toDouble())
              ]),
        if ((data['precio_caja_72'] ?? 0) > 0)
          Presentacion(
              id: 'c72',
              skuCode: '$sku-C72',
              name: 'Caja x72',
              conversionFactor: 72,
              prices: [
                PuntoPrecio(
                    type: 'NORMAL', amount: (data['precio_caja_72']).toDouble())
              ]),
        if ((data['precio_especial'] ?? 0) > 0)
          Presentacion(
              id: 'espe',
              skuCode: '$sku-ESPE',
              name: 'Especial',
              conversionFactor: 1,
              prices: [
                PuntoPrecio(
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
  /// final (success, docId) = await ServicioSupabase.insertarVentaWaterfall(venta);
  /// if (!success) {
  ///   await ServicioDbLocal.guardarVentaPendienteAtomica(...);  // Fallback
  /// }
  /// ```
  static Future<(bool success, String? docId)> insertarVentaWaterfall(
      Venta venta) async {
    try {
      // 1. Validar que hay conexión
      final isOnline = await _checkConectividad();
      if (!isOnline) {
        RegistroApp.warning('Sin conexión. Venta será guardada offline.',
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
        if (venta.orderListId != null) 'order_list_id': venta.orderListId,
        'operacion_gravada': venta.operacionGravada,
        'subtotal': venta.operacionGravada,
        'igv': venta.igv,
        'total': venta.total,
        'metodo_pago': venta.metodoPago.name.toUpperCase(),
        'despachado': false,
      };

      // 3. Insertar venta e items de forma atómica (RPC) o best-effort.
      final itemsNormalized = _itemsForVentaItemsFromVenta(venta);
      final docId = await _insertVentaWithItemsBestEffort(
        ventaPayload: docData,
        itemsNormalized: itemsNormalized,
      );

      // 5. Log de éxito
      RegistroApp.info(
        'Venta guardada en Supabase: $docId | Total: S/.${venta.total.toStringAsFixed(2)}',
        tag: 'WATERFALL',
      );

      return (true, docId);
    } on TimeoutException catch (_) {
      RegistroApp.warning(
        'Timeout guardando en Supabase. Fallback a SQLite.',
        tag: 'WATERFALL',
      );
      return (false, null);
    } on PostgrestException catch (e) {
      RegistroApp.error(
        'Error PostgreSQL al guardar venta: ${e.message}',
        tag: 'WATERFALL',
        error: e,
      );
      return (false, null);
    } catch (e, st) {
      RegistroApp.error(
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

  /// Verifica conectividad real con Supabase (para evitar falsos positivos).
  static Future<bool> tieneConexionRemota() async => _checkConectividad();
}
