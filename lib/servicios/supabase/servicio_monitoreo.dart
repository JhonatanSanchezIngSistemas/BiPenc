import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utilidades/registro_app.dart';

class ServicioMonitoreoSupabase {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Stream de carritos de compra en vivo (`carts_live`).
  static Stream<List<Map<String, dynamic>>> streamCarritosEnVivo(
      {int limit = 100}) {
    return _client
        .from('carts_live')
        .stream(primaryKey: ['user_id'])
        .order('updated_at', ascending: false)
        .limit(limit);
  }

  /// Envía telemetría de carrito desde POS al dashboard de administración.
  static Future<void> upsertCarritoEnVivo(Map<String, dynamic> payload) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return;

      final data = Map<String, dynamic>.from(payload)
        ..['user_id'] = user.id
        ..['updated_at'] = DateTime.now().toUtc().toIso8601String();

      await _client
          .from('carts_live')
          .upsert(data, onConflict: 'user_id');
    } catch (e) {
      RegistroApp.error('Error enviando telemetría de carrito',
          tag: 'MONITOREO', error: e);
    }
  }

  /// Limpia carritos inactivos mediante RPC nativo.
  static Future<void> limpiarCarritosViejos() async {
    try {
      await _client.rpc('limpiar_carritos_viejos');
    } catch (e) {
      RegistroApp.warn('Fallo al limpiar carritos viejos (RPC)',
          tag: 'MONITOREO', error: e);
    }
  }
}
