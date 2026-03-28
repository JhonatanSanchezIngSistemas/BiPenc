import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ServicioSeguridad {
  // REFACTOR: hash y bandera de setup se guardan en secure storage para evitar fugas.
  static const String _adminKey = 'admin_password_hash';
  static const String _setupFlag = 'admin_setup_completed';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  bool _needsInitialSetup = false;

  bool get requiereConfiguracionInicial => _needsInitialSetup;

  /// Inicializa el servicio leyendo el hash de forma segura.
  /// Si no existe hash, marcamos que la app requiere que el usuario cree una clave.
  Future<void> init() async {
    final storedHash = await _secureStorage.read(key: _adminKey);
    _needsInitialSetup = storedHash == null;
  }

  /// Valida si el PIN/Contraseña suministrado coincide con la clave de administrador.
  /// Usa BCrypt para comparación segura.
  Future<bool> validarAccesoAdministrador(String password) async {
    try {
      final storedHash = await _secureStorage.read(key: _adminKey);
      if (storedHash == null) {
        _needsInitialSetup = true;
        debugPrint('[ServicioSeguridad] No hay clave configurada');
        return false;
      }

      // BCrypt.checkpw es seguro contra timing attacks
      final isMatch = BCrypt.checkpw(password, storedHash);

      if (!isMatch) {
        debugPrint('[ServicioSeguridad] Acceso rechazado: password incorrecto');
      }

      return isMatch;
    } catch (e) {
      debugPrint('[ServicioSeguridad] Error validando credenciales: $e');
      return false;
    }
  }

  /// Actualiza la contraseña generando un nuevo hash BCRYPT.
  /// Usa 12 rounds (default) para balance entre seguridad y performance.
  Future<bool> cambiarClaveAdministrador(String nuevaClave) async {
    try {
      // Generar salt (default rounds = ~250ms en mobile)
      final salt = BCrypt.gensalt();

      // Hash con BCrypt
      final newHash = BCrypt.hashpw(nuevaClave, salt);

      await _secureStorage.write(key: _adminKey, value: newHash);
      await _secureStorage.write(key: _setupFlag, value: 'true');
      _needsInitialSetup = false;

      debugPrint('[ServicioSeguridad] Clave actualizada correctamente');
      return true;
    } catch (e) {
      debugPrint('[ServicioSeguridad] Error cambiando clave: $e');
      return false;
    }
  }

  /// Indica si es necesario forzar al usuario a configurar la clave admin.
  Future<bool> necesitaOnboardingClave() async {
    final flag = await _secureStorage.read(key: _setupFlag);
    return _needsInitialSetup || flag != 'true';
  }
}
