import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurityService {
  static const String _adminKey = 'admin_password_hash';
  
  // Hash por defecto para "admin123" usando SHA-256
  // 240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9
  static const String _defaultAdminHash = '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9';

  /// Inicializa el servicio, grabando el hash por defecto si es la primera vez que se abre la app.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_adminKey)) {
      await prefs.setString(_adminKey, _defaultAdminHash);
    }
  }

  /// Valida si el PIN/Contraseña suministrado coincide con la clave de administrador.
  /// Lo hace convirtiendo la entrada a SHA-256 y comparándola con el hash en disco.
  Future<bool> validarAccesoAdministrador(String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedHash = prefs.getString(_adminKey) ?? _defaultAdminHash;
      
      // Convertimos el password entrante a bytes y luego aplicamos el Hash SHA-256
      final bytes = utf8.encode(password);
      final derivedHash = sha256.convert(bytes).toString();
      
      return storedHash == derivedHash;
    } catch (e) {
      debugPrint('Excepción al validar credenciales: $e');
      return false;
    }
  }

  /// Actualiza la contraseña generando un nuevo Hash y sobreescribiendo el anterior.
  Future<bool> cambiarClaveAdministrador(String nuevaClave) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bytes = utf8.encode(nuevaClave);
      final newHash = sha256.convert(bytes).toString();
      return await prefs.setString(_adminKey, newHash);
    } catch (e) {
      debugPrint('Error al cambiar clave en SecurityService: $e');
      return false;
    }
  }
}
