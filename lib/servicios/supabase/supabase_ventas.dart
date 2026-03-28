part of '../servicio_supabase.dart';

num _asNum(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}

List<Map<String, dynamic>> _itemsForVentaItemsFromVenta(Venta venta) {
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

List<Map<String, dynamic>> _itemsForVentaItemsFromJson(List<dynamic> items) {
  final out = <Map<String, dynamic>>[];
  for (final raw in items) {
    if (raw is! Map) continue;
    final map = Map<String, dynamic>.from(raw);
    final productoId =
        (map['producto_id'] ?? map['sku'] ?? map['sku_code'] ?? map['id'])
            ?.toString();
    final presentacionId = map['presentacion_id']?.toString();
    final cantidad = _asNum(map['cantidad']);
    final precioUnit = _asNum(map['precio_unitario'] ?? map['precio']);
    final subtotal = _asNum(map['subtotal']);
    final precioOverride =
        map.containsKey('precio_override') ? _asNum(map['precio_override']) : null;

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

Future<String?> _tryInsertVentaWithItemsRpc({
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

    final res = await ServicioSupabase.client
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

Future<void> _insertVentaItemsBestEffort(
  String ventaId,
  List<Map<String, dynamic>> itemsNormalized,
) async {
  for (final itemData in itemsNormalized) {
    try {
      await ServicioSupabase.client
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

Future<String> _insertVentaWithItemsBestEffort({
  required Map<String, dynamic> ventaPayload,
  required List<Map<String, dynamic>> itemsNormalized,
}) async {
  final rpcId = await _tryInsertVentaWithItemsRpc(
    ventaPayload: ventaPayload,
    itemsNormalized: itemsNormalized,
  );
  if (rpcId != null) return rpcId;

  final docRes =
      await ServicioSupabase._insertVentaReturningWithCompatibility(ventaPayload);
  final docId = docRes['id']?.toString();
  if (docId == null) {
    throw Exception('Response vacío al insertar documento');
  }
  await _insertVentaItemsBestEffort(docId, itemsNormalized);
  return docId;
}

Future<Venta?> _registrarVenta({
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

    final response = await ServicioSupabase.client
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
      'metodoPago': metodoPago.toLowerCase(),
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

Future<bool> _anularVentaEnNube({
  required String correlativo,
  required String motivo,
  required String aliasUsuario,
}) async {
  try {
    final now = DateTime.now().toIso8601String();
    final ok = await ServicioSupabase._updateVentaAnulacionWithCompatibility(
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

Future<(bool success, String? docId)> _insertarVentaWaterfall(Venta venta) async {
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

Future<bool> _checkConectividad() async {
  try {
    await ServicioSupabase.client
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

Future<bool> _tieneConexionRemota() async => _checkConectividad();
