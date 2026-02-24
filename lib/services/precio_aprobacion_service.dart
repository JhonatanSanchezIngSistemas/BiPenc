import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio independiente para la lógica de aprobación/validación de precios.
/// 
/// Cumple con SRP al separar la lógica de negocio de aprobación
/// del servicio general de Supabase, facilitando testing y mantenimiento.
class PrecioAprobacionService {
  final SupabaseClient _client;

  PrecioAprobacionService(this._client);

  /// Aprueba un precio propuesto, convirtiéndolo en precio_base oficial
  /// 
  /// Este método:
  /// 1. Valida que existe un precio propuesto
  /// 2. Actualiza precio_base con el valor propuesto
  /// 3. Limpia los campos de propuesta
  /// 4. Marca el estado como VERIFICADO
  Future<bool> aprobarPrecioPropuesto(String sku) async {
    try {
      final response = await _client
          .from('productos')
          .select('precio_propuesto, precio_mayorista_propuesto')
          .eq('sku', sku)
          .maybeSingle();

      if (response == null) {
        throw Exception('Producto no encontrado');
      }

      final precioPropuesto = response['precio_propuesto'];
      final mayoristaPropuesto = response['precio_mayorista_propuesto'];

      if (precioPropuesto == null) {
        throw Exception('No hay precio propuesto para aprobar');
      }

      await _client.from('productos').update({
        'precio_base': precioPropuesto,
        'precio_mayorista': mayoristaPropuesto ?? response['precio_mayorista'],
        'precio_propuesto': null,
        'precio_mayorista_propuesto': null,
        'estado': 'VERIFICADO',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('sku', sku);

      return true;
    } catch (e) {
      print('Error aprobando precio: $e');
      return false;
    }
  }

  /// Rechaza un precio propuesto, mantieniendo el precio_base actual
  Future<bool> rechazarPrecioPropuesto(String sku) async {
    try {
      await _client.from('productos').update({
        'precio_propuesto': null,
        'precio_mayorista_propuesto': null,
        'estado': 'VERIFICADO',
      }).eq('sku', sku);

      return true;
    } catch (e) {
      print('Error rechazando precio: $e');
      return false;
    }
  }

  /// Obtiene todos los productos con precios pendientes de aprobación
  Future<List<Map<String, dynamic>>> obtenerPreciosPendientes() async {
    try {
      final response = await _client
          .from('productos')
          .select('*')
          .eq('estado', 'PENDIENTE')
          .not('precio_propuesto', 'is', null);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error obteniendo precios pendientes: $e');
      return [];
    }
  }

  /// Valida si un usuario tiene permisos para aprobar precios
  /// (Solo usuarios con rol ADMIN)
  bool puedeAprobarPrecios(String rol) {
    return rol == 'ADMIN';
  }

  /// Calcula diferencia porcentual entre precio actual y propuesto
  double calcularDiferenciaPorcentual(double precioActual, double precioPropuesto) {
    if (precioActual == 0) return 0;
    return ((precioPropuesto - precioActual) / precioActual) * 100;
  }
}
