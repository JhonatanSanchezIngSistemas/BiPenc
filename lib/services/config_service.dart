import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_logger.dart';

/// Servicio para obtener configuraciones globales como tasa de IGV.
/// Cached en SharedPreferences para evitar consultas frecuentes.
class ConfigService {
  static const _igvKey = 'store_igv_rate';
  static const _cacheTsKey = 'store_config_ts';
  static const _cacheDuration = Duration(hours: 24);

  /// Obtiene la tasa de IGV actual. Si la caché expiró, la baja de Supabase.
  static Future<double> obtenerIGVActual() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getDouble(_igvKey);
    final ts = prefs.getInt(_cacheTsKey);

    if (cached != null && ts != null) {
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (age < _cacheDuration.inMilliseconds) {
        return cached;
      }
    }

    try {
      final res = await Supabase.instance.client
          .from('store_config')
          .select('igv_rate')
          .eq('id', 1)
          .maybeSingle();

      if (res != null && res['igv_rate'] != null) {
        final rate = (res['igv_rate'] as num).toDouble();
        await prefs.setDouble(_igvKey, rate);
        await prefs.setInt(_cacheTsKey, DateTime.now().millisecondsSinceEpoch);
        return rate;
      }
    } catch (e) {
      AppLogger.warning('No se pudo cargar IGV de Supabase: $e', tag: 'CONFIG');
    }

    // fallback al 18%
    return 0.18;
  }

  /// Invalida la caché local (usar cuando admin actualice config)
  static Future<void> invalidarCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_igvKey);
    await prefs.remove(_cacheTsKey);
  }
}
