import 'package:shared_preferences/shared_preferences.dart';
import '../utilidades/registro_app.dart';
import 'servicio_backend.dart';

/// Servicio para obtener configuraciones globales como tasa de IGV.
/// Cached en SharedPreferences para evitar consultas frecuentes.
class ServicioConfiguracion {
  static const _igvKey = 'store_igv_rate';
  static const _cacheTsKey = 'store_config_ts';
  static const _cacheDuration = Duration(hours: 24);
  static const _modoPruebaKey = 'modo_prueba_flag';
  static const _liveCartsKey = 'live_carts_enabled';
  static const _liveCartsTsKey = 'live_carts_ts';
  static const _liveCartsCacheDuration = Duration(minutes: 5);

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
      final rate = await ServicioBackend.obtenerIgvRate();
      if (rate != null) {
        await prefs.setDouble(_igvKey, rate);
        await prefs.setInt(_cacheTsKey, DateTime.now().millisecondsSinceEpoch);
        return rate;
      }
    } catch (e) {
      RegistroApp.warning('No se pudo cargar IGV del backend: $e', tag: 'CONFIG');
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

  /// Lee/salva modo prueba localmente; se puede sincronizar con Supabase store_config.modo_prueba (opcional).
  static Future<bool> getModoPrueba() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_modoPruebaKey) ?? false;
  }

  static Future<void> setModoPrueba(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_modoPruebaKey, enabled);
    try {
      await ServicioBackend.upsertModoPrueba(enabled);
    } catch (e) {
      RegistroApp.warn(
          'No se pudo sincronizar modo_prueba en backend (best-effort)',
          tag: 'CONFIG',
          error: e);
    }
  }

  /// Live carts: habilita/deshabilita envío de carritos en vivo (Admin).
  static Future<bool> getLiveCartsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getBool(_liveCartsKey);
    final ts = prefs.getInt(_liveCartsTsKey);

    if (cached != null && ts != null) {
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (age < _liveCartsCacheDuration.inMilliseconds) {
        return cached;
      }
    }

    try {
      final enabled = await ServicioBackend.obtenerLiveCartsEnabled();
      if (enabled != null) {
        await prefs.setBool(_liveCartsKey, enabled);
        await prefs.setInt(_liveCartsTsKey, DateTime.now().millisecondsSinceEpoch);
        return enabled;
      }
    } catch (e) {
      RegistroApp.warn('No se pudo cargar live_carts_enabled del backend',
          tag: 'CONFIG', error: e);
    }

    return cached ?? false;
  }

  static Future<void> setLiveCartsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_liveCartsKey, enabled);
    await prefs.setInt(_liveCartsTsKey, DateTime.now().millisecondsSinceEpoch);
    try {
      await ServicioBackend.upsertLiveCartsEnabled(enabled);
    } catch (e) {
      RegistroApp.warn('No se pudo sincronizar live_carts_enabled en backend',
          tag: 'CONFIG', error: e);
    }
  }
}
