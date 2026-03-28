import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bipenc/servicios/servicio_cifrado.dart';

/// Constitución BiPenc — Artículo 1:
/// Gestión del bloqueo de sesión por inactividad de 15 minutos.
/// La huella solo se pide al (a) abrir la app en frío o (b) tras 15 min sin uso.
class GestorSesion extends ChangeNotifier {
  static const _kLastActivityKey = 'last_activity_ts';
  // cambió 60→15 tras auditoría de seguridad
  static const _inactivityMinutes = 15;

  final LocalAuthentication _auth = LocalAuthentication();
  Timer? _inactivityTimer;
  bool _bloqueado = false;
  bool _biometricoDisponible = false;

  bool get bloqueado => _bloqueado;
  bool get biometricoDisponible => _biometricoDisponible;

  GestorSesion() {
    _init();
  }

  Future<void> _init() async {
    // Inicializar encriptación para proteger datos de sesión
    try {
      await ServicioCifrado().init();
    } catch (e) {
      debugPrint('[GestorSesion] ⚠️ Encryption init fallback: $e');
    }
    _biometricoDisponible = _biometriaSoportada();
    if (_biometricoDisponible) {
      try {
        _biometricoDisponible = await _auth.canCheckBiometrics;
      } catch (e) {
        // En plataformas no soportadas por el plugin (como Desktop Linux sin setup)
        // se atrapa MissingPluginException silenciosamente.
        debugPrint('[GestorSesion] Biometría no disponible (catch): $e');
        _biometricoDisponible = false;
      }
    }
    await _checkInactivity();
    registrarActividad();
  }

  /// Registra actividad del usuario → reinicia el timer de 60 minutos.
  void registrarActividad() {
    _inactivityTimer?.cancel();
    _guardarTimestamp();
    _inactivityTimer = Timer(
      const Duration(minutes: _inactivityMinutes),
      _bloquearPorInactividad,
    );
  }

  Future<void> _guardarTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    try {
      if (ServicioCifrado().isInitialized) {
        final encrypted = ServicioCifrado().encriptar(ts);
        await prefs.setString(_kLastActivityKey, encrypted);
      } else {
        await prefs.setString(_kLastActivityKey, ts);
      }
    } catch (e) {
      // Fallback sin encriptar si hay error
      await prefs.setString(_kLastActivityKey, ts);
    }
  }

  /// Verifica si ya pasaron 60 min desde el último uso (ej: app matada y reabierta).
  Future<void> _checkInactivity() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastActivityKey);
    // Compatibilidad: intentar con int antiguo si string no existe
    if (raw == null) {
      // Primera vez: no bloquear; guardar timestamp ahora.
      _bloqueado = false;
      await _guardarTimestamp();
      notifyListeners();
      return;
    }
    try {
      int lastTs;
      if (ServicioCifrado().isInitialized && raw.contains('.')) {
        lastTs = int.parse(ServicioCifrado().desencriptar(raw));
      } else {
        lastTs = int.parse(raw);
      }
      final elapsed = DateTime.now().millisecondsSinceEpoch - lastTs;
      if (elapsed >= _inactivityMinutes * 60 * 1000) {
        _bloqueado = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[GestorSesion] Error decrypting timestamp: $e');
      _bloqueado = true;
      notifyListeners();
    }
  }

  void _bloquearPorInactividad() {
    _bloqueado = true;
    notifyListeners();
    debugPrint('[GestorSesion] Bloqueado por inactividad de ${_inactivityMinutes}min');
  }

  /// Intenta desbloquear con huella digital (Solo si usuario presiona botón).
  /// No se llama automáticamente. GuardiaSesion maneja el UI.
  /// Esta es una operación A DEMANDA, no automática.
  Future<bool> desbloquear() async {
    if (!_biometriaSoportada()) {
      _bloqueado = false;
      registrarActividad();
      notifyListeners();
      debugPrint('[GestorSesion] Desbloqueado sin biometría (no soportado)');
      return true;
    }
    if (!_biometricoDisponible) {
      _bloqueado = false;
      registrarActividad();
      notifyListeners();
      debugPrint('[GestorSesion] Desbloqueado sin biometría (no disponible)');
      return true;
    }
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Identifícate para continuar en BiPenc',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (ok) {
        _bloqueado = false;
        registrarActividad();
        notifyListeners();
        debugPrint('[GestorSesion] Desbloqueado correctamente');
      }
      return ok;
    } catch (e) {
      // Error técnico biométrico: mantener bloqueado por seguridad.
      debugPrint('[GestorSesion] Error biométrico: $e');
      return false;
    }
  }

  bool _biometriaSoportada() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }

  /// Cierra la sesión manualmente (Logout)
  Future<void> cerrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLastActivityKey);
    _bloqueado = true;
    _inactivityTimer?.cancel();
    notifyListeners();
  }

  /// Marca la sesión como ya autenticada (ej. login biométrico exitoso en LoginPage)
  /// para evitar doble prompt al entrar a rutas protegidas por GuardiaSesion.
  void marcarSesionAutenticada() {
    _bloqueado = false;
    registrarActividad();
    notifyListeners();
  }
}
