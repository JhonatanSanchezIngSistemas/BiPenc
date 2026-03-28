part of '../servicio_supabase.dart';

Future<bool> _sincronizarProductos() async {
  try {
    // T1.2: Resolver conflictos antes de bajar la nueva versión
    await _resolverConflictosSync();

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toUtc();
    final lastFullMs =
        prefs.getInt(ServicioSupabase._productosLastFullSyncKey);
    final lastDeltaMs =
        prefs.getInt(ServicioSupabase._productosLastDeltaSyncKey);
    final lastFull = lastFullMs != null
        ? DateTime.fromMillisecondsSinceEpoch(lastFullMs, isUtc: true)
        : null;
    final doFull = lastFull == null ||
        now.difference(lastFull) >= ServicioSupabase._productosFullSyncInterval;

    if (doFull) {
      final ok = await _fullSyncProductos();
      if (ok) {
        await prefs.setInt(
            ServicioSupabase._productosLastFullSyncKey, now.millisecondsSinceEpoch);
        await prefs.setInt(
            ServicioSupabase._productosLastDeltaSyncKey, now.millisecondsSinceEpoch);
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
            ServicioSupabase._productosLastDeltaSyncKey,
            marker.millisecondsSinceEpoch);
      }
      return result.ok;
    } on PostgrestException catch (e) {
      // Fallback si no existe updated_at o falla el filtro incremental.
      if (ServicioSupabase._isMissingColumnError(e, 'updated_at')) {
        RegistroApp.warning(
          'sincronizarProductos: updated_at no disponible, fallback full sync',
          tag: 'SYNC',
        );
        final ok = await _fullSyncProductos();
        if (ok) {
          await prefs.setInt(
              ServicioSupabase._productosLastFullSyncKey, now.millisecondsSinceEpoch);
          await prefs.setInt(
              ServicioSupabase._productosLastDeltaSyncKey, now.millisecondsSinceEpoch);
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

Future<bool> _fullSyncProductos() async {
  final response =
      await ServicioSupabase.client.from('productos').select().order('nombre');
  final lista = response as List;

  if (lista.isEmpty) {
    RegistroApp.info(
        'sincronizarProductos: tabla "productos" sin filas (catálogo vacío)',
        tag: 'SYNC');
    return true;
  }

  final List<Producto> productos = lista
      .map<Producto>((row) => ServicioSupabase.mapToProducto(row as Map<String, dynamic>))
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

Future<({bool ok, DateTime? maxUpdated, int fetched})> _deltaSyncProductos(
    DateTime since) async {
  DateTime? maxUpdated;
  var totalFetched = 0;
  var offset = 0;
  final sinceIso = since.toUtc().toIso8601String();

  while (true) {
    final data = await ServicioSupabase.client
        .from('productos')
        .select()
        .gt('updated_at', sinceIso)
        .order('updated_at', ascending: true)
        .range(offset, offset + ServicioSupabase._productosPageSize - 1)
        .timeout(const Duration(seconds: 30));

    final lista = data as List;
    if (lista.isEmpty) break;
    totalFetched += lista.length;

    final productos = lista
        .map<Producto>(
            (row) => ServicioSupabase.mapToProducto(row as Map<String, dynamic>))
        .where((p) => p.id.isNotEmpty)
        .toList();

    await ServicioDbLocal.upsertProductos(productos);

    for (final row in lista) {
      final raw = (row as Map<String, dynamic>)['updated_at'];
      final parsed = raw != null ? DateTime.tryParse(raw.toString()) : null;
      final currentMax = maxUpdated;
      if (parsed != null && (currentMax == null || parsed.isAfter(currentMax))) {
        maxUpdated = parsed;
      }
    }

    if (lista.length < ServicioSupabase._productosPageSize) break;
    offset += ServicioSupabase._productosPageSize;
  }

  return (ok: true, maxUpdated: maxUpdated, fetched: totalFetched);
}

/// T1.2: Resuelve conflictos de sincronización usando Last-Timestamp-Wins.
/// Compara productos locales modificados con la versión en Supabase.
Future<void> _resolverConflictosSync() async {
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
        final cloudRow = await ServicioSupabase.client
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
          await ServicioSupabase.client.from('productos').update({
            'last_sync_timestamp': localTs.toIso8601String(),
            'local_version': local.localVersion,
            'presentations':
                local.presentaciones.map((p) => p.toJson()).toList(),
            // ... otros campos críticos ...
          }).eq('id', local.id);

          // Registrar éxito de resolución
          await ServicioSupabase.client.from('sync_conflicts').insert({
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

          await ServicioSupabase.client.from('sync_conflicts').insert({
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
Future<List<String>> _obtenerCategorias() async {
  try {
    final res = await ServicioSupabase.client
        .from('categorias')
        .select('nombre')
        .order('nombre');
    return (res as List).map((row) => row['nombre'].toString()).toList();
  } catch (e) {
    RegistroApp.warning(
        'No se pudo obtener categorías de Supabase. Usando locales.',
        tag: 'SYNC');
    return List.from(CategoriasProducto.lista);
  }
}

Future<void> _agregarCategoria(String nombre) async {
  try {
    await ServicioSupabase.client
        .from('categorias')
        .upsert({'nombre': nombre}, onConflict: 'nombre');
    RegistroApp.info('Categoría agregada/actualizada: $nombre', tag: 'SYNC');
  } catch (e) {
    RegistroApp.error('Error agregando categoría a Supabase',
        tag: 'SYNC', error: e);
  }
}

Future<bool> _eliminarCategoriaSiNoEstaEnUso(String nombre) async {
  try {
    // Si hay productos usándola, los movemos a categoría DEFAULT
    const categoriaFallback = 'SIN CATEGORIA';

    final inUse = await ServicioSupabase.client
        .from('productos')
        .select('id')
        .eq('categoria', nombre)
        .eq('estado', EstadoProducto.activo);

    if ((inUse as List).isNotEmpty) {
      await ServicioSupabase.client
          .from('categorias')
          .upsert({'nombre': categoriaFallback});
      await ServicioSupabase.client
          .from('productos')
          .update({'categoria': categoriaFallback})
          .eq('categoria', nombre);
      RegistroApp.warning(
          'Productos reasignados a "$categoriaFallback" porque la categoría "$nombre" estaba en uso',
          tag: 'SYNC');
    }

    await ServicioSupabase.client.from('categorias').delete().eq('nombre', nombre);
    RegistroApp.info('Categoría eliminada: $nombre', tag: 'SYNC');
    return true;
  } catch (e) {
    RegistroApp.error('Error eliminando categoría en Supabase',
        tag: 'SYNC', error: e);
    return false;
  }
}

@Deprecated('Usa ServicioMonitoreoSupabase.upsertCarritoEnVivo')
Future<void> _upsertCarritoEnVivo(Map<String, dynamic> payload) async {
  await ServicioMonitoreoSupabase.upsertCarritoEnVivo(payload);
}

/// Sincroniza TODO el catálogo local hacia la nube.
/// Útil cuando la nube está vacía pero el dispositivo tiene datos.
Future<int> _subirCatalogoLocal() async {
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

        await ServicioSupabase.client
            .from('productos')
            .upsert(productData, onConflict: 'sku');

        // 2. Upsert de presentaciones (mapeo a tabla product_presentations)
        if (p.presentaciones.isNotEmpty) {
          final List<Map<String, dynamic>> presentationsBatch = [];
          for (final pres in p.presentaciones) {
            presentationsBatch.add({
              'sku_code': pres.barcode ?? pres.id,
              'product_id': null,
              'price': pres.getPriceByType('NORMAL'),
              'conversion_factor': pres.conversionFactor,
              'is_active': true,
            });
          }
          if (presentationsBatch.isNotEmpty) {
            await ServicioSupabase.client
                .from('product_presentations')
                .upsert(presentationsBatch, onConflict: 'sku_code');
          }
        }

        subidos++;
      } catch (e) {
        RegistroApp.error('Error subiendo producto ${p.skuCode}: $e',
            tag: 'SYNC');
      }
    }

    return subidos;
  } catch (e) {
    RegistroApp.error('Error general en subirCatalogoLocal',
        tag: 'SYNC', error: e);
    return 0;
  }
}

Future<void> _subirVentasPendientes() async {
  try {
    final pendientes = await ServicioDbLocal.obtenerVentasPendientes();
    if (pendientes.isEmpty) return;

    RegistroApp.info('Subiendo ${pendientes.length} ventas pendientes',
        tag: 'SYNC');

    for (final raw in pendientes) {
      try {
        final venta = Venta.fromMap(raw);
        final (success, _) =
            await ServicioSupabase.insertarVentaWaterfall(venta);
        if (success) {
          final idRaw = raw['id'];
          final idLocal = idRaw is int
              ? idRaw
              : int.tryParse(idRaw?.toString() ?? '');
          if (idLocal != null) {
            await ServicioDbLocal.marcarVentaSincronizada(idLocal);
          }
        }
      } catch (e) {
        final id = raw['id']?.toString() ?? 'desconocido';
        RegistroApp.error('Error subiendo venta pendiente $id',
            tag: 'SYNC', error: e);
      }
    }
  } catch (e) {
    RegistroApp.error('Error en subirVentasPendientes', tag: 'SYNC', error: e);
  }
}

Future<void> _procesarSyncQueue() async {
  try {
    final eventos = await ServicioDbLocal.obtenerSyncQueue();
    if (eventos.isEmpty) return;

    for (final evento in eventos) {
      try {
        final id = (evento['id'] as num?)?.toInt();
        final tipo = (evento['tipo'] ?? evento['operacion'])?.toString() ?? '';
        final dataRaw = evento['data'] ?? evento['datos'];
        final data = dataRaw is String
            ? (jsonDecode(dataRaw) as Map<String, dynamic>)
            : (dataRaw as Map<String, dynamic>? ?? {});
        if (tipo == 'PRODUCTO_UPSERT') {
          await ServicioSupabase.client.from('productos').upsert(data);
        }
        if (id != null) {
          await ServicioDbLocal.eliminarDeSyncQueue(id);
        }
      } catch (e) {
        final id = evento['id']?.toString() ?? 'desconocido';
        RegistroApp.warn('Error procesando sync_queue item $id',
            tag: 'SYNC', error: e);
      }
    }
  } catch (e) {
    RegistroApp.error('Error general procesando sync_queue', tag: 'SYNC', error: e);
  }
}

Future<void> _procesarSyncQueueV2() async {
  try {
    final eventos = await ServicioDbLocal.obtenerSyncQueueV2Pendiente();
    if (eventos.isEmpty) return;

    for (final evento in eventos) {
      final id = evento['id']?.toString() ?? '';
      final tabla = (evento['tabla'] ?? '').toString();
      final operacion = (evento['operacion'] ?? 'UPSERT').toString().toUpperCase();
      final datosRaw = evento['datos'];
      final data = datosRaw is String
          ? (jsonDecode(datosRaw) as Map<String, dynamic>)
          : (datosRaw as Map<String, dynamic>? ?? {});

      if (id.isEmpty) continue;

      try {
        if (operacion == 'VINCULAR_CODIGO') {
          await ServicioSupabase.client.from('producto_codigos').upsert({
            'codigo_barras': data['codigo_barras'],
            'producto_sku': data['producto_id'] ?? data['producto_sku'],
            'descripcion_variante': data['descripcion_variante'],
          }, onConflict: 'codigo_barras,producto_sku');
        } else if (operacion == 'DESVINCULAR_CODIGO') {
          await ServicioSupabase.client
              .from('producto_codigos')
              .delete()
              .eq('codigo_barras', data['codigo_barras'])
              .eq('producto_sku', data['producto_id'] ?? data['producto_sku']);
        } else if (operacion == 'ANULAR') {
          final correlativo = data['correlativo']?.toString();
          final motivo = data['anulado_motivo']?.toString() ?? 'ANULADO';
          final aliasUsuario = data['anulado_por']?.toString() ?? 'SISTEMA';
          if (correlativo != null && correlativo.isNotEmpty) {
            await ServicioSupabase.anularVentaEnNube(
              correlativo: correlativo,
              motivo: motivo,
              aliasUsuario: aliasUsuario,
            );
          }
        } else if (operacion == 'DELETE') {
          final idRow = data['id']?.toString();
          final skuRow = data['sku']?.toString();
          if (tabla.isNotEmpty) {
            final query = ServicioSupabase.client.from(tabla).delete();
            if (idRow != null && idRow.isNotEmpty) {
              await query.eq('id', idRow);
            } else if (skuRow != null && skuRow.isNotEmpty) {
              await query.eq('sku', skuRow);
            }
          }
        } else if (operacion == 'SALE_EVENT') {
          // Evento de telemetría local; se marca como sincronizado sin acción remota.
          RegistroApp.debug('SALE_EVENT sync omitido', tag: 'SYNC');
        } else {
          if (tabla.isNotEmpty) {
            await ServicioSupabase.client.from(tabla).upsert(data);
          }
        }

        await ServicioDbLocal.marcarSyncQueueV2Sincronizado(id);
      } catch (e) {
        await ServicioDbLocal.registrarIntentoSyncQueueV2(id, e.toString());
        RegistroApp.warn(
            'Error procesando sync_queue_v2 item $id',
            tag: 'SYNC',
            error: e);
      }
    }
  } catch (e) {
    RegistroApp.error('Error general procesando sync_queue_v2',
        tag: 'SYNC', error: e);
  }
}
