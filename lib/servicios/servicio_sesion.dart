import 'dart:async';
import 'package:flutter/foundation.dart';
import '../datos/modelos/producto.dart';
import '../utilidades/registro_app.dart';
import 'servicio_backend.dart';
import 'servicio_db_local.dart';

/// Singleton que mantiene el perfil del usuario en memoria.
/// Evita múltiples llamadas a Supabase para obtener el mismo perfil.
class ServicioSesion extends ChangeNotifier {
  // ── Singleton ──
  static final ServicioSesion _instance = ServicioSesion._();
  factory ServicioSesion() => _instance;
  ServicioSesion._();

  Perfil? _perfil;
  bool _isLoading = false;

  Perfil? get perfil => _perfil;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _perfil != null;

  /// Rol del usuario actual (String vacío si no hay sesión)
  String get rol => _normalizeRole(_perfil?.rol ?? '');

  /// ¿Puede gestionar (crear/editar) productos?
  bool get puedeGestionarProductos => rol == RolesApp.admin;

  /// ¿Puede acceder a módulo de auditoría?
  bool get puedeAuditaria => rol == RolesApp.admin;

  /// ¿Puede ver ventas?
  bool get puedeVender => true; // todos los roles pueden vender

  /// Carga el perfil desde Supabase y lo cachea en memoria.
  /// Si ya está cargado, retorna inmediatamente el cacheado.
  Future<Perfil?> obtenerPerfil({bool forceRefresh = false}) async {
    if (_perfil != null && !forceRefresh) return _perfil;

    _isLoading = true;
    notifyListeners();

    try {
      Perfil? p = await ServicioBackend.obtenerPerfil();

      // Si no existe perfil, intento recuperación automática (Constitución Art 3)
      if (p == null) {
        RegistroApp.warning('Perfil no encontrado, activando modo auto-creación',
            tag: 'SESSION');
        p = await ServicioBackend.crearPerfilDeRecuperacion();
      }

      if (p != null) {
        _perfil = Perfil(
          id: p.id,
          nombre: p.nombre,
          apellido: p.apellido,
          alias: p.alias,
          rol: _normalizeRole(p.rol),
          deviceId: p.deviceId,
        );
        unawaited(ServicioDbLocal.logAudit(
          accion: 'LOGIN',
          usuario: _perfil?.alias,
          detalle: 'Rol ${_perfil?.rol}',
        ));
      } else {
        _perfil = Perfil(
          id: 'guest',
          nombre: 'Usuario',
          apellido: 'BiPenc',
          alias: 'INVITADO',
          rol: RolesApp.ventas,
        );
      }
      RegistroApp.info(
          'Perfil activo: alias=${_perfil?.alias} rol=${_perfil?.rol}',
          tag: 'SESSION');
    } catch (e) {
      RegistroApp.error('Error cargando perfil', tag: 'SESSION', error: e);
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
    RegistroApp.info('Sesión limpiada', tag: 'SESSION');
    unawaited(ServicioDbLocal.logAudit(
      accion: 'LOGOUT',
      usuario: 'guest',
      detalle: 'Logout manual',
    ));
  }

  String _normalizeRole(String raw) {
    final upper = raw.toUpperCase();
    if (upper == 'ADMIN' || upper == 'SERVER') return RolesApp.admin;
    if (upper == 'USER' || upper == 'VENTAS') return RolesApp.ventas;
    return RolesApp.ventas;
  }
}

/// Constantes de roles del sistema BiPenc.
class RolesApp {
  RolesApp._();
  static const String server = 'SERVER';
  static const String admin = 'ADMIN';
  static const String ventas = 'VENTAS';

  static const List<String> todos = [server, admin, ventas];
}
