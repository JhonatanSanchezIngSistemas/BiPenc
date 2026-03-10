import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../utils/app_logger.dart';
import 'local_db_service.dart';

class DniInfo {
  final String dni;
  final String nombre;
  final String apellidoP;
  final String apellidoM;
  final Map<String, dynamic> raw;

  DniInfo({
    required this.dni,
    required this.nombre,
    required this.apellidoP,
    required this.apellidoM,
    required this.raw,
  });

  String get nombreCompleto =>
      '$apellidoP $apellidoM, $nombre'.trim().replaceAll(RegExp(' +'), ' ');
}

class IdentidadService {
  static const _timeout = Duration(seconds: 4);
  static DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);
  static int _callsThisMinute = 0;

  /// Compatibilidad con POS: consulta DNI o RUC (solo DNI implementado).
  /// Retorna nombre completo o:
  /// - 'OFFLINE' si no hay configuración de API
  /// - 'ERROR' en caso de excepción
  static Future<String?> consultarDocumento(String doc, bool esRuc) async {
    final clean = doc.replaceAll(RegExp(r'\\D'), '');
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('dni_api_url') ?? '';
    final token = prefs.getString('dni_api_token') ?? '';
    final apiConfigured = url.isNotEmpty && token.isNotEmpty;

    if (clean.isEmpty) return null;

    if (esRuc || clean.length == 11) {
      // Placeholder: podríamos integrar SUNAT RUC más adelante.
      return apiConfigured ? null : 'OFFLINE';
    }

    if (clean.length != 8) return null;

    try {
      final info = await consultarDni(clean);
      return info?.nombreCompleto;
    } catch (e) {
      return apiConfigured ? 'ERROR' : 'OFFLINE';
    }
  }

  /// Consulta DNI con cache local (24h). Retorna null si no configurado o error.
  static Future<DniInfo?> consultarDni(String dni) async {
    final sanitized = dni.replaceAll(RegExp(r'\\D'), '');
    if (sanitized.length != 8) return null;

    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('dni_api_url') ?? '';
    final token = prefs.getString('dni_api_token') ?? '';
    if (url.isEmpty || token.isEmpty) return _getCache(sanitized);

    // Rate limit sencillo: 5 req/min
    final now = DateTime.now();
    if (now.difference(_lastCall).inMinutes >= 1) {
      _callsThisMinute = 0;
      _lastCall = now;
    }
    if (_callsThisMinute >= 5) {
      AppLogger.warn('DNI API rate limited', tag: 'DNI_API');
      return _getCache(sanitized);
    }
    _callsThisMinute++;

    try {
      final uri = Uri.parse('$url/$sanitized');
      final res = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final info = _mapResponse(sanitized, data);
        await _saveCache(info);
        return info;
      }
      if (res.statusCode == 404) {
        AppLogger.warn('DNI no encontrado', tag: 'DNI_API');
        return null;
      }
      AppLogger.error('Error DNI API: ${res.statusCode} ${res.body}',
          tag: 'DNI_API');
      return _getCache(sanitized);
    } catch (e) {
      AppLogger.error('Excepción DNI API: $e', tag: 'DNI_API', error: e);
      return _getCache(sanitized);
    }
  }

  static DniInfo _mapResponse(String dni, Map<String, dynamic> json) {
    return DniInfo(
      dni: dni,
      nombre: (json['nombres'] ?? json['nombre'] ?? '').toString().trim(),
      apellidoP:
          (json['apellido_paterno'] ?? json['apellidoP'] ?? '').toString().trim(),
      apellidoM:
          (json['apellido_materno'] ?? json['apellidoM'] ?? '').toString().trim(),
      raw: json,
    );
  }

  static Future<void> _saveCache(DniInfo info) async {
    try {
      final db = await LocalDbService.database;
      await db.insert(
        'dni_cache',
        {
          'dni': info.dni,
          'nombre': info.nombre,
          'apellido_p': info.apellidoP,
          'apellido_m': info.apellidoM,
          'json': jsonEncode(info.raw),
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      AppLogger.error('Error guardando cache DNI', tag: 'DNI_API', error: e);
    }
  }

  static Future<DniInfo?> _getCache(String dni) async {
    try {
      final db = await LocalDbService.database;
      final rows =
          await db.query('dni_cache', where: 'dni = ?', whereArgs: [dni], limit: 1);
      if (rows.isEmpty) return null;
      final r = rows.first;
      final updated = DateTime.tryParse(r['updated_at'] as String? ?? '') ??
          DateTime.now();
      if (DateTime.now().difference(updated).inHours > 24) return null;
      final raw = r['json'] != null
          ? jsonDecode(r['json'] as String)
          : <String, dynamic>{};
      return DniInfo(
        dni: dni,
        nombre: r['nombre']?.toString() ?? '',
        apellidoP: r['apellido_p']?.toString() ?? '',
        apellidoM: r['apellido_m']?.toString() ?? '',
        raw: raw is Map<String, dynamic> ? raw : <String, dynamic>{},
      );
    } catch (e) {
      AppLogger.error('Error leyendo cache DNI', tag: 'DNI_API', error: e);
      return null;
    }
  }
}
