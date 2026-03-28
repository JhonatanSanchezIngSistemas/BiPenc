import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utilidades/registro_app.dart';

class ServicioUsuariosSupabase {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Stream de perfiles (usuarios) en tiempo real.
  static Stream<List<Map<String, dynamic>>> streamUsuarios({int limit = 100}) {
    return _client
        .from('perfiles')
        .stream(primaryKey: ['id'])
        .order('nombre', ascending: true)
        .limit(limit);
  }

  /// Actualiza rol o campo del perfil de un usuario.
  static Future<void> actualizarCampoPerfil(String id, String campo, String valor) async {
    try {
      await _client.from('perfiles').update({campo: valor}).eq('id', id);
    } catch (e) {
      RegistroApp.error('Error actualizando perfil ($campo)', tag: 'USUARIOS', error: e);
      rethrow;
    }
  }

  /// Actualización masiva de campos.
  static Future<void> actualizarDatosPerfil(String id, Map<String, dynamic> data) async {
    try {
      await _client.from('perfiles').update(data).eq('id', id);
    } catch (e) {
      RegistroApp.error('Error actualizando datos perfil', tag: 'USUARIOS', error: e);
      rethrow;
    }
  }
}
