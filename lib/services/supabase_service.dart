import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/producto.dart';
import 'package:path/path.dart' as p;

class SupabaseService {
  static final client = Supabase.instance.client;

  /// Sube la imagen al bucket 'productos' y retorna la URL pública.
  static Future<String?> subirImagen(File imageFile) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${p.basename(imageFile.path)}';
      final path = 'public/$fileName';
      
      await client.storage.from('productos').upload(path, imageFile);
      
      final String publicUrl = client.storage.from('productos').getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      print('Error subiendo imagen: $e');
      return null;
    }
  }

  /// Verifica si un SKU ya existe en la base de datos.
  static Future<Map<String, dynamic>?> obtenerProductoPorSku(String sku) async {
    try {
      final response = await client
          .from('productos')
          .select()
          .eq('sku', sku)
          .maybeSingle();
      return response;
    } catch (e) {
      print('Error verificando SKU: $e');
      return null;
    }
  }

  /// Guarda o actualiza un producto. 
  /// Si [isUpdate] es true, realiza un update en lugar de insert.
  static Future<bool> upsertProducto(Producto p, {bool isUpdate = false}) async {
    try {
      final data = {
        'sku': p.id,
        'nombre': p.nombre,
        'marca': p.marca,
        'categoria': p.categoria,
        'precio_base': p.precioBase,
        'precio_mayorista': p.precioMayorista,
        'imagen_url': p.imagenPath,
      };

      if (isUpdate) {
        await client.from('productos').update(data).eq('sku', p.id);
      } else {
        await client.from('productos').insert(data);
      }
      return true;
    } catch (e) {
      print('Error en upsert: $e');
      return false;
    }
  }

  /// Busca productos usando el índice de texto.
  static Future<List<Producto>> buscarProductos(String query) async {
    try {
      final response = await client
          .from('productos')
          .select()
          .textSearch('fts', query) // Asumiendo columna fts configurada en Supabase
          .order('nombre');

      return (response as List).map((data) {
        return Producto(
          id: data['sku'],
          nombre: data['nombre'],
          marca: data['marca'],
          categoria: data['categoria'],
          precioBase: data['precio_base'].toDouble(),
          precioMayorista: data['precio_mayorista'].toDouble(),
          imagenPath: data['imagen_url'],
        );
      }).toList();
    } catch (e) {
      print('Error buscando productos: $e');
      return [];
    }
  }
}
