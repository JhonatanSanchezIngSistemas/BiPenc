part of '../servicio_supabase.dart';

Future<bool> _upsertProducto(
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
      'presentaciones': p.presentaciones.map((pres) => pres.toJson()).toList(),
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
      await ServicioSupabase.client
          .from('productos')
          .update(data)
          .eq('sku', normalizedSku);
    } else {
      await ServicioSupabase.client.from('productos').insert(data);
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

Future<List<Producto>> _buscarProductos(String query) async {
  try {
    final response = await ServicioSupabase.client
        .from('productos')
        .select()
        .or('sku.ilike.%$query%,nombre.ilike.%$query%,marca.ilike.%$query%,categoria.ilike.%$query%')
        .order('nombre');

    final List<dynamic> responseList = response as List;
    return responseList
        .map<Producto>((data) =>
            ServicioSupabase.mapToProducto(data as Map<String, dynamic>))
        .toList();
  } catch (e) {
    RegistroApp.error('Error buscando productos', tag: 'PRODUCTOS', error: e);
    return [];
  }
}

/// Busca todos los productos asociados a un código de barras via tabla puente en Supabase.
Future<List<Producto>> _buscarPorCodigoRemoto(String codigo) async {
  try {
    final rows = await ServicioSupabase.client
        .from('producto_codigos')
        .select('producto_sku')
        .eq('codigo_barras', codigo.trim());
    final skus = (rows as List)
        .map((r) => r['producto_sku']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    if (skus.isEmpty) return [];
    final productoRows = await ServicioSupabase.client
        .from('productos')
        .select()
        .inFilter('sku', skus);
    return (productoRows as List)
        .map<Producto>((d) =>
            ServicioSupabase.mapToProducto(d as Map<String, dynamic>))
        .toList();
  } catch (e) {
    RegistroApp.error('Error buscando por código remoto',
        tag: 'BARCODE', error: e);
    return [];
  }
}

/// Vincula un código de barras a un producto en Supabase (tabla puente).
Future<bool> _vincularCodigoRemoto(
    String codigo, String productoSku, String? variante) async {
  try {
    await ServicioSupabase.client.from('producto_codigos').upsert({
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
Future<bool> _desvincularCodigoRemoto(
    String codigo, String productoSku) async {
  try {
    await ServicioSupabase.client
        .from('producto_codigos')
        .delete()
        .eq('codigo_barras', codigo.trim())
        .eq('producto_sku', productoSku);
    RegistroApp.info('[Remoto] Desvinculado: $codigo ↛ $productoSku', tag: 'BARCODE');
    return true;
  } catch (e) {
    RegistroApp.error('Error desvinculando código remoto',
        tag: 'BARCODE', error: e);
    return false;
  }
}

Future<List<Producto>> _obtenerProductosParaAuditoria() async {
  try {
    final response = await ServicioSupabase.client
        .from('productos')
        .select()
        .eq('estado', 'PENDIENTE')
        .order('updated_at', ascending: false);

    final List<dynamic> responseList = response as List;
    return responseList
        .map<Producto>((data) =>
            ServicioSupabase.mapToProducto(data as Map<String, dynamic>))
        .toList();
  } catch (e) {
    RegistroApp.error('Error en auditoría', tag: 'PRODUCTOS', error: e);
    return [];
  }
}

Future<bool> _aprobarProducto(String sku, double pBase, double pMayorista) async {
  try {
    await ServicioSupabase.client.from('productos').update({
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

Producto _mapToProducto(Map<String, dynamic> data) {
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
    final precioBase = (data['precio_base'] ?? data['precio'] ?? 0).toDouble();
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
                  type: 'NORMAL', amount: (data['precio_especial']).toDouble())
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
