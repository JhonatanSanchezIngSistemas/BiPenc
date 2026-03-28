import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utilidades/registro_app.dart';

class ServicioVentasSupabase {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Stream de ventas recientes en tiempo real.
  static Stream<List<Map<String, dynamic>>> streamVentas({int limit = 20}) {
    return _client
        .from('ventas')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(limit);
  }

  /// Stream de pedidos (order_lists) en tiempo real.
  static Stream<List<Map<String, dynamic>>> streamPedidos({int limit = 50}) {
    return _client
        .from('order_lists')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(limit);
  }

  /// Obtiene los ítems de una venta por su ID.
  static Future<List<Map<String, dynamic>>> fetchVentaItems(String ventaId) async {
    try {
      final res = await _client
          .from('venta_items')
          .select()
          .eq('venta_id', ventaId);
      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      RegistroApp.error('Error obteniendo items de venta', tag: 'VENTAS', error: e);
      return [];
    }
  }

  /// Calcula métricas rápidas de ventas para hoy.
  static Future<Map<String, double>> fetchMetricasHoy() async {
    final now = DateTime.now();
    final inicioDia = DateTime(now.year, now.month, now.day).toIso8601String();
    
    try {
      final res = await _client
          .from('ventas')
          .select('total, metodo_pago, anulado')
          .gte('created_at', inicioDia);
      
      double total = 0, efe = 0, yap = 0;
      for (final r in (res as List)) {
        if (r['anulado'] == true) continue;
        final t = (r['total'] as num?)?.toDouble() ?? 0;
        final m = (r['metodo_pago'] ?? '').toString().toLowerCase();
        
        total += t;
        if (m.contains('efect')) efe += t;
        if (m.contains('yape')) yap += t;
      }
      return {'total': total, 'efectivo': efe, 'yape': yap};
    } catch (e) {
      RegistroApp.error('Error calculando métricas hoy', tag: 'VENTAS', error: e);
      return {'total': 0, 'efectivo': 0, 'yape': 0};
    }
  }
}
