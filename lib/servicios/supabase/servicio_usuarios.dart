import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utilidades/registro_app.dart';

class ServicioUsuariosSupabase {
  static SupabaseClient get _client => Supabase.instance.client;
  static const Set<String> _rolesPermitidos = {'ADMIN', 'VENTAS'};

  static String _limpiarTexto(String value) => value.trim();

  static void _validarInvitacion({
    required String email,
    required String nombre,
    required String apellido,
    required String rol,
  }) {
    final emailOk = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!emailOk) {
      throw ArgumentError('Email inválido');
    }
    if (nombre.isEmpty) {
      throw ArgumentError('Nombre es obligatorio');
    }
    if (apellido.isEmpty) {
      throw ArgumentError('Apellido es obligatorio');
    }
    if (!_rolesPermitidos.contains(rol)) {
      throw ArgumentError('Rol inválido: $rol');
    }
  }

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

  /// Activa o desactiva un usuario (estado ACTIVO/INACTIVO).
  static Future<void> actualizarEstado(String id, String estado) async {
    await actualizarCampoPerfil(id, 'estado', estado.toUpperCase());
  }

  /// Invita/crea usuario vía función segura en backend (Edge Function).
  /// Requiere una función `admin_invitar_usuario` con service role.
  static Future<void> invitarUsuario({
    required String email,
    required String nombre,
    required String apellido,
    required String rol,
  }) async {
    try {
      final emailLimpio = _limpiarTexto(email).toLowerCase();
      final nombreLimpio = _limpiarTexto(nombre);
      final apellidoLimpio = _limpiarTexto(apellido);
      final rolLimpio = _limpiarTexto(rol).toUpperCase();

      _validarInvitacion(
        email: emailLimpio,
        nombre: nombreLimpio,
        apellido: apellidoLimpio,
        rol: rolLimpio,
      );

      final response = await _client.functions.invoke('admin_invitar_usuario', body: {
        'email': emailLimpio,
        'nombre': nombreLimpio,
        'apellido': apellidoLimpio,
        'rol': rolLimpio,
      });

      if (response.error != null) {
        throw Exception(response.error!.message);
      }
      if (response.status < 200 || response.status >= 300) {
        throw Exception('Error invitando usuario (HTTP ${response.status})');
      }
    } catch (e) {
      RegistroApp.error('Error invitando usuario', tag: 'USUARIOS', error: e);
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
