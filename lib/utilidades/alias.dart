/// Helper para generar alias de usuario a partir del nombre completo.
/// 
/// Este helper centraliza la lógica de creación de identificadores únicos
/// para los usuarios del sistema BiPenc.
class Alias {
  /// Genera un alias inteligente basado en nombre y apellido
  /// 
  /// Ejemplos:
  /// - "Jhonatan Gamarra" -> "JG"
  /// - "María Rodríguez" -> "MR"
  /// - "Carlos" + "" -> "CX"
  static String generarAlias(String nombre, String apellido) {
    String n1 = nombre.isNotEmpty ? nombre[0].toUpperCase() : 'X';
    String a1 = apellido.isNotEmpty ? apellido[0].toUpperCase() : 'X';
    return '$n1$a1';
  }
  
  /// Genera un alias extendido usando más caracteres (4-6 letras)
  /// Útil para sistemas con más de 100 usuarios
  static String generarAliasExtendido(String nombre, String apellido) {
    final nombreLimpio = nombre.trim().toUpperCase();
    final apellidoLimpio = apellido.trim().toUpperCase();
    
    if (nombreLimpio.isEmpty || apellidoLimpio.isEmpty) {
      return 'XXXX';
    }
    
    // Tomar primeras 2 letras del nombre y apellido
    final n = nombreLimpio.substring(0, nombreLimpio.length >= 2 ? 2 : 1);
    final a = apellidoLimpio.substring(0, apellidoLimpio.length >= 2 ? 2 : 1);
    
    return '$n$a';
  }
}
