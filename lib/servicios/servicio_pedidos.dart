import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bipenc/datos/modelos/pedido.dart';
import 'package:bipenc/utilidades/registro_app.dart';
import 'package:bipenc/servicios/servicio_backend.dart';

/// Servicio para gestionar listas de pedidos (order_lists)
/// Consume tabla order_lists en Supabase
class ServicioPedidos {
  static final ServicioPedidos _instance = ServicioPedidos._internal();
  final client = Supabase.instance.client;

  factory ServicioPedidos() => _instance;
  ServicioPedidos._internal();

  /// Obtener todas las listas de pedidos del usuario
  /// Opcionalmente filtrar por estado
  Future<List<Pedido>> getPedidos({
    String? estado,
    int limit = 50,
  }) async {
    try {
      dynamic query = client.from('order_lists').select();
      if (estado != null && estado.trim().isNotEmpty) {
        query = query.eq('estado', estado.trim());
      }
      final response =
          await query.order('created_at', ascending: false).limit(limit);

      return (response as List)
          .map((item) => Pedido.fromJson(item))
          .toList();
    } catch (e) {
      RegistroApp.error('Error obteniendo listas de pedidos',
          tag: 'ORDER_LIST', error: e);
      return [];
    }
  }

  Future<List<String>> getResponsablesDisponibles() async {
    try {
      final res = await client
          .from('perfiles')
          .select('alias, nombre, apellido')
          .order('alias');
      final list = <String>{};
      for (final row in (res as List)) {
        final map = row as Map<String, dynamic>;
        final alias = (map['alias'] ?? '').toString().trim();
        if (alias.isEmpty) continue;
        final nombre = (map['nombre'] ?? '').toString().trim();
        final apellido = (map['apellido'] ?? '').toString().trim();
        final display = [
          alias,
          if (nombre.isNotEmpty || apellido.isNotEmpty)
            [nombre, apellido].where((e) => e.isNotEmpty).join(' ')
        ].join(' — ');
        list.add(display);
      }
      if (list.isEmpty) {
        final aliasFallback =
            await ServicioBackend.obtenerAliasVendedorActual();
        list.add(aliasFallback);
      }
      return list.toList()..sort();
    } catch (e) {
      RegistroApp.error('Error obteniendo responsables',
          tag: 'ORDER_LIST', error: e);
      return [];
    }
  }

  /// Obtener lista de pedidos por ID
  Future<Pedido?> getPedidoById(String id) async {
    try {
      final response =
          await client.from('order_lists').select().eq('id', id).maybeSingle();

      if (response == null) return null;
      return Pedido.fromJson(response);
    } catch (e) {
      RegistroApp.error('Error obteniendo lista de pedidos',
          tag: 'ORDER_LIST', error: e);
      return null;
    }
  }

  /// Crear nueva lista de pedidos
  Future<Pedido?> createPedido({
    required String clienteNombre,
    required double montoAdelantado,
    double? totalLista,
    String? telefono,
    String? responsable,
    int? bultos,
    String? destinatario,
    required DateTime fechaRecojo,
    String? notas,
  }) async {
    try {
      // Asegurar que el usuario tenga fila en perfiles (RLS lo exige).
      final alias = await ServicioBackend.ensurePerfilConAlias();
      if (alias == null || alias.isEmpty) {
        throw Exception(
            'No hay perfil asociado al usuario actual. Intenta reautenticar o crea el perfil en Ajustes > Perfil.');
      }

      final now = DateTime.now();
      final meta = PedidoMeta(
        telefono: telefono,
        responsable: responsable,
        totalLista: totalLista,
        bultos: bultos,
        destinatario: destinatario,
      );
      final payload = {
        'alias_vendedor': alias,
        'cliente_nombre': clienteNombre,
        'cliente_telefono': telefono,
        'items': <Map<String, dynamic>>[],
        'total_estimado': totalLista ?? montoAdelantado,
        'monto_adelantado': montoAdelantado,
        'fecha_recojo': fechaRecojo.toIso8601String(),
        'fotos_urls': <String>[],
        'estado': 'PENDIENTE',
        'notas': PedidoMetaCodec.encode(meta: meta, notas: notas),
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final response =
          await client.from('order_lists').insert(payload).select().single();

      final created = Pedido.fromJson(response);
      RegistroApp.info(
        'Lista de pedidos creada: ${created.id} | Cliente: ${created.clienteNombre}',
        tag: 'ORDER_LIST',
      );
      return created;
    } catch (e) {
      RegistroApp.error('Error creando lista de pedidos',
          tag: 'ORDER_LIST', error: e);
      rethrow;
    }
  }

  /// Marca un pedido como completado y enlaza el correlativo de venta.
  /// Usa estrategia tolerante: si la columna correlativo_comprobante no existe,
  /// reintenta sin ella para no romper RLS.
  Future<bool> completarConVenta({
    required String orderId,
    String? correlativoComprobante,
    String? estadoFallback = 'COMPLETADO',
  }) async {
    try {
      final payload = {
        'estado': estadoFallback ?? 'COMPLETADO',
        'updated_at': DateTime.now().toIso8601String(),
        if (correlativoComprobante != null)
          'correlativo_comprobante': correlativoComprobante,
      };
      try {
        await client.from('order_lists').update(payload).eq('id', orderId);
      } on PostgrestException catch (e) {
        if (e.code == 'PGRST204' &&
            (e.message.toLowerCase().contains('correlativo_comprobante'))) {
          payload.remove('correlativo_comprobante');
          await client.from('order_lists').update(payload).eq('id', orderId);
        } else {
          rethrow;
        }
      }
      RegistroApp.info('Pedido $orderId completado con venta $correlativoComprobante',
          tag: 'ORDER_LIST');
      return true;
    } catch (e) {
      RegistroApp.error('Error completando pedido con venta',
          tag: 'ORDER_LIST', error: e);
      return false;
    }
  }

  /// Subir foto de lista a Storage y actualizar fotos_urls
  /// Retorna (success, fotoUrl)
  /// VERBOSE: Cada paso del flujo se registra para debugging
  Future<(bool success, String? fotoUrl)> uploadFotoAndUpdate(
    String orderListId,
    File imagenFile,
  ) async {
    bool uploaded = false;
    String? uploadedPath;
    try {
      // 1. Subir imagen a Storage bucket "pedidos"
      RegistroApp.debug('[1/4] Subiendo foto a Storage...', tag: 'ORDER_LIST');
      final fileName =
          '${orderListId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = 'fotos/$fileName';
      uploadedPath = path;

      RegistroApp.debug('  Nombre archivo: $fileName', tag: 'ORDER_LIST');
      RegistroApp.debug('  Tamaño: ${imagenFile.lengthSync()} bytes',
          tag: 'ORDER_LIST');

      await client.storage.from('pedidos').upload(path, imagenFile);
      uploaded = true;
      RegistroApp.debug('[2/4] ✅ Archivo subido a Storage', tag: 'ORDER_LIST');

      final fotoUrl = client.storage.from('pedidos').getPublicUrl(path);
      RegistroApp.debug('  URL obtenida: $fotoUrl', tag: 'ORDER_LIST');

      // 2. Obtener lista actual para agregar URL
      RegistroApp.debug('[3/4] Recuperando lista actual...', tag: 'ORDER_LIST');
      final lista = await getPedidoById(orderListId);
      if (lista == null) throw Exception('Lista de pedidos no encontrada');

      // 3. Agregar URL a array fotosUrls
      final fotosActualizadas = [...lista.fotosUrls, fotoUrl];
      RegistroApp.debug('  Fotos en lista: ${fotosActualizadas.length}',
          tag: 'ORDER_LIST');

      // 4. Actualizar en base de datos
      RegistroApp.debug('[4/4] Actualizando tabla order_lists...',
          tag: 'ORDER_LIST');
      await client.from('order_lists').update({
        'fotos_urls': fotosActualizadas,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', orderListId);

      RegistroApp.info(
        '✅ Foto subida completamente: $fotoUrl para lista $orderListId',
        tag: 'ORDER_LIST',
      );
      return (true, fotoUrl);
    } on Exception catch (e) {
      RegistroApp.error(
        '❌ Error en uploadFotoAndUpdate: $e',
        tag: 'ORDER_LIST',
        error: e,
      );
      if (uploaded && uploadedPath != null) {
        try {
          await client.storage.from('pedidos').remove([uploadedPath]);
          RegistroApp.warning('Foto huérfana eliminada: $uploadedPath',
              tag: 'ORDER_LIST');
        } catch (_) {}
      }
      return (false, null);
    }
  }

  /// Actualizar estado de la lista de pedidos
  Future<bool> updatePedidoStatus(String id, String nuevoEstado) async {
    try {
      await client.from('order_lists').update({
        'estado': nuevoEstado,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);

      RegistroApp.info('Lista $id actualizada a estado: $nuevoEstado',
          tag: 'ORDER_LIST');
      return true;
    } catch (e) {
      RegistroApp.error('Error actualizando estado', tag: 'ORDER_LIST', error: e);
      return false;
    }
  }

  /// Actualizar notas de la lista
  Future<bool> updatePedidoNotes(String id, String notas) async {
    try {
      await client.from('order_lists').update({
        'notas': notas,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);

      RegistroApp.info('Notas actualizadas para lista $id', tag: 'ORDER_LIST');
      return true;
    } catch (e) {
      RegistroApp.error('Error actualizando notas', tag: 'ORDER_LIST', error: e);
      return false;
    }
  }

  /// Actualiza montos y metadata de contacto/deuda.
  Future<bool> updatePedidoFinancial({
    required Pedido order,
    double? nuevoTotalLista,
    double? nuevoMontoPagado,
    String? nuevoTelefono,
    String? nuevoResponsable,
  }) async {
    try {
      final totalLista = nuevoTotalLista ?? order.totalLista;
      final montoPagado = nuevoMontoPagado ?? order.montoAdelantado;
      final meta = order.meta.copyWith(
        telefono: nuevoTelefono ?? order.telefonoContacto,
        responsable: nuevoResponsable ?? order.responsable,
        totalLista: totalLista,
      );
      final saldo = totalLista - montoPagado;
      final estado = saldo <= 0 ? 'ENTREGADO' : order.estado;

      await client.from('order_lists').update({
        'monto_adelantado': montoPagado,
        'estado': estado,
        'total_estimado': totalLista,
        'notas': PedidoMetaCodec.encode(meta: meta, notas: order.notas),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', order.id);

      return true;
    } catch (e) {
      RegistroApp.error('Error actualizando datos financieros de lista',
          tag: 'ORDER_LIST', error: e);
      return false;
    }
  }

  /// Eliminar lista de pedidos (soft delete recomendado)
  /// Por ahora, actualiza estado a 'CANCELADO'
  Future<bool> cancelPedido(String id) async {
    try {
      await client.from('order_lists').update({
        'estado': 'CANCELADO',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);

      RegistroApp.info('Lista $id cancelada (soft delete)', tag: 'ORDER_LIST');
      return true;
    } catch (e) {
      RegistroApp.error('Error cancelando lista', tag: 'ORDER_LIST', error: e);
      return false;
    }
  }
}
