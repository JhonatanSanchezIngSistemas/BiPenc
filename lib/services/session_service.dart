import 'package:flutter/foundation.dart';
import '../models/producto.dart';
import '../utils/app_logger.dart';
import 'supabase_service.dart';

/// Singleton que mantiene el perfil del usuario en memoria.
/// Evita múltiples llamadas a Supabase para obtener el mismo perfil.
class SessionService extends ChangeNotifier {
  // ── Singleton ──
  static final SessionService _instance = SessionService._();
  factory SessionService() => _instance;
  SessionService._();

  Perfil? _perfil;
  bool _isLoading = false;

  Perfil? get perfil => _perfil;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _perfil != null;

  /// Rol del usuario actual (String vacío si no hay sesión)
  String get rol => _perfil?.rol ?? '';

  /// ¿Puede gestionar (crear/editar) productos?
  bool get puedeGestionarProductos =>
      rol == AppRoles.server || rol == AppRoles.admin;

  /// ¿Puede acceder a módulo de auditoría?
  bool get puedeAuditaria =>
      rol == AppRoles.server || rol == AppRoles.admin;

  /// ¿Puede ver ventas?
  bool get puedeVender => true; // todos los roles pueden vender

  /// Carga el perfil desde Supabase y lo cachea en memoria.
  /// Si ya está cargado, retorna inmediatamente el cacheado.
  Future<Perfil?> obtenerPerfil({bool forceRefresh = false}) async {
    if (_perfil != null && !forceRefresh) return _perfil;

    _isLoading = true;
    notifyListeners();

    try {
      Perfil? p = await SupabaseService.obtenerPerfil();

      // Si no existe perfil, intento recuperación automática
      if (p == null) {
        AppLogger.warning('Perfil no encontrado, intentando recuperación', tag: 'SESSION');
        p = await SupabaseService.crearPerfilDeRecuperacion();
      }

      _perfil = p;
      AppLogger.info('Perfil cargado: alias=${p?.alias} rol=${p?.rol}', tag: 'SESSION');
    } catch (e) {
      AppLogger.error('Error cargando perfil', tag: 'SESSION', error: e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    return _perfil;
  }

  /// Limpia la sesión (al hacer sign out).
  void limpiarSesion() {
    _perfil = null;
    notifyListeners();
    AppLogger.info('Sesión limpiada', tag: 'SESSION');
  }
}

/// Constantes de roles del sistema BiPenc.
class AppRoles {
  AppRoles._();
  static const String server = 'SERVER';
  static const String admin = 'ADMIN';
  static const String ventas = 'VENTAS';

  static const List<String> todos = [server, admin, ventas];
}
