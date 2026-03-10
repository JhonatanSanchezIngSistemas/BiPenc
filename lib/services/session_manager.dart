import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bipenc/services/encryption_service.dart';

/// Constitución BiPenc — Artículo 1:
/// Gestión del bloqueo de sesión por inactividad de 15 minutos.
/// La huella solo se pide al (a) abrir la app en frío o (b) tras 15 min sin uso.
class SessionManager extends ChangeNotifier {
  static const _kLastActivityKey = 'last_activity_ts';
  // cambió 60→15 tras auditoría de seguridad
  static const _inactivityMinutes = 15;

  final LocalAuthentication _auth = LocalAuthentication();
  Timer? _inactivityTimer;
  bool _bloqueado = false;
  bool _biometricoDisponible = false;

  bool get bloqueado => _bloqueado;
  bool get biometricoDisponible => _biometricoDisponible;

  SessionManager() {
    _init();
  }

  Future<void> _init() async {
    // Inicializar encriptación para proteger datos de sesión
    try {
      await EncryptionService().init();
    } catch (e) {
      debugPrint('[SessionManager] ⚠️ Encryption init fallback: $e');
    }
    _biometricoDisponible = await _auth.canCheckBiometrics;
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
      if (EncryptionService().isInitialized) {
        final encrypted = EncryptionService().encriptar(ts);
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
      final legacyTs = prefs.getInt(_kLastActivityKey);
      if (legacyTs == null) {
        _bloqueado = true;
        notifyListeners();
        return;
      }
      final elapsed = DateTime.now().millisecondsSinceEpoch - legacyTs;
      if (elapsed >= _inactivityMinutes * 60 * 1000) {
        _bloqueado = true;
        notifyListeners();
      }
      return;
    }
    try {
      int lastTs;
      if (EncryptionService().isInitialized && raw.contains('.')) {
        lastTs = int.parse(EncryptionService().desencriptar(raw));
      } else {
        lastTs = int.parse(raw);
      }
      final elapsed = DateTime.now().millisecondsSinceEpoch - lastTs;
      if (elapsed >= _inactivityMinutes * 60 * 1000) {
        _bloqueado = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[SessionManager] Error decrypting timestamp: $e');
      _bloqueado = true;
      notifyListeners();
    }
  }

  void _bloquearPorInactividad() {
    _bloqueado = true;
    notifyListeners();
    debugPrint('[SessionManager] Bloqueado por inactividad de ${_inactivityMinutes}min');
  }

  /// Intenta desbloquear con huella digital (Solo si usuario presiona botón).
  /// No se llama automáticamente. SessionGuard maneja el UI.
  /// Esta es una operación A DEMANDA, no automática.
  Future<bool> desbloquear() async {
    if (!_biometricoDisponible) {
      _bloqueado = false;
      registrarActividad();
      notifyListeners();
      debugPrint('[SessionManager] Desbloqueado sin biometría (no disponible)');
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
        debugPrint('[SessionManager] Desbloqueado correctamente');
      }
      return ok;
    } catch (e) {
      // Error técnico biométrico: mantener bloqueado por seguridad.
      debugPrint('[SessionManager] Error biométrico: $e');
      return false;
    }
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
  /// para evitar doble prompt al entrar a rutas protegidas por SessionGuard.
  void marcarSesionAutenticada() {
    _bloqueado = false;
    registrarActividad();
    notifyListeners();
  }
}
