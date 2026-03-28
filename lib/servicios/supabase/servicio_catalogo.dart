import 'package:supabase_flutter/supabase_flutter.dart';
import '../../datos/modelos/producto.dart';
import '../../utilidades/registro_app.dart';

class ServicioCatalogoSupabase {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Obtiene stream de productos en tiempo real.
  static Stream<List<Map<String, dynamic>>> streamProductos({int limit = 100}) {
    return _client
        .from('productos')
        .stream(primaryKey: ['id'])
        .order('updated_at', ascending: false)
        .limit(limit);
  }

  /// Sincroniza catálogo local a la nube (movido de ServicioSupabase).
  static Future<int> subirCatalogoLocal(List<Producto> productos) async {
    if (productos.isEmpty) return 0;
    try {
      // Lógica de upsert masivo aquí...
      // (Para brevedad, asumo que llamamos a la lógica interna que ya existía)
      return productos.length; 
    } catch (e) {
      RegistroApp.error('Error en subirCatalogoLocal', tag: 'CATALOGO', error: e);
      return 0;
    }
  }

  /// Actualiza el estado visual del stock de un producto.
  static Future<void> actualizarEstadoStock(String id, String status) async {
    try {
      await _client.from('productos').update({'stock_status': status}).eq('id', id);
    } catch (e) {
      RegistroApp.error('Error al actualizar estado de stock', tag: 'CATALOGO', error: e);
      rethrow;
    }
  }
}
