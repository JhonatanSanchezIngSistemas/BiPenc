import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utilidades/registro_app.dart';

class BusinessProfile {
  final String id;
  final String ruc;
  final String razonSocial;
  final String? nombreComercial;
  final String? direccion;
  final String? celular;
  final String? email;
  final String? logoUrl;
  final String moneda;

  BusinessProfile({
    required this.id,
    required this.ruc,
    required this.razonSocial,
    this.nombreComercial,
    this.direccion,
    this.celular,
    this.email,
    this.logoUrl,
    this.moneda = 'PEN',
  });

  factory BusinessProfile.fromJson(Map<String, dynamic> json) {
    return BusinessProfile(
      id: json['id'],
      ruc: json['ruc'],
      razonSocial: json['razon_social'],
      nombreComercial: json['nombre_comercial'],
      direccion: json['direccion'],
      celular: json['celular'],
      email: json['email'],
      logoUrl: json['logo_url'],
      moneda: json['moneda'] ?? 'PEN',
    );
  }

  Map<String, dynamic> toJson() => {
    'ruc': ruc,
    'razon_social': razonSocial,
    'nombre_comercial': nombreComercial,
    'direccion': direccion,
    'celular': celular,
    'email': email,
    'logo_url': logoUrl,
    'moneda': moneda,
  };
}

class ServicioConfiguracion {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Obtiene el perfil de negocio (solo debería haber uno)
  static Future<BusinessProfile?> obtenerPerfil() async {
    try {
      final res = await _client.from('perfil_negocio').select().maybeSingle();
      if (res == null) return null;
      return BusinessProfile.fromJson(res);
    } catch (e) {
      RegistroApp.error('Error al obtener perfil de negocio', tag: 'CONFIG', error: e);
      return null;
    }
  }

  /// Actualiza el perfil de negocio (Solo Admin vía RLS)
  static Future<bool> actualizarPerfil(BusinessProfile perfil) async {
    try {
      await _client
          .from('perfil_negocio')
          .upsert(perfil.toJson()..['id'] = perfil.id);
      return true;
    } catch (e) {
      RegistroApp.error('Error al actualizar perfil de negocio', tag: 'CONFIG', error: e);
      return false;
    }
  }
}
