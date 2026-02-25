import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Constitución BiPenc — Artículo 1:
/// Gestiona el bloqueo de sesión por inactividad de 60 minutos.
/// La huella solo se pide al (a) abrir la app en frío o (b) tras 60 min sin uso.
class SessionManager extends ChangeNotifier {
  static const _kLastActivityKey = 'last_activity_ts';
  static const _inactivityMinutes = 60;

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
    await prefs.setInt(_kLastActivityKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Verifica si ya pasaron 60 min desde el último uso (ej: app matada y reabierta).
  Future<void> _checkInactivity() async {
    final prefs = await SharedPreferences.getInstance();
    final lastTs = prefs.getInt(_kLastActivityKey);
    if (lastTs == null) {
      _bloqueado = true;
      notifyListeners();
      return;
    }
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastTs;
    if (elapsed >= _inactivityMinutes * 60 * 1000) {
      _bloqueado = true;
      notifyListeners();
    }
  }

  void _bloquearPorInactividad() {
    _bloqueado = true;
    notifyListeners();
    debugPrint('[SessionManager] Bloqueado por inactividad de ${_inactivityMinutes}min');
  }

  /// Intenta desbloquear con huella digital.
  /// Si el sensor no está disponible, desbloquea directo.
  Future<bool> desbloquear() async {
    if (!_biometricoDisponible) {
      _bloqueado = false;
      registrarActividad();
      notifyListeners();
      return true;
    }
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Identifícate para continuar en BiPenc',
        options: const AuthenticationOptions(biometricOnly: false),
      );
      if (ok) {
        _bloqueado = false;
        registrarActividad();
        notifyListeners();
      }
      return ok;
    } catch (e) {
      // Cualquier error de sensor → desbloquear sin huella
      _bloqueado = false;
      registrarActividad();
      notifyListeners();
      return true;
    }
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }
}
