import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bipenc/data/models/order_list.dart';
import 'package:bipenc/utils/app_logger.dart';

/// Servicio para gestionar listas de pedidos (order_lists)
/// Consume tabla order_lists en Supabase
class OrderListService {
  static final OrderListService _instance = OrderListService._internal();
  final client = Supabase.instance.client;

  factory OrderListService() => _instance;
  OrderListService._internal();

  /// Obtener todas las listas de pedidos del usuario
  /// Opcionalmente filtrar por estado
  Future<List<OrderList>> getOrderLists({
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
          .map((item) => OrderList.fromJson(item))
          .toList();
    } catch (e) {
      AppLogger.error('Error obteniendo listas de pedidos',
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
        if (alias.isNotEmpty) list.add(alias);
      }
      return list.toList()..sort();
    } catch (e) {
      AppLogger.error('Error obteniendo responsables',
          tag: 'ORDER_LIST', error: e);
      return [];
    }
  }

  /// Obtener lista de pedidos por ID
  Future<OrderList?> getOrderListById(String id) async {
    try {
      final response =
          await client.from('order_lists').select().eq('id', id).maybeSingle();

      if (response == null) return null;
      return OrderList.fromJson(response);
    } catch (e) {
      AppLogger.error('Error obteniendo lista de pedidos',
          tag: 'ORDER_LIST', error: e);
      return null;
    }
  }

  /// Crear nueva lista de pedidos
  Future<OrderList?> createOrderList({
    required String clienteNombre,
    required double montoAdelantado,
    double? totalLista,
    String? telefono,
    String? responsable,
    required DateTime fechaRecojo,
    String? notas,
  }) async {
    try {
      final now = DateTime.now();
      final newList = OrderList(
        id: 'OL-${now.millisecondsSinceEpoch}-${(now.microsecond % 1000).toString().padLeft(3, '0')}',
        clienteNombre: clienteNombre,
        montoAdelantado: montoAdelantado,
        fechaRecojo: fechaRecojo,
        estado: 'PENDIENTE',
        fotosUrls: [],
        notas: notas,
        createdAt: now,
        updatedAt: now,
        meta: OrderListMeta(
          telefono: telefono,
          responsable: responsable,
          totalLista: totalLista,
        ),
      );

      final response = await client
          .from('order_lists')
          .insert(newList.toJson())
          .select()
          .single();

      final created = OrderList.fromJson(response);
      AppLogger.info(
        'Lista de pedidos creada: ${created.id} | Cliente: ${created.clienteNombre}',
        tag: 'ORDER_LIST',
      );
      return created;
    } catch (e) {
      AppLogger.error('Error creando lista de pedidos',
          tag: 'ORDER_LIST', error: e);
      rethrow;
    }
  }

  /// Subir foto de lista a Storage y actualizar fotos_urls
  /// Retorna (success, fotoUrl)
  /// VERBOSE: Cada paso del flujo se registra para debugging
  Future<(bool success, String? fotoUrl)> uploadFotoAndUpdate(
    String orderListId,
    File imagenFile,
  ) async {
    try {
      // 1. Subir imagen a Storage bucket "pedidos"
      AppLogger.debug('[1/4] Subiendo foto a Storage...', tag: 'ORDER_LIST');
      final fileName =
          '${orderListId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = 'fotos/$fileName';

      AppLogger.debug('  Nombre archivo: $fileName', tag: 'ORDER_LIST');
      AppLogger.debug('  Tamaño: ${imagenFile.lengthSync()} bytes',
          tag: 'ORDER_LIST');

      await client.storage.from('pedidos').upload(path, imagenFile);
      AppLogger.debug('[2/4] ✅ Archivo subido a Storage', tag: 'ORDER_LIST');

      final fotoUrl = client.storage.from('pedidos').getPublicUrl(path);
      AppLogger.debug('  URL obtenida: $fotoUrl', tag: 'ORDER_LIST');

      // 2. Obtener lista actual para agregar URL
      AppLogger.debug('[3/4] Recuperando lista actual...', tag: 'ORDER_LIST');
      final lista = await getOrderListById(orderListId);
      if (lista == null) throw Exception('Lista de pedidos no encontrada');

      // 3. Agregar URL a array fotosUrls
      final fotosActualizadas = [...lista.fotosUrls, fotoUrl];
      AppLogger.debug('  Fotos en lista: ${fotosActualizadas.length}',
          tag: 'ORDER_LIST');

      // 4. Actualizar en base de datos
      AppLogger.debug('[4/4] Actualizando tabla order_lists...',
          tag: 'ORDER_LIST');
      await client.from('order_lists').update({
        'fotos_urls': fotosActualizadas,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', orderListId);

      AppLogger.info(
        '✅ Foto subida completamente: $fotoUrl para lista $orderListId',
        tag: 'ORDER_LIST',
      );
      return (true, fotoUrl);
    } on Exception catch (e) {
      AppLogger.error(
        '❌ Error en uploadFotoAndUpdate: $e',
        tag: 'ORDER_LIST',
        error: e,
      );
      return (false, null);
    }
  }

  /// Actualizar estado de la lista de pedidos
  Future<bool> updateOrderListStatus(String id, String nuevoEstado) async {
    try {
      await client.from('order_lists').update({
        'estado': nuevoEstado,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);

      AppLogger.info('Lista $id actualizada a estado: $nuevoEstado',
          tag: 'ORDER_LIST');
      return true;
    } catch (e) {
      AppLogger.error('Error actualizando estado', tag: 'ORDER_LIST', error: e);
      return false;
    }
  }

  /// Actualizar notas de la lista
  Future<bool> updateOrderListNotes(String id, String notas) async {
    try {
      await client.from('order_lists').update({
        'notas': notas,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);

      AppLogger.info('Notas actualizadas para lista $id', tag: 'ORDER_LIST');
      return true;
    } catch (e) {
      AppLogger.error('Error actualizando notas', tag: 'ORDER_LIST', error: e);
      return false;
    }
  }

  /// Actualiza montos y metadata de contacto/deuda.
  Future<bool> updateOrderListFinancial({
    required OrderList order,
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
      final estado = saldo <= 0 ? 'COMPLETADO' : order.estado;

      await client.from('order_lists').update({
        'monto_adelantado': montoPagado,
        'estado': estado,
        'notas': OrderListMetaCodec.encode(meta: meta, notas: order.notas),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', order.id);

      return true;
    } catch (e) {
      AppLogger.error('Error actualizando datos financieros de lista',
          tag: 'ORDER_LIST', error: e);
      return false;
    }
  }

  /// Eliminar lista de pedidos (soft delete recomendado)
  /// Por ahora, actualiza estado a 'CANCELADO'
  Future<bool> cancelOrderList(String id) async {
    try {
      await client.from('order_lists').update({
        'estado': 'CANCELADO',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);

      AppLogger.info('Lista $id cancelada (soft delete)', tag: 'ORDER_LIST');
      return true;
    } catch (e) {
      AppLogger.error('Error cancelando lista', tag: 'ORDER_LIST', error: e);
      return false;
    }
  }
}
