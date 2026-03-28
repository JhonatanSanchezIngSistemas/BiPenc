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
  final env = await _loadEnvFile(File('.env'));
  final url = env['SUPABASE_URL'];
  final key = env['SUPABASE_ANON_KEY'];
  if (url == null || key == null) {
    stderr.writeln('ERROR: SUPABASE_URL o SUPABASE_ANON_KEY no encontrados en .env');
    exit(2);
  }

  final tables = [
    'productos',
    'ventas',
    'venta_items',
    'print_queue',
    'correlativos',
    'audit_log'
  ];

  final client = http.Client();
  try {
    for (final t in tables) {
      final uri = Uri.parse('$url/rest/v1/$t?select=*&limit=5');
      final resp = await client.get(uri, headers: {
        'apikey': key,
        'Authorization': 'Bearer $key',
        'Accept': 'application/json'
      });
      print('\n--- Tabla: $t ---');
      print('HTTP ${resp.statusCode}');
      if (resp.body.isNotEmpty) {
        try {
          final d = json.decode(resp.body);
          print(jsonEncode(d));
        } catch (e) {
          print('No JSON: ${resp.body}');
        }
      } else {
        print('(sin cuerpo)');
      }
    }
  } catch (e) {
    stderr.writeln('Error: ${e.toString()}');
  } finally {
    client.close();
  }
}
