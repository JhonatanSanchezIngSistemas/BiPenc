import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

Future<Map<String, String>> _loadEnvFile(File f) async {
  final map = <String, String>{};
  if (!await f.exists()) return map;
  final lines = await f.readAsLines();
  for (var l in lines) {
    l = l.trim();
    if (l.isEmpty || l.startsWith('#')) continue;
    final idx = l.indexOf('=');
    if (idx <= 0) continue;
    final k = l.substring(0, idx).trim();
    var v = l.substring(idx + 1).trim();
    if (v.startsWith('"') && v.endsWith('"')) v = v.substring(1, v.length - 1);
    map[k] = v;
  }
  return map;
}

Future<void> main() async {
  final envFile = File('.env');
  final env = await _loadEnvFile(envFile);

  final url = env['SUPABASE_URL'];
  final key = env['SUPABASE_ANON_KEY'];

  if (url == null || key == null) {
    stderr.writeln('ERROR: SUPABASE_URL o SUPABASE_ANON_KEY no encontrados en .env');
    exit(2);
  }

  print('Intentando conectar a Supabase en: $url');

  final client = http.Client();
  try {
    // Intento 1: consultar information_schema.tables vía PostgREST
    final uri = Uri.parse('$url/rest/v1/information_schema.tables?select=table_schema,table_name&limit=1000');
    final resp = await client.get(uri, headers: {
      'apikey': key,
      'Authorization': 'Bearer $key',
      'Accept': 'application/json'
    });

    print('\n--- Información: /information_schema.tables ---');
    print('Código HTTP: ${resp.statusCode}');
    try {
      final body = resp.body;
      if (body.isEmpty) {
        print('(sin cuerpo)');
      } else {
        final decoded = json.decode(body);
        print(json.encode(decoded));
      }
    } catch (e) {
      print('No se pudo decodificar la respuesta: ${e.toString()}');
      print('Cuerpo: ${resp.body}');
    }

    // Intento 2: listar tablas públicas conocidas (fallback: request al endpoint /rest/v1)
    final root = Uri.parse('$url/rest/v1');
    final resp2 = await client.get(root, headers: {
      'apikey': key,
      'Authorization': 'Bearer $key',
      'Accept': 'application/json'
    });
    print('\n--- Información: /rest/v1 (root) ---');
    print('Código HTTP: ${resp2.statusCode}');
    if (resp2.body.isNotEmpty) print(resp2.body);

    if (resp.statusCode >= 400 || resp2.statusCode >= 400) {
      print('\nNota: es probable que la clave ANON no permita consultar el esquema completo.');
      print('Para un inventario completo y cambios administrativos necesitarás la SUPABASE_SERVICE_ROLE_KEY (clave de servicio).');
    }
  } catch (e) {
    stderr.writeln('Error durante la inspección: ${e.toString()}');
  } finally {
    client.close();
  }
}
