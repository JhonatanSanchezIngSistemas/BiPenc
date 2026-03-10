import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurityService {
  static const String _adminKey = 'admin_password_hash';
  
  /// Hash BCRYPT bootstrap (rounds=12).
  /// Debe cambiarse desde ajustes en el primer uso.
  static const String _defaultAdminHash = 
    r'$2b$12$R9h7cIPz0gi.URNNF3kh2OPST9/PgBkqquzi.Ss7KIUgO2t0jKMUi';

  /// Inicializa el servicio, grabando el hash por defecto si es la primera vez que se abre la app.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_adminKey)) {
      await prefs.setString(_adminKey, _defaultAdminHash);
      debugPrint('[SecurityService] Inicializado con admin por defecto');
    }
  }

  /// Valida si el PIN/Contraseña suministrado coincide con la clave de administrador.
  /// Usa BCrypt para comparación segura.
  Future<bool> validarAccesoAdministrador(String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedHash = prefs.getString(_adminKey) ?? _defaultAdminHash;
      
      // BCrypt.checkpw es seguro contra timing attacks
      final isMatch = BCrypt.checkpw(password, storedHash);
      
      if (!isMatch) {
        debugPrint('[SecurityService] Acceso rechazado: password incorrecto');
      }
      
      return isMatch;
    } catch (e) {
      debugPrint('[SecurityService] Error validando credenciales: $e');
      return false;
    }
  }

  /// Actualiza la contraseña generando un nuevo hash BCRYPT.
  /// Usa 12 rounds (default) para balance entre seguridad y performance.
  Future<bool> cambiarClaveAdministrador(String nuevaClave) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Generar salt (default rounds = ~250ms en mobile)
      final salt = BCrypt.gensalt();
      
      // Hash con BCrypt
      final newHash = BCrypt.hashpw(nuevaClave, salt);
      
      final success = await prefs.setString(_adminKey, newHash);
      
      if (success) {
        debugPrint('[SecurityService] Clave actualizada correctamente');
      }
      
      return success;
    } catch (e) {
      debugPrint('[SecurityService] Error cambiando clave: $e');
      return false;
    }
  }
}
