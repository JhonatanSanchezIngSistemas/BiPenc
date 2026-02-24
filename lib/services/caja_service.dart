import '../models/producto.dart';
import '../services/local_db_service.dart';
import '../utils/precio_engine.dart';

/// Servicio para gestionar el cierre de caja (Corte X y Corte Z).
/// Corte X: Resumen parcial sin borrar datos.
/// Corte Z: Cierre final (borra contadores o marca como cerrados).
class CajaService {
  CajaService._();

  /// Genera un resumen de ventas del día basado en el caché local.
  static Future<Map<String, dynamic>> generarResumenCaja() async {
    final ventas = await LocalDbService.obtenerVentasPendientes();
    
    double totalNeto = 0;
    double totalRedondeado = 0;
    Map<String, double> ventasPorVendedor = {};

    for (final v in ventas) {
      final total = v['total'] as double;
      final alias = v['vendedor_alias'] as String;
      
      totalNeto += total;
      final redondeado = PrecioEngine.ceilingTotal(total);
      totalRedondeado += redondeado;
      
      ventasPorVendedor[alias] = (ventasPorVendedor[alias] ?? 0) + redondeado;
    }

    final ahorro = totalRedondeado - totalNeto;

    return {
      'totalVentas': totalRedondeado,
      'ahorroRedondeo': ahorro,
      'ventasPorVendedor': ventasPorVendedor,
      'conteoVentas': ventas.length,
    };
  }

  /// Realiza el corte y lo sube si hay conexión, o lo guarda localmente.
  static Future<bool> realizarCierreZ() async {
    // En una implementación real, aquí marcaríamos las ventas como 'CERRADAS' 
    // en la BD local para que no entren en el siguiente Corte X.
    return true;
  }
}
