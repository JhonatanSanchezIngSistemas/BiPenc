import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bipenc/datos/modelos/producto.dart';
import 'package:bipenc/datos/modelos/presentacion.dart';
import 'package:bipenc/servicios/servicio_db_local.dart';
import 'package:bipenc/servicios/servicio_backend.dart';
import 'package:bipenc/utilidades/registro_app.dart';
import 'package:bipenc/base/constantes/estados_producto.dart';

/// Servicio de inventario alineado al esquema real de BiPenc:
/// - Tabla principal: `productos`
/// - Presentaciones embebidas en columna JSON `presentaciones`
class ServicioInventario {
  static final ServicioInventario _instance = ServicioInventario._internal();
  final client = Supabase.instance.client;

  factory ServicioInventario() => _instance;
  ServicioInventario._internal();

  Future<List<Producto>> getAllProducts({String? storeId}) async {
    try {
      final response = await client
          .from('productos')
          .select()
          .eq('estado', EstadoProducto.activo)
          .order('updated_at', ascending: false);

      return (response as List)
          .map((p) => ServicioBackend.mapToProducto(p as Map<String, dynamic>))
          .toList();
    } catch (e) {
      RegistroApp.error('Error obteniendo productos', tag: 'INVENTORY', error: e);
      return [];
    }
  }

  Future<Producto?> getProductById(String productId) async {
    try {
      final response = await client
          .from('productos')
          .select()
          .eq('id', productId)
          .maybeSingle();

      if (response == null) return null;
      return ServicioBackend.mapToProducto(response);
    } catch (e) {
      RegistroApp.error('Error obteniendo producto', tag: 'INVENTORY', error: e);
      return null;
    }
  }

  Future<List<Producto>> searchBySku(String skuCode) async {
    try {
      final response = await client
          .from('productos')
          .select()
          .ilike('sku', '%${skuCode.trim()}%')
          .eq('estado', EstadoProducto.activo)
          .limit(20);

      return (response as List)
          .map((p) => ServicioBackend.mapToProducto(p as Map<String, dynamic>))
          .toList();
    } catch (e) {
      RegistroApp.error('Error buscando por SKU', tag: 'INVENTORY', error: e);
      return [];
    }
  }

  Future<List<Presentacion>> getPresentationsByBarcode(String barcode) async {
    try {
      final products = await client
          .from('productos')
          .select('id, sku, nombre, presentaciones')
          .eq('estado', EstadoProducto.activo);

      final result = <Presentacion>[];
      for (final row in (products as List)) {
        final pMap = row as Map<String, dynamic>;
        final presRaw = pMap['presentaciones'];
        if (presRaw is! List) continue;
        for (final item in presRaw) {
          final pres = Presentacion.fromJson(Map<String, dynamic>.from(item));
          if (pres.barcode == barcode || pres.skuCode == barcode) {
            result.add(pres);
          }
        }
      }
      return result;
    } catch (e) {
      RegistroApp.error('Error buscando por código de barras', tag: 'INVENTORY', error: e);
      return [];
    }
  }

  Future<Presentacion?> getPresentationById(String presentationId) async {
    try {
      final products = await client
          .from('productos')
          .select('presentaciones')
          .eq('estado', EstadoProducto.activo);

      for (final row in (products as List)) {
        final presRaw = (row as Map<String, dynamic>)['presentaciones'];
        if (presRaw is! List) continue;
        for (final item in presRaw) {
          final map = Map<String, dynamic>.from(item);
          if ((map['id'] ?? '').toString() == presentationId) {
            return Presentacion.fromJson(map);
          }
        }
      }
      return null;
    } catch (e) {
      RegistroApp.error('Error obteniendo presentación', tag: 'INVENTORY', error: e);
      return null;
    }
  }

  Future<(bool exists, String? existingId)> validateUniqueness(String skuCode) async {
    final normalized = skuCode.trim().toUpperCase();
    try {
      final local = await ServicioDbLocal.buscarLocal(normalized);
      final exactLocal = local.where((p) => p.skuCode.trim().toUpperCase() == normalized).toList();
      if (exactLocal.isNotEmpty) {
        return (true, exactLocal.first.id);
      }
    } catch (_) {}

    try {
      final response = await client
          .from('productos')
          .select('id, sku')
          .eq('sku', normalized)
          .maybeSingle();

      if (response == null) return (false, null);
      return (true, response['id'].toString());
    } catch (e) {
      RegistroApp.error('Error validando SKU', tag: 'INVENTORY', error: e);
      return (false, null);
    }
  }

  Future<bool> saveFullProduct(Producto producto) async {
    final normalizedSku = producto.skuCode.trim().toUpperCase();
    double priceByIdOrZero(String presentationId) {
      final pres = producto.presentaciones.where((p) => p.id == presentationId);
      if (pres.isEmpty) return 0.0;
      return pres.first.getPriceByType('NORMAL');
    }
    try {
      final data = {
        'id': producto.id,
        'sku': normalizedSku,
        'nombre': producto.nombre,
        'marca': producto.marca,
        'categoria': producto.categoria,
        'presentaciones': producto.presentaciones.map((p) => p.toJson()).toList(),
        'precio_base': producto.precioBase,
        'precio_mayorista': producto.precioMayorista,
        'precio_caja_12': priceByIdOrZero('c12'),
        'precio_caja_72': priceByIdOrZero('c72'),
        'precio_especial': priceByIdOrZero('espe'),
        'imagen_url': producto.imagenPath,
        'descripcion': producto.descripcion,
        'estado': producto.estado,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await client.from('productos').upsert(data, onConflict: 'sku');
      return true;
    } catch (e) {
      RegistroApp.warning('Supabase no disponible para producto ${producto.skuCode}, encolando sync: $e', tag: 'INVENTORY');
      final syncId = 'prod_upsert_${producto.id}_${DateTime.now().millisecondsSinceEpoch}';
      await ServicioDbLocal.insertarEnSyncQueueV2(
        id: syncId,
        tabla: 'productos',
        operacion: 'UPSERT',
        datosJson: jsonEncode({
          'id': producto.id,
          'sku': normalizedSku,
          'nombre': producto.nombre,
          'marca': producto.marca,
          'categoria': producto.categoria,
          'presentaciones': producto.presentaciones.map((p) => p.toJson()).toList(),
          'precio_base': producto.precioBase,
          'precio_mayorista': producto.precioMayorista,
          'precio_caja_12': priceByIdOrZero('c12'),
          'precio_caja_72': priceByIdOrZero('c72'),
          'precio_especial': priceByIdOrZero('espe'),
          'imagen_url': producto.imagenPath,
          'descripcion': producto.descripcion,
          'estado': producto.estado,
          'updated_at': DateTime.now().toIso8601String(),
        }),
      );
      return false;
    }
  }

  Future<bool> softDeleteProduct(String productId) async {
    try {
      await client.from('productos').update({'estado': 'DESCONTINUADO'}).eq('id', productId);
      return true;
    } catch (e) {
      RegistroApp.error('Error desactivando producto', tag: 'INVENTORY', error: e);
      return false;
    }
  }

  Future<bool> softDeletePresentation(String presentationId) async {
    try {
      final products = await getAllProducts();
      final owner = products.firstWhere(
        (p) => p.presentaciones.any((pres) => pres.id == presentationId),
        orElse: () => Producto(id: '', skuCode: '', nombre: ''),
      );
      if (owner.id.isEmpty) return false;

      final nuevas = owner.presentaciones
          .where((pres) => pres.id != presentationId)
          .map((pres) => pres.toJson())
          .toList();

      await client.from('productos').update({
        'presentaciones': nuevas,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', owner.id);
      return true;
    } catch (e) {
      RegistroApp.error('Error desactivando presentación', tag: 'INVENTORY', error: e);
      return false;
    }
  }

  Future<List<Producto>> searchByName(String query) async {
    try {
      final response = await client
          .from('productos')
          .select()
          .ilike('nombre', '%${query.trim()}%')
          .eq('estado', EstadoProducto.activo)
          .limit(20);

      return (response as List)
          .map((p) => ServicioBackend.mapToProducto(p as Map<String, dynamic>))
          .toList();
    } catch (e) {
      RegistroApp.error('Error buscando por nombre', tag: 'INVENTORY', error: e);
      return [];
    }
  }

  Future<List<Producto>> getProductsByCategory(String category) async {
    try {
      final response = await client
          .from('productos')
          .select()
          .eq('categoria', category)
          .eq('estado', EstadoProducto.activo)
          .order('nombre', ascending: true);

      return (response as List)
          .map((p) => ServicioBackend.mapToProducto(p as Map<String, dynamic>))
          .toList();
    } catch (e) {
      RegistroApp.error('Error obteniendo por categoría', tag: 'INVENTORY', error: e);
      return [];
    }
  }

  Future<List<String>> getAllCategories() async {
    try {
      final response = await client
          .from('productos')
          .select('categoria')
          .eq('estado', EstadoProducto.activo);
      final set = <String>{};
      for (final row in (response as List)) {
        final cat = ((row as Map<String, dynamic>)['categoria'] ?? '').toString().trim();
        if (cat.isNotEmpty) set.add(cat);
      }
      final list = set.toList()..sort();
      return list;
    } catch (e) {
      RegistroApp.error('Error obteniendo categorías', tag: 'INVENTORY', error: e);
      return [];
    }
  }

  Future<List<String>> getAllBrands() async {
    try {
      final response = await client
          .from('productos')
          .select('marca')
          .eq('estado', EstadoProducto.activo);
      final set = <String>{};
      for (final row in (response as List)) {
        final brand = ((row as Map<String, dynamic>)['marca'] ?? '').toString().trim();
        if (brand.isNotEmpty) set.add(brand);
      }
      final list = set.toList()..sort();
      return list;
    } catch (e) {
      RegistroApp.error('Error obteniendo marcas', tag: 'INVENTORY', error: e);
      return [];
    }
  }
}
